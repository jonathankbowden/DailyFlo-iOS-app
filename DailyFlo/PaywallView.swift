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

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: FloSpacing.xl) {
                    header
                    valueProps
                    planSection
                    Spacer(minLength: FloSpacing.sm)
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.lg)
                .padding(.bottom, FloSpacing.xxxl)
            }

            VStack {
                topBar
                Spacer()
                footer
            }
        }
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
        .padding(.top, FloSpacing.sm)
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
        .padding(.top, FloSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Value props

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            valueRow(
                icon: "moon.stars",
                title: "Your cycle, gently understood",
                subtitle: "Phase-aware insights and predictions, no clinical noise."
            )
            valueRow(
                icon: "heart.text.square",
                title: "Emotion journaling that listens",
                subtitle: "Voice or text, with a framework rooted in self-awareness."
            )
            valueRow(
                icon: "waveform",
                title: "Meditations with original music",
                subtitle: "A growing library to settle, restore, and reconnect."
            )
            valueRow(
                icon: "person.2",
                title: "Share with someone who matters",
                subtitle: "Invite a partner or parent on the terms you choose."
            )
        }
        .padding(.horizontal, FloSpacing.xs)
    }

    private func valueRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: FloSpacing.md) {
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
                Text(subtitle)
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Plan section

    @ViewBuilder
    private var planSection: some View {
        switch manager.loadState {
        case .idle, .loading:
            loadingPlans
        case .loaded:
            loadedPlans
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

    private var loadingPlans: some View {
        VStack(spacing: FloSpacing.md) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: FloRadius.lg)
                    .fill(Color.white)
                    .frame(height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloRadius.lg)
                            .stroke(Color.floLightGray, lineWidth: 1)
                    )
                    .shimmer()
            }
        }
    }

    private var loadedPlans: some View {
        VStack(spacing: FloSpacing.md) {
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
        }
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

    // MARK: - Footer (CTA + restore + legal)

    private var footer: some View {
        VStack(spacing: FloSpacing.md) {
            trialLine
            primaryCTA
            restoreButton
            legalLinks
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.bottom, FloSpacing.lg)
        .padding(.top, FloSpacing.md)
        .background(
            LinearGradient(
                colors: [Color.floCream.opacity(0), Color.floCream],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    private var trialLine: some View {
        Group {
            if let copy = trialCopy {
                Text(copy)
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
                    .multilineTextAlignment(.center)
            }
        }
    }

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
        if let selectedPackage, hasFreeTrial(selectedPackage) {
            return "Start free month"
        }
        return "Continue"
    }

    private var trialCopy: String? {
        guard let selectedPackage else { return nil }
        let price = selectedPackage.storeProduct.localizedPriceString
        if hasFreeTrial(selectedPackage) {
            switch selectedPackage.packageType {
            case .annual:
                return "1 month free, then \(price) per year. Cancel anytime."
            case .monthly:
                return "1 month free, then \(price) per month. Cancel anytime."
            default:
                return "1 month free, then \(price). Cancel anytime."
            }
        }
        switch selectedPackage.packageType {
        case .annual:
            return "\(price) per year. Cancel anytime."
        case .monthly:
            return "\(price) per month. Cancel anytime."
        default:
            return "\(price). Cancel anytime."
        }
    }

    private var canPurchase: Bool {
        selectedPackage != nil && purchaseState == .idle
    }

    private func hasFreeTrial(_ package: Package) -> Bool {
        guard let intro = package.storeProduct.introductoryDiscount else { return false }
        return intro.paymentMode == .freeTrial
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
        await manager.refreshCustomerInfo()
        if manager.isPro {
            FloHaptics.success()
            dismiss()
        } else {
            errorMessage = "We didn't find an active subscription on this Apple ID."
            showError = true
        }
    }
}

#if DEBUG
#Preview {
    PaywallView()
}
#endif
