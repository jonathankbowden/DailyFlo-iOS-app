//
//  JournalEntryView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI
import PhotosUI

/// One journal entry, new or posted, presented as a `.large` sheet that only
/// the back button closes (Brittany's review, Nov 25: no swipe-down, no ✕).
///
/// `entry == nil` = compose for `date` (defaults to today). Under the
/// one-entry-per-day rule the init first resolves any existing entry on that
/// day and, if found, opens it as a posted entry instead of a blank composer.
///
/// One screen for reading and writing: the title and text are always live
/// fields, so tapping the text starts editing in place. There is no Save
/// button: the entry autosaves on back, as long as a feeling is picked. A new
/// entry closed without a feeling is discarded. The bottom bar is CLEAR ENTRY
/// (delete with a 5s Undo, no confirm) and SHARE (iOS share sheet).
struct JournalEntryView: View {
    let journalManager: JournalManager
    let onDismiss: () -> Void

    /// Whether the sheet opened on an already-posted entry.
    private let openedPosted: Bool

    /// The entry as last written; nil until a new entry first saves.
    @State private var currentEntry: JournalEntry?
    @State private var selectedEmotion: CoreEmotion?
    @State private var entryDate: Date
    @State private var entryTitle: String
    @State private var entryBody: String
    @State private var photoImage: UIImage?
    /// True when `photoImage` changed since the last save.
    @State private var photoDirty = false
    @State private var selectedPhoto: PhotosPickerItem?
    /// Drives the photo picker from the "Change photo" menu item.
    @State private var showPhotoPicker = false
    /// What CLEAR ENTRY removed, held while its Undo toast is up.
    @State private var cleared: ClearedEntry?
    @FocusState private var bodyFocused: Bool

    private struct ClearedEntry {
        let id = UUID()
        let emotion: CoreEmotion?
        let title: String
        let body: String
        let photo: UIImage?
    }

    private let feelingRowInset: CGFloat = 30

    init(
        entry: JournalEntry? = nil,
        date: Date? = nil,
        journalManager: JournalManager,
        onDismiss: @escaping () -> Void
    ) {
        self.journalManager = journalManager
        self.onDismiss = onDismiss

        // One-entry-per-day enforcement, shared by every create surface (the
        // tab-bar FAB, the calendar day view, the journal grid): when opened to
        // add a "new" entry, if the target day already has one, open that
        // entry instead of composing a duplicate. `date` falls back to today.
        let resolvedEntry = entry ?? journalManager.entry(for: date ?? Date())
        openedPosted = resolvedEntry != nil
        _currentEntry = State(initialValue: resolvedEntry)

        if let resolvedEntry {
            let parts = Self.splitNote(resolvedEntry.note)
            _selectedEmotion = State(initialValue: resolvedEntry.emotion)
            _entryDate = State(initialValue: resolvedEntry.date)
            _entryTitle = State(initialValue: parts.title)
            _entryBody = State(initialValue: parts.body)
            _photoImage = State(initialValue: JournalPhotoStore.image(forStoredPath: resolvedEntry.userPhotoURL))
        } else {
            let day = date ?? Date()
            _selectedEmotion = State(initialValue: nil)
            _entryDate = State(initialValue: day)
            _entryTitle = State(initialValue: "")
            _entryBody = State(initialValue: "")
            _photoImage = State(initialValue: nil)
        }
    }

