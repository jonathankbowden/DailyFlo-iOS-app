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

    @State private var selectedTab = 0  // 0=Home, 1=Calendar, 2=Journal, 3=Profile, 4=Meditation
    @State private var showJournalEntry = false
    @State private var fabScale: CGFloat = 1.0
    @State private var fabRotation: Double = 0
    @State private var previousTab = 0

    var body: some View {
        ZStack {
            // Main content
            TabView(selection: $selectedTab) {
                HomeView(greeting: greeting, animateFromSplash: animateFromSplash)
                    .tag(0)

                CalendarView()
                    .tag(1)

                JournalView()
                    .tag(2)

                ProfileView()
                    .tag(3)

                MeditationView()
                    .tag(4)
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
                // Black tab bar with icons
                VStack(spacing: 0) {
                    // Main tab bar content
                    HStack(spacing: 0) {
                        // Home tab
                        tabBarItemCustom(icon: "home", tag: 0, size: 24)

                        // Calendar tab
                        tabBarItemCustom(icon: "calendar", tag: 1, size: 24)

                        // Spacer for FAB alignment
                        Spacer()
                            .frame(width: 80)

                        // Profile tab
                        tabBarItemCustom(icon: "partner", tag: 3, size: 24)

                        // Meditation tab
                        tabBarItemCustom(icon: "pause", tag: 4, size: 24)
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
                            tabIndicator(tag: 3)
                            tabIndicator(tag: 4)
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
        case 0: return "Home, your daily dashboard"
        case 1: return "Calendar, view your cycle"
        case 2: return "Journal, view your entries"
        case 3: return "Profile, settings and stats"
        case 4: return "Meditation, guided sessions"
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
// Each tab now uses its full implementation

struct JournalView: View {
    var body: some View {
        EmotionJournalView()
    }
}

struct ProfileView: View {
    var body: some View {
        ProfileMainView()
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
