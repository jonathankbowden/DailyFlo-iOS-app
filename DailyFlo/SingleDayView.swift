//
//  SingleDayView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Day Log Data
struct DayLogData {
    let date: Date
    let phase: CyclePhase
    let dayOfCycle: Int
    let isPeriodDay: Bool
    let journalEntry: String?
    let meditatedMinutes: Int?
    let mood: String?
}

// MARK: - Single Day View
struct SingleDayView: View {
    let date: Date
    var phase: CyclePhase = .follicular
    var dayOfCycle: Int = 1
    let onDismiss: () -> Void

    @State private var currentDate: Date
    @State private var showLogCycle = false
    @State private var showJournalEntry = false
    @State private var journalManager = JournalManager.shared

    private let cycleManager = CycleManager.shared
    private let calendar = Calendar.current

    // Number of days to allow swiping in each direction
    private let swipeRange = 60

    init(date: Date, phase: CyclePhase = .follicular, dayOfCycle: Int = 1, onDismiss: @escaping () -> Void) {
        self.date = date
        self.phase = phase
        self.dayOfCycle = dayOfCycle
        self.onDismiss = onDismiss
        self._currentDate = State(initialValue: Calendar.current.startOfDay(for: date))
    }

    // Generate array of dates around the initial date (normalized to start of day)
    private var datePages: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-swipeRange...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    private func dayData(for pageDate: Date) -> DayLogData {
        let entries = journalManager.entries(for: pageDate)
        let journalText = entries.first?.note
        let mood = entries.first?.emotion.rawValue
        let pagePhase = cycleManager.phase(for: pageDate)

        return DayLogData(
            date: pageDate,
            phase: pagePhase,
            dayOfCycle: cycleManager.dayOfCycle(for: pageDate),
            isPeriodDay: pagePhase == .menstrual,
            journalEntry: journalText,
            meditatedMinutes: nil,
            mood: mood
        )
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }

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

