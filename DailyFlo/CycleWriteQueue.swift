//
//  CycleWriteQueue.swift
//  DailyFlo
//
//  Persisted, per-user queue of cycle writes that haven't reached Supabase yet,
//  so a period logged offline survives a relaunch and syncs on reconnect instead
//  of being dropped by the next server refresh.
//
//  There's a single op kind — upsert a `cycles` row — and the row id is derived
//  deterministically from (user, start_date) by the caller, so re-logging the
//  same start coalesces to one row and a retry can't duplicate. Coalescing is
//  therefore just "latest wins per id".
//

import Foundation

/// One pending cycle upsert. Field names match the `cycles` columns, so the same
/// value is used both for on-disk persistence and the Supabase upsert payload.
struct CycleWriteOp: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let startDate: String          // "yyyy-MM-dd"
    let predictedEndDate: String   // "yyyy-MM-dd"
    let periodLengthDays: Int
    let isPredicted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startDate = "start_date"
        case predictedEndDate = "predicted_end_date"
        case periodLengthDays = "period_length_days"
        case isPredicted = "is_predicted"
    }
}

struct CycleWriteQueue {
    private let store = PendingWriteStore<CycleWriteOp>(keyPrefix: "cycle_pending_queue")

    func all(for userId: UUID) -> [CycleWriteOp] {
        store.all(for: userId)
    }

    /// Adds `op`, replacing any existing op with the same id (latest wins).
    func enqueue(_ op: CycleWriteOp, for userId: UUID) {
        var ops = store.all(for: userId)
        if let index = ops.firstIndex(where: { $0.id == op.id }) {
            ops[index] = op
        } else {
            ops.append(op)
        }
        store.save(ops, for: userId)
    }

    func remove(matching op: CycleWriteOp, for userId: UUID) {
        store.remove(matching: op, for: userId)
    }

    func clear(for userId: UUID) {
        store.clear(for: userId)
    }
}
