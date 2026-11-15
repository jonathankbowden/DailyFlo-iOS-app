//
//  JournalManager.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import Foundation
import Network
import Supabase
import SwiftUI
import UIKit

// MARK: - Journal Manager
/// Source of truth for emotion journal entries.
///
/// Persistence model: Supabase `emotion_entries` is authoritative; UserDefaults
/// is an offline cache so the UI can render before/without a network round trip.
/// All public CRUD methods stay synchronous to match existing call sites — local
/// state and the cache update immediately, and the remote write is recorded in a
/// persisted per-user pending-write queue (`JournalWriteQueue`) and attempted.
///
/// Offline safety: a write made offline stays in the queue (survives relaunch)
/// and replays — in order, insert-as-upsert so a lost response can't duplicate —
/// on app foreground, on sign-in, when the network returns (NWPathMonitor), and
/// at the start of every `refresh()`. `refresh()` re-applies anything still
/// pending on top of the fetched server rows before publishing, so a round-trip
/// never drops unsynced work. The queue is cleared on sign-out and account
/// deletion so old writes can't resurrect a removed row.
///
/// Known v1 limitations:
/// - `entry_date` is a DATE in the DB, so the original time-of-day is lost on
///   round-trip. We use `created_at` to recover a time for display. If backdating
///   becomes important, add an `entry_at` TIMESTAMPTZ column to `emotion_entries`.
/// - User photos (`userPhotoURL`) are device-local only; they aren't in the
///   pending queue's server payload because `emotion_entries` has no photo column.
@Observable
class JournalManager {
    static let shared = JournalManager()

    var entries: [JournalEntry] = []

    private let saveKey = "journal_entries"
    private let table = "emotion_entries"

