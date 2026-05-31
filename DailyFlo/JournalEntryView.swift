//
//  JournalEntryView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI
import PhotosUI

/// New-entry composer presented as a swipe-dismissable `.large` sheet.
/// Matches Brittany's "Journal — Entry Overlay" mockup: DATE row, feeling
/// chip strip, one merged entry card (image + title + body + mic), and
/// floating LOG CYCLE / CLOSE buttons.
struct JournalEntryView: View {
    var journalManager: JournalManager
    var onDismiss: () -> Void

    @State private var selectedFeeling: String? = nil
    @State private var entryDate: Date = Date()
    @State private var dateChosen: Bool = false
    @State private var entryTitle: String = ""
    @State private var entryBody: String = ""
    @State private var showLogCycleModal: Bool = false
    @State private var showDatePicker: Bool = false
    @State private var selectedIntensity: Int = 3
    @State private var isSaving: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var showVoiceEntry: Bool = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil

    // Chip Dodd's eight core feelings.
    private let feelings = ["Sad", "Anger", "Fear", "Hurt", "Lonely", "Shame", "Guilt", "Glad"]

    // Display label → CoreEmotion lookup for save + placeholder image.
    private let feelingToEmotion: [String: CoreEmotion] = [
        "Sad": .sad, "Anger": .angry, "Fear": .afraid,
        "Hurt": .hurt, "Lonely": .lonely, "Shame": .ashamed,
        "Guilt": .guilty, "Glad": .glad
    ]

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    dragIndicator
                        .padding(.top, FloSpacing.sm)
                        .padding(.bottom, FloSpacing.md)

                    dateRow
                        .padding(.horizontal, FloSpacing.lg)
                        .padding(.top, FloSpacing.md)

                    FloDivider(color: Color.floLightGray, thickness: 0.5)
                        .padding(.horizontal, FloSpacing.lg)
                        .padding(.top, FloSpacing.md)

                    feelingSection
                        .padding(.top, FloSpacing.lg)

                    FloDivider(color: Color.floLightGray, thickness: 0.5)
                        .padding(.horizontal, FloSpacing.lg)
                        .padding(.top, FloSpacing.lg)

