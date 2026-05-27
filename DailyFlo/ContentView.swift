//
//  ContentView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

struct ContentView: View {
    let greeting: SplashGreeting
    var animateFromSplash: Bool

    init(greeting: SplashGreeting = .random, animateFromSplash: Bool = false) {
        self.greeting = greeting
        self.animateFromSplash = animateFromSplash
    }

    // 0=Profile (dashboard + account), 1=Calendar, 2=Journal, 3=Meditation.
    // Profile is the default tab on launch per the locked planned-UI changes.
    @State private var selectedTab = 0
    @State private var showJournalEntry = false
    @State private var fabScale: CGFloat = 1.0
    @State private var fabRotation: Double = 0
    @State private var previousTab = 0

    var body: some View {
        ZStack {
            // Main content
            TabView(selection: $selectedTab) {
                ProfileTabView(greeting: greeting, animateFromSplash: animateFromSplash)
                    .tag(0)

                CalendarView()
                    .tag(1)

                JournalView()
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
    }

    // MARK: - Tab Bar with centered FAB
    private var tabBarWithFAB: some View {
        GeometryReader { geometry in
            let bottomSafeArea = geometry.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                // Black tab bar with icons — L→R: Profile, Calendar, [+], Journal, Pause
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // Profile (dashboard + account) — default tab
                        tabBarItemCustom(icon: "partner", tag: 0, size: 24)

                        // Calendar
                        tabBarItemCustom(icon: "calendar", tag: 1, size: 24)

                        // Spacer for centered FAB alignment
                        Spacer()
                            .frame(width: 80)

                        // Journal
                        tabBarItemSF(icon: "square.and.pencil", tag: 2, size: 22)

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
                        // Shadow layer
                        Circle()
                            .fill(Color.floSage)
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.floSage.opacity(0.4), radius: 12, x: 0, y: 6)

                        // Icon
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(fabRotation))
                    }
                    .scaleEffect(fabScale)
                }
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
        .accessibilityLabel(tabAccessibilityLabel(for: tag))
        .accessibilityAddTraits(selectedTab == tag ? [.isButton, .isSelected] : .isButton)
    }

    private func tabAccessibilityLabel(for tag: Int) -> String {
        switch tag {
        case 0: return "Profile, your dashboard and account"
        case 1: return "Calendar, view your cycle"
        case 2: return "Journal, view your entries"
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
        // Greeting + search header on top, with the 2D day-card grid below
        // when search is empty (or filtered results when it isn't).
        JournalBaseView()
    }
}

/// Profile tab: dashboard on top, account/stats/sign-out below — one scroll.
/// Composes HomeView and ProfileMainView in embedded mode so both views'
/// content flows inside a single outer ScrollView.
struct ProfileTabView: View {
    let greeting: SplashGreeting
    let animateFromSplash: Bool

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    HomeView(greeting: greeting, animateFromSplash: animateFromSplash, isEmbedded: true)

                    ProfileMainView(isEmbedded: true)

                    // Space for the tab bar
                    Spacer(minLength: 140)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
    }
}

struct MeditationView: View {
    var body: some View {
        MeditationMainView()
    }
}

#Preview {
    ContentView()
}
