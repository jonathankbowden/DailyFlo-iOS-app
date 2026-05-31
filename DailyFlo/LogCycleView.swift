//
//  LogCycleView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Log Cycle View
/// Compact "log a new period start" modal. Per the locked product rule
/// in CLAUDE.md this view never asks for symptoms, flow/heaviness, or
/// notes — just a start date. The owning caller is responsible for the
/// actual cycle write (typically `CycleManager.shared.logCycle(startDate:)`).
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
        ZStack(alignment: .topTrailing) {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: FloSpacing.lg) {
                Text("SELECT A START DATE:")
                    .font(.floLabel)
                    .fontWeight(.semibold)
                    .foregroundColor(.floCharcoal)
                    .tracking(1.5)
                    .padding(.top, FloSpacing.xl)

                FloDivider(color: Color.floLightGray, thickness: 0.5)
                    .padding(.horizontal, FloSpacing.lg)

                DatePicker(
                    "",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, FloSpacing.lg)

                Button {
                    FloHaptics.success()
                    onSave(startDate)
                    onDismiss()
                } label: {
                    HStack(spacing: FloSpacing.sm) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 18, weight: .medium))
                        Text("LOG CYCLE")
                            .tracking(1.5)
                    }
                }
                .buttonStyle(FloSecondaryButtonStyle())
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            closeButton
                .padding(.top, FloSpacing.lg)
                .padding(.trailing, FloSpacing.lg)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private var closeButton: some View {
        Button {
            FloHaptics.light()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.floCharcoal)
                .frame(width: 32, height: 32)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel("Close")
    }
}

#Preview {
    LogCycleView(
        selectedDate: Date(),
        onSave: { _ in },
        onDismiss: {}
    )
}
