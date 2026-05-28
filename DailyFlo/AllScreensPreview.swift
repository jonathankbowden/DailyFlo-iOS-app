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
    JournalBaseView()
}

#Preview("9b - Journal Search List") {
    EmotionJournalView()
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
