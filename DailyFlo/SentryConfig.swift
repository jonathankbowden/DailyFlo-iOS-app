//
//  SentryConfig.swift
//  DailyFlo
//
//  Single source of truth for Sentry crash reporting. `start()` is called as
//  early as possible from DailyFloApp.init(). Deliberately conservative about
//  what leaves the device: no screenshots, no view hierarchy, no default PII —
//  journal and cycle data must never ride along in a crash report. The only
//  identity attached is the Supabase auth UUID, set/cleared through the central
//  auth loop via `setUser(id:)` / `clearUser()`.
//

import Foundation
import Sentry

enum SentryConfig {
    /// Sentry DSN for the DailyFLO project. Safe to ship in the client binary.
    static let dsn = "https://269694ef8653e707145522a91ffc017a@o4511412965933056.ingest.us.sentry.io/4511412975566848"

    /// Boots the Sentry SDK. Call once, as early as possible in app launch.
    static func start() {
        SentrySDK.start { options in
            options.dsn = dsn

            // Never let private content leave the phone in a crash report.
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // release = marketing version + build number (e.g. "1.0+20").
            options.releaseName = releaseName

            #if DEBUG
            options.environment = "debug"
            options.tracesSampleRate = 1.0
            #else
            options.environment = "production"
            options.tracesSampleRate = 0.2
            #endif
        }
    }

    /// Ties subsequent events to the Supabase auth UUID — and nothing else
    /// (no email, no name). Called from the central auth loop on sign-in.
    static func setUser(id: String) {
        let user = User()
        user.userId = id
        SentrySDK.setUser(user)
    }

    /// Drops the attached identity so later events are anonymous. Called on
    /// sign-out and account deletion.
    static func clearUser() {
        SentrySDK.setUser(nil)
    }

    /// Marketing version + build number, e.g. "1.0+20".
    private static var releaseName: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version)+\(build)"
    }
}
