//
//  EmotionJournalView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

struct EmotionJournalView: View {
    @State private var journalManager = JournalManager.shared
    @State private var searchText: String = ""
    @State private var hasAppeared = false
    @State private var selectedEntry: JournalEntry? = nil
    @FocusState private var isSearchFocused: Bool

    private var userName: String { CycleManager.shared.userName }

    private var filteredEntries: [JournalEntry] {
        if searchText.isEmpty {
            return journalManager.entries
        }
        let query = searchText.lowercased()
        return journalManager.entries.filter {
            $0.note.lowercased().contains(query) ||
            $0.emotion.rawValue.lowercased().contains(query) ||
            $0.formattedDate.lowercased().contains(query)
        }
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .fadeIn(delay: hasAppeared ? 0 : 0.1)

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Greeting
                        greetingSection
                            .fadeIn(delay: hasAppeared ? 0 : 0.15)

                        // Search bar
                        searchBar
                            .padding(.top, FloSpacing.lg)
                            .fadeIn(delay: hasAppeared ? 0 : 0.2)

                        // Journal entries
                        journalEntriesList
                            .padding(.top, FloSpacing.lg)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.bottom, 140) // Space for tab bar
                }
            }
        }
        .dismissKeyboardOnTap()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
        .sheet(item: $selectedEntry) { entry in
            JournalEntryDetailView(entry: entry, journalManager: journalManager, onDismiss: {
                selectedEntry = nil
            })
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            // Journal/device icon
            Image("journal")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.floCharcoal)
                .accessibilityLabel("Journal")

            Spacer()

            // FLO text
            Text("FLO")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.floCharcoal)
                .tracking(3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.md)
    }

    // MARK: - Greeting Section
    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.xs) {
            Text("Hello, \(userName)!")
                .font(.floSerif(size: 36))
                .foregroundColor(.floCharcoal)
                .accessibilityAddTraits(.isHeader)

            Text("WAY TO TAKE TIME TO WRITE IT DOWN.")
                .font(.floLabel)
                .fontWeight(.medium)
                .foregroundColor(.floCharcoal)
                .tracking(1)
        }
        .padding(.top, FloSpacing.md)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: FloSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(isSearchFocused ? .floSage : .floGray)
                .animation(FloAnimation.easeOutQuick, value: isSearchFocused)

            TextField("keyword search", text: $searchText)
                .font(.floSerif(size: 16))
                .foregroundColor(.floCharcoal)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .accessibilityLabel("Search journal entries")

            if !searchText.isEmpty {
                Button(action: {
                    FloHaptics.light()
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.floGray)
                }
                .buttonStyle(.floPressed)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FloRadius.xl)
                .stroke(isSearchFocused ? Color.floSage : Color.clear, lineWidth: 2)
        )
        .shadow(color: FloShadow.small.color, radius: FloShadow.small.radius, x: 0, y: FloShadow.small.y)
        .animation(FloAnimation.easeOutQuick, value: searchText.isEmpty)
    }

    // MARK: - Journal Entries List
    private var journalEntriesList: some View {
        LazyVStack(spacing: FloSpacing.lg) {
            let entries = filteredEntries
            if entries.isEmpty && searchText.isEmpty {
                // Empty state
                VStack(spacing: FloSpacing.md) {
                    Spacer().frame(height: FloSpacing.xxl)

                    Image(systemName: "book.closed")
                        .font(.system(size: 48))
                        .foregroundColor(.floGray.opacity(0.4))

                    Text("No entries yet")
                        .font(.floBodyLarge)
                        .foregroundColor(.floGray)

                    Text("Tap the + button to start journaling")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
            } else if entries.isEmpty {
                // No search results
                VStack(spacing: FloSpacing.md) {
                    Spacer().frame(height: FloSpacing.xxl)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.floGray.opacity(0.4))

                    Text("No entries match \"\(searchText)\"")
                        .font(.floBodyMedium)
                        .foregroundColor(.floGray)
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    JournalCardView(
                        entry: entry,
                        onTap: {
                            selectedEntry = entry
                        }
                    )
                    .fadeIn(delay: hasAppeared ? 0 : 0.25 + Double(index) * 0.1)
                }
            }
        }
    }
}

