//
//  LogCycleView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Flow Level
enum FlowLevel: String, CaseIterable, Identifiable {
    case spotting = "Spotting"
    case light = "Light"
    case medium = "Medium"
    case heavy = "Heavy"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .spotting: return "drop"
        case .light: return "drop.fill"
        case .medium: return "drop.fill"
        case .heavy: return "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .spotting: return Color.phaseMenstrual.opacity(0.4)
        case .light: return Color.phaseMenstrual.opacity(0.6)
        case .medium: return Color.phaseMenstrual.opacity(0.8)
        case .heavy: return Color.phaseMenstrual
        }
    }

    var dropCount: Int {
        switch self {
        case .spotting: return 1
        case .light: return 2
        case .medium: return 3
        case .heavy: return 4
        }
    }
}

// MARK: - Symptom
struct Symptom: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let category: SymptomCategory
}

enum SymptomCategory: String, CaseIterable {
    case physical = "Physical"
    case mood = "Mood"
    case other = "Other"
}

// MARK: - Log Cycle View
struct LogCycleView: View {
    let selectedDate: Date
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var isPeriodDay = false
    @State private var selectedFlow: FlowLevel = .medium
    @State private var selectedSymptoms: Set<Symptom> = []
    @State private var notes = ""
    @State private var showSymptomPicker = false

    private let symptoms: [Symptom] = [
        // Physical
        Symptom(name: "Cramps", icon: "bolt.fill", category: .physical),
        Symptom(name: "Bloating", icon: "circle.fill", category: .physical),
        Symptom(name: "Headache", icon: "brain.head.profile", category: .physical),
        Symptom(name: "Fatigue", icon: "battery.25", category: .physical),
        Symptom(name: "Back Pain", icon: "figure.stand", category: .physical),
        Symptom(name: "Breast Tenderness", icon: "heart.fill", category: .physical),
        Symptom(name: "Acne", icon: "circle.hexagongrid.fill", category: .physical),
        Symptom(name: "Nausea", icon: "stomach", category: .physical),

        // Mood
        Symptom(name: "Irritable", icon: "cloud.bolt.fill", category: .mood),
        Symptom(name: "Anxious", icon: "exclamationmark.triangle.fill", category: .mood),
        Symptom(name: "Sad", icon: "cloud.rain.fill", category: .mood),
        Symptom(name: "Happy", icon: "sun.max.fill", category: .mood),
        Symptom(name: "Calm", icon: "leaf.fill", category: .mood),
        Symptom(name: "Energetic", icon: "bolt.fill", category: .mood),

        // Other
        Symptom(name: "Cravings", icon: "fork.knife", category: .other),
        Symptom(name: "Insomnia", icon: "moon.zzz.fill", category: .other),
        Symptom(name: "Vivid Dreams", icon: "sparkles", category: .other),
    ]

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
                        // Date header
                        dateHeader

                        // Period toggle
                        periodToggle

                        // Flow selector (only if period day)
                        if isPeriodDay {
                            flowSelector
                        }

                        // Symptoms section
                        symptomsSection

                        // Notes section
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
            .sheet(isPresented: $showSymptomPicker) {
                SymptomPickerSheet(
                    symptoms: symptoms,
                    selectedSymptoms: $selectedSymptoms
                )
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

            // Phase indicator
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

    // MARK: - Flow Selector
    private var flowSelector: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("FLOW LEVEL")
                .font(.floLabel)
                .fontWeight(.medium)
                .foregroundColor(.floGray)
                .tracking(1)

            HStack(spacing: FloSpacing.sm) {
                ForEach(FlowLevel.allCases) { flow in
                    FlowLevelButton(
                        flow: flow,
                        isSelected: selectedFlow == flow,
                        onTap: { selectedFlow = flow }
                    )
                }
            }
        }
        .padding(FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Symptoms Section
    private var symptomsSection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            HStack {
                Text("SYMPTOMS")
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floGray)
                    .tracking(1)

                Spacer()

                Button(action: {
                    showSymptomPicker = true
                }) {
                    HStack(spacing: FloSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.floBodySmall)
                    .foregroundColor(.floSage)
                }
            }

