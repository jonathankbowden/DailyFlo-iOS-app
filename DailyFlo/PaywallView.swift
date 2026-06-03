//
//  PaywallView.swift
//  DailyFlo
//
//  Subscription paywall driven by SubscriptionManager. Pulls $rc_annual +
//  $rc_monthly from the active "default" Offering, frames the annual with
//  a 1-month free trial, and routes the CTA through SubscriptionManager's
//  `purchase(package:)` (stubbed until the next prompt).
//

import RevenueCat
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let manager = SubscriptionManager.shared

    @State private var selectedPackage: Package?
    @State private var purchaseState: PurchaseState = .idle
    @State private var errorMessage: String?
    @State private var showError = false

    private enum PurchaseState: Equatable {
        case idle
        case purchasing
        case restoring
    }

    private static let termsURL = URL(string: "https://dailyflo.app/terms")!
    private static let privacyURL = URL(string: "https://dailyflo.app/privacy")!

    #if DEBUG
    /// Forces the trial copy/CTA into a deterministic state for previews,
    /// so the footer can be rendered in both "eligible" and "ineligible"
    /// configurations without depending on a live RC offering.
    struct PreviewTrialDemo {
        var price: String          // e.g. "$59.99"
        var periodSuffix: String   // e.g. "/year"
        var eligible: Bool
    }

    private let previewTrialDemo: PreviewTrialDemo?

    init(previewTrialDemo: PreviewTrialDemo? = nil) {
        self.previewTrialDemo = previewTrialDemo
    }
    #else
    init() {}
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: FloSpacing.lg) {
                header
                valueProps
                planSection
                primaryCTA
                if let disclosure = trialDisclosureCopy {
                    Text(disclosure)
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, FloSpacing.xs)
                }
                restoreButton
                legalLinks
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.md)
            .padding(.bottom, FloSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.floCream.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .onAppear { syncDefaultSelection() }
        .onChange(of: manager.loadState) { _, _ in syncDefaultSelection() }
        .alert("Something went wrong", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            // In-content drag grabber, matching PhaseDetailView. We render
            // our own rather than using `.presentationDragIndicator(.visible)`
            // so the affordance sits visually inside the sheet's cream
            // surface instead of floating above it on the dim backdrop.
            Capsule()
                .fill(Color.floGray.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, FloSpacing.sm)
                .padding(.bottom, FloSpacing.xs)
                .accessibilityHidden(true)

            HStack {
                Spacer()
                Button {
                    FloHaptics.light()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.floCharcoal.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.7))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, FloSpacing.md)
            .padding(.bottom, FloSpacing.xs)
        }
        .background(Color.floCream)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: FloSpacing.sm) {
            Text("DailyFLO Pro")
                .font(.floDisplayMedium)
                .foregroundColor(.floCharcoal)

            Text("A calmer way to know yourself.")
                .font(.floBodyLarge)
                .foregroundColor(.floGray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Value props

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            valueRow(
                icon: "moon.stars",
                title: "Your cycle, gently understood",
                subtitle: "Phase-aware insights, no clinical noise."
            )
            valueRow(
                icon: "heart.text.square",
                title: "Emotion journaling that listens",
                subtitle: "Voice or text, rooted in self-awareness."
            )
            valueRow(
                icon: "waveform",
                title: "Meditations with original music",
                subtitle: "A growing library to settle and restore."
            )
            valueRow(
                icon: "person.2",
                title: "Share with someone who matters",
                subtitle: "Invite a partner on your own terms."
            )
        }
        .padding(.horizontal, FloSpacing.xs)
    }

    private func valueRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: FloSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.floMint.opacity(0.5))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.floTeal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.floBodyLarge.weight(.semibold))
                    .foregroundColor(.floCharcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(subtitle)
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Plan section
    //
    // Emits Annual + Monthly (or their loading/empty/failed equivalents) as
    // DIRECT siblings of the outer VStack so each card participates in the
    // outer even spacing — no nested sub-VStack with its own spacing rules.

    @ViewBuilder
    private var planSection: some View {
        switch manager.loadState {
        case .idle, .loading:
            loadingCard
            loadingCard
        case .loaded:
            if let annual = manager.annualPackage {
                planCard(
                    package: annual,
                    title: "Annual",
                    priceLine: annualPriceLine(annual),
                    detailLine: annualDetailLine(annual),
                    badge: "Best value"
                )
            }
            if let monthly = manager.monthlyPackage {
                planCard(
                    package: monthly,
                    title: "Monthly",
                    priceLine: "\(monthly.storeProduct.localizedPriceString) / month",
                    detailLine: "Billed monthly. Cancel anytime.",
                    badge: nil
                )
            }
            if manager.annualPackage == nil && manager.monthlyPackage == nil {
                planMessage(
                    title: "Plans unavailable",
                    body: "The default offering didn't include $rc_annual or $rc_monthly packages.",
                    showRetry: true
                )
            }
        case .empty:
            planMessage(
                title: "Plans are loading",
                body: "Your subscription options are still propagating from the App Store. Give it a moment and try again.",
                showRetry: true
            )
        case .failed(let message):
            planMessage(
                title: "Couldn't load plans",
                body: message,
                showRetry: true
            )
        }
    }

    private var loadingCard: some View {
        RoundedRectangle(cornerRadius: FloRadius.lg)
            .fill(Color.white)
            .frame(height: 96)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.lg)
                    .stroke(Color.floLightGray, lineWidth: 1)
            )
            .shimmer()
    }

    private func planCard(
        package: Package,
        title: String,
        priceLine: String,
        detailLine: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedPackage?.identifier == package.identifier

        return Button {
            FloHaptics.selection()
            selectedPackage = package
        } label: {
            HStack(alignment: .center, spacing: FloSpacing.md) {
                selectionDot(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: FloSpacing.sm) {
                        Text(title)
                            .font(.floBodyLarge.weight(.semibold))
                            .foregroundColor(.floCharcoal)

                        if let badge {
                            Text(badge.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(.white)
                                .padding(.horizontal, FloSpacing.sm)
                                .padding(.vertical, 4)
                                .background(Color.floSage)
                                .clipShape(Capsule())
                        }
                    }

                    Text(priceLine)
                        .font(.floBodyMedium.weight(.medium))
                        .foregroundColor(.floCharcoal)

                    Text(detailLine)
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                }

                Spacer(minLength: 0)
            }
            .padding(FloSpacing.md)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.lg)
                    .stroke(isSelected ? Color.floSage : Color.floLightGray, lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(FloRadius.lg)
            .animation(FloAnimation.springGentle, value: isSelected)
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel("\(title) plan, \(priceLine)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func selectionDot(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.floSage : Color.floLightGray, lineWidth: 2)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle()
                    .fill(Color.floSage)
                    .frame(width: 12, height: 12)
            }
        }
    }

    private func planMessage(title: String, body: String, showRetry: Bool = false) -> some View {
        VStack(spacing: FloSpacing.sm) {
            Text(title)
                .font(.floBodyLarge.weight(.semibold))
                .foregroundColor(.floCharcoal)
            Text(body)
                .font(.floBodyMedium)
                .foregroundColor(.floGray)
                .multilineTextAlignment(.center)
            if showRetry {
                Button {
                    Task { await manager.fetchOffering() }
                } label: {
                    Text("Try again")
                }
                .buttonStyle(.floTertiary)
                .padding(.top, FloSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(FloSpacing.lg)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: FloRadius.lg)
                .stroke(Color.floLightGray, lineWidth: 1)
        )
        .cornerRadius(FloRadius.lg)
    }

    // MARK: - CTA + ancillary actions

    private var primaryCTA: some View {
        Button {
            Task { await handlePurchase() }
        } label: {
            HStack(spacing: FloSpacing.sm) {
                if purchaseState == .purchasing {
                    FloLoadingIndicator(size: 18, color: .white, lineWidth: 2.5)
                }
                Text(ctaTitle)
            }
        }
        .buttonStyle(.floPrimary(disabled: !canPurchase))
        .disabled(!canPurchase)
    }

    private var restoreButton: some View {
        Button {
            Task { await handleRestore() }
        } label: {
            HStack(spacing: 6) {
                if purchaseState == .restoring {
                    FloLoadingIndicator(size: 14, color: .floSage, lineWidth: 2)
                }
                Text("Restore purchases")
                    .font(.floBodyMedium.weight(.medium))
            }
        }
        .buttonStyle(.floTertiary)
        .disabled(purchaseState != .idle)
    }

    private var legalLinks: some View {
        HStack(spacing: FloSpacing.md) {
            Button("Terms") { openURL(Self.termsURL) }
            Text("•").foregroundColor(.floGray.opacity(0.5))
            Button("Privacy") { openURL(Self.privacyURL) }
        }
        .font(.floCaption)
        .foregroundColor(.floGray)
        .tint(.floGray)
    }

    // MARK: - Derived copy

    private var ctaTitle: String {
        if purchaseState == .purchasing { return "Working…" }
        #if DEBUG
        if let demo = previewTrialDemo {
            return demo.eligible ? "Start free month" : "Continue"
        }
        #endif
        if let selectedPackage, hasFreeTrial(selectedPackage) {
            return "Start free month"
        }
        return "Continue"
    }

    /// Compliance disclosure rendered directly under the CTA in the
    /// trial-eligible state. Nil when the user isn't trial-eligible (the
    /// "Continue" CTA stands alone — no disclosure required).
    private var trialDisclosureCopy: String? {
        #if DEBUG
        if let demo = previewTrialDemo {
            guard demo.eligible else { return nil }
            return "1 month free, then \(demo.price)\(demo.periodSuffix). Cancel anytime."
        }
        #endif
        guard let selectedPackage, hasFreeTrial(selectedPackage) else { return nil }
        let price = selectedPackage.storeProduct.localizedPriceString
        switch selectedPackage.packageType {
        case .annual:
            return "1 month free, then \(price)/year. Cancel anytime."
        case .monthly:
            return "1 month free, then \(price)/month. Cancel anytime."
        default:
            return "1 month free, then \(price). Cancel anytime."
        }
    }

    private var canPurchase: Bool {
        #if DEBUG
        if previewTrialDemo != nil { return purchaseState == .idle }
        #endif
        return selectedPackage != nil && purchaseState == .idle
    }

    /// True only when the product offers a free trial AND the current Apple ID
    /// is still eligible for it. Treats `.unknown` (eligibility check in
    /// flight) as eligible so the CTA doesn't briefly lie before settling —
    /// the CTA copy is best-effort and corrects itself when the check returns.
    private func hasFreeTrial(_ package: Package) -> Bool {
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.paymentMode == .freeTrial else { return false }
        switch manager.introEligibility(for: package) {
        case .ineligible, .noIntroOfferExists: return false
        case .eligible, .unknown: return true
        @unknown default: return true
        }
    }

    private func annualPriceLine(_ annual: Package) -> String {
        "\(annual.storeProduct.localizedPriceString) / year"
    }

    private func annualDetailLine(_ annual: Package) -> String {
        let yearly = annual.storeProduct.localizedPriceString
        if let perMonth = perMonthString(forAnnual: annual) {
            return "Just \(perMonth)/mo, billed yearly (\(yearly))."
        }
        return "Billed yearly. Cancel anytime."
    }

    private func perMonthString(forAnnual annual: Package) -> String? {
        let price = annual.storeProduct.price as NSDecimalNumber
        guard price.doubleValue > 0 else { return nil }
        let monthly = price.dividing(by: NSDecimalNumber(value: 12))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = annual.storeProduct.priceFormatter?.locale ?? .current
        return formatter.string(from: monthly)
    }

    // MARK: - Actions

    private func syncDefaultSelection() {
        guard selectedPackage == nil else { return }
        selectedPackage = manager.annualPackage ?? manager.monthlyPackage
    }

    private func handlePurchase() async {
        guard let package = selectedPackage, purchaseState == .idle else { return }
        FloHaptics.medium()
        purchaseState = .purchasing
        defer { purchaseState = .idle }

        do {
            let result = try await manager.purchase(package: package)
            switch result {
            case .success:
                FloHaptics.success()
                dismiss()
            case .userCancelled:
                break
            case .pending:
                // Ask-to-Buy / SCA — Apple hasn't approved the purchase yet.
                // CustomerInfo will flip when it does (handled by the
                // SDK's customerInfoStream); for now, just let the user know.
                errorMessage = "Your purchase is awaiting approval. We'll unlock Pro automatically once it goes through."
                showError = true
            }
        } catch {
            FloHaptics.error()
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handleRestore() async {
        guard purchaseState == .idle else { return }
        purchaseState = .restoring
        defer { purchaseState = .idle }

        do {
            switch try await manager.restorePurchases() {
            case .restored:
                FloHaptics.success()
                dismiss()
            case .nothingToRestore:
                errorMessage = "We didn't find an active DailyFLO Pro subscription on this Apple ID."
                showError = true
            }
        } catch {
            FloHaptics.error()
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#if DEBUG
#Preview("Live") {
    PaywallView()
}

#Preview("Trial eligible") {
    PaywallView(previewTrialDemo: .init(
        price: "$59.99",
        periodSuffix: "/year",
        eligible: true
    ))
}

#Preview("Trial ineligible") {
    PaywallView(previewTrialDemo: .init(
        price: "$59.99",
        periodSuffix: "/year",
        eligible: false
    ))
}

#Preview("iPhone SE — eligible", traits: .fixedLayout(width: 375, height: 667)) {
    PaywallView(previewTrialDemo: .init(
        price: "$59.99",
        periodSuffix: "/year",
        eligible: true
    ))
}
#endif