// MARK: - Journal Card View
struct JournalCardView: View {
    let entry: JournalEntry
    let onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo banner with emotion overlay
            ZStack(alignment: .topLeading) {
                // Real photo background
                Image(entry.emotion.photoName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .clipped()

                // Subtle dark overlay for text legibility
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.1),
                        Color.black.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)

                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    // Emotion chip
                    HStack(spacing: FloSpacing.xs) {
                        Image(systemName: entry.emotion.icon)
                            .font(.system(size: 14))
                        Text(entry.emotion.rawValue.uppercased())
                            .font(.floLabel)
                            .fontWeight(.medium)
                            .tracking(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, FloSpacing.md)
                    .padding(.vertical, FloSpacing.xs)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(FloRadius.full)

                    Spacer()

                    // Intensity dots
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Circle()
                                .fill(i <= entry.intensity ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(FloSpacing.lg)
            }

            // Content section
            VStack(alignment: .leading, spacing: FloSpacing.sm) {
                FloDivider(color: Color.floGray.opacity(0.2))
                    .padding(.bottom, FloSpacing.xs)

                Text(entry.note.isEmpty ? "Untitled Entry" : entry.note)
                    .font(.floBodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.floCharcoal)
                    .tracking(0.5)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DATE POSTED:")
                        .font(.floCaption)
                        .fontWeight(.semibold)
                        .foregroundColor(.floCharcoal)
                        .tracking(0.5)
                    Text(entry.formattedDate)
                        .font(.floBodySmall)
                        .foregroundColor(.floCharcoal)
                }
            }
            .padding(FloSpacing.lg)
        }
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: FloShadow.medium.color, radius: FloShadow.medium.radius, x: 0, y: FloShadow.medium.y)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(FloAnimation.buttonPress, value: isPressed)
        .onTapGesture {
            FloHaptics.light()
            onTap()
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.emotion.rawValue) - \(entry.note), posted on \(entry.formattedDate)")
        .accessibilityHint("Double tap to view entry")
    }
}

// MARK: - Journal Entry Detail View (read-only view of a past entry)
struct JournalEntryDetailView: View {
    let entry: JournalEntry
    let journalManager: JournalManager
    let onDismiss: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        FloHaptics.light()
                        onDismiss()
                    }) {
                        HStack(spacing: FloSpacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text("Journal")
                                .font(.floBodyMedium)
                        }
                        .foregroundColor(.floSage)
                    }

                    Spacer()

                    Button(action: {
                        showDeleteConfirm = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(.phaseMenstrual)
                    }
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.vertical, FloSpacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: FloSpacing.xl) {
                        // Date & time
                        VStack(alignment: .leading, spacing: FloSpacing.xs) {
                            Text(entry.formattedDate)
                                .font(.floDisplaySmall)
                                .foregroundColor(.floCharcoal)

                            Text(entry.formattedTime)
                                .font(.floBodyMedium)
                                .foregroundColor(.floGray)
                        }

                        // Emotion card
                        HStack(spacing: FloSpacing.md) {
                            ZStack {
                                Circle()
                                    .fill(entry.emotion.color.opacity(0.15))
                                    .frame(width: 56, height: 56)

                                Image(systemName: entry.emotion.icon)
                                    .font(.system(size: 24))
                                    .foregroundColor(entry.emotion.color)
                            }

                            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                                Text(entry.emotion.rawValue)
                                    .font(.floBodyLarge)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.floCharcoal)

                                HStack(spacing: 4) {
                                    Text("Intensity:")
                                        .font(.floBodySmall)
                                        .foregroundColor(.floGray)

                                    ForEach(1...5, id: \.self) { i in
                                        Circle()
                                            .fill(i <= entry.intensity ? entry.emotion.color : Color.floGray.opacity(0.2))
                                            .frame(width: 10, height: 10)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(FloSpacing.lg)
                        .background(Color.white)
                        .cornerRadius(FloRadius.lg)

                        // Phase info
                        HStack(spacing: FloSpacing.sm) {
                            Circle()
                                .fill(entry.phase.color)
                                .frame(width: 10, height: 10)

                            Text(entry.phase.name)
                                .font(.floBodySmall)
                                .foregroundColor(.floGray)
                        }

                        // Journal text
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.floSerif(size: 18))
                                .foregroundColor(.floCharcoal)
                                .lineSpacing(8)
                        }

                        Spacer().frame(height: FloSpacing.xxl)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                }
            }
        }
        .alert("Delete Entry?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                journalManager.deleteEntry(entry)
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will be permanently removed.")
        }
    }
}

