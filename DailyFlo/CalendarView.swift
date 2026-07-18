//
//  CalendarView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

struct CalendarView: View {
    @State private var selectedDate: Date? = nil
    @State private var showPhaseDetail = false
    @State private var showSingleDay = false
    @State private var selectedPhase: CyclePhase = .menstrual

    // Drives scrollPosition anchoring; starts on the current month (offset 0).
    @State private var scrolledMonth: Int? = 0

    // Log-confirmation choreography. When a log-cycle sheet collapses back to the
    // calendar, `pendingLogConfirmation` is set so the sheet's onDismiss can play
    // a one-shot soft emphasis (`emphasizeLoggedStart`) on the new start day.
    @State private var pendingLogConfirmation = false
    @State private var emphasizeLoggedStart = false

    private let cycleManager = CycleManager.shared
    private let calendar = Calendar.current
    private let daysOfWeek = ["M", "T", "W", "T", "F", "S", "S"]

    // Month window: 6 past (back-extrapolated), the current month, and the
    // forward horizon. Rendered lazily; the current month is the open position.
    private let pastMonthsToShow = 6
    private let futureMonthsToShow = 12

    // Offsets from the current month: -6 ... (futureMonthsToShow - 1). 0 = current.
    private var monthOffsets: [Int] { Array(-pastMonthsToShow..<futureMonthsToShow) }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Greeting & Phase Info
                greetingSection

                // Full-width divider line (top of days row)
                Rectangle()
                    .fill(Color(hex: "E5E5E5"))
                    .frame(height: 1)
                    .padding(.top, FloSpacing.lg)

                // Day of week headers (42px height with lines above and below)
                dayOfWeekHeader
                    .frame(height: 42)
                    .background(Color.white)

                // Bottom divider line (darker)
                Rectangle()
                    .fill(Color(hex: "707070"))
                    .frame(height: 1)

