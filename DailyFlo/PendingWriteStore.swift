//
//  PendingWriteStore.swift
//  DailyFlo
//
//  Per-user, UserDefaults-backed persistence for a list of pending write ops.
//  Shared by the journal and cycle offline queues: it owns the load / save /
//  remove / clear boilerplate, while each queue layers its own coalescing on top
//  (journal has row-vs-photo rules; cycles are a simple per-id upsert).
//

import Foundation

struct PendingWriteStore<Op: Codable> {
    private let defaults = UserDefaults.standard
    private let keyPrefix: String

    init(keyPrefix: String) {
        self.keyPrefix = keyPrefix
    }

    private func key(for userId: UUID) -> String {
        "\(keyPrefix)_\(userId.uuidString)"
    }

    /// The pending ops for a user, in replay order.
    func all(for userId: UUID) -> [Op] {
        guard let data = defaults.data(forKey: key(for: userId)),
              let ops = try? JSONDecoder().decode([Op].self, from: data) else {
            return []
        }
        return ops
    }

    func save(_ ops: [Op], for userId: UUID) {
        if ops.isEmpty {
            defaults.removeObject(forKey: key(for: userId))
        } else if let data = try? JSONEncoder().encode(ops) {
            defaults.set(data, forKey: key(for: userId))
        }
    }

    /// Removes the op(s) byte-for-byte identical to `op` after it syncs. If the
    /// stored op changed since (a re-edit mid-replay), it differs and survives.
    func remove(matching op: Op, for userId: UUID) {
        let target = try? JSONEncoder().encode(op)
        var ops = all(for: userId)
        ops.removeAll { (try? JSONEncoder().encode($0)) == target }
        save(ops, for: userId)
    }

    /// Drops the whole queue for a user (sign-out / account deletion).
    func clear(for userId: UUID) {
        defaults.removeObject(forKey: key(for: userId))
    }
}