            if selectedSymptoms.isEmpty {
                // Empty state
                Button(action: {
                    showSymptomPicker = true
                }) {
                    HStack {
                        Spacer()
                        VStack(spacing: FloSpacing.sm) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.floGray.opacity(0.5))

                            Text("Tap to add symptoms")
                                .font(.floBodyMedium)
                                .foregroundColor(.floGray)
                        }
                        .padding(.vertical, FloSpacing.xl)
                        Spacer()
                    }
                }
            } else {
                // Selected symptoms
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: FloSpacing.sm) {
                    ForEach(Array(selectedSymptoms)) { symptom in
                        SymptomChip(symptom: symptom) {
                            selectedSymptoms.remove(symptom)
                        }
                    }
                }
            }
        }
        .padding(FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("NOTES")
                .font(.floLabel)
                .fontWeight(.medium)
                .foregroundColor(.floGray)
                .tracking(1)

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
                    .padding(.leading, FloSpacing.sm)
                    .offset(y: -90)
                    .allowsHitTesting(false)
            }
        }
        .padding(FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Save Action
    private func saveLog() {
        // Save to database/UserDefaults
        // In a real app, this would persist to your data store
        onSave()
        onDismiss()
    }
}

// MARK: - Flow Level Button
struct FlowLevelButton: View {
    let flow: FlowLevel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            FloHaptics.selection()
            onTap()
        }) {
            VStack(spacing: FloSpacing.xs) {
                // Drop indicators
                HStack(spacing: 2) {
                    ForEach(0..<flow.dropCount, id: \.self) { _ in
                        Image(systemName: flow.icon)
                            .font(.system(size: 12))
                            .foregroundColor(isSelected ? .white : flow.color)
                    }
                }
                .frame(height: 20)

                Text(flow.rawValue)
                    .font(.floLabel)
                    .foregroundColor(isSelected ? .white : .floCharcoal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FloSpacing.sm)
            .background(isSelected ? flow.color : Color.floCream)
            .cornerRadius(FloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.md)
                    .stroke(isSelected ? Color.clear : Color.floGray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isSelected ? flow.color.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.floPressed)
        .animation(FloAnimation.springSnappy, value: isSelected)
    }
}

// MARK: - Symptom Chip
struct SymptomChip: View {
    let symptom: Symptom
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: FloSpacing.xs) {
            Image(systemName: symptom.icon)
                .font(.system(size: 12))

            Text(symptom.name)
                .font(.floLabel)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.floGray)
            }
        }
        .foregroundColor(.floCharcoal)
        .padding(.horizontal, FloSpacing.sm)
        .padding(.vertical, FloSpacing.xs)
        .background(Color.floMint.opacity(0.3))
        .cornerRadius(FloRadius.full)
    }
}

// MARK: - Symptom Picker Sheet
struct SymptomPickerSheet: View {
    let symptoms: [Symptom]
    @Binding var selectedSymptoms: Set<Symptom>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FloSpacing.lg) {
                    ForEach(SymptomCategory.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: FloSpacing.md) {
                            Text(category.rawValue.uppercased())
                                .font(.floLabel)
                                .fontWeight(.medium)
                                .foregroundColor(.floGray)
                                .tracking(1)
                                .padding(.horizontal, FloSpacing.lg)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: FloSpacing.sm) {
                                ForEach(symptoms.filter { $0.category == category }) { symptom in
                                    SymptomSelectButton(
                                        symptom: symptom,
                                        isSelected: selectedSymptoms.contains(symptom),
                                        onToggle: {
                                            if selectedSymptoms.contains(symptom) {
                                                selectedSymptoms.remove(symptom)
                                            } else {
                                                selectedSymptoms.insert(symptom)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, FloSpacing.lg)
                        }
                    }
                }
                .padding(.vertical, FloSpacing.lg)
            }
            .background(Color.floCream)
            .navigationTitle("Add Symptoms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.floButton)
                    .foregroundColor(.floSage)
                }
            }
        }
    }
}

// MARK: - Symptom Select Button
struct SymptomSelectButton: View {
    let symptom: Symptom
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            FloHaptics.selection()
            onToggle()
        }) {
            HStack(spacing: FloSpacing.xs) {
                Image(systemName: symptom.icon)
                    .font(.system(size: 14))

                Text(symptom.name)
                    .font(.floBodySmall)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .floCharcoal)
            .padding(.horizontal, FloSpacing.sm)
            .padding(.vertical, FloSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.floSage : Color.white)
            .cornerRadius(FloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.md)
                    .stroke(isSelected ? Color.clear : Color.floGray.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

#Preview {
    LogCycleView(
        selectedDate: Date(),
        onSave: {},
        onDismiss: {}
    )
}
