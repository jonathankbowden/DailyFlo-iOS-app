//
//  SubscriptionManager.swift
//  DailyFlo
//
//  Thin wrapper around the RevenueCat SDK. Owns the app's view of
//  subscription state (isPro), the fetched "default" Offering, and the
//  monthly + annual packages a paywall will eventually display.
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

    private(set) var isPro: Bool = false
    private(set) var offering: Offering?
    private(set) var loadState: LoadState = .idle

    /// `$rc_monthly` package on the active offering, if present.
    var monthlyPackage: Package? { offering?.monthly }
    /// `$rc_annual` package on the active offering, if present.
    var annualPackage: Package? { offering?.annual }

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
    /// after first config).
    func fetchOffering() async {
        loadState = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            let resolved = offerings.all[RevenueCatConfig.defaultOfferingID]
                ?? offerings.current

            if let resolved {
                self.offering = resolved
                self.loadState = .loaded
            } else {
                self.offering = nil
                self.loadState = .empty
            }
        } catch {
            self.offering = nil
            self.loadState = .failed(error.localizedDescription)
        }
    }

    /// Pulls the latest CustomerInfo and recomputes `isPro`. Safe to call
    /// repeatedly — invoked on launch and whenever the app foregrounds.
    func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            updateIsPro(from: info)
        } catch {
            // Non-fatal: leave the last known `isPro` value in place rather
            // than flipping the user out of Pro on a transient network blip.
        }
    }

    private func updateIsPro(from info: CustomerInfo) {
        let active = info.entitlements[RevenueCatConfig.proEntitlementID]?.isActive == true
        if active != isPro {
            isPro = active
        }
    }

    /// Continuously reflects entitlement changes the SDK pushes (e.g. after
    /// a successful purchase or a restored receipt).
    private func observeCustomerInfo() async {
        for await info in Purchases.shared.customerInfoStream {
            updateIsPro(from: info)
        }
    }

    // MARK: - Purchase

    enum PurchaseResult: Equatable {
        case success
        case userCancelled
    }

    enum PurchaseError: LocalizedError {
        case notImplemented
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .notImplemented:
                return "Purchases aren't wired up yet — the full flow lands in the next build step."
            case .underlying(let message):
                return message
            }
        }
    }

    /// Stub. The real implementation will call `Purchases.shared.purchase(package:)`,
    /// map the result, and refresh `isPro` via the customerInfoStream.
    func purchase(package: Package) async throws -> PurchaseResult {
        throw PurchaseError.notImplemented
    }
}
