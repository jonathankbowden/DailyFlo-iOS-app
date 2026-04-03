//
//  DailyFloApp.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

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
        }
    }

    // MARK: - Splash Navigation
    private func advanceFromSplash() {
        guard !hasAdvancedFromSplash else { return }
        hasAdvancedFromSplash = true

        let targetState: AppState = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") ? .main : .onboarding
        appState = targetState
    }
}

// MARK: - App Reset Helper (for testing)
extension DailyFloApp {
    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "userName")
    }
}
