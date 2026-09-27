//
//  SingleDayView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//
//  The day sheet: opened from a calendar day (and from Home's phase cards
//  for today). Phase header, MIND | BODY | SOUL tabs over a swipeable card
//  carousel, and LOG CYCLE + ADD/EDIT ENTRY at the bottom.
//

import SwiftUI

struct SingleDayView: View {
    let date: Date
    let onDismiss: () -> Void
    /// Non-nil only when presented from the calendar: called after a successful
    /// log so the calendar can collapse this sheet and confirm the change.
    let onLoggedCycle: (() -> Void)?

    @State private var selectedTab: PhaseContentTab = .body
    @State private var showLogCycle = false
    @State private var showJournalEntry = false
    @State private var didLogCycle = false

    private let cycleManager = CycleManager.shared
    private let journalManager = JournalManager.shared

    // Carousel geometry (Figma "Phases" 15:4208, 393pt frame).
    private let cardWidth: CGFloat = 332
    private let cardSpacing: CGFloat = 16

    init(date: Date, onDismiss: @escaping () -> Void, onLoggedCycle: (() -> Void)? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        self.onDismiss = onDismiss
        self.onLoggedCycle = onLoggedCycle
    }

    private var phase: CyclePhase { cycleManager.phase(for: date) }
    private var dayOfCycle: Int { cycleManager.dayOfCycle(for: date) }
    private var entry: JournalEntry? { journalManager.entry(for: date) }

    /// Two-way binding for `.scrollPosition(id:)` over the same state the tab
    /// row drives, so a tab tap scrolls the carousel and a swipe moves the tab.
    private var tabScrollBinding: Binding<PhaseContentTab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                guard let newValue, newValue != selectedTab else { return }
                FloHaptics.selection()
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()

            header
                .padding(.horizontal, 30)
                .padding(.top, FloSpacing.md)
                .padding(.bottom, 18)

            SegmentedCapsTabs(
                options: PhaseContentTab.allCases,
                selection: $selectedTab,
                title: { $0.rawValue },
                highlight: .floPhaseTab
            )

            carousel
                .padding(.top, 28)

            actionRow
                .padding(.horizontal, 30)
                .padding(.top, 20)
                .padding(.bottom, FloSpacing.md)
        }
        .background(Color.floBackground.ignoresSafeArea())
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
            // The one-entry-per-day resolver in JournalEntryView opens this
            // day's existing entry when there is one, else composes a new one.
            JournalEntryView(
                date: date,
                journalManager: journalManager,
                onDismiss: { showJournalEntry = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Text(phase.number)
                    .font(.floLunary(size: 54))
                    .foregroundStyle(Color.black)

                VStack(alignment: .leading, spacing: 3) {
                    Text(phase.name)
                        .font(.floLunary(size: 24))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(phase.subtitle.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.floDeepTeal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: FloSpacing.sm)

                SageCloseButton(action: onDismiss)
            }

            Text(statusLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.floGray)
        }
        .accessibilityElement(children: .contain)
    }

    private var statusLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        let logged = entry == nil ? "Nothing logged" : "Entry logged ✓"
        return "\(formatter.string(from: date)) · Day \(dayOfCycle) · \(logged)"
    }

    // MARK: - Carousel

    private var carousel: some View {
        GeometryReader { geo in
            let sideMargin = max(FloSpacing.md, (geo.size.width - cardWidth) / 2)
            ScrollView(.horizontal) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(PhaseContentTab.allCases, id: \.self) { tab in
                        PhaseTabCard(phase: phase, tab: tab)
                            .frame(width: min(cardWidth, geo.size.width - 2 * FloSpacing.md))
                            // Leave room under the card for its deep shadow.
                            .padding(.bottom, 30)
                            .id(tab)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: tabScrollBinding, anchor: .center)
            .scrollClipDisabled()
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 14) {
            OutlinedActionButton(title: "Log cycle", icon: "checkmark.circle") {
                showLogCycle = true
            }

            if entry == nil {
                OutlinedActionButton(title: "Add entry", icon: "plus") {
                    showJournalEntry = true
                }
            } else {
                OutlinedActionButton(title: "Edit entry", icon: "pencil") {
                    showJournalEntry = true
                }
            }
        }
    }
}

// MARK: - Phase tab card

/// One MIND / BODY / SOUL card: a photo strip, a caps label over a hairline,
/// and the phase copy, scrolling inside the card when it runs long.
struct PhaseTabCard: View {
    let phase: CyclePhase
    let tab: PhaseContentTab

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 62)
                .overlay {
                    Image(PhaseTabCard.photoName(for: phase, tab: tab))
                        .resizable()
                        .scaledToFill()
                }
                .clipped()

            Text("MY \(tab.rawValue)")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Color.black)
                .padding(.top, 20)
                .padding(.bottom, 14)

            FloHairline()
                .padding(.horizontal, 18)

            ScrollView(.vertical) {
                Text(PhaseTabCard.copy(for: phase, tab: tab))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black)
                    .lineSpacing(15 * 0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .floShadow(FloShadow.deep)
    }

    /// Photo for each phase + tab.
    static func photoName(for phase: CyclePhase, tab: PhaseContentTab) -> String {
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

    /// The tab's copy plus the extra paragraph a few tabs carry.
    static func copy(for phase: CyclePhase, tab: PhaseContentTab) -> String {
        let base = PhaseContent.content(for: phase, tab: tab).content
        guard let extra = additionalCopy(for: phase, tab: tab) else { return base }
        return base + "\n\n" + extra
    }

    private static func additionalCopy(for phase: CyclePhase, tab: PhaseContentTab) -> String? {
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
    Color.gray.sheet(isPresented: .constant(true)) {
        SingleDayView(date: Date(), onDismiss: {})
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
    }
}
