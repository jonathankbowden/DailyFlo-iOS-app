//
//  JournalEntryView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI
import PhotosUI

/// One journal entry, new or posted, presented as a swipe-dismissable
/// `.large` sheet (Figma "January 14" 15:3782 and "Add new journal entry"
/// 15:3879).
///
/// `entry == nil` = compose for `date` (defaults to today). Under the
/// one-entry-per-day rule the init first resolves any existing entry on that
/// day and, if found, opens it as a posted entry instead of a blank composer.
///
/// There is no Save button: the entry autosaves when the sheet closes (X,
/// CLOSE or swipe) and before LOG CYCLE, as long as a feeling is picked. A new
/// entry closed without a feeling is discarded.
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
    /// Posted entries open read-only; the photo's edit button switches to
    /// the editor card. New entries open straight in the editor.
    @State private var isEditing: Bool
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showLogCycleModal = false
    @State private var showDeleteConfirm = false
    /// Drives the photo picker from the "Change photo" menu item (editing mode).
    @State private var showPhotoPicker = false
    /// Set when the entry is deleted, so the dismiss-time autosave is skipped.
    @State private var isDeleted = false

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
        _isEditing = State(initialValue: resolvedEntry == nil)

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
            SheetGrabber()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FloHairline()
                        .padding(.top, FloSpacing.md)

                    header

                    FloHairline()

                    Text("Feeling:")
                        .font(.floLunary(size: 32))
                        .foregroundStyle(Color.black)
                        .padding(.leading, feelingRowInset)
                        .padding(.top, 18)

                    feelingRow
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                    FloRuleLine()

                    if isEditing {
                        editorCard
                            .padding(.horizontal, feelingRowInset)
                            .padding(.top, 20)
                            .padding(.bottom, FloSpacing.lg)
                    } else {
                        postedContent
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            actionRow
                .padding(.horizontal, 36)
                .padding(.top, 12)
                .padding(.bottom, FloSpacing.md)
        }
        .background(Color.floBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .logCycleModal(isPresented: $showLogCycleModal, date: entryDate)
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await importPhoto(newItem) }
        }
        // "Change photo" menu item (editing mode) presents the picker here.
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .alert("Delete this entry?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        // Swipe-to-dismiss autosave. After an X close this is a no-op
        // because nothing changed since that save.
        .onDisappear {
            autosave()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
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

            HStack(spacing: FloSpacing.xs) {
                // Delete is offered once the entry exists in the store (a posted
                // entry, or a new one that has autosaved).
                if currentEntry != nil {
                    Button {
                        FloHaptics.light()
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.floError)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.floPressed)
                    .accessibilityLabel("Delete entry")
                }

                SageCloseButton(action: close)
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, FloSpacing.md)
        .padding(.vertical, 18)
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
                // Room for the buttons' drop shadow inside the scroll clip.
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
                .floShadow(FloShadow.button)
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel(emotion.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Posted entry

    private var postedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            photoView
                .frame(height: 232)
                .frame(maxWidth: .infinity)
                .clipped()
                // Hit area = the drawn 232pt header, not the overflowing image.
                .contentShape(Rectangle())
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        FloHaptics.light()
                        withAnimation(FloAnimation.springGentle) { isEditing = true }
                    } label: {
                        RoundPhotoEditLabel()
                    }
                    .buttonStyle(.floPressed)
                    .offset(y: 22)
                    .padding(.trailing, 22)
                    .accessibilityLabel("Edit entry")
                }

            if !entryTitle.isEmpty {
                Text(entryTitle.uppercased())
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, feelingRowInset)
                    .padding(.top, 34)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 34)
            }

            FloHairline()
                .padding(.horizontal, feelingRowInset)

            Group {
                if entryBody.isEmpty && entryTitle.isEmpty {
                    Text("Nothing written yet. Tap the pencil to add to this entry.")
                        .foregroundStyle(Color.floGray)
                } else {
                    Text(entryBody)
                        .foregroundStyle(Color.black)
                }
            }
            .font(.system(size: 16))
            .lineSpacing(16 * 0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, feelingRowInset)
            .padding(.top, 18)
            .padding(.bottom, FloSpacing.xl)
        }
    }

    /// The entry's photo, or the feeling's stock photo when there isn't one.
    ///
    /// The image is `scaledToFill` inside short frames (48pt editor strip,
    /// 232pt posted header), so it lays out far taller than its frame. `.clipped()`
    /// on the caller only clips DRAWING, not hit-testing — an unclipped,
    /// near-screen-height portrait image would otherwise swallow taps across the
    /// whole sheet (feeling row, title, editor, mic). Mark the image itself
    /// non-interactive so a photo can never take touches anywhere it's used.
    @ViewBuilder
    private var photoView: some View {
        if let photoImage {
            Color.clear.overlay {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
            }
        } else {
            Color.clear.overlay {
                Image((selectedEmotion ?? .ashamed).photoName)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
            }
        }
    }

    /// Photo button on the editor strip. With the entry's own photo it's a menu
    /// (Change / Remove); otherwise a plain picker to add one.
    @ViewBuilder
    private var photoEditControl: some View {
        if photoImage != nil {
            Menu {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Change photo", systemImage: "photo")
                }
                Button(role: .destructive) {
                    removePhoto()
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            } label: {
                RoundPhotoEditLabel()
            }
            .accessibilityLabel("Change or remove photo")
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                RoundPhotoEditLabel()
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel("Add a photo")
        }
    }

    // MARK: - Editor card (new entry, or a posted entry being edited)

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            photoView
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .clipped()
                // Confine the hit area to the drawn 48pt strip (clipped() only
                // clips drawing, not hit-testing).
                .contentShape(Rectangle())
                .overlay(alignment: .bottomTrailing) {
                    photoEditControl
                        .offset(y: 20)
                        .padding(.trailing, 8)
                }
                // Kept: the edit button offsets below the 48pt strip into the
                // title row, so the strip must sit above the later VStack
                // siblings for the button to render on top.
                .zIndex(1)

            TextField(
                "",
                text: $entryTitle,
                prompt: Text("ENTER TITLE HERE").foregroundStyle(Color.black)
            )
            .font(.system(size: 12, weight: .heavy))
            .tracking(2.5)
            .foregroundStyle(Color.black)
            .textInputAutocapitalization(.characters)
            .submitLabel(.next)
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 14)
            .accessibilityLabel("Title")

            FloHairline()
                .padding(.horizontal, 18)

            ZStack(alignment: .topLeading) {
                if entryBody.isEmpty {
                    Text("Start typing here…")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.floCharcoal)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $entryBody)
                    .font(.system(size: 16))
                    .lineSpacing(16 * 0.7)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 300)
                    .accessibilityLabel("Entry")
            }
            .padding(.leading, 23)
            .padding(.trailing, 23)
            .padding(.top, 12)
            .padding(.bottom, FloSpacing.md)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .floShadow(FloShadow.raised)
    }

    // MARK: - Actions row

    /// LOG CYCLE + CLOSE, equal widths, per Brittany's "Journal Entry
    /// Overlay" frame (2052:3261). CLOSE autosaves and dismisses, same as
    /// the X in the header. Sharing an entry was removed with it (Nov 2026);
    /// the ShareLink version is in git history if it comes back in v1.1.
    private var actionRow: some View {
        HStack(spacing: FloSpacing.md) {
            OutlinedActionButton(title: "Log cycle", icon: "checkmark.circle") {
                autosave()
                showLogCycleModal = true
            }

            OutlinedActionButton(title: "Close", icon: "xmark.circle") {
                close()
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

    /// Deletes the posted entry (JournalManager handles the local file + queued
    /// Storage photo delete) and dismisses. `isDeleted` stops the dismiss-time
    /// autosave from resurrecting the row.
    private func deleteEntry() {
        guard let entry = currentEntry else { return }
        FloHaptics.medium()
        isDeleted = true
        journalManager.deleteEntry(entry)
        onDismiss()
    }

    /// Removes the entry's own photo: the strip falls back to the feeling's stock
    /// photo. For an existing entry this persists now (local file deleted + Storage
    /// delete queued via `updateEntry`); a brand-new entry just clears it.
    private func removePhoto() {
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
        guard !isDeleted, let emotion = selectedEmotion else { return }
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
