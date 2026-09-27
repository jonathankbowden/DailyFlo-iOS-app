//
//  FeelingSheet.swift
//  DailyFlo
//
//  Quick "How are you feeling?" bottom sheet opened from Home's feeling
//  card. Saves the feeling onto the day's entry — updating it if the day
//  already has one, else creating it (JournalManager keeps one per day).
//

import SwiftUI

struct FeelingSheet: View {
    let date: Date
    let onDismiss: () -> Void

    @State private var selection: CoreEmotion?

    private let journalManager = JournalManager.shared
    private let cycleManager = CycleManager.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    init(date: Date = Date(), onDismiss: @escaping () -> Void) {
        self.date = date
        self.onDismiss = onDismiss
        _selection = State(initialValue: JournalManager.shared.entry(for: date)?.emotion)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()

            HStack {
                Spacer()
                RoundCloseButton(action: onDismiss)
            }
            .padding(.horizontal, FloSpacing.md)

            Text("How are you feeling?")
                .font(.floLunary(size: 28))
                .foregroundStyle(Color.black)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.floGray)
                .padding(.top, 6)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CoreEmotion.allCases, id: \.self) { emotion in
                    feelingButton(emotion)
                }
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.lg)

            Button("Save", action: save)
                .buttonStyle(.floPrimary(disabled: selection == nil))
                .disabled(selection == nil)
                .floHitTargetFullWidth()
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.lg)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color.floBackground.ignoresSafeArea())
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
    }

    private func feelingButton(_ emotion: CoreEmotion) -> some View {
        let isSelected = selection == emotion
        return Button {
            FloHaptics.selection()
            withAnimation(FloAnimation.springSnappy) { selection = emotion }
        } label: {
            Text(emotion.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.floTeal : Color.floButtonFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.floTeal : Color.floInk, lineWidth: 1.5)
                )
        }
        .buttonStyle(.floPressed)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return "\(formatter.string(from: date)) · \(cycleManager.phase(for: date).name)"
    }

    private func save() {
        guard let emotion = selection else { return }
        if let existing = journalManager.entry(for: date) {
            journalManager.updateEntry(existing.updating(emotion: emotion))
        } else {
            journalManager.addEntry(
                JournalEntry(
                    date: date,
                    emotion: emotion,
                    intensity: 3,
                    note: "",
                    cyclePhase: cycleManager.phase(for: date)
                )
            )
        }
        FloHaptics.success()
        onDismiss()
    }
}

#Preview {
    Color.gray.sheet(isPresented: .constant(true)) {
        FeelingSheet(onDismiss: {})
    }
}
