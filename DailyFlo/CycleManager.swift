//
//  CycleManager.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 3/10/26.
//

import Foundation
import Network
import Supabase
import SwiftUI
import UIKit

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
///
/// Offline safety: cycle writes go through a persisted per-user queue
/// (`CycleWriteQueue`). Logging a period writes UserDefaults optimistically and
/// enqueues an UPSERT (the row id is derived from user+start_date, so a retry
/// can't duplicate); the queue replays on foreground / network return / sign-in
/// and at the start of `refresh()`, which also re-applies anything still pending
/// on top of the server's latest cycle before publishing. The queue is cleared
/// on sign-out and account deletion.
@Observable
class CycleManager {
    static let shared = CycleManager()

    private let profilesTable = "profiles"
    private let cyclesTable = "cycles"

    /// Persisted, per-user queue of cycle writes not yet confirmed by Supabase.
    private let writeQueue = CycleWriteQueue()
    /// The user whose queue is in play — remembered so sign-out can clear it.
    private var activeUserId: UUID?
    /// Re-entrancy guard + "run again" flag for overlapping replay triggers.
    private var isReplaying = false
    private var replayRequested = false

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "app.dailyflo.cycle.network")

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        startNetworkMonitor()
        observeForeground()
        Task { @MainActor in
            await observeAuthState()
        }
    }

    /// Replays the pending cycle queue whenever connectivity is (re)established.
    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.replayQueue() }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    /// Replays the pending cycle queue each time the app returns to the foreground.
    private func observeForeground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.replayQueue() }
        }
    }

    private func currentUserId() -> UUID? {
        SupabaseClient.shared.auth.currentSession?.user.id
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
        Self.dayOfCycle(on: date, lastPeriodStart: lastPeriodDate, cycleLength: cycleLength)
    }

    // MARK: - Pure cycle math
    // Static so the supporter side can run the same arithmetic on a
    // partner's numbers without standing up a second manager.

    /// Day of cycle (1-based) on `date`, given the most recent period start.
    static func dayOfCycle(on date: Date, lastPeriodStart: Date, cycleLength: Int) -> Int {
        let calendar = Calendar.current
        let length = max(1, cycleLength)
        let startOfLast = calendar.startOfDay(for: lastPeriodStart)
        let startOfDate = calendar.startOfDay(for: date)
        let daysSinceStart = calendar.dateComponents([.day], from: startOfLast, to: startOfDate).day ?? 0

        // Normalize to cycle position (1-based)
        let mod = daysSinceStart % length
        return mod >= 0 ? mod + 1 : length + mod + 1
    }

    /// Phase for a cycle day, with boundaries proportional to cycle length.
    /// Mirrors `ovulationDay` / `follicularEnd` / `ovulationEnd` above.
    static func phase(forCycleDay day: Int, cycleLength: Int, periodLength: Int) -> CyclePhase {
        let ovulationDay = max(cycleLength - 14, periodLength + 2)
        let follicularEnd = ovulationDay - 2
        let ovulationEnd = ovulationDay + 1

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

    /// Returns the cycle phase for any given date
    func phase(for date: Date) -> CyclePhase {
        let day = dayOfCycle(for: date)
        return phase(forCycleDay: day)
    }

    /// Returns the cycle phase for a given day number within the cycle
    func phase(forCycleDay day: Int) -> CyclePhase {
        Self.phase(forCycleDay: day, cycleLength: cycleLength, periodLength: periodLength)
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
                activeUserId = session.user.id
                await pushPendingOnboardingIfNeeded(userId: session.user.id)
                // refresh() starts by replaying the queue, covering sign-in.
                await refresh(userId: session.user.id)
            case .signedOut, .userDeleted:
                if let userId = activeUserId {
                    writeQueue.clear(for: userId)
                }
                activeUserId = nil
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
        let pendingLastPeriod = UserDefaults.standard.object(forKey: "lastPeriodDate") as? Date
        let storedCycle = UserDefaults.standard.integer(forKey: "cycleLength")
        let storedPeriod = UserDefaults.standard.integer(forKey: "periodLength")
        let pendingCycleLength = storedCycle > 0 ? storedCycle.clamped(to: 21...45) : 28
        let pendingPeriodLength = storedPeriod > 0 ? storedPeriod.clamped(to: 2...10) : 5

        // Birth date is the 13+ gate, so it's the one hard requirement. A
        // missing name used to abort the whole push — which also silently
        // dropped the initial cycle for Sign in with Apple users whose name
        // never arrived. The name is optional; the cycle is not.
        guard let birth = pendingBirth else {
            #if DEBUG
            print("[CycleManager] pendingOnboardingPayload: birthDate missing — refusing to upsert")
            #endif
            return
        }

        let profileRow = ProfileUpsertRow(
            userId: userId,
            displayName: pendingName.isEmpty ? nil : pendingName,
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
            #if DEBUG
            print("[CycleManager] profile upsert OK for user \(userId)")
            #endif
        } catch {
            logRemoteError(operation: "profile upsert", error: error)
            // Don't clear the flag — we want to retry next launch.
            return
        }

        // Only a real, user-entered period date becomes a cycle row. With
        // none, there's nothing truthful to insert; `refresh` backfills the
        // moment one exists locally.
        if let pendingLastPeriod {
            await insertInitialCycle(
                userId: userId,
                startDate: pendingLastPeriod,
                cycleLength: pendingCycleLength,
                periodLength: pendingPeriodLength
            )
        }

        UserDefaults.standard.set(false, forKey: "pendingOnboardingPayload")
    }

    /// Queues the onboarding-era cycle (is_predicted) from a locally known period
    /// start. Shared by the one-shot push and by `refresh`, which uses it to heal
    /// accounts whose cycle never landed. The deterministic id makes repeated
    /// calls for the same start idempotent (one row, not many).
    @MainActor
    private func insertInitialCycle(userId: UUID, startDate: Date, cycleLength: Int, periodLength: Int) async {
        enqueueCycle(userId: userId, startDate: startDate, cycleLength: cycleLength, periodLength: periodLength, isPredicted: true)
        await replayQueue()
    }

    /// Builds and enqueues a cycle upsert op. The row id is derived from
    /// (user, start_date) so re-logging the same start never duplicates.
    private func enqueueCycle(userId: UUID, startDate: Date, cycleLength: Int, periodLength: Int, isPredicted: Bool) {
        let startString = Self.dbDateFormatter.string(from: startDate)
        let predictedEnd = Calendar.current.date(byAdding: .day, value: cycleLength, to: startDate) ?? startDate
        let op = CycleWriteOp(
            id: Self.deterministicCycleId(userId: userId, startDate: startString),
            userId: userId,
            startDate: startString,
            predictedEndDate: Self.dbDateFormatter.string(from: predictedEnd),
            periodLengthDays: periodLength,
            isPredicted: isPredicted
        )
        writeQueue.enqueue(op, for: userId)
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

        guard let userId = currentUserId() else {
            #if DEBUG
            print("[CycleManager] logCycle: no signed-in session — saved locally only")
            #endif
            return
        }

        activeUserId = userId
        // Durable: enqueue an upsert (is_predicted = false, user-confirmed) and
        // try to send now. Offline, it rides the queue and replays on reconnect.
        enqueueCycle(userId: userId, startDate: startDate, cycleLength: cycleLength, periodLength: periodLength, isPredicted: false)
        await replayQueue()
    }

    // MARK: - Pending-write queue

    /// Sends each pending cycle upsert in order, removing it on success. Stops at
    /// the first failure (likely offline) and re-runs if work is enqueued during
    /// the pass. Re-entrant-safe via `isReplaying`.
    @MainActor
    func replayQueue() async {
        guard let userId = currentUserId() else { return }
        guard !isReplaying else { replayRequested = true; return }
        isReplaying = true
        defer { isReplaying = false }

        repeat {
            replayRequested = false
            var stoppedOnFailure = false
            for op in writeQueue.all(for: userId) {
                if await remoteUpsertCycle(op) {
                    writeQueue.remove(matching: op, for: userId)
                } else {
                    stoppedOnFailure = true
                    break
                }
            }
            if stoppedOnFailure { break }
        } while replayRequested
    }

    @discardableResult
    private func remoteUpsertCycle(_ op: CycleWriteOp) async -> Bool {
        do {
            try await SupabaseClient.shared
                .from(cyclesTable)
                .upsert(op, onConflict: "id")
                .execute()
            #if DEBUG
            print("[CycleManager] cycle upsert OK for user \(op.userId) (start \(op.startDate))")
            #endif
            return true
        } catch {
            logRemoteError(operation: "cycle upsert", error: error)
            return false
        }
    }

    /// Abandons queued cycle writes for the signed-in user. Called by account
    /// deletion before the server delete so a reconnect can't replay them.
    func clearPendingQueueForCurrentUser() {
        if let userId = currentUserId() ?? activeUserId {
            writeQueue.clear(for: userId)
        }
        activeUserId = nil
    }

    /// Stable `cycles.id` for a (user, start_date): re-logging the same start
    /// upserts the same row instead of creating a duplicate. Pure, dependency-free
    /// (two FNV-1a passes → 16 bytes), so it's identical across launches/devices.
    static func deterministicCycleId(userId: UUID, startDate: String) -> UUID {
        let input = Array("\(userId.uuidString)|\(startDate)".utf8)
        func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            return hash
        }
        func octets(_ value: UInt64) -> [UInt8] {
            (0..<8).map { UInt8((value >> (8 * (7 - $0))) & 0xFF) }
        }
        let high = fnv1a(input, seed: 14695981039346656037)
        let low = fnv1a(input.reversed(), seed: 1099511628211)
        let b = octets(high) + octets(low)
        let uuid: uuid_t = (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
        return UUID(uuid: uuid)
    }

    // MARK: - Refresh from Supabase

    /// Pulls the signed-in user's profile + most recent cycle and writes them
    /// through to UserDefaults so the synchronous read API sees fresh data.
    @MainActor
    func refresh(userId: UUID) async {
        activeUserId = userId
        // Flush anything logged offline BEFORE reading the server.
        await replayQueue()

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

            // Newest start wins across the server's latest row AND anything still
            // pending (e.g. a replay above that failed while offline), so a refresh
            // never drops an unsynced log.
            let serverStart = cycles.first.flatMap { Self.dbDateFormatter.date(from: $0.startDate) }
            let pendingStarts = writeQueue.all(for: userId).compactMap { Self.dbDateFormatter.date(from: $0.startDate) }
            let newest = ([serverStart].compactMap { $0 } + pendingStarts).max()

            if let newest {
                lastPeriodDate = newest
            } else if cycles.isEmpty,
                      let localStart = UserDefaults.standard.object(forKey: "lastPeriodDate") as? Date {
                // The device knows a period start neither the server nor the queue
                // has (a pre-queue install, or an onboarding push that was refused).
                // Backfill it so partner share and other devices see this cycle.
                await insertInitialCycle(
                    userId: userId,
                    startDate: localStart,
                    cycleLength: cycleLength,
                    periodLength: periodLength
                )
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
        #if DEBUG
        if let pg = error as? PostgrestError {
            print("[CycleManager] \(operation) failed — PostgrestError code=\(pg.code ?? "nil") message=\"\(pg.message)\" detail=\(pg.detail ?? "nil") hint=\(pg.hint ?? "nil")")
        } else if let http = error as? HTTPError {
            let body = String(data: http.data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[CycleManager] \(operation) failed — HTTP \(http.response.statusCode): \(body)")
        } else {
            print("[CycleManager] \(operation) failed — \(type(of: error)): \(error.localizedDescription)")
        }
        #endif
    }
}

// MARK: - DB row representations

private struct ProfileUpsertRow: Encodable {
    let userId: UUID
    /// Optional on purpose: a name is never required (the app greets
    /// neutrally without one). When nil the key is omitted entirely, so an
    /// upsert never overwrites a name the server already has with null.
    let displayName: String?
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encode(birthDate, forKey: .birthDate)
        try c.encode(timezone, forKey: .timezone)
        try c.encode(defaultCycleLengthDays, forKey: .defaultCycleLengthDays)
        try c.encode(defaultPeriodLengthDays, forKey: .defaultPeriodLengthDays)
        try c.encode(onboardingCompletedAt, forKey: .onboardingCompletedAt)
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