    /// Persisted, per-user queue of writes not yet confirmed by Supabase.
    private let writeQueue = JournalWriteQueue()
    /// The user whose queue is currently in play — remembered so we can clear it
    /// on sign-out, where the new auth state no longer carries a session.
    private var activeUserId: UUID?
    /// Re-entrancy guard so overlapping replay triggers (foreground + network +
    /// refresh) don't double-send.
    private var isReplaying = false

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "app.dailyflo.journal.network")

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        loadFromCache()
        collapseDuplicateDays()
        startNetworkMonitor()
        observeForeground()
        Task { @MainActor in
            await observeAuthState()
        }
    }

    /// Replays the pending queue whenever connectivity is (re)established.
    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.replayQueue() }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    /// Replays the pending queue each time the app returns to the foreground.
    private func observeForeground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.replayQueue() }
        }
    }

    // MARK: - CRUD Operations

    func addEntry(_ entry: JournalEntry) {
        // One-entry-per-day backstop (data layer). Primary enforcement lives in
        // the create surfaces: when a day already has an entry they open it for
        // editing instead of presenting a blank composer. This catches anything
        // that still reaches addEntry for an occupied day — merge into the
        // existing record rather than inserting a duplicate, so no note is lost.
        //
        // Follow-up (deferred): add a UNIQUE(user_id, entry_date) constraint on
        // emotion_entries so this invariant is enforced server-side too. Not done
        // in this task — duplicates still exist on un-migrated devices until
        // collapseDuplicateDays() has run everywhere.
        if let existing = self.entry(for: entry.date), existing.id != entry.id {
            updateEntry(Self.mergeDay([entry, existing], keepingIdOf: existing))
            return
        }

        entries.insert(entry, at: 0)
        saveToCache()
        enqueueAndReplay(JournalWriteOp(kind: .insert, id: entry.id, entry: entry), context: "addEntry")
    }

    func updateEntry(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveToCache()
        }
        enqueueAndReplay(JournalWriteOp(kind: .update, id: entry.id, entry: entry), context: "updateEntry")
    }

    func deleteEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        saveToCache()
        enqueueAndReplay(JournalWriteOp(kind: .softDelete, id: entry.id, entry: nil), context: "deleteEntry")
    }

    /// Records a write in the per-user queue and kicks off a replay. Local state
    /// and the cache have already been updated by the caller; with no session
    /// the op is simply held until sign-in. Public CRUD stays synchronous.
    private func enqueueAndReplay(_ op: JournalWriteOp, context: String) {
        guard let userId = currentUserId() else {
            #if DEBUG
            print("[JournalManager] \(context): no signed-in session — entry \(op.id) saved locally only")
            #endif
            return
        }
        activeUserId = userId
        writeQueue.enqueue(op, for: userId)
        Task { @MainActor in await replayQueue() }
    }

    // MARK: - Filtering

    func entries(for date: Date) -> [JournalEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The single entry for a calendar day, or nil. Under the one-entry-per-day
    /// rule the store holds at most one per day; if legacy duplicates survive
    /// (a day not yet processed by `collapseDuplicateDays`), the most recent one
    /// is returned so callers still land on the freshest content.
    func entry(for date: Date) -> JournalEntry? {
        entries(for: date).max { $0.date < $1.date }
    }

    func entries(for emotion: CoreEmotion) -> [JournalEntry] {
        entries.filter { $0.emotion == emotion }
    }

    func entriesThisWeek() -> [JournalEntry] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.filter { $0.date >= weekAgo }
    }

    func entriesThisMonth() -> [JournalEntry] {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return entries.filter { $0.date >= monthAgo }
    }

    // MARK: - Statistics

    func mostFrequentEmotion() -> CoreEmotion? {
        let counts = Dictionary(grouping: entries, by: { $0.emotion })
        return counts.max(by: { $0.value.count < $1.value.count })?.key
    }

    func averageIntensity(for emotion: CoreEmotion) -> Double {
        let emotionEntries = entries(for: emotion)
        guard !emotionEntries.isEmpty else { return 0 }
        let total = emotionEntries.reduce(0) { $0 + $1.intensity }
        return Double(total) / Double(emotionEntries.count)
    }

    // MARK: - One entry per day

    /// Merges several same-day entries into one, losslessly. Notes are
    /// concatenated newest-first beneath a soft divider — skipping any note whose
    /// text is already present, so a re-run can't double it — and the newest
    /// available photo is adopted when the surviving record has none. The
    /// survivor's identity (`keepingIdOf` when given, else the most-recent entry)
    /// decides which DB row and photo file stay authoritative.
    private static func mergeDay(_ dayEntries: [JournalEntry], keepingIdOf survivor: JournalEntry? = nil) -> JournalEntry {
        let newestFirst = dayEntries.sorted { $0.date > $1.date }
        let base = survivor ?? newestFirst[0]

        var combinedNote = ""
        for note in newestFirst.map({ $0.note.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard !note.isEmpty else { continue }
            if combinedNote.isEmpty {
                combinedNote = note
            } else if !combinedNote.contains(note) {
                combinedNote += "\n\n— earlier that day —\n" + note
            }
        }

        let adoptedPhoto = newestFirst.compactMap { $0.userPhotoURL }.first
        return JournalEntry(
            id: base.id,
            date: base.date,
            emotion: base.emotion,
            intensity: base.intensity,
            note: combinedNote,
            cyclePhase: base.phase,
            userPhotoURL: base.userPhotoURL ?? adoptedPhoto
        )
    }

    /// Non-destructive collapse of any calendar day holding more than one entry
    /// (legacy data created before the one-entry-per-day rule). The most-recent
    /// entry survives carrying the merged note — and a sibling photo if it had
    /// none — while the older duplicates are soft-deleted so their rows stay
    /// recoverable behind `deleted_at` and their photo files remain on disk.
    /// Idempotent: once every day holds a single entry it does nothing, so it's
    /// safe to call on load and after each `refresh()`.
    func collapseDuplicateDays() {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        let duplicateDays = byDay.filter { $0.value.count > 1 }
        guard !duplicateDays.isEmpty else { return }

        for (_, dayEntries) in duplicateDays {
            let newestFirst = dayEntries.sorted { $0.date > $1.date }
            updateEntry(Self.mergeDay(dayEntries))   // survivor defaults to most recent
            for loser in newestFirst.dropFirst() {
                deleteEntry(loser)                   // soft delete; keeps the photo file
            }
        }
        #if DEBUG
        print("[JournalManager] collapseDuplicateDays: merged \(duplicateDays.count) day(s) with duplicate entries")
        #endif
    }

    // MARK: - Remote sync

    /// Pulls the signed-in user's entries from Supabase and replaces the local
    /// list. No-op if not signed in. Leaves the cache untouched on failure.
    @MainActor
    func refresh() async {
        guard let userId = currentUserId() else { return }
        activeUserId = userId

        // Flush anything written offline BEFORE reading the server, so the fetch
        // ideally already includes it.
        await replayQueue()

        do {
            let rows: [EmotionEntryRow] = try await SupabaseClient.shared
                .from(table)
                .select()
                .eq("user_id", value: userId)
                .filter("deleted_at", operator: "is", value: "null")
                .order("entry_date", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value

            var merged = rows.compactMap { $0.toJournalEntry() }
            // Re-apply any ops STILL pending (e.g. the replay above failed while
            // offline) on top of the server rows, so a refresh never drops
            // unsynced work.
            merged = applyPending(to: merged, userId: userId)
            entries = merged
            // Collapse any day the server returned with more than one entry.
            // Runs on every refresh because a round-trip can resurface duplicates
            // another device hasn't soft-deleted yet; it's idempotent and a no-op
            // once each day holds a single entry.
            collapseDuplicateDays()
            saveToCache()
        } catch {
            #if DEBUG
            print("[JournalManager] refresh failed: \(error)")
            #endif
        }
    }

    // MARK: - Pending-write queue

    /// Sends each pending op in order, insert-as-upsert so a retry can't
    /// duplicate a row. Removes an op only once the server confirms it; stops at
    /// the first failure (likely offline) and leaves the rest for the next
    /// trigger. Re-entrant-safe via `isReplaying`.
    @MainActor
    func replayQueue() async {
        guard let userId = currentUserId() else { return }
        guard !isReplaying else { return }
        isReplaying = true
        defer { isReplaying = false }

        for op in writeQueue.all(for: userId) {
            let succeeded: Bool
            switch op.kind {
            case .insert:
                guard let entry = op.entry else { writeQueue.remove(matching: op, for: userId); continue }
                succeeded = await remoteUpsert(entry, userId: userId)
            case .update:
                guard let entry = op.entry else { writeQueue.remove(matching: op, for: userId); continue }
                succeeded = await remoteUpdate(entry, userId: userId)
            case .softDelete:
                succeeded = await remoteSoftDelete(id: op.id)
            }

            if succeeded {
                writeQueue.remove(matching: op, for: userId)
            } else {
                break
            }
        }
    }

    /// Overlays the still-pending ops onto a list of server rows: insert/update
    /// upsert the entry into the list; softDelete removes it.
    private func applyPending(to serverEntries: [JournalEntry], userId: UUID) -> [JournalEntry] {
        var result = serverEntries
        for op in writeQueue.all(for: userId) {
            switch op.kind {
            case .insert, .update:
                guard let entry = op.entry else { continue }
                if let index = result.firstIndex(where: { $0.id == entry.id }) {
                    result[index] = entry
                } else {
                    result.insert(entry, at: 0)
                }
            case .softDelete:
                result.removeAll { $0.id == op.id }
            }
        }
        return result
    }

    /// Abandons any queued offline writes for the signed-in user. Called by
    /// account deletion BEFORE the server delete so a reconnect can't replay old
    /// writes and resurrect a row the account removal just erased.
    func clearPendingQueueForCurrentUser() {
        if let userId = currentUserId() ?? activeUserId {
            writeQueue.clear(for: userId)
        }
        activeUserId = nil
    }

    /// Insert-or-update by id. Upsert (not insert) so replaying a write after a
    /// lost response can't create a duplicate row. Returns whether it reached
    /// the server.
    @discardableResult
    private func remoteUpsert(_ entry: JournalEntry, userId: UUID) async -> Bool {
        do {
            let row = EmotionEntryRow(from: entry, userId: userId)
            try await SupabaseClient.shared
                .from(table)
                .upsert(row, onConflict: "id")
                .execute()
            #if DEBUG
            print("[JournalManager] upsert OK for \(entry.id)")
            #endif
            return true
        } catch {
            logRemoteError(operation: "upsert", id: entry.id, error: error)
            return false
        }
    }

    @discardableResult
    private func remoteUpdate(_ entry: JournalEntry, userId: UUID) async -> Bool {
        do {
            let row = EmotionEntryRow(from: entry, userId: userId)
            try await SupabaseClient.shared
                .from(table)
                .update(row)
                .eq("id", value: entry.id)
                .execute()
            #if DEBUG
            print("[JournalManager] update OK for \(entry.id)")
            #endif
            return true
        } catch {
            logRemoteError(operation: "update", id: entry.id, error: error)
            return false
        }
    }

    @discardableResult
    private func remoteSoftDelete(id: UUID) async -> Bool {
        let payload = ["deleted_at": ISO8601DateFormatter().string(from: Date())]
        do {
            try await SupabaseClient.shared
                .from(table)
                .update(payload)
                .eq("id", value: id)
                .execute()
            #if DEBUG
            print("[JournalManager] soft-delete OK for \(id)")
            #endif
            return true
        } catch {
            logRemoteError(operation: "soft-delete", id: id, error: error)
            return false
        }
    }

    /// Unwraps the structured Supabase error types so the console message names
    /// the actual cause (RLS rejection, CHECK violation, network failure, etc).
    private func logRemoteError(operation: String, id: UUID, error: Error) {
        #if DEBUG
        if let pg = error as? PostgrestError {
            print("[JournalManager] \(operation) failed for \(id) — PostgrestError code=\(pg.code ?? "nil") message=\"\(pg.message)\" detail=\(pg.detail ?? "nil") hint=\(pg.hint ?? "nil")")
        } else if let http = error as? HTTPError {
            let body = String(data: http.data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[JournalManager] \(operation) failed for \(id) — HTTP \(http.response.statusCode): \(body)")
        } else {
            print("[JournalManager] \(operation) failed for \(id) — \(type(of: error)): \(error.localizedDescription) / \(error)")
        }
        #endif
    }

    // MARK: - Auth observation

    @MainActor
    private func observeAuthState() async {
        for await (event, session) in SupabaseClient.shared.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn:
                if let session {
                    activeUserId = session.user.id
                    // refresh() starts by replaying the queue, covering sign-in.
                    await refresh()
                }
            case .signedOut, .userDeleted:
                // Abandon any unsynced writes so they don't replay for the next
                // user, or after deletion.
                if let userId = activeUserId {
                    writeQueue.clear(for: userId)
                }
                activeUserId = nil
                entries = []
                clearCache()
            default:
                break
            }
        }
    }

    private func currentUserId() -> UUID? {
        SupabaseClient.shared.auth.currentSession?.user.id
    }

    // MARK: - Persistence (cache)

    private func saveToCache() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        }
        // No first-launch seeding: a fresh install starts with a genuinely empty
        // journal (calm empty state). Entries populate from Supabase once a
        // session refreshes. JournalEntry.sampleEntries is retained for previews only.
    }

    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: saveKey)
    }
}

