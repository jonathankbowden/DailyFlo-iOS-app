//
//  RevenueCatConfig.swift
//  DailyFlo
//
//  Single source of truth for the RevenueCat public API key. Read by
//  DailyFloApp at launch and nowhere else — never inline the key.
//

import Foundation

enum RevenueCatConfig {
    /// RevenueCat iOS public API key (starts with `appl_`). Safe to ship
    /// in the client binary.
    static let apiKey = "appl_vGQvYKnNpigXffSmwTBsybaDwwT"

    /// Entitlement identifier that grants Pro access. Note the literal space.
    static let proEntitlementID = "DailyFLO Pro"

    /// Offering identifier to fetch on launch.
    static let defaultOfferingID = "default"
}
