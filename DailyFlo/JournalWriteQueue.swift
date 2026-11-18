//
//  JournalWriteQueue.swift
//  DailyFlo
//
//  Persisted, per-user queue of journal writes that haven't reached Supabase
//  yet. Lets a journal entry written offline survive a relaunch and sync later
//  instead of being wiped by the next successful `refresh()`.
//
//  Each op is coalesced per entry id so a burst of edits collapses to a single
//  pending write:
//    insert → update   = one insert carrying the latest data
//    insert → softDelete = both dropped (the row never reached the server)
//    update → update   = the latest update
//    update → softDelete = a softDelete
//  Stored in UserDefaults under a per-user key, so signing in as a different
//  user never replays someone else's writes.
//

import Foundation

enum JournalWriteKind: String, Codable {
    // emotion_entries row
    case insert
    case update
    case softDelete
    // journal-photos Storage object for the entry
    case photoUpload
    case photoDelete

    /// Row ops and photo ops are coalesced independently, so a single entry id
    /// can hold one pending row op AND one pending photo op at once.
    var isPhoto: Bool { self == .photoUpload || self == .photoDelete }
}

/// One pending write. `entry` carries the full payload for insert/update and is
/// nil for a softDelete (only the id is needed).
struct JournalWriteOp: Codable {
    let kind: JournalWriteKind
    let id: UUID
    let entry: JournalEntry?
}

/// Thin coalescing wrapper over `PendingWriteStore`. Stateless itself —
/// everything lives in UserDefaults keyed by user id — so it's safe to hold as a
/// `let` and call from any actor.
struct JournalWriteQueue {
    private let store = PendingWriteStore<JournalWriteOp>(keyPrefix: "journal_pending_queue")

    /// The pending ops for a user, in replay order.
    func all(for userId: UUID) -> [JournalWriteOp] {
        store.all(for: userId)
    }

    /// Adds `op`, coalescing with any existing op of the SAME category (row vs
    /// photo) for the same id.
    func enqueue(_ op: JournalWriteOp, for userId: UUID) {
        var ops = store.all(for: userId)

        if let index = ops.firstIndex(where: { $0.id == op.id && $0.kind.isPhoto == op.kind.isPhoto }) {
            let existing = ops[index]
            switch (existing.kind, op.kind) {
            case (.insert, .softDelete):
                // A row insert that never synced, then a delete → forget both
                // (there's no server row to delete).
                ops.remove(at: index)
            case (.photoUpload, .photoDelete):
                // NOT drop-both: the photo may already be in Storage (the upload
                // synced, or is mid-flight in a replay snapshot), so the delete
                // MUST survive or the object is orphaned. Cancel the pending
                // upload but keep the delete; deleting a never-uploaded object is
                // a harmless no-op.
                ops[index] = op
            case (.insert, .insert), (.insert, .update):
                // Stays an insert, carrying the newest payload.
                ops[index] = JournalWriteOp(kind: .insert, id: op.id, entry: op.entry ?? existing.entry)
            default:
                // update→update, update→softDelete, softDelete→*, photoUpload→
                // photoUpload, photoDelete→*: the latest op wins.
                ops[index] = op
            }
        } else {
            ops.append(op)
        }

        store.save(ops, for: userId)
    }

    /// Removes a specific op after it syncs — but only if the stored op is byte-
    /// for-byte what we replayed. If the user re-edited the same id mid-replay,
    /// the newer op differs and is left to sync on the next pass.
    func remove(matching op: JournalWriteOp, for userId: UUID) {
        store.remove(matching: op, for: userId)
    }

    /// Drops the whole queue for a user (sign-out / account deletion).
    func clear(for userId: UUID) {
        store.clear(for: userId)
    }
}
