import SwiftUI

// Temporary helper - renders all screens to PNG files in the app's documents directory
// Delete this file after capturing screenshots

@MainActor
struct ScreenshotHelper {

    static func captureAllScreens() {
        let screens: [(String, AnyView)] = [
            ("01_calendar", AnyView(CalendarView())),
            ("02_journal", AnyView(EmotionJournalView())),
            ("03_journal_entry", AnyView(JournalEntryView(journalManager: JournalManager.shared, onDismiss: {}))),
            ("04_meditation", AnyView(MeditationMainView())),
            ("05_connect", AnyView(ConnectMainView())),
            ("06_profile", AnyView(ProfileMainView())),
            ("07_phase_detail", AnyView(PhaseDetailView(phase: CyclePhase.follicular, onDismiss: {}))),
            ("08_log_cycle", AnyView(LogCycleView(selectedDate: Date(), onSave: { _ in }, onDismiss: {}))),
            ("09_onboarding", AnyView(OnboardingView(isOnboardingComplete: .constant(false)))),
            ("10_signin", AnyView(SignInView(isSignedIn: .constant(false)))),
        ]

        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        for (name, view) in screens {
            let wrapper = view
                .frame(width: 393, height: 852)

            let renderer = ImageRenderer(content: wrapper)
            renderer.scale = 3.0

            if let image = renderer.uiImage, let data = image.pngData() {
                let url = docsDir.appendingPathComponent("\(name).png")
                try? data.write(to: url)
                print("Saved: \(url.lastPathComponent)")
            }
        }
        print("SCREENSHOTS_DONE: \(docsDir.path)")
    }
}
