//
//  CycleManager.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 3/10/26.
//

import Foundation
import Supabase
import SwiftUI

// MARK: - Cycle Manager
/// Central source of truth for cycle calculations.
///
/// Persistence model: Supabase `profiles` (display_name, birth_date, defaults)
/// and `cycles` (start_date of latest cycle) are authoritative; UserDefaults is
/// the local cache so the read API stays synchronous and survives offline use.
///
/// Reads are unchanged — every property still reads from UserDefaults under the
/// hood. The new behavior is on sign-in:
///   1. If a `pendingOnboardingPayload` flag is set (from the most recent
///      onboarding flow), UPSERT the profile and INSERT an initial cycles row,
///      then clear the flag. UPSERT is required because the `handle_new_user`
///      trigger on auth.users inserts a placeholder profile on signup, and we
///      need to overwrite display_name + birth_date.
///   2. Refresh from the server: pull the profile + latest cycle and write
///      them through to UserDefaults so views see fresh data.
@Observable
class CycleManager {
    static let shared = CycleManager()

    private let profilesTable = "profiles"
    private let cyclesTable = "cycles"

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        Task { @MainActor in
            await observeAuthState()
        }
    }

    // MARK: - User Cycle Data (cached in UserDefaults)
    //
    // These stay backed by UserDefaults (the single source of truth, shared with
    // OnboardingView / ProfileMainView), but are bracketed with the Observation
    // registrar's `access`/`withMutation` so SwiftUI actually tracks them. Without
    // this, the @Observable macro only instruments *stored* properties — a plain
    // computed UserDefaults read is invisible to Observation, so writing a new
    // cycle never invalidated any observing view. Writers must go through the
    // setters (not raw UserDefaults.set) for the mutation notification to fire.
    var lastPeriodDate: Date {
        get {
            access(keyPath: \.lastPeriodDate)
            return UserDefaults.standard.object(forKey: "lastPeriodDate") as? Date ?? Date()
        }
        set {
            withMutation(keyPath: \.lastPeriodDate) {
                UserDefaults.standard.set(newValue, forKey: "lastPeriodDate")
            }
        }
    }

    var cycleLength: Int {
        get {
            access(keyPath: \.cycleLength)
            let stored = UserDefaults.standard.integer(forKey: "cycleLength")
            return stored > 0 ? stored.clamped(to: 21...45) : 28
        }
        set {
            withMutation(keyPath: \.cycleLength) {
                UserDefaults.standard.set(newValue, forKey: "cycleLength")
            }
        }
    }

    var periodLength: Int {
        get {
            access(keyPath: \.periodLength)
            let stored = UserDefaults.standard.integer(forKey: "periodLength")
            return stored > 0 ? stored.clamped(to: 2...10) : 5
        }
        set {
            withMutation(keyPath: \.periodLength) {
                UserDefaults.standard.set(newValue, forKey: "periodLength")
            }
        }
    }

    var userName: String {
        get {
            access(keyPath: \.userName)
            return UserDefaults.standard.string(forKey: "userName") ?? "Friend"
        }
        set {
            withMutation(keyPath: \.userName) {
                UserDefaults.standard.set(newValue, forKey: "userName")
            }
        }
    }

    var birthDate: Date? {
        UserDefaults.standard.object(forKey: "birthDate") as? Date
    }

    // MARK: - Role (partner-share routing)

    /// Authoritative role from the `profiles.role` column. Cached locally
    /// so the launch render can resolve a destination before the network
    /// refresh returns; updated through `apply(profile:)` after each fetch.
    var userRole: UserRole = {
        if let raw = UserDefaults.standard.string(forKey: "userRole"),
           let role = UserRole(rawValue: raw) {
            return role
        }
        return .tracker
    }() {
        didSet { UserDefaults.standard.set(userRole.rawValue, forKey: "userRole") }
    }

    #if DEBUG
    /// DEBUG harness: when true, `effectiveRole` reports `.supporter`
    /// regardless of the signed-in profile so supporter surfaces can be
    /// driven without standing up real relationship data.
    var debugForceSupporter: Bool = UserDefaults.standard.bool(forKey: "debugForceSupporter") {
        didSet { UserDefaults.standard.set(debugForceSupporter, forKey: "debugForceSupporter") }
    }
    #endif

    /// The role the app should route on. Honors the DEBUG override first,
    /// then falls back to the stored profile role. "both" routes to the
    /// tracker experience in this step; supporter view is opt-in only.
    var effectiveRole: UserRole {
        #if DEBUG
        if debugForceSupporter { return .supporter }
        #endif
        return userRole
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

    /// Generates CycleData for a given month.
    ///
    /// This is the single data seam for the calendar: the view asks for any
    /// month and never knows whether the phases were computed here or (later)
    /// fetched as real logged cycles from Supabase. Today, past months are
    /// back-extrapolated from `lastPeriodDate` + averages via the modulo in
    /// `dayOfCycle(for:)`; a future migration swaps the source without touching
    /// this signature or the view.
    ///
    /// Two honesty flags travel with the data:
    /// - `hasPhaseData` is false when no period start has ever been recorded, so
    ///   the view draws a plain calendar instead of fabricating phases.
    /// - `isEstimated` marks months before the current month, which the view
    ///   renders muted. Journal/emotion activity is real data in every month and
    ///   is never gated by these flags.
    func cycleData(for monthDate: Date) -> CycleData {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: monthDate)!
        let daysInMonth = range.count

        // Real anchor to compute phases from? `lastPeriodDate`'s getter falls back
        // to Date(), so probe the raw store to distinguish "never set" from a value.
        let hasPhaseData = UserDefaults.standard.object(forKey: "lastPeriodDate") != nil

        // Months strictly before the current month are shown muted (estimated).
        let firstOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate
        let isEstimated = firstOfMonth < firstOfThisMonth

        var periodDays: Set<Int> = []
        var follicularDays: Set<Int> = []
        var fertileWindow: Set<Int> = []
        var ovDay: Int = 0
        var lutealDays: Set<Int> = []

        // No anchor → leave every phase set empty so the view renders plainly.
        if hasPhaseData {
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
            activityData: activityData,
            isEstimated: isEstimated,
            hasPhaseData: hasPhaseData
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

    // MARK: - Auth observation

    @MainActor
    private func observeAuthState() async {
        for await (event, session) in SupabaseClient.shared.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn:
                guard let session else { break }
                await pushPendingOnboardingIfNeeded(userId: session.user.id)
                await refresh(userId: session.user.id)
            case .signedOut, .userDeleted:
                clearLocalCache()
            default:
                break
            }
        }
    }

    // MARK: - Push pending onboarding payload (one-shot, post-sign-in fixup)

    @MainActor
    private func pushPendingOnboardingIfNeeded(userId: UUID) async {
        guard UserDefaults.standard.bool(forKey: "pendingOnboardingPayload") else { return }

        let pendingName = (UserDefaults.standard.string(forKey: "userName") ?? "").trimmingCharacters(in: .whitespaces)
        let pendingBirth = UserDefaults.standard.object(forKey: "birthDate") as? Date
        let pendingLastPeriod = UserDefaults.standard.object(forKey: "lastPeriodDate") as? Date ?? Date()
        let storedCycle = UserDefaults.standard.integer(forKey: "cycleLength")
        let storedPeriod = UserDefaults.standard.integer(forKey: "periodLength")
        let pendingCycleLength = storedCycle > 0 ? storedCycle.clamped(to: 21...45) : 28
        let pendingPeriodLength = storedPeriod > 0 ? storedPeriod.clamped(to: 2...10) : 5

        guard let birth = pendingBirth else {
            print("[CycleManager] pendingOnboardingPayload: birthDate missing — refusing to upsert")
            return
        }
        guard !pendingName.isEmpty else {
            print("[CycleManager] pendingOnboardingPayload: display name missing — refusing to upsert")
            return
        }

        let profileRow = ProfileUpsertRow(
            userId: userId,
            displayName: pendingName,
            birthDate: Self.dbDateFormatter.string(from: birth),
            timezone: TimeZone.current.identifier,
            defaultCycleLengthDays: pendingCycleLength,
            defaultPeriodLengthDays: pendingPeriodLength,
            onboardingCompletedAt: ISO8601DateFormatter().string(from: Date())
        )

        do {
            try await SupabaseClient.shared
                .from(profilesTable)
                .upsert(profileRow, onConflict: "user_id")
                .execute()
            print("[CycleManager] profile upsert OK for user \(userId)")
        } catch {
            logRemoteError(operation: "profile upsert", error: error)
            // Don't clear the flag — we want to retry next launch.
            return
        }

        let predictedEnd = Calendar.current.date(byAdding: .day, value: pendingCycleLength, to: pendingLastPeriod) ?? pendingLastPeriod
        let cycleRow = CycleInsertRow(
            userId: userId,
            startDate: Self.dbDateFormatter.string(from: pendingLastPeriod),
            predictedEndDate: Self.dbDateFormatter.string(from: predictedEnd),
            periodLengthDays: pendingPeriodLength,
            isPredicted: true
        )

        do {
            try await SupabaseClient.shared
                .from(cyclesTable)
                .insert(cycleRow)
                .execute()
            print("[CycleManager] initial cycle insert OK for user \(userId)")
        } catch {
            logRemoteError(operation: "initial cycle insert", error: error)
            // Profile upsert already succeeded; we don't want to keep retrying
            // the upsert. Clear the flag anyway and let the user log a cycle
            // manually if needed.
        }

        UserDefaults.standard.set(false, forKey: "pendingOnboardingPayload")
    }

    // MARK: - Log a confirmed cycle start (post-onboarding)

    /// Records a real (user-confirmed) period start. Writes UserDefaults
    /// optimistically so the UI is instant, then inserts a `cycles` row with
    /// `is_predicted = false`. If there's no signed-in session, the local
    /// write still lands and the remote insert is skipped gracefully.
    @MainActor
    func logCycle(startDate: Date) async {
        // Optimistic local write — preserves the offline-cache contract.
        // Goes through the setter so Observation fires and observing views
        // (e.g. CalendarView) update instantly on modal dismiss.
        lastPeriodDate = startDate

        guard let userId = SupabaseClient.shared.auth.currentSession?.user.id else {
            print("[CycleManager] logCycle: no signed-in session — saved locally only")
            return
        }

        let predictedEnd = Calendar.current.date(byAdding: .day, value: cycleLength, to: startDate) ?? startDate
        let row = CycleInsertRow(
            userId: userId,
            startDate: Self.dbDateFormatter.string(from: startDate),
            predictedEndDate: Self.dbDateFormatter.string(from: predictedEnd),
            periodLengthDays: periodLength,
            isPredicted: false
        )

        do {
            try await SupabaseClient.shared
                .from(cyclesTable)
                .insert(row)
                .execute()
            print("[CycleManager] logCycle insert OK for user \(userId)")
        } catch {
            logRemoteError(operation: "logCycle insert", error: error)
        }
    }

    // MARK: - Refresh from Supabase

    /// Pulls the signed-in user's profile + most recent cycle and writes them
    /// through to UserDefaults so the synchronous read API sees fresh data.
    @MainActor
    func refresh(userId: UUID) async {
        do {
            let profile: ProfileFetchRow = try await SupabaseClient.shared
                .from(profilesTable)
                .select("display_name, birth_date, default_cycle_length_days, default_period_length_days, role")
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value

            apply(profile: profile)
        } catch {
            logRemoteError(operation: "profile fetch", error: error)
        }

        do {
            let cycles: [CycleFetchRow] = try await SupabaseClient.shared
                .from(cyclesTable)
                .select("start_date")
                .eq("user_id", value: userId)
                .filter("deleted_at", operator: "is", value: "null")
                .order("start_date", ascending: false)
                .limit(1)
                .execute()
                .value

            if let mostRecent = cycles.first,
               let date = Self.dbDateFormatter.date(from: mostRecent.startDate) {
                lastPeriodDate = date
            }
        } catch {
            logRemoteError(operation: "latest cycle fetch", error: error)
        }
    }

    private func apply(profile: ProfileFetchRow) {
        if !profile.displayName.isEmpty {
            userName = profile.displayName
        }
        if let birthDateString = profile.birthDate,
           let bd = Self.dbDateFormatter.date(from: birthDateString) {
            UserDefaults.standard.set(bd, forKey: "birthDate")
        }
        if let cl = profile.defaultCycleLengthDays {
            cycleLength = cl.clamped(to: 21...45)
        }
        if let pl = profile.defaultPeriodLengthDays {
            periodLength = pl.clamped(to: 2...10)
        }
        if let role = UserRole(rawString: profile.role) {
            userRole = role
        }
    }

    // MARK: - Cache lifecycle

    private func clearLocalCache() {
        for key in ["userName", "birthDate", "lastPeriodDate", "cycleLength", "periodLength", "userRole"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        userRole = .tracker
    }

    private func logRemoteError(operation: String, error: Error) {
        if let pg = error as? PostgrestError {
            print("[CycleManager] \(operation) failed — PostgrestError code=\(pg.code ?? "nil") message=\"\(pg.message)\" detail=\(pg.detail ?? "nil") hint=\(pg.hint ?? "nil")")
        } else if let http = error as? HTTPError {
            let body = String(data: http.data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[CycleManager] \(operation) failed — HTTP \(http.response.statusCode): \(body)")
        } else {
            print("[CycleManager] \(operation) failed — \(type(of: error)): \(error.localizedDescription)")
        }
    }
}

// MARK: - DB row representations

private struct ProfileUpsertRow: Encodable {
    let userId: UUID
    let displayName: String
    let birthDate: String              // "yyyy-MM-dd"
    let timezone: String
    let defaultCycleLengthDays: Int
    let defaultPeriodLengthDays: Int
    let onboardingCompletedAt: String  // ISO 8601 timestamp

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case birthDate = "birth_date"
        case timezone
        case defaultCycleLengthDays = "default_cycle_length_days"
        case defaultPeriodLengthDays = "default_period_length_days"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}

private struct CycleInsertRow: Encodable {
    let userId: UUID
    let startDate: String         // "yyyy-MM-dd"
    let predictedEndDate: String  // "yyyy-MM-dd"
    let periodLengthDays: Int
    let isPredicted: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case startDate = "start_date"
        case predictedEndDate = "predicted_end_date"
        case periodLengthDays = "period_length_days"
        case isPredicted = "is_predicted"
    }
}

private struct ProfileFetchRow: Decodable {
    let displayName: String
    let birthDate: String?
    let defaultCycleLengthDays: Int?
    let defaultPeriodLengthDays: Int?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case birthDate = "birth_date"
        case defaultCycleLengthDays = "default_cycle_length_days"
        case defaultPeriodLengthDays = "default_period_length_days"
        case role
    }
}

private struct CycleFetchRow: Decodable {
    let startDate: String

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
    }
}

// MARK: - Int Clamping Helper
extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - User Role

/// Mirrors the `profiles.role` enum. Internal naming uses tracker/supporter;
/// surface copy never exposes the word "tracker".
enum UserRole: String, Sendable {
    case tracker
    case supporter
    case both

    /// Tolerant init for db-side strings: trims whitespace + lowercases so
    /// off-by-case rows ("Tracker", "SUPPORTER") still resolve.
    init?(rawString: String?) {
        guard let raw = rawString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        self.init(rawValue: raw)
    }
}