                // Scrollable calendar with multiple months
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monthOffsets, id: \.self) { monthOffset in
                            monthView(for: monthOffset)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.lg) // Vertical padding before calendar
                    .padding(.bottom, 140) // Space for tab bar
                }
                .scrollPosition(id: $scrolledMonth, anchor: .top)
            }
        }
        .sheet(isPresented: $showPhaseDetail, onDismiss: playLogConfirmationIfNeeded) {
            PhaseDetailView(
                phase: selectedPhase,
                onDismiss: { showPhaseDetail = false },
                onLoggedCycle: {
                    pendingLogConfirmation = true
                    showPhaseDetail = false
                }
            )
        }
        .sheet(isPresented: $showSingleDay, onDismiss: playLogConfirmationIfNeeded) {
            if let date = selectedDate {
                SingleDayView(
                    date: date,
                    phase: cycleManager.phase(for: date),
                    dayOfCycle: cycleManager.dayOfCycle(for: date),
                    onDismiss: { showSingleDay = false },
                    onLoggedCycle: {
                        pendingLogConfirmation = true
                        showSingleDay = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            // Calendar icon
            Image("calendar")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.floCharcoal)
                .accessibilityLabel("Calendar tab")

            Spacer()

            // FLO text
            Text("FLO")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.floCharcoal)
                .tracking(3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.md)
    }

    // MARK: - Greeting Section
    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("Hello, \(cycleManager.userName)!")
                .font(.custom("LUNARY free", size: 36))
                .foregroundColor(.floCharcoal)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                Text(cycleManager.currentPhaseLabel)
                    .font(.floLabel)
                    .fontWeight(.bold)
                    .foregroundColor(.floCharcoal)
                    .tracking(2)

                Text("Next Period: \(cycleManager.nextPeriodFormatted)")
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.sm)
        .padding(.bottom, FloSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Day of Week Header
    private var dayOfWeekHeader: some View {
        HStack {
            ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floCharcoal)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, FloSpacing.lg)
    }

    // MARK: - Month View
    private func monthView(for monthOffset: Int) -> some View {
        let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: startOfCurrentMonth()) ?? Date()
        let days = daysInMonth(for: monthDate)
        let firstWeekday = firstWeekdayOfMonth(for: monthDate)
        let cycleData = getCycleData(for: monthDate)

        let monthAbbrev = monthAbbreviation(for: monthDate)

        // Always render a uniform 6-row (42-cell) grid: leading blanks before the
        // 1st, trailing blanks after the last day. Equal-height month rows make the
        // LazyVStack's offset math exact, so scrollPosition lands on the current
        // month and scrolling up into lazily-realized past months doesn't jump.
        let totalCells = 42
        let cellData: [Int?] = (0..<totalCells).map { index in
            let dayNumber = index - firstWeekday + 1
            return (index >= firstWeekday && dayNumber <= days) ? dayNumber : nil
        }

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: FloSpacing.xs) {
            ForEach(Array(cellData.enumerated()), id: \.offset) { index, dayNumber in
                if let day = dayNumber {
                    DayCellWithPhase(
                        day: day,
                        isSelected: isSelected(day, in: monthDate),
                        isToday: isToday(day, in: monthDate),
                        isFuture: isFuture(day, in: monthDate),
                        cycleData: cycleData,
                        monthLabel: day == 1 ? monthAbbrev : nil,
                        columnIndex: index % 7,
                        emphasizeAsNewStart: emphasizeLoggedStart && isLoggedCycleStart(day, in: monthDate),
                        onTapDay: {
                            selectDay(day, in: monthDate, cycleData: cycleData)
                        },
                        onTapPhase: {
                            showPhaseForDay(day, cycleData: cycleData)
                        }
                    )
                } else {
                    Color.clear
                        .frame(height: 56)
                }
            }
        }
    }

    // MARK: - Phase Background for tappable blocks
    @ViewBuilder
    private func phaseBackground(day: Int, cycleData: CycleData) -> some View {
        let phase = cycleData.phase(for: day)
        switch phase {
        case .menstrual:
            Color.floSage.opacity(0.35)
        case .follicular:
            Color.floSage.opacity(0.2)
        case .ovulation:
            Color.floSage.opacity(0.25)
        case .luteal:
            Color.floSage.opacity(0.12)
        }
    }

    // MARK: - Indicator Dots Helper
    @ViewBuilder
    private func indicatorDots(day: Int, cycleData: CycleData) -> some View {
        let activity = cycleData.activity(for: day)

        HStack(spacing: 2) {
            // Journaled dot (dark teal)
            if activity.journaled {
                Circle()
                    .fill(Color.dotJournaled)
                    .frame(width: 5, height: 5)
            }
            // Selected feelings dot (black)
            if activity.selectedFeelings {
                Circle()
                    .fill(Color.dotFeelings)
                    .frame(width: 5, height: 5)
            }
            // Meditated dot (light mint)
            if activity.meditated {
                Circle()
                    .fill(Color.dotMeditated)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Helper Functions
    private func startOfCurrentMonth() -> Date {
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private func monthAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).uppercased()
    }

    private func daysInMonth(for date: Date) -> Int {
        let range = calendar.range(of: .day, in: .month, for: date)!
        return range.count
    }

    private func firstWeekdayOfMonth(for date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        let firstDay = calendar.date(from: components)!
        let weekday = calendar.component(.weekday, from: firstDay)
        // Swift weekday: Sunday = 1, Monday = 2, ..., Saturday = 7
        // We want: Monday = 0, Tuesday = 1, ..., Sunday = 6
        // So Monday (2) -> 0, Tuesday (3) -> 1, ..., Sunday (1) -> 6
        return (weekday + 5) % 7
    }

    private func isSelected(_ day: Int, in monthDate: Date) -> Bool {
        guard let selected = selectedDate else { return false }
        let selectedComponents = calendar.dateComponents([.year, .month, .day], from: selected)
        let monthComponents = calendar.dateComponents([.year, .month], from: monthDate)
        return selectedComponents.year == monthComponents.year &&
               selectedComponents.month == monthComponents.month &&
               selectedComponents.day == day
    }

    private func isToday(_ day: Int, in monthDate: Date) -> Bool {
        let today = Date()
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        let monthComponents = calendar.dateComponents([.year, .month], from: monthDate)
        return todayComponents.year == monthComponents.year &&
               todayComponents.month == monthComponents.month &&
               todayComponents.day == day
    }

    private func isFuture(_ day: Int, in monthDate: Date) -> Bool {
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = day
        guard let dayDate = calendar.date(from: components) else { return false }
        return dayDate > Date()
    }

    private func selectDay(_ day: Int, in monthDate: Date, cycleData: CycleData) {
        FloHaptics.selection()
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = day
        let date = calendar.date(from: components) ?? Date()
        withAnimation(FloAnimation.springSnappy) {
            selectedDate = date
        }
        showSingleDay = true
    }

    private func showPhaseForDay(_ day: Int, cycleData: CycleData) {
        FloHaptics.light()
        selectedPhase = phaseForDay(day, cycleData: cycleData)
        showPhaseDetail = true
    }

    private func phaseForDay(_ day: Int, cycleData: CycleData) -> CyclePhase {
        return cycleData.phase(for: day)
    }

    // MARK: - Cycle Data (from CycleManager using real onboarding data)
    private func getCycleData(for monthDate: Date) -> CycleData {
        return cycleManager.cycleData(for: monthDate)
    }

    // MARK: - Log Confirmation Choreography

    /// Whether a given calendar day is the most-recently-logged cycle start.
    /// Used only to place the transient post-log emphasis ring.
    private func isLoggedCycleStart(_ day: Int, in monthDate: Date) -> Bool {
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = day
        guard let dayDate = calendar.date(from: components) else { return false }
        return calendar.isDate(dayDate, inSameDayAs: cycleManager.lastPeriodDate)
    }

    /// Runs when a log-cycle sheet finishes dismissing back to the calendar. The
    /// data is already correct (instant-update fix); this plays a single soft
    /// emphasis on the newly-logged start day so the change is felt as it lands,
    /// then fades it out. No timers — the fade-out is the animation's completion.
    private func playLogConfirmationIfNeeded() {
        guard pendingLogConfirmation else { return }
        pendingLogConfirmation = false
        withAnimation(FloAnimation.springGentle) {
            emphasizeLoggedStart = true
        } completion: {
            withAnimation(FloAnimation.easeOutMedium) {
                emphasizeLoggedStart = false
            }
        }
    }
}

// MARK: - Day Activity Data Model
struct DayActivityData {
    let journaled: Bool
    let selectedFeelings: Bool
    let meditated: Bool
}

// MARK: - Cycle Data Model
struct CycleData {
    let periodDays: Set<Int>
    let follicularDays: Set<Int>
    let fertileWindow: Set<Int>
    let ovulationDay: Int
    let lutealDays: Set<Int>
    let daysInMonth: Int
    let activityData: [Int: DayActivityData] // day -> activity
    let isEstimated: Bool   // past/back-extrapolated month → render phases muted
    let hasPhaseData: Bool  // false → no cycle anchor, draw a plain calendar

    func phase(for day: Int) -> CyclePhase {
        if periodDays.contains(day) {
            return .menstrual
        } else if day == ovulationDay {
            return .ovulation
        } else if fertileWindow.contains(day) || follicularDays.contains(day) {
            return .follicular
        } else {
            return .luteal
        }
    }

    // Check if this day is the start of its phase (previous day has different phase or is day 1)
    func isPhaseStart(for day: Int) -> Bool {
        if day == 1 { return true }
        return phase(for: day) != phase(for: day - 1)
    }

    // Check if this day is the end of its phase (next day has different phase or is last day)
    func isPhaseEnd(for day: Int) -> Bool {
        if day >= daysInMonth { return true }
        return phase(for: day) != phase(for: day + 1)
    }

    func activity(for day: Int) -> DayActivityData {
        return activityData[day] ?? DayActivityData(journaled: false, selectedFeelings: false, meditated: false)
    }
}

// MARK: - Day Cell with Phase Background
struct DayCellWithPhase: View {
    let day: Int
    let isSelected: Bool
    let isToday: Bool
    let isFuture: Bool
    let cycleData: CycleData
    let monthLabel: String? // Shows month abbreviation on day 1
    let columnIndex: Int // 0-6, which column this day is in
    var emphasizeAsNewStart: Bool = false // transient soft ring after logging a cycle
    let onTapDay: () -> Void
    let onTapPhase: () -> Void

    /// Opacity applied to phase tints in estimated (past) months. Muting is done
    /// via opacity on the existing phase tokens — no new colors introduced.
    private static let estimatedPhaseOpacity: Double = 0.45

    private var phase: CyclePhase { cycleData.phase(for: day) }
    private var isOvulation: Bool { day == cycleData.ovulationDay }
    private var isPhaseStart: Bool { cycleData.isPhaseStart(for: day) }
    private var isPhaseEnd: Bool { cycleData.isPhaseEnd(for: day) }

    // Round left edge if: phase starts OR day is in first column (Monday)
    private var shouldRoundLeft: Bool { isPhaseStart || columnIndex == 0 }
    // Round right edge if: phase ends OR day is in last column (Sunday)
    private var shouldRoundRight: Bool { isPhaseEnd || columnIndex == 6 }

    var body: some View {
        ZStack {
            // Phase background bar - 22px tall, vertically centered on day number.
            // Rounded corners on outside edges of phase blocks AND grid edges.
            // Only drawn when there's real cycle data to anchor to (honest
            // degradation); estimated past months are muted via reduced opacity
            // on the same phase tokens.
            if cycleData.hasPhaseData {
                phaseBackgroundColor
                    .frame(height: 22)
                    .frame(maxWidth: .infinity)
                    .clipShape(PhaseBarShape(
                        roundLeft: shouldRoundLeft,
                        roundRight: shouldRoundRight,
                        cornerRadius: 11
                    ))
                    .padding(.leading, isPhaseStart && day != 1 ? 4 : 0)
                    .padding(.trailing, isPhaseEnd && day != cycleData.daysInMonth ? 4 : 0)
                    .opacity(cycleData.isEstimated ? Self.estimatedPhaseOpacity : 1)
                    .offset(y: -4)
                    .animation(FloAnimation.easeOutQuick, value: isSelected)
            }

            VStack(spacing: 2) {
                ZStack {
                    // Current date: charcoal outline only — phase tint shows
                    // through. Takes priority over the selected-fill so today
                    // stays an outline even when it's also the selected day.
                    if isToday {
                        Circle()
                            .stroke(Color.floCharcoal, lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                    } else if isSelected {
                        // Selected state (non-today) with subtle scale animation
                        Circle()
                            .fill(Color.floSage)
                            .frame(width: 32, height: 32)
                            .scaleEffect(1.0)
                            .shadow(color: Color.floSage.opacity(0.3), radius: 4, x: 0, y: 2)
                    }

                    // Transient soft ring confirming a just-logged cycle start.
                    // Blooms in and fades out via the parent's one-shot animation.
                    if emphasizeAsNewStart {
                        Circle()
                            .stroke(Color.floSage, lineWidth: 2)
                            .frame(width: 38, height: 38)
                            .transition(.scale(scale: 1.3).combined(with: .opacity))
                    }

                    Text("\(day)")
                        .font(.floBodyMedium)
                        .fontWeight(isToday || isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected && !isToday ? .white : .floCharcoal)
                }
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .onTapGesture { onTapDay() }
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(FloAnimation.springSnappy, value: isSelected)

                // Phase indicator dots
                indicatorDots
                    .padding(.top, 2)
            }

            // Month label (only on day 1) - positioned above the day number as overlay
            if let label = monthLabel {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.floGray)
                    .offset(y: -22)
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapPhase()
        }
    }

    @ViewBuilder
    private var phaseBackgroundColor: some View {
        // Source of truth: CyclePhase.backgroundColor (PhaseModel.swift).
        phase.backgroundColor
    }

    @ViewBuilder
    private var indicatorDots: some View {
        // Only show dots for past or today dates, not future
        if !isFuture {
            let activity = cycleData.activity(for: day)

            HStack(spacing: 2) {
                // Journaled dot (dark teal)
                if activity.journaled {
                    Circle()
                        .fill(Color.dotJournaled)
                        .frame(width: 5, height: 5)
                }
                // Selected feelings dot (black)
                if activity.selectedFeelings {
                    Circle()
                        .fill(Color.dotFeelings)
                        .frame(width: 5, height: 5)
                }
                // Meditated dot (light mint)
                if activity.meditated {
                    Circle()
                        .fill(Color.dotMeditated)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        } else {
            // Empty spacer to maintain layout
            Color.clear.frame(height: 5)
        }
    }
}

// MARK: - Phase Bar Shape with Selective Rounded Corners
struct PhaseBarShape: Shape {
    let roundLeft: Bool
    let roundRight: Bool
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let topLeft = roundLeft ? cornerRadius : 0
        let bottomLeft = roundLeft ? cornerRadius : 0
        let topRight = roundRight ? cornerRadius : 0
        let bottomRight = roundRight ? cornerRadius : 0

        // Start from top-left
        path.move(to: CGPoint(x: topLeft, y: 0))

        // Top edge to top-right
        path.addLine(to: CGPoint(x: rect.width - topRight, y: 0))

        // Top-right corner
        if roundRight {
            path.addArc(
                center: CGPoint(x: rect.width - topRight, y: topRight),
                radius: topRight,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }

        // Right edge to bottom-right
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - bottomRight))

        // Bottom-right corner
        if roundRight {
            path.addArc(
                center: CGPoint(x: rect.width - bottomRight, y: rect.height - bottomRight),
                radius: bottomRight,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        // Bottom edge to bottom-left
        path.addLine(to: CGPoint(x: bottomLeft, y: rect.height))

        // Bottom-left corner
        if roundLeft {
            path.addArc(
                center: CGPoint(x: bottomLeft, y: rect.height - bottomLeft),
                radius: bottomLeft,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        // Left edge to top-left
        path.addLine(to: CGPoint(x: 0, y: topLeft))

        // Top-left corner
        if roundLeft {
            path.addArc(
                center: CGPoint(x: topLeft, y: topLeft),
                radius: topLeft,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}

#Preview {
    CalendarView()
}
