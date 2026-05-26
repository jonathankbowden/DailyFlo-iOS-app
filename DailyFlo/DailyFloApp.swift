//
//  DailyFloApp.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import GoogleSignIn
import Supabase
import SwiftUI

// MARK: - App State
enum AppState: Equatable {
    case splash
    case onboarding
    case signIn
    case main
}

@main
struct DailyFloApp: App {
    @State private var appState: AppState = .splash
    @State private var hasAdvancedFromSplash = false
    private let greeting = SplashGreeting.random

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Black base prevents white flash during crossfade transitions
                Color.black.ignoresSafeArea()
                switch appState {
                case .splash:
                    SplashView(greeting: greeting, onTapAdvance: {
                        advanceFromSplash()
                    })
                    .transition(.opacity)
                    .onAppear {
                        // Auto-advance after 8 seconds (logo 2.2s + nature greeting ~5s)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                            advanceFromSplash()
                        }
                    }

                case .onboarding:
                    OnboardingView(isOnboardingComplete: Binding(
                        get: { appState == .signIn || appState == .main },
                        set: { if $0 {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                appState = .signIn
                            }
                        }}
                    ))
                    .transition(.opacity)

                case .signIn:
                    SignInView(isSignedIn: Binding(
                        get: { appState == .main },
                        set: { if $0 {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                appState = .main
                            }
                        }}
                    ))
                    .transition(.opacity)

                case .main:
                    ContentView(greeting: greeting, animateFromSplash: true)
                        .transition(.opacity)
                        .task {
                            // TEMP: capture all screen screenshots - remove after use
                            if ProcessInfo.processInfo.arguments.contains("--screenshots") {
                                ScreenshotHelper.captureAllScreens()
                            }
                        }
                }
            }
            // Single smooth crossfade between app states
            .animation(.easeInOut(duration: 1.0), value: appState)
            .task {
                await observeAuthState()
            }
            .onOpenURL { url in
                // Delivers the OAuth redirect callback from Google Sign-In
                // back into the SDK so it can complete the flow.
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    // MARK: - Splash Navigation
    private func advanceFromSplash() {
        guard !hasAdvancedFromSplash else { return }
        hasAdvancedFromSplash = true

        appState = initialDestination()
    }

    /// Resolves the launch destination based on the current Supabase session
    /// and whether onboarding has been completed.
    private func initialDestination() -> AppState {
        let hasSession = SupabaseClient.shared.auth.currentSession != nil
        let onboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if hasSession {
            return .main
        } else if onboarded {
            return .signIn
        } else {
            return .onboarding
        }
    }

    /// Subscribes to Supabase auth state. Drives sign-out (anywhere → sign-in)
    /// and recovers from races where the initial session resolves after splash.
    private func observeAuthState() async {
        for await (event, session) in SupabaseClient.shared.auth.authStateChanges {
            switch event {
            case .initialSession:
                if session != nil, appState == .signIn {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        appState = .main
                    }
                }
            case .signedIn:
                if appState != .main {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        appState = .main
                    }
                }
            case .signedOut, .userDeleted:
                // Route to whichever state the user belongs in given current
                // local flags. After the in-app "Reset" wipes UserDefaults,
                // hasCompletedOnboarding is false and we land at onboarding;
                // otherwise we land at sign-in.
                let target: AppState = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") ? .signIn : .onboarding
                if appState != target {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        appState = target
                    }
                }
            case .tokenRefreshed, .passwordRecovery, .userUpdated, .mfaChallengeVerified:
                break
            @unknown default:
                break
            }
        }
    }
}

// MARK: - App Reset Helper (for testing)
extension DailyFloApp {
    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "userName")
    }
}
