//
//  SubscriptionDebugView.swift
//  DailyFlo
//
//  DEBUG-only inspector for the RevenueCat integration. Drop into any
//  screen during testing to verify isPro state, the resolved offering,
//  the monthly/annual package metadata, and to force isPro on/off without
//  routing through the App Store. Not shipped in release.
//

#if DEBUG

import SwiftUI
import RevenueCat

struct SubscriptionDebugView: View {
    @Bindable private var manager = SubscriptionManager.shared

    /// Mirrors `manager.debugProOverride`: nil → .fromRC, true → .forceOn, false → .forceOff.
    /// Bound through a Picker so flips propagate immediately to anything reading `isPro`.
    private enum ProSource: String, CaseIterable, Identifiable {
        case fromRC = "From RC"
        case forceOn = "Force ON"
        case forceOff = "Force OFF"
        var id: String { rawValue }
    }

    private var proSourceBinding: Binding<ProSource> {
        Binding(
            get: {
                switch manager.debugProOverride {
                case .none: return .fromRC
                case .some(true): return .forceOn
                case .some(false): return .forceOff
                }
            },
            set: { newValue in
                switch newValue {
                case .fromRC: manager.debugProOverride = nil
                case .forceOn: manager.debugProOverride = true
                case .forceOff: manager.debugProOverride = false
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RevenueCat Debug")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.secondary)

            row(label: "isPro", value: manager.isPro ? "true" : "false")
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

            Divider()
                .padding(.vertical, 2)

            HStack(alignment: .firstTextBaseline) {
                Text("Pro source")
                    .foregroundColor(.secondary)
                    .frame(width: 110, alignment: .leading)
                Picker("", selection: proSourceBinding) {
                    ForEach(ProSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Button("Refresh") {
                Task {
                    await manager.refreshCustomerInfo()
                    await manager.fetchOffering()
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.top, 4)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(12)
        .background(Color.black.opacity(0.04))
        .cornerRadius(8)
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
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
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

#Preview {
    SubscriptionDebugView()
        .padding()
}

#endif
