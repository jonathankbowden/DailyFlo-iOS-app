//
//  TitleGenerator.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 3/22/26.
//

import Foundation
import FoundationModels

/// The result of distilling a raw voice transcript into a journal entry.
struct DistilledEntry {
    var title: String
    var body: String
}

/// Uses the on-device Foundation Model to distill a raw voice transcript
/// into a polished journal entry with both a title and body text.
struct TitleGenerator {

    @available(iOS 26.0, *)
    @Generable(description: "A distilled journal entry from a voice transcript")
    struct JournalEntry {
        @Guide(description: "A concise, reflective title for the journal entry, 2 to 6 words")
        var title: String

        @Guide(description: "The journal entry body text, distilled from the spoken transcript into clean, well-written prose. Preserve the author's voice and meaning but remove filler words, false starts, and repetitions. Use proper punctuation and paragraph breaks.")
        var body: String
    }

    /// Returns `true` when the on-device model is ready for use.
    @available(iOS 26.0, *)
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Distills a raw voice transcript into a polished journal entry with title and body.
    /// Falls back to simple extraction on pre-iOS-26 devices or when the model is unavailable.
    static func distill(from transcript: String) async -> DistilledEntry {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DistilledEntry(title: "", body: "")
        }

        if #available(iOS 26.0, *) {
            return await distillWithModel(trimmed)
        } else {
            return fallback(from: trimmed)
        }
    }

    @available(iOS 26.0, *)
    private static func distillWithModel(_ trimmed: String) async -> DistilledEntry {
        guard isAvailable else {
            return fallback(from: trimmed)
        }

        do {
            let session = LanguageModelSession(
                instructions: """
                    You are a journal assistant. The user spoke their journal entry aloud \
                    and you are given the raw transcript. Produce a short, reflective title \
                    (2 to 6 words, no quotes) and a clean body text. For the body, distill \
                    the spoken words into well-written prose. Preserve the author's voice, \
                    meaning, and emotional tone, but clean up filler words, false starts, \
                    repetitions, and awkward phrasing from speech-to-text. Use proper \
                    punctuation and paragraph breaks where appropriate.
                    """
            )

            let response = try await session.respond(
                to: trimmed,
                generating: JournalEntry.self
            )

            let title = response.content.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = response.content.body
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return DistilledEntry(
                title: title.isEmpty ? fallbackTitle(from: trimmed) : title,
                body: body.isEmpty ? trimmed : body
            )
        } catch {
            return fallback(from: trimmed)
        }
    }

    /// Generates only a title (kept for backward compatibility if needed).
    static func generateTitle(from text: String) async -> String {
        let entry = await distill(from: text)
        return entry.title
    }

    // MARK: - Fallback

    private static func fallback(from text: String) -> DistilledEntry {
        DistilledEntry(
            title: fallbackTitle(from: text),
            body: text
        )
    }

    /// Takes the first handful of words as a naive title.
    private static func fallbackTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(5)
        let title = words.joined(separator: " ")
        return title.count > 40 ? String(title.prefix(40)) + "..." : title
    }
}
