//
//  LogCycleView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Log Cycle card
/// Compact "log a new period start" card. Per the locked product rule in
/// CLAUDE.md this never asks for symptoms, flow/heaviness, or notes — just a
/// start date. The caller does the write; `.logCycleModal` presents this card
/// floating over the current screen and writes through `CycleManager`.
struct LogCycleView: View {
    let selectedDate: Date
    let onSave: (Date) -> Void
    let onDismiss: () -> Void

    @State private var startDate: Date

    init(
        selectedDate: Date,
        onSave: @escaping (Date) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedDate = selectedDate
        self.onSave = onSave
        self.onDismiss = onDismiss
        _startDate = State(initialValue: selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Stone header strip with the round close X on the right.
            HStack {
                Spacer()
                RoundCloseButton(action: onDismiss)
                    .padding(.trailing, 10)
            }
            .frame(height: 62)
            .background(Color.floStone)

            Text("SELECT A START DATE:")
                .font(.system(size: 14, weight: .heavy))
                .tracking(3)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, FloSpacing.md)
                .padding(.top, 26)
                .padding(.bottom, FloSpacing.md)

            FloHairline()
                .padding(.horizontal, FloSpacing.lg)

            DatePicker(
                "Start date",
                selection: $startDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding(.horizontal, FloSpacing.md)

            OutlinedActionButton(title: "Log cycle", icon: "checkmark.circle") {
                FloHaptics.success()
                onSave(startDate)
                onDismiss()
            }
            .frame(width: 182)
            .padding(.top, FloSpacing.sm)
            .padding(.bottom, 28)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .floShadow(FloShadow.elevated)
    }
}

// MARK: - Floating modal presentation

extension View {
    /// Presents the Log Cycle card centered over the current screen, which is
    /// washed out with white rather than dimmed. Logging writes through
    /// `CycleManager.logCycle(startDate:)`; `onLogged` runs once the modal has
    /// finished dismissing after a successful log (not after a cancel).
    func logCycleModal(
        isPresented: Binding<Bool>,
        date: Date,
        onLogged: (() -> Void)? = nil
    ) -> some View {
        modifier(LogCycleModalModifier(isPresented: isPresented, date: date, onLogged: onLogged))
    }
}

private struct LogCycleModalModifier: ViewModifier {
    @Binding var isPresented: Bool
    let date: Date
    let onLogged: (() -> Void)?

    /// Drives the cover without the system slide-up; the card and wash
    /// animate themselves inside `LogCycleModalHost`.
    @State private var coverShown = false
    @State private var didLog = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if isPresented { setCover(true) }
            }
            .onChange(of: isPresented) { _, newValue in
                setCover(newValue)
            }
            .fullScreenCover(isPresented: $coverShown, onDismiss: {
                if isPresented { isPresented = false }
                if didLog {
                    didLog = false
                    onLogged?()
                }
            }) {
                LogCycleModalHost(
                    date: date,
                    onSave: { startDate in
                        didLog = true
                        Task { await CycleManager.shared.logCycle(startDate: startDate) }
                    },
                    onFinished: {
                        setCover(false)
                    }
                )
                .presentationBackground(.clear)
            }
    }

    private func setCover(_ shown: Bool) {
        guard coverShown != shown else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { coverShown = shown }
    }
}

/// White wash plus the floating card, fading and scaling in on appear and
/// out before the cover is removed.
private struct LogCycleModalHost: View {
    let date: Date
    let onSave: (Date) -> Void
    let onFinished: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)

            LogCycleView(
                selectedDate: date,
                onSave: onSave,
                onDismiss: close
            )
            .padding(.horizontal, 18)
            .scaleEffect(appeared ? 1 : 0.94)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(FloAnimation.easeOutMedium) { appeared = true }
        }
    }

    private func close() {
        withAnimation(FloAnimation.easeOutQuick) {
            appeared = false
        } completion: {
            onFinished()
        }
    }
}

#Preview {
    ZStack {
        Color.floBackground.ignoresSafeArea()
        LogCycleView(
            selectedDate: Date(),
            onSave: { _ in },
            onDismiss: {}
        )
        .padding(.horizontal, 18)
    }
}
