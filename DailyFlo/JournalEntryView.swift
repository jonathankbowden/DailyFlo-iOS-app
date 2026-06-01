//
//  JournalEntryView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI
import PhotosUI

/// Unified new + edit composer presented as a swipe-dismissable `.large`
/// sheet. Four-card layout — feeling, photo, voice, text — over a cream
/// background, with LOG CYCLE + CLOSE floating at the bottom.
///
/// `entry == nil` = new entry (creates via addEntry on CLOSE).
/// `entry != nil` = edit that entry (state seeded from it; CLOSE writes
/// back via updateEntry preserving the id; header shows a delete button).
struct JournalEntryView: View {
    let entry: JournalEntry?
    let journalManager: JournalManager
    let onDismiss: () -> Void

    @State private var selectedFeeling: String?
    @State private var entryDate: Date
    @State private var entryTitle: String
    @State private var entryBody: String
    @State private var showLogCycleModal: Bool = false
    @State private var showDatePicker: Bool = false
    @State private var selectedIntensity: Int
    @State private var isSaving: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var showVoiceEntry: Bool = false
    @State private var showTextEntry: Bool = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil
    @State private var showDeleteConfirm: Bool = false

    // Chip Dodd's eight core feelings.
    private let feelings = ["Sad", "Anger", "Fear", "Hurt", "Lonely", "Shame", "Guilt", "Glad"]

    // Display label → CoreEmotion lookup for save.
    private let feelingToEmotion: [String: CoreEmotion] = [
        "Sad": .sad, "Anger": .angry, "Fear": .afraid,
        "Hurt": .hurt, "Lonely": .lonely, "Shame": .ashamed,
        "Guilt": .guilty, "Glad": .glad
    ]

    // Reverse mapping for seeding `selectedFeeling` when editing an entry.
    private static let emotionToFeeling: [CoreEmotion: String] = [
        .sad: "Sad", .angry: "Anger", .afraid: "Fear",
        .hurt: "Hurt", .lonely: "Lonely", .ashamed: "Shame",
        .guilty: "Guilt", .glad: "Glad"
    ]

    init(
        entry: JournalEntry? = nil,
        journalManager: JournalManager,
        onDismiss: @escaping () -> Void
    ) {
        self.entry = entry
        self.journalManager = journalManager
        self.onDismiss = onDismiss

        if let entry {
            let parts = Self.splitNote(entry.note)
            _selectedFeeling = State(initialValue: Self.emotionToFeeling[entry.emotion])
            _entryDate = State(initialValue: entry.date)
            _entryTitle = State(initialValue: parts.title)
            _entryBody = State(initialValue: parts.body)
            _selectedIntensity = State(initialValue: entry.intensity)
        } else {
            _selectedFeeling = State(initialValue: nil)
            _entryDate = State(initialValue: Date())
            _entryTitle = State(initialValue: "")
            _entryBody = State(initialValue: "")
            _selectedIntensity = State(initialValue: 3)
        }
    }

