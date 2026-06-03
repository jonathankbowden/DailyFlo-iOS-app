//
//  SubscriptionManager.swift
//  DailyFlo
//
//  Thin wrapper around the RevenueCat SDK. Owns the app's view of
//  subscription state (isPro), the fetched "default" Offering, the
//  monthly + annual packages the paywall displays, and per-package
//  trial eligibility for that paywall's CTA copy.
//
//  Lifecycle assumption: `Purchases.configure(withAPIKey:)` is called from
//  DailyFloApp's init BEFORE any caller touches `SubscriptionManager.shared`.
//

import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty       // Purchases returned, but no "default" offering yet
        case failed(String)
    }

    enum PurchaseOutcome: Equatable {
        case success
        case userCancelled
        case pending     // Ask-to-Buy / SCA — Apple will confirm later
    }

    enum RestoreOutcome: Equatable {
        case restored
        case nothingToRestore
    }

    private(set) var offering: Offering?
    private(set) var loadState: LoadState = .idle

    // Per-package trial/intro-discount eligibility, keyed by `package.identifier`.
    // `.unknown` until `refreshIntroEligibility` returns.
    private(set) var introEligibility: [String: IntroEligibilityStatus] = [:]

    /// `$rc_monthly` package on the active offering, if present.
    var monthlyPackage: Package? { offering?.monthly }
    /// `$rc_annual` package on the active offering, if present.
    var annualPackage: Package? { offering?.annual }

    // The "real" Pro state driven by RC CustomerInfo. Hidden behind the
    // public `isPro` so the DEBUG override can pin it without losing the
    // underlying truth.
    private var realIsPro: Bool = false

    #if DEBUG
    /// nil = follow RC. true/false = pin `isPro` regardless of CustomerInfo.
    /// Stored in @Observable so toggling it from the debug inspector
    /// propagates to the paywall, gating wrapper, and any view reading `isPro`.
    var debugProOverride: Bool? = nil
    #endif

    /// The value the rest of the app gates on. Reads through the DEBUG
    /// override when one is set, otherwise mirrors RC's CustomerInfo.
    var isPro: Bool {
        #if DEBUG
        if let debugProOverride { return debugProOverride }
        #endif
        return realIsPro
    }

    private init() {
        Task { await observeCustomerInfo() }
        Task {
            await refreshCustomerInfo()
            await fetchOffering()
        }
    }

    /// Fetches the "default" Offering. Falls back to `offerings.current`
    /// when the literal identifier isn't found. Marks `.empty` if neither
    /// is available (App Store products often take minutes to propagate
    /// after first config). When an offering loads, fans out to refresh
    /// trial eligibility for its packages.
    func fetchOffering() async {
        loadState = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            let resolved = offerings.all[RevenueCatConfig.defaultOfferingID]
                ?? offerings.current

            if let resolved {
                self.offering = resolved
                self.loadState = .loaded
                await refreshIntroEligibility(for: resolved)
            } else {
                self.offering = nil
                self.loadState = .empty
            }
        } catch {
            self.offering = nil
            self.loadState = .failed(error.localizedDescription)
        }
    }

    /// Pulls the latest CustomerInfo and recomputes `realIsPro`. Safe to call
    /// repeatedly — invoked on launch and whenever the app foregrounds.
    func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            updateIsPro(from: info)
        } catch {
            // Non-fatal: leave the last known value in place rather
            // than flipping the user out of Pro on a transient network blip.
        }
    }

    /// Initiates a real purchase via RevenueCat. Returns:
    ///   - `.success`    : entitlement updated; caller can dismiss the paywall.
    ///   - `.userCancelled` : user closed the App Store sheet; stay silent.
    ///   - `.pending`    : Ask-to-Buy / SCA — Apple will confirm later. UI
    ///                     should tell the user we'll unlock Pro when it lands.
    /// Throws anything else (network, billing, product unavailable) so the
    /// caller can surface a localized error.
    func purchase(package: Package) async throws -> PurchaseOutcome {
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                return .userCancelled
            }
            updateIsPro(from: result.customerInfo)
            return .success
        } catch ErrorCode.paymentPendingError {
            return .pending
        } catch ErrorCode.purchaseCancelledError {
            return .userCancelled
        }
    }

    /// Restores past purchases on this Apple ID. `.restored` if a Pro
    /// entitlement is now active, `.nothingToRestore` otherwise. Throws
    /// on network / store errors.
    func restorePurchases() async throws -> RestoreOutcome {
        let info = try await Purchases.shared.restorePurchases()
        updateIsPro(from: info)
        return realIsPro ? .restored : .nothingToRestore
    }

    /// Trial/intro eligibility for a specific package. Returns `.unknown`
    /// until the offering loads and the eligibility check returns.
    func introEligibility(for package: Package) -> IntroEligibilityStatus {
        introEligibility[package.identifier] ?? .unknown
    }

    private func refreshIntroEligibility(for offering: Offering) async {
        let productIds = offering.availablePackages.map {
            $0.storeProduct.productIdentifier
        }
        guard !productIds.isEmpty else { return }

        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: productIds
        )

        var next: [String: IntroEligibilityStatus] = [:]
        for package in offering.availablePackages {
            let pid = package.storeProduct.productIdentifier
            if let eligibility = result[pid] {
                next[package.identifier] = eligibility.status
            }
        }
        self.introEligibility = next
    }

    private func updateIsPro(from info: CustomerInfo) {
        let active = info.entitlements[RevenueCatConfig.proEntitlementID]?.isActive == true
        if active != realIsPro {
            realIsPro = active
        }
    }

    /// Continuously reflects entitlement changes the SDK pushes (e.g. after
    /// a successful purchase or a restored receipt).
    private func observeCustomerInfo() async {
        for await info in Purchases.shared.customerInfoStream {
            updateIsPro(from: info)
        }
    }
}
