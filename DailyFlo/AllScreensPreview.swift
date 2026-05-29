import SwiftUI

// Open this file and press Cmd+Option+Enter to see all screens in the Canvas
// Scroll through them in the preview pane

#Preview("1 - Splash") {
    SplashView()
}

#Preview("2 - Onboarding") {
    OnboardingView(isOnboardingComplete: .constant(false))
}

#Preview("3 - Sign In") {
    SignInView(isSignedIn: .constant(false))
}

#Preview("4 - Home / Calendar") {
    ContentView()
}

#Preview("5 - Calendar") {
    CalendarView()
}

#Preview("6 - Single Day") {
    SingleDayView(date: Date(), onDismiss: {})
}

#Preview("7 - Log Cycle") {
    LogCycleView(selectedDate: Date(), onSave: {}, onDismiss: {})
}

#Preview("8 - Phase Detail") {
    PhaseDetailView(phase: CyclePhase.follicular, onDismiss: {})
}

#Preview("9 - Journal") {
    JournalFeedMixPreview()
}

#Preview("9b - Journal Search List") {
    EmotionJournalView()
}

#Preview("9c - Journal (photo card)") {
    JournalPhotoCardPreview()
}

#Preview("10 - Journal Entry") {
    JournalEntryView(journalManager: JournalManager.shared, onDismiss: {})
}

#Preview("11 - Meditation") {
    MeditationMainView()
}

#Preview("12 - Connect") {
    ConnectMainView()
}

#Preview("13 - Profile") {
    ProfileMainView()
}

// MARK: - Preview helpers

/// Mixed-feed snapshot of the Journal tab:
///   • today = no entry → "Add entry" sliver
///   • two past days WITH photos (State-3 large cards)
///   • two past days WITHOUT photos (State-2 sliver cards)
/// Seeds the shared manager in init; preview-only — production data and
/// JournalEntry.sampleEntries are untouched.
private struct JournalFeedMixPreview: View {
    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }
        JournalManager.shared.entries = [
            JournalEntry(
                date: day(-1),
                emotion: .glad,
                intensity: 4,
                note: "A grounded morning\nWoke up to soft light and felt held.",
                cyclePhase: .ovulation,
                userPhotoURL: "greencliff"
            ),
            JournalEntry(
                date: day(-2),
                emotion: .sad,
                intensity: 3,
                note: "Missing my family\nA quiet evening. Called mom — that helped.",
                cyclePhase: .ovulation
            ),
            JournalEntry(
                date: day(-4),
                emotion: .lonely,
                intensity: 2,
                note: "Long walk alone\nThe trail was empty in a good way.",
                cyclePhase: .luteal,
                userPhotoURL: "mtns"
            ),
            JournalEntry(
                date: day(-5),
                emotion: .hurt,
                intensity: 3,
                note: "Tender today\nSomething a friend said landed harder than expected.",
                cyclePhase: .luteal
            )
        ]
    }

    var body: some View {
        JournalBaseView()
    }
}

/// Seeds the shared JournalManager with a top entry that opts into the
/// State-3 photo card (large image + bottom-right pencil badge), plus two
/// past entries in the default sliver state for natural scroll context.
/// Preview-only; production data and JournalEntry.sampleEntries are untouched.
private struct JournalPhotoCardPreview: View {
    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        JournalManager.shared.entries = [
            JournalEntry(
                date: today,
                emotion: .glad,
                intensity: 4,
                note: "A grounded morning\nWoke up to soft light and felt held.",
                cyclePhase: .ovulation,
                userPhotoURL: "greencliff"
            ),
            JournalEntry(
                date: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                emotion: .sad,
                intensity: 3,
                note: "Missing my family\nA quiet evening. Called mom — that helped.",
                cyclePhase: .ovulation
            ),
            JournalEntry(
                date: calendar.date(byAdding: .day, value: -2, to: today) ?? today,
                emotion: .hurt,
                intensity: 3,
                note: "Tender today\nSomething a friend said landed harder than expected.",
                cyclePhase: .luteal
            )
        ]
    }

    var body: some View {
        JournalBaseView()
    }
}

