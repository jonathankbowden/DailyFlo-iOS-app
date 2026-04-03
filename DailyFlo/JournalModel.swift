//
//  JournalModel.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

// MARK: - Core Emotion (Chip Dodd Framework)
enum CoreEmotion: String, CaseIterable, Codable {
    case glad = "Glad"
    case sad = "Sad"
    case angry = "Angry"
    case afraid = "Afraid"
    case ashamed = "Ashamed"
    case hurt = "Hurt"
    case lonely = "Lonely"
    case guilty = "Guilty"

    var color: Color {
        switch self {
        case .glad: return .emotionGlad
        case .sad: return .emotionSad
        case .angry: return .emotionAngry
        case .afraid, .ashamed, .hurt, .lonely, .guilty: return .emotionFear
        }
    }

    var icon: String {
        switch self {
        case .glad: return "sun.max.fill"
        case .sad: return "cloud.rain.fill"
        case .angry: return "flame.fill"
        case .afraid: return "exclamationmark.triangle.fill"
        case .ashamed: return "eye.slash.fill"
        case .hurt: return "heart.slash.fill"
        case .lonely: return "person.fill.questionmark"
        case .guilty: return "hand.raised.fill"
        }
    }

    /// Nature photo mapped to each emotion for journal card backgrounds
    var photoName: String {
        switch self {
        case .glad: return "sunsetrocks"
        case .sad: return "cloudystars"
        case .angry: return "wavecrash"
        case .afraid: return "nightsky"
        case .ashamed: return "caves"
        case .hurt: return "rocks"
        case .lonely: return "starynight"
        case .guilty: return "mtns"
        }
    }
}

// MARK: - Journal Entry
struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let emotion: CoreEmotion
    let intensity: Int // 1-5 scale
    let note: String
    let cyclePhase: Int // Raw value of CyclePhase

    init(id: UUID = UUID(), date: Date = Date(), emotion: CoreEmotion, intensity: Int, note: String, cyclePhase: CyclePhase) {
        self.id = id
        self.date = date
        self.emotion = emotion
        self.intensity = intensity
        self.note = note
        self.cyclePhase = cyclePhase.rawValue
    }

    var phase: CyclePhase {
        CyclePhase(rawValue: cyclePhase) ?? .menstrual
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Sample Data
extension JournalEntry {
    static let sampleEntries: [JournalEntry] = [
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 0),
            emotion: .glad,
            intensity: 4,
            note: "Feeling grateful for the sunshine today. Had a lovely morning walk and the fresh air really lifted my spirits.",
            cyclePhase: .ovulation
        ),
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 1),
            emotion: .sad,
            intensity: 3,
            note: "Missing my family. Called mom which helped a lot. Sometimes you just need to hear a familiar voice.",
            cyclePhase: .ovulation
        ),
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 2),
            emotion: .angry,
            intensity: 2,
            note: "Frustrated with work deadlines but managed to stay calm. Deep breaths really do help.",
            cyclePhase: .follicular
        ),
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 3),
            emotion: .glad,
            intensity: 5,
            note: "Amazing yoga class this morning. My body feels strong and my mind is clear. Love this phase of my cycle!",
            cyclePhase: .follicular
        ),
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 5),
            emotion: .afraid,
            intensity: 3,
            note: "Anxious about the presentation next week. Writing down my fears helps put them in perspective.",
            cyclePhase: .menstrual
        ),
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 6),
            emotion: .lonely,
            intensity: 2,
            note: "Quiet evening at home. Journaling and tea are my companions tonight. It's okay to need alone time.",
            cyclePhase: .menstrual
        ),
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 8),
            emotion: .hurt,
            intensity: 3,
            note: "A comment from a friend stung today. Trying to give myself grace and remember it wasn't intentional.",
            cyclePhase: .luteal
        ),
        JournalEntry(
            date: Date().addingTimeInterval(-86400 * 10),
            emotion: .glad,
            intensity: 4,
            note: "Cooked a new recipe for dinner and it turned out beautifully. Small wins matter.",
            cyclePhase: .luteal
        )
    ]
}
