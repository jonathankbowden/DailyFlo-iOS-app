//
//  LogCycleView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Log Cycle View
/// Daily cycle logging. Per the locked product rule in CLAUDE.md, this view
/// never asks for symptoms or flow/heaviness — only a period-day marker and
/// optional notes.
struct LogCycleView: View {
    let selectedDate: Date
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var isPeriodDay = false
    @State private var notes = ""

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.floCream.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: FloSpacing.xl) {
                        dateHeader
                        periodToggle
                        notesSection

                        Spacer()
                            .frame(height: FloSpacing.xxl)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.md)
                }
            }
            .navigationTitle("Log Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        FloHaptics.light()
                        onDismiss()
                    }
                    .foregroundColor(.floGray)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        FloHaptics.success()
                        saveLog()
                    }
                    .font(.floButton)
                    .foregroundColor(.floSage)
                }
            }
        }
    }

    // MARK: - Date Header
    private var dateHeader: some View {
        let currentPhase = CycleManager.shared.phase(for: selectedDate)
        return VStack(spacing: FloSpacing.xs) {
            Text(dateFormatter.string(from: selectedDate))
                .font(.floDisplaySmall)
                .foregroundColor(.floCharcoal)

            HStack(spacing: FloSpacing.xs) {
                Circle()
                    .fill(currentPhase.color)
                    .frame(width: 8, height: 8)

                Text(currentPhase.name)
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
            }
        }
    }

    // MARK: - Period Toggle
    private var periodToggle: some View {
        VStack(spacing: FloSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    Text("Period Day?")
                        .font(.floBodyLarge)
                        .fontWeight(.medium)
                        .foregroundColor(.floCharcoal)

                    Text("Log if you're on your period")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                }

                Spacer()

                Toggle("", isOn: $isPeriodDay)
                    .toggleStyle(SwitchToggleStyle(tint: .phaseMenstrual))
            }
            .padding(FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        }
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("NOTES")
                .font(.floLabel)
                .fontWeight(.medium)
                .foregroundColor(.floGray)
                .tracking(1)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.floBodyMedium)
                    .frame(minHeight: 100)
                    .padding(FloSpacing.sm)
                    .background(Color.floCream)
                    .cornerRadius(FloRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloRadius.md)
                            .stroke(Color.floGray.opacity(0.2), lineWidth: 1)
                    )

                if notes.isEmpty {
                    Text("How are you feeling today?")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                        .padding(.horizontal, FloSpacing.md)
                        .padding(.top, FloSpacing.md + 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Save Action
    private func saveLog() {
        // Persistence is handled by the caller; this view just collects input
        // and delegates the actual write upstream.
        onSave()
        onDismiss()
    }
}

#Preview {
    LogCycleView(
        selectedDate: Date(),
        onSave: {},
        onDismiss: {}
    )
}