#Preview {
    EmotionJournalView()
}

// MARK: - Journal Grid (2D day-card navigation)
/// Journal tab's base view. Each day is a full-screen card whose face is the
/// most recent entry; empty days show a calm empty-state. Navigation is
/// anchored on today: left/right paging by ±1 day comes from a single
/// horizontal paging ScrollView; up/down by ±7 days (same weekday) comes
/// from a DragGesture that jumps the scroll position. One ScrollView keeps
/// the initial position rock-steady and avoids nested-scroll layout races.
struct JournalGridView: View {
    @State private var journalManager = JournalManager.shared
    @State private var currentDate: Date?
    @State private var detailDate: Date? = nil
    @State private var showNewEntry = false

    private let calendar = Calendar.current

    /// Days available to scroll through. A year of history + ~a month forward.
    private let dates: [Date] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-365...30).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: today)
        }
    }()

    init() {
        _currentDate = State(initialValue: Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        GeometryReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(dates, id: \.self) { date in
                        dayCardPage(for: date, pageHeight: reader.size.height)
                            .containerRelativeFrame(.horizontal)
                            .id(date)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentDate, anchor: .leading)
            .simultaneousGesture(verticalSwipeGesture)
        }
        .sheet(item: Binding(
            get: { detailDate.map { JournalDayAnchor(date: $0) } },
            set: { detailDate = $0?.date }
        )) { anchor in
            JournalDaySheet(date: anchor.date, journalManager: journalManager) {
                detailDate = nil
            }
        }
        .sheet(isPresented: $showNewEntry) {
            JournalEntryView(
                journalManager: JournalManager.shared,
                onDismiss: { showNewEntry = false }
            )
        }
    }

    /// Vertical swipe → ±7 days (same weekday). Attached as a simultaneous
    /// gesture so it doesn't fight the horizontal ScrollView's paging.
    private var verticalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Only react to predominantly vertical swipes.
                guard abs(dy) > abs(dx), abs(dy) > 50 else { return }
                // SwiftUI: +y is down. Swipe DOWN (dy > 0) = next week.
                let weekDelta = dy > 0 ? 7 : -7
                guard let current = currentDate,
                      let target = calendar.date(byAdding: .day, value: weekDelta, to: current),
                      dates.contains(where: { calendar.isDate($0, inSameDayAs: target) })
                else { return }
                FloHaptics.light()
                withAnimation(.snappy) {
                    currentDate = target
                }
            }
    }

    /// One page = cream margins + a contained, rounded card with a soft shadow.
    /// Vertical sizing comes from the parent GeometryReader (pageHeight) rather
    /// than containerRelativeFrame(.vertical) — container-relative in the
    /// cross-axis of a horizontal scroll has unreliable initial-paint math,
    /// which would otherwise show as a top cutoff on first load.
    private func dayCardPage(for cellDate: Date, pageHeight: CGFloat) -> some View {
        let hasEntries = !journalManager.entries(for: cellDate).isEmpty

        // Card hugs its content vertically; the page itself fills pageHeight
        // and top-aligns the card so the cream margin sits below it.
        return VStack(spacing: 0) {
            dayCard(for: cellDate)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: FloRadius.xl, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
                .contentShape(RoundedRectangle(cornerRadius: FloRadius.xl, style: .continuous))
                .onTapGesture {
                    FloHaptics.light()
                    if hasEntries {
                        detailDate = cellDate
                    } else {
                        showNewEntry = true
                    }
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.sm)

            Spacer(minLength: 0)
        }
        .frame(height: pageHeight)
    }

    // MARK: - Day card
    //
    // Three visual states (Brittany's Figma — Summer-2026-Build node 2029:1156):
    //   STATE 1 — no entry: short sliver banner, edit pencil top-right,
    //             muted "Add entry" title, hairline, POSTED + date.
    //   STATE 2 — entry, no user photo: short sliver banner with the entry's
    //             emotion image, edit pencil top-right, bold one-line title.
    //   STATE 3 — entry with user photo: large image (~339:213) on top,
    //             edit pencil bottom-right with subtle light circle backing.
    //             Gated by `entry.userPhotoURL` which is currently always
    //             nil — layout is ready, but no real entry renders it yet.
    @ViewBuilder
    private func dayCard(for date: Date) -> some View {
        let entries = journalManager.entries(for: date).sorted { $0.date > $1.date }
        if let mostRecent = entries.first {
            if mostRecent.userPhotoURL != nil {
                largePhotoCard(date: date, entry: mostRecent)
            } else {
                sliverEntryCard(date: date, entry: mostRecent)
            }
        } else {
            sliverEmptyCard(date: date)
        }
    }

    // MARK: STATE 1 — empty day
    private func sliverEmptyCard(date: Date) -> some View {
        VStack(spacing: 0) {
            sliverImageBanner(imageName: "sunsetrocks")
            cardContentArea(
                title: "Add entry",
                titleIsMuted: true,
                date: date
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No entries on \(longDateString(date)). Tap to add an entry.")
    }

    // MARK: STATE 2 — entry, no user photo
    private func sliverEntryCard(date: Date, entry: JournalEntry) -> some View {
        VStack(spacing: 0) {
            sliverImageBanner(imageName: entry.emotion.photoName)
            cardContentArea(
                title: entryTitle(entry),
                titleIsMuted: false,
                date: date
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entryTitle(entry)). Posted \(longDateString(date)). Tap to open.")
    }

    // MARK: STATE 3 — entry with user photo
    private func largePhotoCard(date: Date, entry: JournalEntry) -> some View {
        VStack(spacing: 0) {
            largeImageBanner(imageName: entry.userPhotoURL ?? entry.emotion.photoName)
            cardContentArea(
                title: entryTitle(entry),
                titleIsMuted: false,
                date: date
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entryTitle(entry)). Posted \(longDateString(date)). Tap to open.")
    }

    // MARK: - Card sub-components

    /// Short 72pt nature image with the edit pencil in the top-right.
    /// Pencil sits in a soft white circle so it stays legible over dark
    /// banner imagery (parity with `largeImageBanner`).
    private func sliverImageBanner(imageName: String) -> some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .clipped()
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                    editPencilIcon()
                }
                .frame(width: 36, height: 36)
                .padding(.top, FloSpacing.md)
                .padding(.trailing, FloSpacing.md)
            }
    }

    /// Large image preserving the ~339:213 aspect, edit pencil bottom-right
    /// with a soft light-circle backing so it stays legible over photo content.
    private func largeImageBanner(imageName: String) -> some View {
        Color.clear
            .aspectRatio(339.0 / 213.0, contentMode: .fit)
            .overlay(
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                    editPencilIcon()
                }
                .frame(width: 36, height: 36)
                .padding(.bottom, FloSpacing.md)
                .padding(.trailing, FloSpacing.md)
            }
    }

    private func editPencilIcon() -> some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.floCharcoal)
            .allowsHitTesting(false)
    }

    /// White content block: title → hairline → POSTED + date.
    /// Title is truncated to one line at the tail. The block hugs its
    /// content vertically, ending 32pt below the date.
    private func cardContentArea(title: String, titleIsMuted: Bool, date: Date) -> some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(titleIsMuted ? .floGray : .floCharcoal)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            FloDivider(color: Color.floLightGray, thickness: 0.5)

            VStack(alignment: .leading, spacing: FloSpacing.sm) {
                Text("POSTED")
                    .font(.floLabel)
                    .fontWeight(.semibold)
                    .foregroundColor(.floCharcoal)
                    .tracking(1.5)

                Text(postedDateString(date))
                    .font(.floBodyLarge)
                    .foregroundColor(.floCharcoal)
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.lg)
        .padding(.bottom, FloSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    /// Pull a short title out of the entry. The composer joins title + body
    /// with a newline, so the first non-empty line is the user's intended
    /// title. Falls back to the trimmed note or the emotion name.
    private func entryTitle(_ entry: JournalEntry) -> String {
        let trimmedWhole = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstNewline = trimmedWhole.firstIndex(of: "\n") {
            let candidate = String(trimmedWhole[..<firstNewline])
                .trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty { return candidate }
        }
        return trimmedWhole.isEmpty ? entry.emotion.rawValue : trimmedWhole
    }

    // MARK: - Date formatting

    private func weekdayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }

    private func longDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: date)
    }

    /// "May 28, 2026" — used under the POSTED label on day-cards.
    private func postedDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: date)
    }
}