                TabView(selection: $currentDate) {
                    ForEach(datePages, id: \.self) { pageDate in
                        dayPageContent(for: pageDate)
                            .tag(pageDate)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            // Floating action buttons
            VStack {
                Spacer()
                floatingActionButtons
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .sheet(isPresented: $showLogCycle) {
            LogCycleView(
                selectedDate: currentDate,
                onSave: {},
                onDismiss: { showLogCycle = false }
            )
        }
        .sheet(isPresented: $showJournalEntry) {
            JournalEntryView(
                journalManager: JournalManager.shared,
                onDismiss: { showJournalEntry = false }
            )
        }
    }

    // MARK: - Day Page Content
    private func dayPageContent(for pageDate: Date) -> some View {
        let data = dayData(for: pageDate)

        return ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: FloSpacing.lg) {
                    // Header with date
                    headerSection(for: pageDate)

                    // Phase info card
                    phaseInfoCard(for: data)

                    // Activity summary
                    activitySummary(for: data)

                    // Journal snippet
                    if data.journalEntry != nil {
                        journalSnippet(for: data)
                    }

                    // Tips for the day
                    tipsSection(for: data)

                    Spacer()
                        .frame(height: 80)
                }
                .padding(.horizontal, FloSpacing.lg)
            }
        }
    }

    // MARK: - Header Section
    private func headerSection(for pageDate: Date) -> some View {
        VStack(spacing: FloSpacing.xs) {
            Text(dateFormatter.string(from: pageDate))
                .font(.floDisplayLarge)
                .foregroundColor(.floCharcoal)

            Text(dayFormatter.string(from: pageDate))
                .font(.floBodyMedium)
                .foregroundColor(.floGray)
        }
        .padding(.top, FloSpacing.sm)
    }

    // MARK: - Phase Info Card
    private func phaseInfoCard(for data: DayLogData) -> some View {
        VStack(spacing: 0) {
            // Header with phase color
            HStack {
                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    Text("DAY \(data.dayOfCycle) OF CYCLE")
                        .font(.floLabel)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(1)

                    Text(data.phase.name)
                        .font(.floDisplaySmall)
                        .foregroundColor(.white)
                }

                Spacer()

                // Phase number
                Text(data.phase.number)
                    .font(.custom("LUNARY free", size: 48))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(FloSpacing.lg)
            .background(data.phase.color)

            // Phase description
            VStack(alignment: .leading, spacing: FloSpacing.sm) {
                Text(data.phase.subtitle)
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floSage)
                    .tracking(1)

                Text(phaseDescription(for: data.phase))
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
                    .lineSpacing(4)
            }
            .padding(FloSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .cornerRadius(FloRadius.xl)
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func phaseDescription(for phase: CyclePhase) -> String {
        switch phase {
        case .menstrual:
            return "Your body is renewing. Rest and gentle movement are your friends today."
        case .follicular:
            return "Energy is rising! Great time for new projects and physical activity."
        case .ovulation:
            return "You're at your peak. Communication and connection flow naturally."
        case .luteal:
            return "Time to wrap up projects and prepare for rest. Honor your need for boundaries."
        }
    }

    // MARK: - Activity Summary
    private func activitySummary(for data: DayLogData) -> some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("TODAY'S ACTIVITY")
                .font(.floLabel)
                .fontWeight(.medium)
                .foregroundColor(.floGray)
                .tracking(1)

            HStack(spacing: FloSpacing.md) {
                // Mood indicator
                activityItem(
                    icon: "face.smiling.fill",
                    label: "Mood",
                    value: data.mood ?? "Not logged",
                    color: .floSage
                )

                // Meditation
                activityItem(
                    icon: "leaf.fill",
                    label: "Meditation",
                    value: data.meditatedMinutes != nil ? "\(data.meditatedMinutes!) min" : "None",
                    color: .floTeal
                )
            }
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    private func activityItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: FloSpacing.xs) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }

            Text(label)
                .font(.floLabel)
                .foregroundColor(.floGray)

            Text(value)
                .font(.floBodySmall)
                .fontWeight(.medium)
                .foregroundColor(.floCharcoal)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Journal Snippet
    private func journalSnippet(for data: DayLogData) -> some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            HStack {
                Text("JOURNAL ENTRY")
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floGray)
                    .tracking(1)

                Spacer()

                Button(action: {
                    showJournalEntry = true
                }) {
                    Text("Edit")
                        .font(.floBodySmall)
                        .foregroundColor(.floSage)
                }
            }

            Text(data.journalEntry ?? "")
                .font(.floBodyMedium)
                .foregroundColor(.floCharcoal)
                .lineSpacing(6)
                .lineLimit(4)

            if (data.journalEntry?.count ?? 0) > 150 {
                Button(action: {
                    showJournalEntry = true
                }) {
                    Text("Read more...")
                        .font(.floBodySmall)
                        .foregroundColor(.floSage)
                }
            }
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Tips Section
    private func tipsSection(for data: DayLogData) -> some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("TIPS FOR TODAY")
                .font(.floLabel)
                .fontWeight(.medium)
                .foregroundColor(.floGray)
                .tracking(1)

            ForEach(phaseTips(for: data.phase), id: \.self) { tip in
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
        .background(Color.floMint.opacity(0.3))
        .cornerRadius(FloRadius.lg)
    }

    private func phaseTips(for phase: CyclePhase) -> [String] {
        switch phase {
        case .menstrual:
            return [
                "Prioritize rest and sleep",
                "Gentle yoga or stretching",
                "Iron-rich foods like spinach and lentils"
            ]
        case .follicular:
            return [
                "Great day for high-intensity workouts",
                "Start new projects or learn something new",
                "Your body handles carbs well now"
            ]
        case .ovulation:
            return [
                "Schedule important meetings or conversations",
                "Peak time for social activities",
                "Your verbal skills are at their best"
            ]
        case .luteal:
            return [
                "Focus on completing existing tasks",
                "Lower intensity exercise is ideal",
                "Increase magnesium-rich foods"
            ]
        }
    }

    // MARK: - Floating Action Buttons
    private var floatingActionButtons: some View {
        VStack(spacing: 0) {
            HStack(spacing: FloSpacing.md) {
                // Log Day button
                Button(action: {
                    FloHaptics.medium()
                    showLogCycle = true
                }) {
                    HStack(spacing: FloSpacing.sm) {
                        Image(systemName: "checkmark.circle")
                        Text("Log Day")
                    }
                    .font(.floButton)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.floSage)
                    .cornerRadius(FloRadius.full)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }

                // Journal button
                Button(action: {
                    FloHaptics.light()
                    showJournalEntry = true
                }) {
                    HStack(spacing: FloSpacing.sm) {
                        Image(systemName: "square.and.pencil")
                        Text("Journal")
                    }
                    .font(.floButton)
                    .foregroundColor(.floSage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.white)
                    .cornerRadius(FloRadius.full)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloRadius.full)
                            .stroke(Color.floSage, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
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
}

#Preview {
    SingleDayView(date: Date(), phase: .follicular, dayOfCycle: 8, onDismiss: {})
}
