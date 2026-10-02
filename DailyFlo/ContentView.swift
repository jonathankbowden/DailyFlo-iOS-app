//
//  ContentView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

struct ContentView: View {
    // Tabs, left to right: 0=Calendar, 1=Journal, [+ FAB], 2=Profile, 3=Pause.
    // Calendar is the default tab on launch — it's the app's home screen.
    @State private var selectedTab = 0
    @State private var showJournalEntry = false
    @State private var fabScale: CGFloat = 1.0
    @State private var fabRotation: Double = 0
    @State private var previousTab = 0

    // Single Pro gate for the whole app. Entitlement is checked once, here at
    // the top level, right after onboarding/sign-in land the user on the tabs —
    // never per feature. `hasEvaluatedProGate` keeps it to one evaluation per
    // launch. Day 5 moves this gate to the end of onboarding; keeping it as one
    // modifier on the tab container is what makes that move a lift-and-shift.
    private let subs = SubscriptionManager.shared
    @State private var showProGate = false
    @State private var hasEvaluatedProGate = false

    var body: some View {
        ZStack {
            // Main content
            TabView(selection: $selectedTab) {
                CalendarView()
                    .tag(0)

                JournalView()
                    .tag(1)

                ProfileMainView()
                    .tag(2)

                MeditationView()
                    .tag(3)
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                previousTab = oldValue
            }

            // Custom Tab Bar with FAB
            VStack {
                Spacer()
                tabBarWithFAB
            }
        }
        .sheet(isPresented: $showJournalEntry) {
            JournalEntryView(
                journalManager: JournalManager.shared,
                onDismiss: {
                    showJournalEntry = false
                }
            )
        }
        .task {
            await evaluateProGate()
        }
        .onChange(of: subs.isPro) { _, isPro in
            // Purchased or restored while the gate is up — drop it immediately.
            if isPro { showProGate = false }
        }
        .sheet(isPresented: $showProGate) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    /// Resolves entitlement once per launch and presents the paywall when the
    /// user has neither an active subscription nor an active trial. In
    /// RevenueCat an in-progress free trial keeps the entitlement `isActive`,
    /// so `isPro` is true throughout the trial — this gate only fires once the
    /// trial has lapsed (or was never started). We refresh CustomerInfo first
    /// so a Pro/trial user never sees the paywall flash before state settles.
    private func evaluateProGate() async {
        guard !hasEvaluatedProGate else { return }
        hasEvaluatedProGate = true
        await subs.refreshCustomerInfo()
        if !subs.isPro {
            showProGate = true
        }
    }

    // MARK: - Tab Bar with centered FAB
    private var tabBarWithFAB: some View {
        GeometryReader { geometry in
            let bottomSafeArea = geometry.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                // Black tab bar with icons — L→R: Calendar, Journal, [+], Profile, Pause
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // Calendar — home / default tab
                        tabBarItemCustom(icon: "calendar", tag: 0, size: 24)

                        // Journal
                        tabBarItemCustom(icon: "journal", tag: 1, size: 24)

                        // Spacer for centered FAB alignment
                        Spacer()
                            .frame(width: 80)

                        // Profile (account & settings)
                        tabBarItemCustom(icon: "partner", tag: 2, size: 24)

                        // Pause (Meditation)
                        tabBarItemCustom(icon: "pause", tag: 3, size: 24)
                    }
                    .padding(.horizontal, FloSpacing.xl)
                    .frame(height: 88)

                    // Safe area spacer + indicators
                    ZStack(alignment: .bottom) {
                        Color.floCharcoal
                            .frame(height: bottomSafeArea)

                        // Active indicators - at very bottom
                        HStack(spacing: 0) {
                            tabIndicator(tag: 0)
                            tabIndicator(tag: 1)
                            Spacer().frame(width: 80)
                            tabIndicator(tag: 2)
                            tabIndicator(tag: 3)
                        }
                        .padding(.horizontal, FloSpacing.xl)
                        .padding(.bottom, 4)
                    }
                }
                .background(Color.floCharcoal)

                // Green FAB button - positioned to peek halfway out
                Button(action: {
                    FloHaptics.medium()
                    // Scale animation feedback
                    withAnimation(FloAnimation.springBouncy) {
                        fabScale = 0.9
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(FloAnimation.springBouncy) {
                            fabScale = 1.0
                        }
                    }
                    showJournalEntry = true
                }) {
                    ZStack {
                        // Flat fill — the canvas drops the glow behind the FAB.
                        Circle()
                            .fill(Color.floSage)
                            .frame(width: 72, height: 72)

                        // Icon
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(fabRotation))
                    }
                    .scaleEffect(fabScale)
                }
                .floHitTarget()
                .offset(y: -bottomSafeArea - 44 - 14)
                .accessibilityLabel("Add journal entry")
                .accessibilityHint("Opens journal entry screen to log your day")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func tabBarItemCustom(icon: String, tag: Int, size: CGFloat = 24) -> some View {
        Button(action: {
            // Haptic feedback for tab selection
            if selectedTab != tag {
                FloHaptics.selection()
                withAnimation(FloAnimation.tabSwitch) {
                    selectedTab = tag
                }
            }
        }) {
            VStack(spacing: FloSpacing.xs) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .foregroundColor(.white)
                    .opacity(selectedTab == tag ? 1.0 : 0.55)
                    .scaleEffect(selectedTab == tag ? 1.0 : 0.92)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabBarButtonStyle())
        .floHitTarget()
        .accessibilityLabel(tabAccessibilityLabel(for: tag))
        .accessibilityAddTraits(selectedTab == tag ? [.isButton, .isSelected] : .isButton)
    }

    private func tabBarItemSF(icon: String, tag: Int, size: CGFloat = 24) -> some View {
        Button(action: {
            if selectedTab != tag {
                FloHaptics.selection()
                withAnimation(FloAnimation.tabSwitch) {
                    selectedTab = tag
                }
            }
        }) {
            VStack(spacing: FloSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: size))
                    .foregroundColor(.white)
                    .opacity(selectedTab == tag ? 1.0 : 0.55)
                    .scaleEffect(selectedTab == tag ? 1.0 : 0.92)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabBarButtonStyle())
        .floHitTarget()
        .accessibilityLabel(tabAccessibilityLabel(for: tag))
        .accessibilityAddTraits(selectedTab == tag ? [.isButton, .isSelected] : .isButton)
    }

    private func tabAccessibilityLabel(for tag: Int) -> String {
        switch tag {
        case 0: return "Calendar, view your cycle"
        case 1: return "Journal, view your entries"
        case 2: return "Profile, your account and settings"
        case 3: return "Pause, guided meditation sessions"
        default: return "Tab"
        }
    }

    private func tabIndicator(tag: Int) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 3)
            .fill(selectedTab == tag ? Color.floSage : Color.clear)
            .frame(width: selectedTab == tag ? 32 : 0, height: 6)
            .frame(maxWidth: .infinity)
            .animation(FloAnimation.tabSwitch, value: selectedTab)
    }
}

// MARK: - Custom Tab Bar Button Style
struct TabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(FloAnimation.buttonPress, value: configuration.isPressed)
    }
}

// MARK: - Tab Views

struct JournalView: View {
    var body: some View {
        JournalBaseView()
    }
}

/// Pause tab entry. The meditation player opens directly — Pro access is no
/// longer checked here. Entitlement is gated once at the top level (see the
/// `evaluateProGate` modifier on `ContentView`), so by the time the user can
/// reach this tab the single launch-level check has already run.
struct MeditationView: View {
    var body: some View {
        MeditationMainView()
    }
}

#Preview {
    ContentView()
}
