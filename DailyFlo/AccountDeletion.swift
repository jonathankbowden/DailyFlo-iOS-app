//
//  AccountDeletion.swift
//  DailyFlo
//
//  In-app account deletion (App Store Guideline 5.1.1(v)). Runs the
//  `delete_my_account` Postgres RPC — which erases the caller's auth row and
//  every row they own in one transaction — then tears the app back down to a
//  fresh-install state (RevenueCat logout, local caches, Supabase sign-out), so
//  the app's auth listener routes to onboarding.
//

import Foundation
import Supabase

enum AccountDeletionError: LocalizedError {
    case rpcFailed(String)

    var errorDescription: String? {
        switch self {
        case .rpcFailed(let message): return message
        }
    }
}

@MainActor
enum AccountDeletion {
    /// Permanently deletes the signed-in user's account and returns the app to
    /// a fresh-install state. Throws if the server-side delete fails (caller
    /// should surface an error and stay signed in). Local teardown and sign-out
    /// only run after the server delete succeeds.
    static func deleteAccount() async throws {
        // 0. Abandon any queued offline journal writes FIRST, so a reconnect
        //    mid-deletion can't replay them and resurrect rows the server delete
        //    is about to erase.
        JournalManager.shared.clearPendingQueueForCurrentUser()

        // 1. Server: delete the auth user + every owned row in one transaction.
        //    auth.uid() inside the function guarantees it only touches the
        //    caller's data.
        do {
            try await SupabaseClient.shared.rpc("delete_my_account").execute()
        } catch {
            throw AccountDeletionError.rpcFailed(error.localizedDescription)
        }

        // 2. RevenueCat: drop the Supabase identity so the next person on this
        //    device doesn't inherit anything.
        await SubscriptionManager.shared.unlinkUser()

        // 3. Local caches → fresh install.
        clearLocalData()

        // 4. End the Supabase session. The app-level auth listener routes to
        //    onboarding because hasCompletedOnboarding was just wiped.
        try? await SupabaseClient.shared.auth.signOut()
    }

    /// Wipes every on-device trace of the user: the whole UserDefaults domain
    /// (onboarding flag, cycle/journal caches, userName…), the meditation
    /// catalog cache, and stored journal photos.
    private static func clearLocalData() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        MeditationCatalog.shared.clearDiskCache()
        JournalPhotoStore.deleteAll()
    }
}
