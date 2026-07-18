//
//  PhaseDetailView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI
import UIKit

struct PhaseDetailView: View {
    let phase: CyclePhase
    let onDismiss: () -> Void
    /// Non-nil only when presented from the calendar: called after a successful
    /// log so the calendar can collapse this sheet and confirm the change.
    var onLoggedCycle: (() -> Void)? = nil

    @State private var selectedTab: PhaseContentTab = .body
    @State private var showLogCycle = false
    @State private var didLogCycle = false

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.floGray.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, FloSpacing.sm)
                    .padding(.bottom, FloSpacing.md)

                // Phase title section
                phaseTitleView

                // Top divider line
                Rectangle()
                    .fill(Color(hex: "E5E5E5"))
                    .frame(height: 1)

                // Tab selector
                tabSelector

                // Bottom divider line
                Rectangle()
                    .fill(Color(hex: "707070"))
                    .frame(height: 1)
                    .padding(.bottom, FloSpacing.sm)

                // Swipeable content pages
                TabView(selection: $selectedTab) {
                    ForEach(PhaseContentTab.allCases, id: \.self) { tab in
                        tabPageContent(for: tab)
                            .tag(tab)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(FloAnimation.springSnappy, value: selectedTab)
            }

            // Floating log cycle button
            VStack {
                Spacer()
                logCycleButton
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .sheet(isPresented: $showLogCycle, onDismiss: {
            // Fires after the LogCycle sheet finishes dismissing. If the user
            // actually logged (not cancelled) and we were presented from the
            // calendar, collapse this sheet too so we land back on the calendar.
            if didLogCycle {
                didLogCycle = false
                onLoggedCycle?()
            }
        }) {
            LogCycleView(
                selectedDate: Date(),
                onSave: { startDate in
                    didLogCycle = true
                    Task { await CycleManager.shared.logCycle(startDate: startDate) }
                },
                onDismiss: { showLogCycle = false }
            )
        }
    }

    // MARK: - Phase Title
    private var phaseTitleView: some View {
        HStack(alignment: .center, spacing: FloSpacing.md) {
            // Large phase number
            Text(phase.number)
                .font(.custom("LUNARY free", size: 64))
                .foregroundColor(.floCharcoal)

            // Phase name and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.name)
                    .font(.floDisplayMedium)
                    .foregroundColor(.floCharcoal)

                Text(phase.subtitle)
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floSage)
                    .tracking(1.5)
            }

            Spacer()
        }
        .padding(.horizontal, FloSpacing.lg)
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        let allTabs = PhaseContentTab.allCases
        return HStack(spacing: 0) {
            ForEach(Array(allTabs.enumerated()), id: \.element) { index, tab in
                Button(action: {
                    FloHaptics.selection()
                    withAnimation(FloAnimation.springSnappy) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.floLabel)
                        .fontWeight(.medium)
                        .foregroundColor(.floCharcoal)
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.sm)
                        .background(selectedTab == tab ? Color.floMint.opacity(0.5) : Color.clear)
                        .cornerRadius(FloRadius.sm)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(tab.rawValue) tab")
                .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)

                // Divider between tabs - hide when adjacent tab is selected
                if index < allTabs.count - 1 {
                    let nextTab = allTabs[index + 1]
                    if selectedTab != tab && selectedTab != nextTab {
                        Rectangle()
                            .fill(Color.floGray.opacity(0.3))
                            .frame(width: 1, height: 20)
                    }
                }
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.sm)
    }

    // MARK: - Tab Page Content
    private func tabPageContent(for tab: PhaseContentTab) -> some View {
        ScrollView {
            VStack(spacing: FloSpacing.lg) {
                contentCard(for: tab)

                // Additional tips
                tipsCard(for: tab)
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.md + 2)
            .padding(.bottom, 100)
        }
    }

    // Photo mapped to each phase + tab
    private func contentPhotoName(for tab: PhaseContentTab) -> String {
        switch (phase, tab) {
        // Menstrual — calm, grounded, introspective
        case (.menstrual, .mind): return "rocks"
        case (.menstrual, .body): return "caves"
        case (.menstrual, .soul): return "starynight"
        // Follicular — fresh, energetic, growth
        case (.follicular, .mind): return "greencliff"
        case (.follicular, .body): return "treepath"
        case (.follicular, .soul): return "treetops"
        // Ovulation — warm, vibrant, connected
        case (.ovulation, .mind): return "sunsetrocks"
        case (.ovulation, .body): return "surfer"
        case (.ovulation, .soul): return "rivertrees"
        // Luteal — quiet, reflective, deep
        case (.luteal, .mind): return "cloudystars"
        case (.luteal, .body): return "mtnpath"
        case (.luteal, .soul): return "nightsky"
        }
    }

    // MARK: - Content Card
    private func contentCard(for tab: PhaseContentTab) -> some View {
        let content = PhaseContent.content(for: phase, tab: tab)

        return VStack(spacing: 0) {
            // Image area - real nature photo matched to phase
            Image(contentPhotoName(for: tab))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 80)
                .clipped()
                .clipShape(
                    RoundedCorner(radius: FloRadius.lg, corners: [.topLeft, .topRight])
            )

            // Text content area
            VStack(alignment: .leading, spacing: FloSpacing.md) {
                Text(content.content)
                    .font(.floBodyMedium)
                    .foregroundColor(.floCharcoal)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                if let additionalContent = getAdditionalContent(for: phase, tab: tab) {
                    Rectangle()
                        .fill(Color(hex: "E5E5E5"))
                        .frame(height: 1)

                    Text(additionalContent)
                        .font(.floBodyMedium)
                        .foregroundColor(.floCharcoal)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(FloSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(
                RoundedCorner(radius: FloRadius.lg, corners: [.bottomLeft, .bottomRight])
            )
        }
        .shadow(color: FloShadow.large.color, radius: FloShadow.large.radius, x: FloShadow.large.x, y: FloShadow.large.y)
    }

    // MARK: - Tips Card
    private func tipsCard(for tab: PhaseContentTab) -> some View {
        let tips = phaseTips(for: tab)

        return VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("\(tab.rawValue) TIPS")
                .font(.floLabel)
                .fontWeight(.medium)
                .foregroundColor(.floGray)
                .tracking(1)

            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: FloSpacing.sm) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
                        .foregroundColor(.floSage)
                        .padding(.top, 3)

                    Text(tip)
                        .font(.floBodyMedium)
                        .foregroundColor(.floCharcoal)
                }
            }
        }
        .padding(FloSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.floMint.opacity(0.3))
        .cornerRadius(FloRadius.lg)
    }

    private func phaseTips(for tab: PhaseContentTab) -> [String] {
        switch (phase, tab) {
        case (.menstrual, .body):
            return [
                "Gentle yoga or stretching only",
                "Iron-rich foods: spinach, lentils, red meat",
                "Stay hydrated — herbal teas are great"
            ]
        case (.menstrual, .mind):
            return [
                "Journaling and reflection",
                "Set intentions for the month",
                "Reduce stimulation and screen time"
            ]
        case (.menstrual, .soul):
            return [
                "Meditation and breathwork",
                "Practice letting go of what no longer serves you",
                "Create space for stillness"
            ]
        case (.follicular, .body):
            return [
                "Great time for high-intensity workouts",
                "Your body handles carbs well now",
                "Try something new — dance, climbing, HIIT"
            ]
        case (.follicular, .mind):
            return [
                "Start new projects or learn something new",
                "Brainstorm and plan ahead",
                "Your creativity is peaking"
            ]
        case (.follicular, .soul):
            return [
                "Plant seeds of intention",
                "Connect with your deeper purpose",
                "Embrace optimism and fresh starts"
            ]
        case (.ovulation, .body):
            return [
                "Peak energy for challenging workouts",
                "Your body temperature rises slightly",
                "Stay active — you'll feel your best"
            ]
        case (.ovulation, .mind):
            return [
                "Schedule important conversations",
                "Your verbal skills are at their best",
                "Great time for presentations and pitches"
            ]
        case (.ovulation, .soul):
            return [
                "Deepen your relationships",
                "Acts of service and quality time",
                "Channel loving energy into creativity"
            ]
        case (.luteal, .body):
            return [
                "Lower intensity exercise is ideal",
                "Increase magnesium-rich foods",
                "Prioritize sleep and recovery"
            ]
        case (.luteal, .mind):
            return [
                "Focus on completing existing tasks",
                "Editing and organizing come naturally",
                "Honor your need for boundaries"
            ]
        case (.luteal, .soul):
            return [
                "Heightened intuition — trust it",
                "Journal and reflect on the cycle",
                "Prepare for renewal and release"
            ]
        }
    }

    // MARK: - Log Cycle Button
    private var logCycleButton: some View {
        VStack(spacing: 0) {
            Button(action: {
                FloHaptics.medium()
                showLogCycle = true
            }) {
                HStack(spacing: FloSpacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                    Text("LOG CYCLE")
                        .font(.floLabel)
                        .fontWeight(.semibold)
                        .tracking(1)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FloSpacing.md)
                .background(Color.floSage)
                .cornerRadius(FloRadius.full)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, FloSpacing.lg)
        }
        .padding(.top, FloSpacing.md)
        .padding(.bottom, FloSpacing.lg)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.4)
                    )
                )
        )
    }

    // MARK: - Additional Content Helper
    private func getAdditionalContent(for phase: CyclePhase, tab: PhaseContentTab) -> String? {
        switch (phase, tab) {
        case (.menstrual, .mind):
            return "Your testosterone levels will be on the rise, too, stimulating your libido. With this renewed energy, you can participate in more physical activities. Intimacy with your partner is enjoyable in this phase."
        case (.menstrual, .body):
            return "The follicular phase brings about a lower basal body temperature. You are also more sensitive to insulin, making this a good time to focus on carbohydrate-rich foods."
        case (.follicular, .mind):
            return "This is an excellent time to start new projects, have important conversations, or tackle challenging tasks that require mental clarity."
        default:
            return nil
        }
    }
}

#Preview {
    PhaseDetailView(phase: .menstrual, onDismiss: {})
}