                    entryCard
                        .padding(.horizontal, FloSpacing.lg)
                        .padding(.top, FloSpacing.lg)
                }
                .padding(.bottom, 140)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack {
                Spacer()
                floatingBottomButtons
            }
            .ignoresSafeArea(.container, edges: .bottom)

            if showLogCycleModal {
                LogCycleModal(isPresented: $showLogCycleModal)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .presentationDetents([.large])
        .animation(FloAnimation.easeOutMedium, value: showLogCycleModal)
        .sheet(isPresented: $showVoiceEntry) {
            VoiceEntryView(
                onComplete: { title, body in
                    entryTitle = title
                    entryBody = body
                    showVoiceEntry = false
                },
                onDismiss: { showVoiceEntry = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $entryDate, isPresented: $showDatePicker)
                .presentationDetents([.height(360)])
        }
        .onChange(of: showDatePicker) { _, newValue in
            // Mark a real selection when the picker closes (initial value
            // counts once the user has confirmed via "Done").
            if newValue == false {
                dateChosen = true
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    withAnimation(FloAnimation.springSnappy) {
                        photoImage = image
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Drag indicator
    private var dragIndicator: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.floGray.opacity(0.3))
                .frame(width: 36, height: 5)
            Spacer()
        }
    }

    // MARK: - Date row
    private var dateRow: some View {
        Button {
            FloHaptics.light()
            showDatePicker = true
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                    Text("DATE")
                        .font(.floLabel)
                        .fontWeight(.bold)
                        .foregroundColor(.floCharcoal)
                        .tracking(1.5)

                    if dateChosen {
                        Text(formattedDate)
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(.floCharcoal)
                    } else {
                        Text("Enter date here…")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(.floGray.opacity(0.6))
                    }
                }

                Spacer()

                Image("calendar")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .foregroundColor(.floCharcoal)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date: \(dateChosen ? formattedDate : "Not set")")
        .accessibilityHint("Opens the date picker")
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: entryDate)
    }

    // MARK: - Feeling section (serif label + horizontal chip scroll)
    private var feelingSection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("Feeling:")
                .font(.floSerif(size: 28))
                .foregroundColor(.floCharcoal)
                .padding(.horizontal, FloSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FloSpacing.sm) {
                    ForEach(feelings, id: \.self) { feeling in
                        feelingChip(feeling)
                    }
                }
                .padding(.horizontal, FloSpacing.lg)
            }
        }
    }

    private func feelingChip(_ feeling: String) -> some View {
        let isSelected = selectedFeeling == feeling
        return Button {
            FloHaptics.selection()
            withAnimation(FloAnimation.springSnappy) {
                selectedFeeling = isSelected ? nil : feeling
            }
        } label: {
            Text(feeling)
                .font(.floSerif(size: 20))
                .foregroundColor(isSelected ? .white : .floCharcoal)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.vertical, FloSpacing.sm)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.floSage : Color.floCream)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.floLightGray, lineWidth: 0.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(feeling)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Entry card (image + title + body + mic, one container)
    private var entryCard: some View {
        VStack(spacing: 0) {
            imageBanner
                .zIndex(1)

            VStack(alignment: .leading, spacing: 0) {
                TextField(
                    "",
                    text: $entryTitle,
                    prompt: Text("ENTER TITLE")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.floGray.opacity(0.5))
                )
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.floCharcoal)
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.lg + FloSpacing.sm)
                .accessibilityLabel("Entry title")

                FloDivider(color: Color.floLightGray, thickness: 0.5)
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.vertical, FloSpacing.md)

                ZStack(alignment: .topLeading) {
                    if entryBody.isEmpty {
                        Text("Start typing or talk here…")
                            .font(.floBodyLarge)
                            .foregroundColor(.floGray.opacity(0.6))
                            .padding(.horizontal, FloSpacing.lg + 4)
                            .padding(.top, FloSpacing.sm + 4)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $entryBody)
                        .font(.floBodyLarge)
                        .foregroundColor(.floCharcoal)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, FloSpacing.md)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Entry body")
                }

                HStack {
                    Spacer()
                    micButton
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.lg)
            }
            .background(Color.white)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: FloRadius.xl, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
    }

    /// Image area at the top of the entry card. Large when the user has
    /// uploaded a photo; otherwise a 72pt sliver of the selected feeling's
    /// nature image (or a neutral default). The white-circle edit-pencil
    /// badge straddles the bottom edge — tap opens the system photo picker.
    private var imageBanner: some View {
        Group {
            if let photoImage {
                Color.clear
                    .aspectRatio(339.0 / 213.0, contentMode: .fit)
                    .overlay(
                        Image(uiImage: photoImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipped()
            } else {
                Image(placeholderImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .clipped()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.floCharcoal)
                }
                .frame(width: 36, height: 36)
                .padding(.trailing, FloSpacing.md)
                .offset(y: 18)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            }
            .accessibilityLabel(photoImage == nil ? "Add a photo" : "Change photo")
        }
    }

    /// Defaults to the selected feeling's nature photo so the sliver feels
    /// consistent with the day-card visuals; falls back to a calm neutral.
    private var placeholderImageName: String {
        if let feeling = selectedFeeling,
           let emotion = feelingToEmotion[feeling] {
            return emotion.photoName
        }
        return "sunsetrocks"
    }

    private var micButton: some View {
        Button {
            FloHaptics.medium()
            showVoiceEntry = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.floSage)
                    .shadow(color: Color.floSage.opacity(0.3), radius: 6, x: 0, y: 3)
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel("Voice input")
        .accessibilityHint("Opens voice recording for journaling")
    }

    // MARK: - Floating bottom buttons
    private var floatingBottomButtons: some View {
        HStack(spacing: FloSpacing.md) {
            Button {
                FloHaptics.medium()
                withAnimation(FloAnimation.easeOutMedium) {
                    showLogCycleModal = true
                }
            } label: {
                HStack(spacing: FloSpacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .medium))
                    Text("LOG CYCLE")
                        .tracking(1.5)
                }
            }
            .buttonStyle(FloSecondaryButtonStyle())
            .accessibilityLabel("Log cycle")

            Button(action: saveEntry) {
                HStack(spacing: FloSpacing.sm) {
                    if isSaving {
                        FloLoadingIndicator(size: 16, color: .white, lineWidth: 2)
                    } else {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 18, weight: .medium))
                        Text("CLOSE")
                            .tracking(1.5)
                    }
                }
            }
            .buttonStyle(FloPrimaryButtonStyle(isDisabled: !canSave || isSaving))
            .disabled(!canSave || isSaving)
            .accessibilityLabel("Save and close")
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.md)
        .padding(.bottom, FloSpacing.lg)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.4)
                    )
                )
                .allowsHitTesting(false)
        )
    }

    // MARK: - Save gate
    private var canSave: Bool {
        selectedFeeling != nil || !entryTitle.isEmpty || !entryBody.isEmpty
    }

    // MARK: - Actions
    private func saveEntry() {
        guard canSave else {
            // Even an empty CLOSE should dismiss — but only swallow the tap
            // if there's literally nothing to save. Per spec, CLOSE runs the
            // existing save path and dismisses, so for an empty form just
            // dismiss without writing.
            FloHaptics.light()
            onDismiss()
            return
        }

        FloHaptics.light()
        isSaving = true

        let emotion = selectedFeeling.flatMap { feelingToEmotion[$0] } ?? .glad
        let fullNote = entryTitle.isEmpty
            ? entryBody
            : (entryBody.isEmpty ? entryTitle : "\(entryTitle)\n\(entryBody)")

        let entry = JournalEntry(
            date: entryDate,
            emotion: emotion,
            intensity: selectedIntensity,
            note: fullNote,
            cyclePhase: CycleManager.shared.phase(for: entryDate)
        )

        journalManager.addEntry(entry)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSaving = false
            FloHaptics.success()
            onDismiss()
        }
    }
}

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: FloSpacing.md) {
            Capsule()
                .fill(Color.floGray.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, FloSpacing.sm)

            Text("Select Date")
                .font(.floDisplaySmall)
                .foregroundColor(.floCharcoal)

            DatePicker(
                "",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            Button {
                FloHaptics.light()
                isPresented = false
            } label: {
                Text("Done")
                    .font(.floButton)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.floSage)
                    .cornerRadius(FloRadius.full)
            }
            .buttonStyle(.floPressed)
            .padding(.horizontal, FloSpacing.lg)
            .padding(.bottom, FloSpacing.lg)
        }
        .background(Color.floCream)
    }
}