    /// Inverse of the `"\(title)\n\(body)"` join in `composedNote`. If the
    /// stored note has a newline, split on the first one; otherwise treat the
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
        VStack(spacing: 0) {
            // Frozen header: stays put while the entry scrolls.
            header
            FloHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Feeling:")
                        .font(.floSerif(size: 32))
                        .foregroundStyle(Color.black)
                        .padding(.leading, feelingRowInset)
                        .padding(.top, 18)

                    feelingRow
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                    FloRuleLine()

                    entryContent
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            FloHairline()

            actionRow
                .padding(.horizontal, 36)
                .padding(.top, 12)
                .padding(.bottom, FloSpacing.md)
        }
        .background(Color.floBackground.ignoresSafeArea())
        .overlay(alignment: .bottom) { undoToast }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Back button only: no swipe-down to close.
        .interactiveDismissDisabled()
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await importPhoto(newItem) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onDisappear {
            autosave()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: FloSpacing.xs) {
            Button(action: close) {
                FloIcon("chevron.left", size: 21)
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 4) {
                Text(openedPosted ? "DATE POSTED:" : "DATE:")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.black)

                Text(formattedDate)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.black)
            }

            Spacer()
        }
        .padding(.leading, FloSpacing.sm)
        .padding(.trailing, FloSpacing.md)
        .padding(.vertical, 12)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: entryDate)
    }

    // MARK: - Feeling row

    /// All eight feelings in a snapping horizontal row. It starts inset 30pt
    /// and the third button runs off the right edge as the swipe hint. A
    /// posted entry scrolls its feeling into view on open.
    private var feelingRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: FloSpacing.md) {
                    ForEach(CoreEmotion.allCases, id: \.self) { emotion in
                        feelingButton(emotion)
                            .id(emotion)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
            }
            .contentMargins(.horizontal, feelingRowInset, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .onAppear {
                guard openedPosted, let selectedEmotion else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(selectedEmotion, anchor: .center)
                }
            }
        }
    }

    private func feelingButton(_ emotion: CoreEmotion) -> some View {
        let isSelected = selectedEmotion == emotion
        return Button {
            FloHaptics.selection()
            withAnimation(FloAnimation.springSnappy) { selectedEmotion = emotion }
        } label: {
            Text(emotion.rawValue)
                .font(.floSerif(size: 20))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 120, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.floFeelingSelected : Color.floButtonFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.floInk, lineWidth: 1.5)
                )
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel(emotion.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Entry (one layout for reading and writing)

    /// Photo, title and text. The fields are always live: tapping the text
    /// starts editing right here. The text field grows with what's written,
    /// and the whole page scrolls (no box-in-a-box scrolling).
    private var entryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            photoHeader

            TextField(
                "",
                text: $entryTitle,
                prompt: Text("ENTER TITLE HERE").foregroundStyle(Color.floGray)
            )
            .font(.system(size: 13, weight: .heavy))
            .tracking(3)
            .foregroundStyle(Color.black)
            .textInputAutocapitalization(.characters)
            .submitLabel(.next)
            .onSubmit { bodyFocused = true }
            .padding(.horizontal, feelingRowInset)
            .padding(.top, 34)
            .padding(.bottom, 12)
            .accessibilityLabel("Title")

            FloHairline()
                .padding(.horizontal, feelingRowInset)

            TextField(
                "",
                text: $entryBody,
                prompt: Text("Start typing here…").foregroundStyle(Color.floGray),
                axis: .vertical
            )
            .font(.system(size: 15))
            .lineSpacing(15 * 0.7)
            .foregroundStyle(Color.black)
            .lineLimit(10...)
            .focused($bodyFocused)
            .padding(.horizontal, feelingRowInset)
            .padding(.top, 18)
            .padding(.bottom, FloSpacing.xl)
            .accessibilityLabel("Entry")
        }
    }

    /// The entry's own photo at its true proportions (never cropped short),
    /// or the feeling's stock photo as a fixed band when there isn't one.
    /// Flat: no shadow.
    private var photoHeader: some View {
        Group {
            if let photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            } else {
                // scaledToFill lays out taller than its frame; .clipped() only
                // clips drawing, so pin the hit area to the drawn band.
                Color.clear
                    .frame(height: 232)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Image((selectedEmotion ?? .ashamed).photoName)
                            .resizable()
                            .scaledToFill()
                            .allowsHitTesting(false)
                    }
                    .clipped()
                    .contentShape(Rectangle())
            }
        }
        .overlay(alignment: .bottomTrailing) {
            photoEditControl
                .offset(y: 22)
                .padding(.trailing, 22)
        }
        .zIndex(1)
    }

    /// Photo button: Change photo / Clear photo when the entry has its own
    /// photo, otherwise a picker to add one.
    @ViewBuilder
    private var photoEditControl: some View {
        if photoImage != nil {
            Menu {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Change photo", image: "fi-image")
                }
                Button {
                    clearPhoto()
                } label: {
                    Label("Clear photo", image: "fi-x")
                }
            } label: {
                RoundPhotoEditLabel()
            }
            .accessibilityLabel("Change or clear photo")
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                RoundPhotoEditLabel()
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel("Add a photo")
        }
    }

    // MARK: - Bottom bar

    private var hasContent: Bool {
        selectedEmotion != nil || !entryTitle.isEmpty || !entryBody.isEmpty || photoImage != nil
    }

    /// CLEAR ENTRY + SHARE, equal widths, a hairline above (Brittany's sketch).
    private var actionRow: some View {
        HStack(spacing: FloSpacing.md) {
            OutlinedActionButton(title: "Clear entry") {
                clearEntry()
            }
            .disabled(!hasContent)

            shareButton
                .disabled(composedNote.isEmpty && photoImage == nil)
        }
    }

    /// iOS share sheet: the photo (if any) with the title and text.
    @ViewBuilder
    private var shareButton: some View {
        let title = entryTitle.isEmpty ? "Journal entry" : entryTitle
        if let photoImage {
            let image = Image(uiImage: photoImage)
            ShareLink(
                item: image,
                subject: Text(title),
                message: Text(composedNote),
                preview: SharePreview(title, image: image)
            ) {
                OutlinedActionLabel(title: "Share")
            }
            .buttonStyle(.floPressed)
        } else {
            ShareLink(item: composedNote, subject: Text(title)) {
                OutlinedActionLabel(title: "Share")
            }
            .buttonStyle(.floPressed)
        }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let cleared {
            HStack {
                Text("Entry cleared")
                    .font(.floBodyMedium)
                    .foregroundStyle(Color.white)
                Spacer()
                Button("Undo") { undoClear() }
                    .font(.floButton)
                    .foregroundStyle(Color.floSage)
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.vertical, FloSpacing.md)
            .background(Capsule().fill(Color.black))
            .padding(.horizontal, FloSpacing.lg)
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: cleared.id) {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(FloAnimation.springGentle) { self.cleared = nil }
            }
        }
    }

    // MARK: - Photo import

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        withAnimation(FloAnimation.springSnappy) {
            photoImage = image
        }
        photoDirty = true
    }

    // MARK: - Save

    private var composedNote: String {
        let title = entryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = entryBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body }
        return body.isEmpty ? title : "\(title)\n\(body)"
    }

    private func close() {
        autosave()
        onDismiss()
    }

    /// CLEAR ENTRY: deletes the stored entry now (JournalManager handles the
    /// local file + queued Storage photo delete), empties the page, and holds
    /// what was there for the 5s Undo. Nothing is left to autosave, because
    /// the feeling is cleared too.
    private func clearEntry() {
        FloHaptics.medium()
        let snapshot = ClearedEntry(
            emotion: selectedEmotion,
            title: entryTitle,
            body: entryBody,
            photo: photoImage
        )
        if let entry = currentEntry {
            journalManager.deleteEntry(entry)
        }
        currentEntry = nil
        photoDirty = false
        bodyFocused = false
        withAnimation(FloAnimation.springSnappy) {
            selectedEmotion = nil
            entryTitle = ""
            entryBody = ""
            photoImage = nil
            cleared = snapshot
        }
    }

    /// Undo: puts everything back and saves it as the day's entry again
    /// (photo re-saved and re-uploaded through the normal path).
    private func undoClear() {
        guard let snapshot = cleared else { return }
        FloHaptics.light()
        withAnimation(FloAnimation.springSnappy) {
            selectedEmotion = snapshot.emotion
            entryTitle = snapshot.title
            entryBody = snapshot.body
            photoImage = snapshot.photo
            cleared = nil
        }
        photoDirty = snapshot.photo != nil
        autosave()
    }

    /// Clears the entry's own photo: the header falls back to the feeling's
    /// stock photo. For an existing entry this persists now (local file deleted
    /// + Storage delete queued via `updateEntry`); a new entry just clears it.
    private func clearPhoto() {
        FloHaptics.light()
        withAnimation(FloAnimation.springSnappy) { photoImage = nil }
        photoDirty = true
        if currentEntry != nil {
            autosave()
        }
    }

    /// Writes the entry if a feeling is picked and something changed.
    /// Idempotent: repeated calls with no edits write nothing.
    private func autosave() {
        guard let emotion = selectedEmotion else { return }
        let note = composedNote
        let phase = CycleManager.shared.phase(for: entryDate)

        if let existing = currentEntry {
            guard existing.emotion != emotion || existing.note != note || photoDirty else { return }

            var photoURL = existing.userPhotoURL
            if photoDirty {
                if let photoImage {
                    photoURL = JournalPhotoStore.save(photoImage, for: existing.id) ?? photoURL
                } else {
                    photoURL = nil   // photo removed
                }
            }
            let updated = JournalEntry(
                id: existing.id,
                date: existing.date,
                emotion: emotion,
                intensity: existing.intensity,
                note: note,
                cyclePhase: phase,
                userPhotoURL: photoURL
            )
            journalManager.updateEntry(updated)
            currentEntry = updated
        } else {
            var new = JournalEntry(
                date: entryDate,
                emotion: emotion,
                intensity: 3,
                note: note,
                cyclePhase: phase
            )
            if photoDirty, let photoImage {
                new.userPhotoURL = JournalPhotoStore.save(photoImage, for: new.id)
            }
            journalManager.addEntry(new)
            // addEntry may merge into an entry that appeared for this day in
            // the meantime, so re-read what the store now holds.
            let stored = journalManager.entry(for: entryDate) ?? new
            currentEntry = stored
            if stored.note != note {
                // Merged with earlier text for the day: show the merged note
                // so the next autosave doesn't overwrite it with ours alone.
                let parts = Self.splitNote(stored.note)
                entryTitle = parts.title
                entryBody = parts.body
            }
        }
        photoDirty = false
        FloHaptics.success()
    }
}

#Preview {
    Color.gray.sheet(isPresented: .constant(true)) {
        JournalEntryView(journalManager: JournalManager.shared, onDismiss: {})
    }
}
