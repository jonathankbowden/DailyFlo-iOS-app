//
//  JournalManager.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

// MARK: - Journal Manager
@Observable
class JournalManager {
    static let shared = JournalManager()

    var entries: [JournalEntry] = []

    private let saveKey = "journal_entries"

    init() {
        loadEntries()
    }

    // MARK: - CRUD Operations

    func addEntry(_ entry: JournalEntry) {
        entries.insert(entry, at: 0)
        saveEntries()
    }

    func deleteEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func updateEntry(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveEntries()
        }
    }

    // MARK: - Filtering

    func entries(for date: Date) -> [JournalEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
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

    // MARK: - Persistence

    private func saveEntries() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadEntries() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        } else {
            // Load sample data for first launch
            entries = JournalEntry.sampleEntries
        }
    }
}
