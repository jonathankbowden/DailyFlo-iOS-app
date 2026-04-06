//
//  CycleManager.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 3/10/26.
//

import SwiftUI

// MARK: - Cycle Manager
/// Central source of truth for cycle calculations using real onboarding data.
@Observable
class CycleManager {
    static let shared = CycleManager()

    // MARK: - User Cycle Data (from onboarding)
    var lastPeriodDate: Date {
        UserDefaults.standard.object(forKey: "lastPeriodDate") as? Date ?? Date()
    }

    var cycleLength: Int {
        let stored = UserDefaults.standard.integer(forKey: "cycleLength")
        return stored > 0 ? stored.clamped(to: 21...45) : 28
    }

    var periodLength: Int {
        let stored = UserDefaults.standard.integer(forKey: "periodLength")
        return stored > 0 ? stored.clamped(to: 2...10) : 5
    }

    var userName: String {
        UserDefaults.standard.string(forKey: "userName") ?? "Friend"
    }

    // MARK: - Phase Boundaries (proportional to cycle length)
    // Menstrual: days 1...periodLength
    // Follicular: periodLength+1 ... ovulationStart-1
    // Ovulation: ~3 days centered around day cycleLength-14
    // Luteal: after ovulation ... cycleLength

    private var ovulationDay: Int {
        max(cycleLength - 14, periodLength + 2)
    }

    private var follicularEnd: Int {
        ovulationDay - 2
    }

    private var ovulationEnd: Int {
        ovulationDay + 1
    }

    // MARK: - Day in Cycle Calculation

    /// Returns the day of cycle (1-based) for any given date
    func dayOfCycle(for date: Date) -> Int {
        let calendar = Calendar.current
        let startOfLast = calendar.startOfDay(for: lastPeriodDate)
        let startOfDate = calendar.startOfDay(for: date)
        let daysSinceStart = calendar.dateComponents([.day], from: startOfLast, to: startOfDate).day ?? 0

        // Normalize to cycle position (1-based)
        let mod = daysSinceStart % cycleLength
        let normalizedDay = mod >= 0 ? mod + 1 : cycleLength + mod + 1
        return normalizedDay
    }

    /// Returns the cycle phase for any given date
    func phase(for date: Date) -> CyclePhase {
        let day = dayOfCycle(for: date)
        return phase(forCycleDay: day)
    }

    /// Returns the cycle phase for a given day number within the cycle
    func phase(forCycleDay day: Int) -> CyclePhase {
        if day >= 1 && day <= periodLength {
            return .menstrual
        } else if day <= follicularEnd {
            return .follicular
        } else if day <= ovulationEnd {
            return .ovulation
        } else {
            return .luteal
        }
    }

    // MARK: - Next Period Prediction

    /// Returns the date of the next predicted period start
    var nextPeriodDate: Date {
        let calendar = Calendar.current
        let today = Date()
        let currentDay = dayOfCycle(for: today)
        let daysUntilNextPeriod = cycleLength - currentDay + 1

        if daysUntilNextPeriod <= 0 {
            // Already past, calculate next cycle
            return calendar.date(byAdding: .day, value: daysUntilNextPeriod + cycleLength, to: today) ?? today
        }
        return calendar.date(byAdding: .day, value: daysUntilNextPeriod, to: today) ?? today
    }

    var nextPeriodFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: nextPeriodDate)
    }

    var daysUntilNextPeriod: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let next = calendar.startOfDay(for: nextPeriodDate)
        return max(0, calendar.dateComponents([.day], from: today, to: next).day ?? 0)
    }

    // MARK: - Current Phase Info

    var currentPhase: CyclePhase {
        phase(for: Date())
    }

    var currentDayOfCycle: Int {
        dayOfCycle(for: Date())
    }

    var currentPhaseLabel: String {
        "\(currentPhase.name.uppercased())"
    }

    // MARK: - Cycle Data for Calendar Month

    /// Generates CycleData for a given month using real user data
    func cycleData(for monthDate: Date) -> CycleData {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: monthDate)!
        let daysInMonth = range.count

        var periodDays: Set<Int> = []
        var follicularDays: Set<Int> = []
        var fertileWindow: Set<Int> = []
        var ovDay: Int = 0
        var lutealDays: Set<Int> = []

        for day in 1...daysInMonth {
            var components = calendar.dateComponents([.year, .month], from: monthDate)
            components.day = day
            guard let dayDate = calendar.date(from: components) else { continue }

            let phase = self.phase(for: dayDate)
            switch phase {
            case .menstrual:
                periodDays.insert(day)
            case .follicular:
                follicularDays.insert(day)
            case .ovulation:
                fertileWindow.insert(day)
                // Mark the actual ovulation day
                let cycDay = dayOfCycle(for: dayDate)
                if cycDay == ovulationDay {
                    ovDay = day
                }
            case .luteal:
                lutealDays.insert(day)
            }
        }

        // Build activity data from journal entries
        var activityData: [Int: DayActivityData] = [:]
        let journalManager = JournalManager.shared
        for day in 1...daysInMonth {
            var components = calendar.dateComponents([.year, .month], from: monthDate)
            components.day = day
            guard let dayDate = calendar.date(from: components) else { continue }

            let dayEntries = journalManager.entries(for: dayDate)
            if !dayEntries.isEmpty {
                activityData[day] = DayActivityData(
                    journaled: true,
                    selectedFeelings: !dayEntries.isEmpty,
                    meditated: false // TODO: track meditation sessions
                )
            }
        }

        return CycleData(
            periodDays: periodDays,
            follicularDays: follicularDays,
            fertileWindow: fertileWindow,
            ovulationDay: ovDay,
            lutealDays: lutealDays,
            daysInMonth: daysInMonth,
            activityData: activityData
        )
    }

    // MARK: - Period Start Date for a Specific Month

    /// Returns the predicted period start dates that fall within a given month
    func periodStartDates(in monthDate: Date) -> [Date] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: monthDate)!
        var starts: [Date] = []

        for day in range {
            var components = calendar.dateComponents([.year, .month], from: monthDate)
            components.day = day
            guard let dayDate = calendar.date(from: components) else { continue }
            if dayOfCycle(for: dayDate) == 1 {
                starts.append(dayDate)
            }
        }
        return starts
    }
}

// MARK: - Int Clamping Helper
extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