// MARK: - DB row representation

private struct EmotionEntryRow: Codable {
    let id: UUID
    let userId: UUID
    let entryDate: String        // "yyyy-MM-dd"
    let primaryEmotion: String   // CoreEmotion.databaseValue
    let intensity: Int
    let notes: String?
    let voiceNoteUrl: String?
    let createdAt: Date?         // populated on decode, nil on encode

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case entryDate = "entry_date"
        case primaryEmotion = "primary_emotion"
        case intensity
        case notes
        case voiceNoteUrl = "voice_note_url"
        case createdAt = "created_at"
    }

    init(from entry: JournalEntry, userId: UUID) {
        self.id = entry.id
        self.userId = userId
        self.entryDate = JournalManager.formatDBDate(entry.date)
        self.primaryEmotion = entry.emotion.databaseValue
        self.intensity = entry.intensity
        self.notes = entry.note.isEmpty ? nil : entry.note
        self.voiceNoteUrl = nil
        self.createdAt = nil
    }

    // Don't encode created_at on insert/update; let the DB own it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(entryDate, forKey: .entryDate)
        try container.encode(primaryEmotion, forKey: .primaryEmotion)
        try container.encode(intensity, forKey: .intensity)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(voiceNoteUrl, forKey: .voiceNoteUrl)
    }

    func toJournalEntry() -> JournalEntry? {
        guard let emotion = CoreEmotion(databaseValue: primaryEmotion) else {
            #if DEBUG
            print("[JournalManager] dropping row \(id): unknown primary_emotion '\(primaryEmotion)'")
            #endif
            return nil
        }
        guard let date = JournalManager.mergeDateAndTime(dayString: entryDate, createdAt: createdAt) else {
            return nil
        }
        let phase = CycleManager.shared.phase(for: date)
        return JournalEntry(
            id: id,
            date: date,
            emotion: emotion,
            intensity: intensity,
            note: notes ?? "",
            cyclePhase: phase
        )
    }
}

// MARK: - Date helpers (file-private to JournalManager but reachable from row above)

extension JournalManager {
    fileprivate static func formatDBDate(_ date: Date) -> String {
        dbDateFormatter.string(from: date)
    }

    fileprivate static func mergeDateAndTime(dayString: String, createdAt: Date?) -> Date? {
        guard let day = dbDateFormatter.date(from: dayString) else { return nil }
        guard let createdAt else { return day }
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute, .second], from: createdAt)
        var components = cal.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return cal.date(from: components) ?? day
    }
}
