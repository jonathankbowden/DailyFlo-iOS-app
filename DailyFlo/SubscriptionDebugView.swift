//
//  SubscriptionDebugView.swift
//  DailyFlo
//
//  DEBUG-only inspector for the RevenueCat integration. Drop into any
//  screen during testing to verify isPro state, the resolved offering,
//  and the monthly/annual package metadata. Not shipped in release.
//

#if DEBUG

import SwiftUI
import RevenueCat

struct SubscriptionDebugView: View {
    private let manager = SubscriptionManager.shared

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
