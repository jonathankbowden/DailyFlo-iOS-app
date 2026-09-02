//
//  DayPhaseView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 9/2/26.
//

import SwiftUI

/// Alternative single-day view, opened when a day is tapped on the calendar.
///
/// This is the "phase-first" treatment: the tapped day is framed by the phase
/// it falls in (numbered phase header, MIND / BODY / SOUL tabs, a tall photo
/// card with the phase teaching), with the day's two actions pinned at the
/// bottom. It is the alternative to `SingleDayView`, which is the
/// "dashboard" treatment (date header, phase card, activity, tips).
///
/// The layout mirrors the original phase-detail mock: sage circular back
/// button, phase title row, three-way tab selector, and an outlined button pair.
struct DayPhaseView: View {
    let date: Date
    let onDismiss: () -> Void
    /// Non-nil only when presented from the calendar: called after a successful
    /// log so the calendar can collapse this sheet and confirm the change.
    var onLoggedCycle: (() -> Void)? = nil

    @State private var selectedTab: PhaseContentTab = .mind
    @State private var showLogCycle = false
    @State private var showJournalEntry = false
    @State private var didLogCycle = false
    // Observed so the entry button flips from "Add" to "View" as soon as an
    // entry is saved for this day.
    @State private var journalManager = JournalManager.shared

    private let cycleManager = CycleManager.shared
    private let calendar = Calendar.current

    private var phase: CyclePhase { cycleManager.phase(for: date) }
    private var dayOfCycle: Int { cycleManager.dayOfCycle(for: date) }

