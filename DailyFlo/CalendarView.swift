//
//  CalendarView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

struct CalendarView: View {
    @State private var selectedDate: Date? = nil
    @State private var showSingleDay = false

    // Drives scrollPosition anchoring; starts on the current month (offset 0).
    @State private var scrolledMonth: Int? = 0

    // Log-confirmation choreography. When a log-cycle sheet collapses back to the
    // calendar, `pendingLogConfirmation` is set so the sheet's onDismiss can play
    // a one-shot soft emphasis (`emphasizeLoggedStart`) on the new start day.
    @State private var pendingLogConfirmation = false
    @State private var emphasizeLoggedStart = false

    /// Bottom inset so the last week clears the custom tab bar (bar height +
    /// device safe-area inset), injected by `ContentView`.
    @Environment(\.tabBarClearance) private var tabBarClearance

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
                // Shared header: calendar icon + FLO, "Hello, name!", phase
                // eyebrow, next-period subtitle.
                ScreenHeader(
                    title: "Hello, \(cycleManager.userName)!",
                    eyebrow: cycleManager.currentPhaseLabel,
                    subtitle: "Next period: \(cycleManager.nextPeriodFormatted)",
                    leadingIcon: "calendar"
                )

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

                // Scrollable calendar with multiple months. Vertical-only.
                // Each month block carries its OWN Layout.screenMargin inset, so
                // the scroll content is full viewport width: no horizontal
                // padding sits outside scrollTargetLayout for the initial
                // scrollPosition pass to skip, and the anchor's x (0.5) can't
                // shift full-width content. Each month leads with its label row
                // so anchoring the current month's top (scrolledMonth = 0) puts
                // the label just under the sticky weekday row with today's week
                // visible below — no hardcoded nudge.
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(monthOffsets, id: \.self) { monthOffset in
                            monthView(for: monthOffset)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, tabBarClearance) // clear the tab bar
                }
                .scrollPosition(id: $scrolledMonth, anchor: .top)
            }
        }
        .sheet(isPresented: $showSingleDay, onDismiss: playLogConfirmationIfNeeded) {
            if let date = selectedDate {
                SingleDayView(
                    date: date,
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

    // MARK: - Day of Week Header
    /// Same 7 columns as every week row (`CalendarColumns.gridItems`) inside
    /// the same `Layout.screenMargin`, so each letter sits dead-center over its
    /// column of day numbers.
    private var dayOfWeekHeader: some View {
        LazyVGrid(columns: CalendarColumns.gridItems, spacing: 0) {
            ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floCharcoal)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Layout.screenMargin)
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

        // Each month leads with a uniform label row (keeps month blocks equal
        // height so the LazyVStack offset math — and scrollPosition — stays
        // exact), then the 7-column grid shared with the weekday header. The
        // Layout.screenMargin inset lives HERE, inside the scroll content, so
        // the grid's left edge aligns with the greeting and weekday row at 24pt
        // on cold launch — no scroll API can move it.
        return VStack(spacing: 0) {
            monthLabelRow(monthAbbrev, firstDayColumn: firstWeekday)

            LazyVGrid(columns: CalendarColumns.gridItems, spacing: FloSpacing.xs) {
                ForEach(Array(cellData.enumerated()), id: \.offset) { index, dayNumber in
                    if let day = dayNumber {
                        DayCellWithPhase(
                            day: day,
                            isSelected: isSelected(day, in: monthDate),
                            isToday: isToday(day, in: monthDate),
                            isFuture: isFuture(day, in: monthDate),
                            cycleData: cycleData,
                            columnIndex: index % 7,
                            emphasizeAsNewStart: emphasizeLoggedStart && isLoggedCycleStart(day, in: monthDate),
                            onTapDay: {
                                selectDay(day, in: monthDate, cycleData: cycleData)
                            }
                        )
                    } else {
                        Color.clear
                            .frame(height: 56)
                    }
                }
            }
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // MARK: - Month label row
    /// Month abbreviation centered over the column of the month's first day
    /// (NOV over Sunday for Nov 2026), ~27pt above that first week row, per
    /// Brittany's frame (node 2383:2152). Laid out with the same
    /// `CalendarColumns` as the grid so it tracks the first-day column exactly;
    /// rendered as a real row (not a negative-offset overlay) so it can't be
    /// clipped when its month is anchored to the top of the scroll viewport.
    private func monthLabelRow(_ abbrev: String, firstDayColumn: Int) -> some View {
        LazyVGrid(columns: CalendarColumns.gridItems, spacing: 0) {
            ForEach(0..<CalendarColumns.count, id: \.self) { column in
                Text(column == firstDayColumn ? abbrev : "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.floGray)
                    .tracking(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, FloSpacing.md)
        .padding(.bottom, 27) // Figma: label sits ~27pt above the first week row
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
    let columnIndex: Int // 0-6, which column this day is in
    var emphasizeAsNewStart: Bool = false // transient soft ring after logging a cycle
    /// Any tap in the cell opens the day sheet.
    let onTapDay: () -> Void

    /// Opacity applied to phase tints in estimated (past) months. Muting is done
    /// via opacity on the existing phase tokens — no new colors introduced.
    private static let estimatedPhaseOpacity: Double = 0.45

    /// Phase band height; its ends round fully (radius = half the height).
    private static let bandHeight: CGFloat = 32
    /// Today ring diameter.
    private static let todayRingSize: CGFloat = 46
    /// The number sits above the dots in a 41pt stack (32 number + 4 gap +
    /// 5 dots) centered in the 56pt cell, so its center is 4.5pt above the
    /// cell's. The band is shifted by the same amount to center on it.
    private static let numberCenterOffset: CGFloat = -4.5

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
            // Phase background bar - 32pt tall, vertically centered on day number.
            // Rounded corners on outside edges of phase blocks AND grid edges.
            // Only drawn when there's real cycle data to anchor to (honest
            // degradation); estimated past months are muted via reduced opacity
            // on the same phase tokens.
            if cycleData.hasPhaseData {
                phaseBackgroundColor
                    .frame(height: Self.bandHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(PhaseBarShape(
                        roundLeft: shouldRoundLeft,
                        roundRight: shouldRoundRight,
                        cornerRadius: Self.bandHeight / 2
                    ))
                    .padding(.leading, isPhaseStart && day != 1 ? 4 : 0)
                    .padding(.trailing, isPhaseEnd && day != cycleData.daysInMonth ? 4 : 0)
                    .opacity(cycleData.isEstimated ? Self.estimatedPhaseOpacity : 1)
                    .offset(y: Self.numberCenterOffset)
                    .animation(FloAnimation.easeOutQuick, value: isSelected)
            }

            VStack(spacing: 2) {
                ZStack {
                    // Current date: a 46pt black hairline ring, no fill — the
                    // phase band shows through. It overflows the 32pt number
                    // frame on purpose so the grid layout doesn't shift. Takes
                    // priority over the selected fill.
                    if isToday {
                        Circle()
                            .stroke(Color.black, lineWidth: 1)
                            .frame(width: Self.todayRingSize, height: Self.todayRingSize)
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
                        .font(isToday ? .system(size: 16, weight: .bold) : .floBodyMedium)
                        .fontWeight(isToday ? .bold : (isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected && !isToday ? .white : (isToday ? .black : .floCharcoal))
                }
                .frame(width: 32, height: 32)
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(FloAnimation.springSnappy, value: isSelected)

                // Phase indicator dots
                indicatorDots
                    .padding(.top, 2)
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapDay()
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