    /// Inverse of saveEntry's `"\(title)\n\(body)"` join. If the stored
    /// note has a newline, split on the first one; otherwise treat the
    /// whole thing as the title and leave the body empty.
    private static func splitNote(_ note: String) -> (title: String, body: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            let title = String(trimmed[..<firstNewline])
                .trimmingCharacters(in: .whitespaces)
            let body = String(trimmed[trimmed.index(after: firstNewline)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, body)
        }
        return (trimmed, "")
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    editorHeader
                        .padding(.top, FloSpacing.sm)
                        .padding(.bottom, FloSpacing.md)

                    dateSection
                        .padding(.horizontal, FloSpacing.lg)
                        .fadeIn(delay: hasAppeared ? 0 : 0.1)

                    FloDivider()
                        .padding(.top, FloSpacing.md)
                        .padding(.horizontal, FloSpacing.lg)

                    VStack(spacing: FloSpacing.md) {
                        feelingCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.15)
                        photoCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.18)
                        textCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.2)
                        voiceCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.22)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.lg)

                    if entry != nil {
                        deleteEntryButton
                            .frame(maxWidth: .infinity)
                            .padding(.top, FloSpacing.xl)
                            .padding(.bottom, FloSpacing.lg)
                            .fadeIn(delay: hasAppeared ? 0 : 0.25)
                    }
                }
                .padding(.bottom, 140)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack {
                Spacer()
                floatingBottomButtons
                    .fadeIn(delay: hasAppeared ? 0 : 0.25)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showLogCycleModal) {
            LogCycleView(
                selectedDate: entryDate,
                onSave: { date in
                    Task { @MainActor in
                        await CycleManager.shared.logCycle(startDate: date)
                    }
                },
                onDismiss: { showLogCycleModal = false }
            )
        }
        .alert("Delete Entry?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let entry {
                    FloHaptics.success()
                    journalManager.deleteEntry(entry)
                    onDismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will be permanently removed.")
        }
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
        .sheet(isPresented: $showTextEntry) {
            TextEntryView(
                initialTitle: entryTitle,
                initialBody: entryBody,
                onComplete: { title, body in
                    entryTitle = title
                    entryBody = body
                    showTextEntry = false
                },
                onDismiss: { showTextEntry = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $entryDate, isPresented: $showDatePicker)
                .presentationDetents([.height(360)])
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

    // MARK: - Editor header (drag handle)
    private var editorHeader: some View {
        Capsule()
            .fill(Color.floGray.opacity(0.3))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom destructive action (edit mode only)
    private var deleteEntryButton: some View {
        Button {
            FloHaptics.light()
            showDeleteConfirm = true
        } label: {
            Text("DELETE ENTRY")
                .font(.floLabel)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundColor(.floCharcoal)
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel("Delete entry")
        .accessibilityHint("Permanently removes this entry")
    }

    // MARK: - Date section
    private var dateSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                Text("DATE")
                    .font(.floCaption)
                    .fontWeight(.black)
                    .foregroundColor(.floCharcoal)
                    .tracking(1.5)

                Text(formattedDate)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(.floCharcoal)
            }

            Spacer()

            Button {
                FloHaptics.light()
                showDatePicker = true
            } label: {
                Image("calendar")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .foregroundColor(.floCharcoal)
            }
            .buttonStyle(.floPressed)
        }
        .padding(.top, FloSpacing.lg)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: entryDate)
    }

    // MARK: - Card wrapper (chunky white card with sage border)
    private func cardWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(Color.white)
            .cornerRadius(FloRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.lg)
                    .stroke(Color.floSage.opacity(0.3), lineWidth: 1.5)
            )
            .shadow(
                color: FloShadow.small.color,
                radius: FloShadow.small.radius,
                x: 0,
                y: FloShadow.small.y
            )
    }

    // MARK: - 1. Feeling card
    private var feelingCard: some View {
        cardWrapper {
            VStack(alignment: .leading, spacing: FloSpacing.md) {
                HStack(spacing: FloSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.floSage.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "heart")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.floSage)
                    }

                    VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                        Text("SELECT A FEELING")
                            .font(.floLabel)
                            .fontWeight(.bold)
                            .foregroundColor(.floCharcoal)
                            .tracking(1.5)

                        Text(selectedFeeling ?? "How are you right now?")
                            .font(.floBodySmall)
                            .foregroundColor(selectedFeeling != nil ? .floTeal : .floGray)
                    }

                    Spacer()
                }

                let topRow = Array(feelings.prefix(4))
                let bottomRow = Array(feelings.suffix(4))

                VStack(spacing: FloSpacing.sm) {
                    HStack(spacing: FloSpacing.sm) {
                        ForEach(topRow, id: \.self) { feeling in
                            feelingChip(feeling)
                        }
                    }
                    HStack(spacing: FloSpacing.sm) {
                        ForEach(bottomRow, id: \.self) { feeling in
                            feelingChip(feeling)
                        }
                    }
                }
            }
            .padding(FloSpacing.lg)
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
                .font(.floLabel)
                .fontWeight(isSelected ? .bold : .medium)
                .tracking(0.5)
                .foregroundColor(isSelected ? .white : .floCharcoal)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: FloRadius.sm)
                        .fill(isSelected ? Color.floTeal : Color.floCream)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(feeling)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - 2. Photo card
    private var photoCard: some View {
        cardWrapper {
            VStack(spacing: 0) {
                if let photoImage {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photoImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipped()

                        Button {
                            FloHaptics.light()
                            withAnimation(FloAnimation.springSnappy) {
                                self.photoImage = nil
                                self.selectedPhoto = nil
                            }
                        } label: {
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        .buttonStyle(.floPressed)
                        .padding(FloSpacing.sm)
                    }
                } else if let assetName = entry?.userPhotoURL {
                    // Edit mode: existing entry already has a stored photo
                    // (currently an asset name). Tapping the swap badge
                    // opens the picker to replace it.
                    ZStack(alignment: .topTrailing) {
                        Image(assetName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipped()

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        .padding(FloSpacing.sm)
                        .accessibilityLabel("Change photo")
                    }
                } else {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: FloSpacing.md) {
                            ZStack {
                                Circle()
                                    .fill(Color.floSage.opacity(0.12))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "photo")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.floSage)
                            }

                            VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                                Text("ADD A PHOTO")
                                    .font(.floLabel)
                                    .fontWeight(.bold)
                                    .foregroundColor(.floCharcoal)
                                    .tracking(1.5)
                                Text("Attach an image to your entry")
                                    .font(.floBodySmall)
                                    .foregroundColor(.floGray)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.floGray.opacity(0.5))
                        }
                        .padding(FloSpacing.lg)
                    }
                    .buttonStyle(.floPressed)
                    .accessibilityLabel("Add a photo")
                }
            }
        }
    }

    // MARK: - 3. Voice card
    private var voiceCard: some View {
        cardWrapper {
            Button {
                FloHaptics.medium()
                showVoiceEntry = true
            } label: {
                HStack(spacing: FloSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.floSage.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.floSage)
                    }

                    VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                        Text("VOICE INPUT")
                            .font(.floLabel)
                            .fontWeight(.bold)
                            .foregroundColor(.floCharcoal)
                            .tracking(1.5)
                        Text("Tap to speak your thoughts")
                            .font(.floBodySmall)
                            .foregroundColor(.floGray)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.floGray.opacity(0.5))
                }
                .padding(FloSpacing.lg)
            }
            .buttonStyle(.floPressed)
        }
        .accessibilityLabel("Voice input")
        .accessibilityHint("Opens voice recording for journaling")
    }

    // MARK: - 4. Text card
    private var textCard: some View {
        cardWrapper {
            Button {
                FloHaptics.medium()
                showTextEntry = true
            } label: {
                HStack(spacing: FloSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.floSage.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.floSage)
                    }

                    VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                        Text("WRITE IT DOWN")
                            .font(.floLabel)
                            .fontWeight(.bold)
                            .foregroundColor(.floCharcoal)
                            .tracking(1.5)
                        Text(entryTitle.isEmpty && entryBody.isEmpty
                             ? "Title and body text"
                             : (entryTitle.isEmpty ? entryBody : entryTitle))
                            .font(.floBodySmall)
                            .foregroundColor(.floGray)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.floGray.opacity(0.5))
                }
                .padding(FloSpacing.lg)
            }
            .buttonStyle(.floPressed)
        }
        .accessibilityLabel("Write it down")
        .accessibilityHint("Opens title and body text fields")
    }

    // MARK: - Floating bottom buttons (LOG CYCLE + CLOSE)
    private var floatingBottomButtons: some View {
        HStack(spacing: FloSpacing.md) {
            Button {
                FloHaptics.medium()
                showLogCycleModal = true
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
            // Empty form on CLOSE: dismiss without writing. (For a new
            // entry this drops the empty draft; in edit mode `canSave`
            // stays true as long as anything is present, so an existing
            // entry can't be silently emptied this way.)
            FloHaptics.light()
            onDismiss()
            return
        }

        FloHaptics.light()
        isSaving = true

        let emotion = selectedFeeling.flatMap { feelingToEmotion[$0] }
            ?? entry?.emotion
            ?? .glad
        let fullNote = entryTitle.isEmpty
            ? entryBody
            : (entryBody.isEmpty ? entryTitle : "\(entryTitle)\n\(entryBody)")
        let phase = CycleManager.shared.phase(for: entryDate)

        if let existing = entry {
            let updated = JournalEntry(
                id: existing.id,
                date: entryDate,
                emotion: emotion,
                intensity: selectedIntensity,
                note: fullNote,
                cyclePhase: phase,
                userPhotoURL: existing.userPhotoURL
            )
            journalManager.updateEntry(updated)
        } else {
            let new = JournalEntry(
                date: entryDate,
                emotion: emotion,
                intensity: selectedIntensity,
                note: fullNote,
                cyclePhase: phase
            )
            journalManager.addEntry(new)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSaving = false
            FloHaptics.success()
            onDismiss()
        }
    }
}