/// Identifiable wrapper so a Date can drive a `.sheet(item:)`.
private struct JournalDayAnchor: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - Journal Day Sheet
/// Sheet presented when a day card is tapped. Hands off to JournalEntryDetailView
/// for single entries, lists them for multi-entry days, and shows a calm
/// empty state when nothing has been logged.
struct JournalDaySheet: View {
    let date: Date
    let journalManager: JournalManager
    let onDismiss: () -> Void

    @State private var selectedEntry: JournalEntry? = nil

    private var entries: [JournalEntry] {
        journalManager.entries(for: date).sorted { $0.date > $1.date }
    }

    var body: some View {
        if entries.count == 1, let only = entries.first {
            // Single entry — go straight to the detail view.
            JournalEntryDetailView(entry: only, journalManager: journalManager, onDismiss: onDismiss)
        } else {
            multiOrEmptyView
        }
    }

    @ViewBuilder
    private var multiOrEmptyView: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        FloHaptics.light()
                        onDismiss()
                    } label: {
                        HStack(spacing: FloSpacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text("Journal")
                                .font(.floBodyMedium)
                        }
                        .foregroundColor(.floSage)
                    }

                    Spacer()
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.vertical, FloSpacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: FloSpacing.lg) {
                        VStack(alignment: .leading, spacing: FloSpacing.xs) {
                            Text(dayHeader.uppercased())
                                .font(.floLabel)
                                .foregroundColor(.floGray)
                                .tracking(2)

                            Text(longDay)
                                .font(.floDisplaySmall)
                                .foregroundColor(.floCharcoal)
                        }

                        if entries.isEmpty {
                            emptyState
                        } else {
                            entryList
                        }
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.bottom, FloSpacing.xxl)
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            JournalEntryDetailView(entry: entry, journalManager: journalManager, onDismiss: {
                selectedEntry = nil
            })
        }
    }

    private var entryList: some View {
        VStack(spacing: FloSpacing.md) {
            ForEach(entries) { entry in
                Button {
                    FloHaptics.light()
                    selectedEntry = entry
                } label: {
                    entryRow(entry)
                }
                .buttonStyle(.floPressed)
            }
        }
    }

    private func entryRow(_ entry: JournalEntry) -> some View {
        HStack(spacing: FloSpacing.md) {
            ZStack {
                Circle()
                    .fill(entry.emotion.color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: entry.emotion.icon)
                    .font(.system(size: 18))
                    .foregroundColor(entry.emotion.color)
            }

            VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                Text(entry.emotion.rawValue)
                    .font(.floBodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.floCharcoal)

                Text(entry.formattedTime)
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)

                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.floBodySmall)
                        .foregroundColor(.floCharcoal)
                        .lineLimit(2)
                        .padding(.top, FloSpacing.xxs)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.floGray)
        }
        .padding(FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Image(systemName: "leaf")
                .font(.system(size: 36))
                .foregroundColor(.floSage.opacity(0.6))

            Text("Nothing logged on this day.")
                .font(.floBodyLarge)
                .foregroundColor(.floCharcoal)

            Text("Use the + button on the tab bar to add an entry.")
                .font(.floBodySmall)
                .foregroundColor(.floGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var dayHeader: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private var longDay: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: date)
    }
}

