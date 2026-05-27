//
//  JournalEntryView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI
import PhotosUI

struct JournalEntryView: View {
    var journalManager: JournalManager
    var onDismiss: () -> Void

    @State private var selectedFeeling: String? = nil
    @State private var entryDate: Date = Date()
    @State private var entryTitle: String = ""
    @State private var entryBody: String = ""
    @State private var showLogCycleModal: Bool = false
    @State private var showDatePicker: Bool = false
    @State private var selectedIntensity: Int = 3
    @State private var isSaving: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var showVoiceEntry: Bool = false
    @State private var showTextEntry: Bool = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil

    // Chip Dodd's eight core feelings
    private let feelings = ["Sad", "Anger", "Fear", "Hurt", "Lonely", "Shame", "Guilt", "Glad"]

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Drag indicator
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.floGray.opacity(0.3))
                            .frame(width: 36, height: 5)
                        Spacer()
                    }
                    .padding(.top, FloSpacing.sm)
                    .padding(.bottom, FloSpacing.md)

                    // Date field
                    dateSection
                        .padding(.horizontal, FloSpacing.lg)
                        .fadeIn(delay: hasAppeared ? 0 : 0.1)

                    // Divider
                    dividerLine
                        .padding(.top, FloSpacing.md)
                        .padding(.horizontal, FloSpacing.lg)

                    // Four input cards - uniform chunky styling
                    VStack(spacing: FloSpacing.md) {
                        feelingCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.15)

                        photoCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.18)

                        voiceCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.2)

                        textCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.22)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.lg)
                }
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)

            // Floating bottom buttons
            VStack {
                Spacer()
                floatingBottomButtons
                    .fadeIn(delay: hasAppeared ? 0 : 0.25)
            }
            .ignoresSafeArea(.container, edges: .bottom)

            // Log Cycle Modal
            if showLogCycleModal {
                LogCycleModal(isPresented: $showLogCycleModal)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(FloAnimation.easeOutMedium, value: showLogCycleModal)
        .sheet(isPresented: $showVoiceEntry) {
            VoiceEntryView(
                onComplete: { title, body in
                    entryTitle = title
                    entryBody = body
                    showVoiceEntry = false
                },
                onDismiss: {
                    showVoiceEntry = false
                }
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
                onDismiss: {
                    showTextEntry = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Date Section
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

            Button(action: {
                FloHaptics.light()
                showDatePicker = true
            }) {
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
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $entryDate, isPresented: $showDatePicker)
                .presentationDetents([.height(300)])
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: entryDate)
    }

    // MARK: - Divider
    private var dividerLine: some View {
        FloDivider()
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
            .shadow(color: FloShadow.small.color, radius: FloShadow.small.radius, x: 0, y: FloShadow.small.y)
    }

    // MARK: - 1. Feeling Card
    private var feelingCard: some View {
        cardWrapper {
            VStack(alignment: .leading, spacing: FloSpacing.md) {
                // Header row
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

                // Feeling chips - two rows
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
        return Button(action: {
            FloHaptics.selection()
            withAnimation(FloAnimation.springSnappy) {
                selectedFeeling = isSelected ? nil : feeling
            }
        }) {
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

    // MARK: - 2. Photo Card
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

                        Button(action: {
                            FloHaptics.light()
                            withAnimation(FloAnimation.springSnappy) {
                                self.photoImage = nil
                                self.selectedPhoto = nil
                            }
                        }) {
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
                }
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
        .accessibilityLabel("Add a photo")
    }

    // MARK: - 3. Voice Card
    private var voiceCard: some View {
        cardWrapper {
            Button(action: {
                FloHaptics.medium()
                showVoiceEntry = true
            }) {
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

    // MARK: - 4. Text Card
    private var textCard: some View {
        cardWrapper {
            Button(action: {
                FloHaptics.medium()
                showTextEntry = true
            }) {
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

                        Text(entryTitle.isEmpty && entryBody.isEmpty ? "Title and body text" : (entryTitle.isEmpty ? entryBody : entryTitle))
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

    // MARK: - Floating Bottom Buttons
    private var floatingBottomButtons: some View {
        VStack(spacing: 0) {
            HStack(spacing: FloSpacing.md) {
                // Save button
                Button(action: saveEntry) {
                    HStack(spacing: FloSpacing.sm) {
                        if isSaving {
                            FloLoadingIndicator(size: 16, color: .white, lineWidth: 2)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16))
                            Text("Save")
                                .font(.floButton)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.floSage)
                    .cornerRadius(FloRadius.full)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.floPressed)
                .disabled(isSaving || !canSave)
                .opacity(canSave ? 1.0 : 0.5)
                .accessibilityLabel("Save entry")

                // Share button
                Button(action: {
                    FloHaptics.light()
                    let text = [entryTitle, entryBody].filter { !$0.isEmpty }.joined(separator: "\n\n")
                    guard !text.isEmpty else { return }
                    let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = windowScene.windows.first?.rootViewController {
                        root.present(av, animated: true)
                    }
                }) {
                    HStack(spacing: FloSpacing.sm) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                        Text("Share")
                            .font(.floButton)
                    }
                    .foregroundColor(.floSage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.white)
                    .cornerRadius(FloRadius.full)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloRadius.full)
                            .stroke(Color.floSage, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.floPressed)
                .accessibilityLabel("Share entry")
            }
            .padding(.horizontal, FloSpacing.lg)
        }
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
        guard canSave else { return }

        FloHaptics.light()
        isSaving = true

        // Map feeling label to CoreEmotion
        let feelingMap: [String: CoreEmotion] = [
            "Sad": .sad, "Anger": .angry, "Fear": .afraid,
            "Hurt": .hurt, "Lonely": .lonely, "Shame": .ashamed,
            "Guilt": .guilty, "Glad": .glad
        ]
        let emotion = selectedFeeling.flatMap { feelingMap[$0] } ?? .glad

        // Build the note from title + body
        let fullNote = entryTitle.isEmpty ? entryBody : (entryBody.isEmpty ? entryTitle : "\(entryTitle)\n\(entryBody)")

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

// MARK: - Text Entry Drawer
/// A full-screen sheet for writing a journal entry's title and body. Mirrors
/// the voice entry flow so both modalities feel parallel.
struct TextEntryView: View {
    let initialTitle: String
    let initialBody: String
    var onComplete: (_ title: String, _ body: String) -> Void
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var hasAppeared: Bool = false
    @FocusState private var focused: Field?

    enum Field {
        case title, body
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.floGray.opacity(0.3))
                        .frame(width: 36, height: 5)
                    Spacer()
                }
                .padding(.top, FloSpacing.sm)
                .padding(.bottom, FloSpacing.md)

                // Header
                Text("Write it down")
                    .font(.floSerif(size: 28))
                    .foregroundColor(.floCharcoal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.bottom, FloSpacing.lg)
                    .accessibilityAddTraits(.isHeader)

                // Title field
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

                // Body editor
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

                // Bottom actions
                HStack(spacing: FloSpacing.md) {
                    Button(action: {
                        FloHaptics.light()
                        onDismiss()
                    }) {
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

                    Button(action: {
                        FloHaptics.success()
                        onComplete(title, bodyText)
                    }) {
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
            // Defer focus until the sheet finishes mounting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                focused = .title
                hasAppeared = true
            }
        }
    }
}

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: FloSpacing.md) {
            // Handle bar
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

            Button(action: {
                FloHaptics.light()
                isPresented = false
            }) {
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

// MARK: - Log Cycle Modal
struct LogCycleModal: View {
    @Binding var isPresented: Bool
    @State private var selectedDate: Date = Date()

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    FloHaptics.light()
                    isPresented = false
                }

            // Modal card
            VStack(spacing: 0) {
                // Header with close button
                ZStack {
                    // Gray header background
                    Color(hex: "F5F5F5")
                        .frame(height: 60)

                    HStack {
                        Text("Log Cycle")
                            .font(.floBodyLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(.floCharcoal)
                            .padding(.leading, FloSpacing.lg)

                        Spacer()

                        Button(action: {
                            FloHaptics.light()
                            isPresented = false
                        }) {
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

                // Content
                VStack(spacing: FloSpacing.lg) {
                    // Title
                    Text("SELECT A START DATE:")
                        .font(.floLabel)
                        .fontWeight(.semibold)
                        .foregroundColor(.floCharcoal)
                        .tracking(1.5)

                    // Divider
                    FloDivider()
                        .padding(.horizontal, FloSpacing.xl)

                    // Date picker wheels
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 150)

                    // Log Cycle button
                    Button(action: {
                        FloHaptics.success()
                        // CycleManager handles the local UserDefaults write
                        // and the Supabase insert; the Task is fire-and-forget
                        // so dismissing the modal doesn't block on the network.
                        Task { @MainActor in
                            await CycleManager.shared.logCycle(startDate: selectedDate)
                        }
                        isPresented = false
                    }) {
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