// MARK: - Text Entry Drawer
/// A full-screen sheet for writing a journal entry's title and body.
/// Mirrors the voice entry flow so both modalities feel parallel.
struct TextEntryView: View {
    let initialTitle: String
    let initialBody: String
    var onComplete: (_ title: String, _ body: String) -> Void
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var hasAppeared: Bool = false
    @State private var showVoice: Bool = false
    @FocusState private var focused: Field?

    enum Field {
        case title, body
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.floGray.opacity(0.3))
                        .frame(width: 36, height: 5)
                    Spacer()
                }
                .padding(.top, FloSpacing.sm)
                .padding(.bottom, FloSpacing.md)

                HStack(alignment: .center) {
                    Text("Write it down")
                        .font(.floSerif(size: 28))
                        .foregroundColor(.floCharcoal)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button {
                        FloHaptics.medium()
                        focused = nil
                        showVoice = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.floSage.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.floSage)
                        }
                    }
                    .buttonStyle(.floPressed)
                    .accessibilityLabel("Dictate")
                    .accessibilityHint("Opens voice recording to fill title and body")
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.lg)

                TextField("Title", text: $title)
                    .font(.floLabel)
                    .fontWeight(.semibold)
                    .foregroundColor(.floCharcoal)
                    .tracking(1)
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.white)
                    .cornerRadius(FloRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloRadius.md)
                            .stroke(
                                focused == .title ? Color.floSage : Color.floGray.opacity(0.3),
                                lineWidth: focused == .title ? 2 : 1
                            )
                    )
                    .focused($focused, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focused = .body }
                    .padding(.horizontal, FloSpacing.lg)
                    .animation(FloAnimation.easeOutQuick, value: focused)
                    .accessibilityLabel("Journal entry title")

                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("Start typing here...")
                            .font(.floBodyMedium)
                            .foregroundColor(.floGray)
                            .padding(.top, FloSpacing.md + 4)
                            .padding(.horizontal, FloSpacing.lg + 4)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $bodyText)
                        .font(.floBodyMedium)
                        .foregroundColor(.floCharcoal)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, FloSpacing.md)
                        .padding(.vertical, FloSpacing.sm)
                        .focused($focused, equals: .body)
                        .accessibilityLabel("Journal entry content")
                }
                .background(Color.white)
                .cornerRadius(FloRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: FloRadius.md)
                        .stroke(
                            focused == .body ? Color.floSage : Color.floGray.opacity(0.3),
                            lineWidth: focused == .body ? 2 : 1
                        )
                )
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.md)
                .animation(FloAnimation.easeOutQuick, value: focused)

                Spacer(minLength: FloSpacing.lg)

                HStack(spacing: FloSpacing.md) {
                    Button {
                        FloHaptics.light()
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.floButton)
                            .foregroundColor(.floGray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FloSpacing.md)
                            .background(Color.white)
                            .cornerRadius(FloRadius.full)
                            .overlay(
                                RoundedRectangle(cornerRadius: FloRadius.full)
                                    .stroke(Color.floGray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.floPressed)

                    Button {
                        FloHaptics.success()
                        onComplete(title, bodyText)
                    } label: {
                        Text("Done")
                            .font(.floButton)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FloSpacing.md)
                            .background(Color.floSage)
                            .cornerRadius(FloRadius.full)
                            .shadow(color: Color.floSage.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.floPressed)
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.xl)
            }
        }
        .onAppear {
            title = initialTitle
            bodyText = initialBody
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                focused = .title
                hasAppeared = true
            }
        }
        .sheet(isPresented: $showVoice) {
            VoiceEntryView(
                onComplete: { voicedTitle, voicedBody in
                    title = voicedTitle
                    bodyText = voicedBody
                    showVoice = false
                },
                onDismiss: { showVoice = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
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

#Preview {
    JournalEntryView(
        journalManager: JournalManager.shared,
        onDismiss: {}
    )
}