// MARK: - Journal Base View (header + grid or filtered list)
/// Journal tab's base view. Persistent header with greeting + search at top.
/// Below the header: the 2D paged day-card grid when search is empty, or a
/// filtered list of entries when the user is searching.
struct JournalBaseView: View {
    @State private var journalManager = JournalManager.shared
    @State private var searchText: String = ""
    @State private var selectedEntry: JournalEntry? = nil
    @State private var hasAppeared = false
    @FocusState private var isSearchFocused: Bool

    private var userName: String { CycleManager.shared.userName }

    private var filteredEntries: [JournalEntry] {
        let query = searchText.lowercased()
        return journalManager.entries.filter {
            $0.note.lowercased().contains(query) ||
            $0.emotion.rawValue.lowercased().contains(query) ||
            $0.formattedDate.lowercased().contains(query)
        }
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                tabHeaderBar

                header
                    .padding(.bottom, FloSpacing.md)

                if searchText.isEmpty {
                    JournalGridView()
                } else {
                    searchResultsList
                }
            }
        }
        .dismissKeyboardOnTap()
        .sheet(item: $selectedEntry) { entry in
            JournalEntryDetailView(entry: entry, journalManager: journalManager, onDismiss: {
                selectedEntry = nil
            })
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Tab header bar (journal icon left, FLO wordmark right)
    private var tabHeaderBar: some View {
        HStack {
            Image("journal")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.floCharcoal)
                .accessibilityLabel("Journal")

            Spacer()

            Text("FLO")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.floCharcoal)
                .tracking(3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.md)
    }

    // MARK: - Greeting + search
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hello, \(userName)!")
                .font(.floSerif(size: 36))
                .foregroundColor(.floCharcoal)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, FloSpacing.md)
                .padding(.horizontal, FloSpacing.lg)

            // Bracketed subtitle — full-bleed divider lines matching
            // CalendarView's day-letter row (lighter above, darker below).
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: "E5E5E5"))
                    .frame(height: 1)

                Text("WAY TO TAKE TIME TO WRITE IT DOWN.")
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floCharcoal)
                    .tracking(1)
                    .padding(.vertical, FloSpacing.sm)
                    .padding(.horizontal, FloSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color(hex: "707070"))
                    .frame(height: 1)
            }
            .padding(.top, FloSpacing.sm)

            searchBar
                .padding(.top, FloSpacing.lg)
                .padding(.horizontal, FloSpacing.lg)
        }
    }

    private var searchBar: some View {
        HStack(spacing: FloSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(isSearchFocused ? .floSage : .floGray)
                .animation(FloAnimation.easeOutQuick, value: isSearchFocused)

            TextField("keyword search", text: $searchText)
                .font(.floSerif(size: 16))
                .foregroundColor(.floCharcoal)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .accessibilityLabel("Search journal entries")

            if !searchText.isEmpty {
                Button(action: {
                    FloHaptics.light()
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.floGray)
                }
                .buttonStyle(.floPressed)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FloRadius.xl)
                .stroke(isSearchFocused ? Color.floSage : Color.clear, lineWidth: 2)
        )
        .shadow(color: FloShadow.small.color, radius: FloShadow.small.radius, x: 0, y: FloShadow.small.y)
        .animation(FloAnimation.easeOutQuick, value: searchText.isEmpty)
    }

    // MARK: - Search results list
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: FloSpacing.lg) {
                let entries = filteredEntries
                if entries.isEmpty {
                    VStack(spacing: FloSpacing.md) {
                        Spacer().frame(height: FloSpacing.xxl)

                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.floGray.opacity(0.4))

                        Text("No entries match \"\(searchText)\"")
                            .font(.floBodyMedium)
                            .foregroundColor(.floGray)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(entries) { entry in
                        JournalCardView(
                            entry: entry,
                            onTap: { selectedEntry = entry }
                        )
                    }
                }
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.md)
            .padding(.bottom, 140)
        }
    }
}

#Preview("Journal Grid (focused card)") {
    JournalGridView()
}

#Preview("Journal Tab (header + grid)") {
    JournalBaseView()
}
