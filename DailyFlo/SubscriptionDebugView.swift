//
//  SubscriptionDebugView.swift
//  DailyFlo
//
//  DEBUG-only inspector for the RevenueCat integration. Surfaces the
//  current isPro state, the resolved offering, the monthly/annual package
//  metadata, and a three-way override (From RC / Force ON / Force OFF)
//  so the entitlement gate can be flipped on-device. Not shipped in release.
//

#if DEBUG

import RevenueCat
import SwiftUI

struct SubscriptionDebugView: View {
    private let manager = SubscriptionManager.shared

    /// When presented as a sheet/full-screen, the host passes its dismiss
    /// callback through. Embedded uses (e.g. dropped into another screen
    /// for inline inspection) leave it nil so no Done bar renders.
    var onClose: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FloSpacing.lg) {
                if onClose != nil {
                    titleBar
                }
                gateOverrideCard
                liveGatePreview
                inspectorCard
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.md)
            .padding(.bottom, FloSpacing.xxl)
        }
        .background(Color.floCream.ignoresSafeArea())
    }

    // MARK: - Title bar (sheet mode only)

    private var titleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer")
                    .font(.floDisplaySmall)
                    .foregroundColor(.floCharcoal)
                Text("RevenueCat & subscription gate")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
            }
            Spacer()
            Button {
                FloHaptics.light()
                onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.floCharcoal.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, FloSpacing.sm)
    }

    // MARK: - Gate override

    private var gateOverrideCard: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            sectionLabel("Pro gate override")

            Picker("Override", selection: overrideBinding) {
                Text("From RC").tag(Optional<Bool>.none)
                Text("Force ON").tag(Optional<Bool>(true))
                Text("Force OFF").tag(Optional<Bool>(false))
            }
            .pickerStyle(.segmented)

            Text(overrideExplainer)
                .font(.floBodySmall)
                .foregroundColor(.floGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FloRadius.lg)
                .stroke(Color.floLightGray, lineWidth: 1)
        )
    }

    private var overrideBinding: Binding<Bool?> {
        Binding(
            get: { manager.debugProOverride },
            set: { newValue in
                FloHaptics.selection()
                manager.debugProOverride = newValue
            }
        )
    }

    private var overrideExplainer: String {
        switch manager.debugProOverride {
        case .none:
            return "Following RevenueCat. The gate reflects the user's real entitlement."
        case .some(true):
            return "Pinned ON. Every Pro-gated surface should treat the user as a subscriber."
        case .some(false):
            return "Pinned OFF. Every Pro-gated surface should treat the user as free."
        }
    }

    // MARK: - Live gate preview

    private var liveGatePreview: some View {
        let isPro = manager.isPro

        return HStack(spacing: FloSpacing.md) {
            ZStack {
                Circle()
                    .fill(isPro ? Color.floSage.opacity(0.2) : Color.floGray.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: isPro ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isPro ? .floSage : .floGray)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isPro ? "Pro features unlocked" : "Pro features locked")
                    .font(.floBodyLarge.weight(.semibold))
                    .foregroundColor(.floCharcoal)
                Text(isPro ? "manager.isPro == true" : "manager.isPro == false")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.floGray)
            }

            Spacer(minLength: 0)
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FloRadius.lg)
                .stroke(isPro ? Color.floSage : Color.floLightGray, lineWidth: isPro ? 2 : 1)
        )
        .animation(FloAnimation.springGentle, value: isPro)
    }

    // MARK: - Inspector

    private var inspectorCard: some View {
        VStack(alignment: .leading, spacing: FloSpacing.sm) {
            sectionLabel("RevenueCat snapshot")

            row(label: "isPro (effective)", value: manager.isPro ? "true" : "false")
            row(label: "RC truth (realIsPro)", value: manager.rcIsProDebugDescription)
            row(label: "State", value: stateString)
            row(label: "Offering", value: manager.offering?.identifier ?? "—")

            if let monthly = manager.monthlyPackage {
                packageRow(label: "$rc_monthly", package: monthly)
            } else {
                row(label: "$rc_monthly", value: "—")
            }

            if let annual = manager.annualPackage {
                packageRow(label: "$rc_annual", package: annual)
            } else {
                row(label: "$rc_annual", value: "—")
            }

            Button("Refresh") {
                Task {
                    await manager.refreshCustomerInfo()
                    await manager.fetchOffering()
                }
            }
            .buttonStyle(.floTertiary)
            .padding(.top, FloSpacing.xs)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FloRadius.lg)
                .stroke(Color.floLightGray, lineWidth: 1)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.floGray)
    }

    private var stateString: String {
        switch manager.loadState {
        case .idle: return "idle"
        case .loading: return "loading…"
        case .loaded: return "loaded"
        case .empty: return "empty (products still propagating?)"
        case .failed(let msg): return "failed: \(msg)"
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.floGray)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundColor(.floCharcoal)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func packageRow(label: String, package: Package) -> some View {
        let product = package.storeProduct
        return row(
            label: label,
            value: "\(product.productIdentifier) — \(product.localizedPriceString)"
        )
    }
}

// Bridge so the inspector can show whatever the manager privately knows
// about the underlying RC truth without exposing the raw stored property.
private extension SubscriptionManager {
    var rcIsProDebugDescription: String {
        // The override-aware `isPro` plus the override state are enough to
        // reconstruct realIsPro: when override is nil, isPro == realIsPro;
        // otherwise the override is what the app sees and the RC truth is
        // whatever the last refresh produced. We can't read the private
        // field directly, so derive it by reading `isPro` under a "follow
        // RC" lens.
        if debugProOverride == nil {
            return isPro ? "true" : "false"
        }
        // When pinned, we don't currently expose realIsPro. Reflect that
        // honestly — the value lives in CustomerInfo and the inspector's
        // Refresh button is the way to surface it.
        return "(hidden — flip to From RC to see)"
    }
}

#Preview {
    SubscriptionDebugView(onClose: {})
}

#endif