// MARK: - Log Cycle Modal (inline overlay invoked by LOG CYCLE button)
struct LogCycleModal: View {
    @Binding var isPresented: Bool
    @State private var selectedDate: Date = Date()

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    FloHaptics.light()
                    isPresented = false
                }

            VStack(spacing: 0) {
                ZStack {
                    Color(hex: "F5F5F5")
                        .frame(height: 60)

                    HStack {
                        Text("Log Cycle")
                            .font(.floBodyLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(.floCharcoal)
                            .padding(.leading, FloSpacing.lg)

                        Spacer()

                        Button {
                            FloHaptics.light()
                            isPresented = false
                        } label: {
                            Circle()
                                .stroke(Color.floCharcoal, lineWidth: 1.5)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.floCharcoal)
                                )
                        }
                        .buttonStyle(.floPressed)
                        .padding(.trailing, FloSpacing.lg)
                        .accessibilityLabel("Close")
                    }
                }

                VStack(spacing: FloSpacing.lg) {
                    Text("SELECT A START DATE:")
                        .font(.floLabel)
                        .fontWeight(.semibold)
                        .foregroundColor(.floCharcoal)
                        .tracking(1.5)

                    FloDivider()
                        .padding(.horizontal, FloSpacing.xl)

                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 150)

                    Button {
                        FloHaptics.success()
                        // CycleManager handles the local UserDefaults write
                        // and the Supabase insert; the Task is fire-and-forget
                        // so dismissing the modal doesn't block on the network.
                        Task { @MainActor in
                            await CycleManager.shared.logCycle(startDate: selectedDate)
                        }
                        isPresented = false
                    } label: {
                        HStack(spacing: FloSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text("LOG CYCLE")
                                .font(.floLabel)
                                .fontWeight(.semibold)
                                .tracking(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, FloSpacing.xl)
                        .padding(.vertical, FloSpacing.md)
                        .background(Color.floSage)
                        .cornerRadius(FloRadius.full)
                        .shadow(color: Color.floSage.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.floPressed)
                    .padding(.bottom, FloSpacing.xl)
                }
                .padding(.top, FloSpacing.xl)
                .background(Color.white)
            }
            .background(Color.white)
            .cornerRadius(FloRadius.xl)
            .padding(.horizontal, FloSpacing.lg)
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        }
    }
}

#Preview {
    JournalEntryView(
        journalManager: JournalManager.shared,
        onDismiss: {}
    )
}