    /// Days after today get no journal action: there is nothing to view and
    /// nothing to add yet.
    private var isFutureDay: Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
    }

    private var hasEntry: Bool {
        journalManager.entry(for: date) != nil
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date).uppercased()
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                divider(Color(hex: "E5E5E5"))

                phaseTitleView
                    .padding(.vertical, FloSpacing.xl)

                divider(Color(hex: "E5E5E5"))

                tabSelector

                divider(Color(hex: "707070"))

                // Swipeable MIND / BODY / SOUL pages
                TabView(selection: $selectedTab) {
                    ForEach(PhaseContentTab.allCases, id: \.self) { tab in
                        tabPage(for: tab)
                            .tag(tab)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(FloAnimation.springSnappy, value: selectedTab)
            }

            // Pinned day actions
            VStack {
                Spacer()
                actionButtons
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
                selectedDate: date,
                onSave: { startDate in
                    didLogCycle = true
                    Task { await CycleManager.shared.logCycle(startDate: startDate) }
                },
                onDismiss: { showLogCycle = false }
            )
        }
        .sheet(isPresented: $showJournalEntry) {
            // Target the day being viewed (not today). The one-entry-per-day
            // resolver opens this day's existing entry ("View Entry") or
            // composes a new one for it ("Add Entry").
            JournalEntryView(
                date: date,
                journalManager: journalManager,
                onDismiss: { showJournalEntry = false }
            )
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(alignment: .center) {
            Button(action: {
                FloHaptics.light()
                onDismiss()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.floSage)
                        .frame(width: 56, height: 56)

                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel("Back to calendar")

            Spacer()

            // Which day this phase teaching is framing
            VStack(alignment: .trailing, spacing: FloSpacing.xs) {
                Text(dateLabel)
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floCharcoal)
                    .tracking(1)

                Text("DAY \(dayOfCycle) OF CYCLE")
                    .font(.floCaption)
                    .foregroundColor(.floGray)
                    .tracking(1)
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.lg)
        .padding(.bottom, FloSpacing.xl)
    }

    // MARK: - Phase Title
    private var phaseTitleView: some View {
        HStack(alignment: .center, spacing: FloSpacing.md) {
            Text(phase.number)
                .font(.floSerif(size: 64))
                .foregroundColor(.floCharcoal)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase.name)
                    .font(.floDisplayMedium)
                    .foregroundColor(.floCharcoal)

                Text(phase.subtitle)
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floTeal)
                    .tracking(1.5)
            }

            Spacer()
        }
        .padding(.horizontal, FloSpacing.xl)
        .accessibilityElement(children: .combine)
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
                        .fontWeight(.bold)
                        .foregroundColor(.floCharcoal)
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.sm + 2)
                        .background(selectedTab == tab ? Color.floMint.opacity(0.6) : Color.clear)
                        .cornerRadius(FloRadius.xs)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(tab.rawValue) tab")
                .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)

                // Divider between tabs
                if index < allTabs.count - 1 {
                    Rectangle()
                        .fill(Color.floCharcoal)
                        .frame(width: 2, height: 32)
                }
            }
        }
        .padding(.horizontal, FloSpacing.xl)
        .padding(.vertical, FloSpacing.sm + 2)
    }

    // MARK: - Tab Page
    private func tabPage(for tab: PhaseContentTab) -> some View {
        ScrollView {
            contentCard(for: tab)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.xxl)
                .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Content Card
    private func contentCard(for tab: PhaseContentTab) -> some View {
        let content = PhaseContent.content(for: phase, tab: tab)

        return VStack(spacing: 0) {
            Image(photoName(for: tab))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 116)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(spacing: 0) {
                // Centered card title with a hairline underneath
                Text("MY \(tab.rawValue)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.floCharcoal)
                    .tracking(0.5)
                    .padding(.top, FloSpacing.xl)
                    .padding(.bottom, FloSpacing.md)

                divider(Color(hex: "E5E5E5"))
                    .padding(.horizontal, FloSpacing.xl)

                Text(content.content)
                    .font(.floBodyLarge)
                    .foregroundColor(.floCharcoal)
                    .lineSpacing(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FloSpacing.xl)
                    .padding(.top, FloSpacing.xl)
                    .padding(.bottom, FloSpacing.xxl)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: FloRadius.xl, style: .continuous))
        .shadow(
            color: FloShadow.large.color,
            radius: FloShadow.large.radius,
            x: FloShadow.large.x,
            y: FloShadow.large.y
        )
    }

    /// Nature photo matched to phase + tab. Same mapping as `PhaseDetailView`
    /// so the two treatments stay visually consistent.
    private func photoName(for tab: PhaseContentTab) -> String {
        switch (phase, tab) {
        case (.menstrual, .mind): return "rocks"
        case (.menstrual, .body): return "caves"
        case (.menstrual, .soul): return "starynight"
        case (.follicular, .mind): return "greencliff"
        case (.follicular, .body): return "treepath"
        case (.follicular, .soul): return "treetops"
        case (.ovulation, .mind): return "sunsetrocks"
        case (.ovulation, .body): return "surfer"
        case (.ovulation, .soul): return "rivertrees"
        case (.luteal, .mind): return "cloudystars"
        case (.luteal, .body): return "mtnpath"
        case (.luteal, .soul): return "nightsky"
        }
    }

    // MARK: - Action Buttons
    //
    // Left: LOG CYCLE, always.
    // Right, by the day's relationship to today:
    //   today or past, has an entry     → VIEW ENTRY
    //   today or past, no entry         → ADD ENTRY
    //   future                          → no button (LOG CYCLE spans the row)
    private var actionButtons: some View {
        HStack(spacing: 0) {
            outlinedAction(
                icon: "checkmark.circle",
                title: "LOG CYCLE",
                corners: isFutureDay ? .allCorners : [.topLeft, .bottomLeft]
            ) {
                FloHaptics.medium()
                showLogCycle = true
            }

            if !isFutureDay {
                outlinedAction(
                    icon: hasEntry ? "book" : "square.and.pencil",
                    title: hasEntry ? "VIEW ENTRY" : "ADD ENTRY",
                    corners: [.topRight, .bottomRight]
                ) {
                    FloHaptics.light()
                    showJournalEntry = true
                }
            }
        }
        .animation(FloAnimation.springSnappy, value: hasEntry)
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.md)
        .padding(.bottom, FloSpacing.xl)
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

    private func outlinedAction(
        icon: String,
        title: String,
        corners: UIRectCorner,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FloSpacing.sm + 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.floTeal)

                Text(title)
                    .font(.floTitle)
                    .foregroundColor(.floCharcoal)
                    .tracking(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FloSpacing.lg)
            .background(Color.white)
            .clipShape(RoundedCorner(radius: FloRadius.md, corners: corners))
            .overlay(
                RoundedCorner(radius: FloRadius.md, corners: corners)
                    .stroke(Color.floCharcoal.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.floPressed)
        .shadow(
            color: FloShadow.medium.color,
            radius: FloShadow.medium.radius,
            x: FloShadow.medium.x,
            y: FloShadow.medium.y
        )
        .accessibilityLabel(title.capitalized)
    }

    // MARK: - Helpers
    private func divider(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

#Preview("Day Phase — Today") {
    DayPhaseView(date: Date(), onDismiss: {})
}

#Preview("Day Phase — Future day") {
    DayPhaseView(
        date: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
        onDismiss: {}
    )
}
