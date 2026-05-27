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

// MARK: - Journal Grid (2D day-card grid)
/// Journal tab's base view. Each day is a full-screen card whose face is the
/// most recent entry; empty days show a calm empty-state. Navigation is
/// anchored on today: left/right paging by ±1 day, up/down paging by ±7 days
/// (same weekday) using iOS-17 paging ScrollViews.
struct JournalGridView: View {
    @State private var journalManager = JournalManager.shared
    @State private var currentWeekIdx: Int? = 0
    @State private var currentDayIdx: Int?
    @State private var detailDate: Date? = nil
    @State private var showListView = false

    /// Window of weeks shown (centered on today's week). ~13 months back gives
    /// plenty of history; a small forward window lets users browse upcoming days.
    private let weekRange = -56...4

    private let calendar = Calendar.current

    init() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayWeekday = cal.component(.weekday, from: today)
        // 0..6 within the week, anchored on the locale's firstWeekday.
        let dayIdx = (todayWeekday - cal.firstWeekday + 7) % 7
        _currentDayIdx = State(initialValue: dayIdx)
    }

    private func date(weekIdx: Int, dayIdx: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let todayDayIdx = (todayWeekday - calendar.firstWeekday + 7) % 7
        let startOfThisWeek = calendar.date(byAdding: .day, value: -todayDayIdx, to: today) ?? today
        let startOfTargetWeek = calendar.date(byAdding: .weekOfYear, value: weekIdx, to: startOfThisWeek) ?? startOfThisWeek
        return calendar.date(byAdding: .day, value: dayIdx, to: startOfTargetWeek) ?? startOfTargetWeek
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.floCream.ignoresSafeArea()

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(weekRange, id: \.self) { weekIdx in
                            weekRow(weekIdx: weekIdx, pageSize: geo.size)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(weekIdx)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentWeekIdx)
            }

            // Toggle to the searchable list view.
            Button {
                FloHaptics.light()
                showListView = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.floCharcoal)
                    .padding(FloSpacing.sm)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
            }
            .padding(.top, FloSpacing.lg)
            .padding(.trailing, FloSpacing.lg)
            .accessibilityLabel("Show journal as list")
        }
        .sheet(item: Binding(
            get: { detailDate.map { JournalDayAnchor(date: $0) } },
            set: { detailDate = $0?.date }
        )) { anchor in
            JournalDaySheet(date: anchor.date, journalManager: journalManager) {
                detailDate = nil
            }
        }
        .sheet(isPresented: $showListView) {
            EmotionJournalView()
        }
    }

    // MARK: - Week row (horizontal paging by day)
    @ViewBuilder
    private func weekRow(weekIdx: Int, pageSize: CGSize) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { dayIdx in
                    let cellDate = date(weekIdx: weekIdx, dayIdx: dayIdx)
                    dayCardPage(for: cellDate)
                        .frame(width: pageSize.width, height: pageSize.height)
                        .id(dayIdx)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentDayIdx)
    }

    /// One page = cream margins + a contained, rounded card with a soft shadow.
    /// The bottom inset leaves room for the floating tab bar.
    private func dayCardPage(for cellDate: Date) -> some View {
        dayCard(for: cellDate)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: FloRadius.xl, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: FloRadius.xl, style: .continuous))
            .onTapGesture {
                FloHaptics.light()
                detailDate = cellDate
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.md)
            .padding(.bottom, 130)
    }

    // MARK: - Day card
    @ViewBuilder
    private func dayCard(for date: Date) -> some View {
        let entries = journalManager.entries(for: date).sorted { $0.date > $1.date }
        if let mostRecent = entries.first {
            populatedCard(date: date, entry: mostRecent, total: entries.count)
        } else {
            emptyCard(date: date)
        }
    }

    private func populatedCard(date: Date, entry: JournalEntry, total: Int) -> some View {
        ZStack(alignment: .topLeading) {
            // Nature photo for this emotion, full-bleed.
            Image(entry.emotion.photoName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()

            // Darken for text legibility.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                // Top — date
                Text(weekdayString(date).uppercased())
                    .font(.floLabel)
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(3)

                Text(dateString(date))
                    .font(.custom("LUNARY free", size: 40))
                    .foregroundColor(.white)
                    .padding(.top, FloSpacing.xxs)

                Spacer()

                // Bottom — most recent entry summary
                VStack(alignment: .leading, spacing: FloSpacing.sm) {
                    Text(entry.emotion.rawValue.uppercased())
                        .font(.floLabel)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .tracking(3)

                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Circle()
                                .fill(i <= entry.intensity ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }

                    if !entry.note.isEmpty {
                        Text(entry.note)
                            .font(.floBodyMedium)
                            .foregroundColor(.white)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .padding(.top, FloSpacing.xs)
                    }

                    if total > 1 {
                        Text("\(total) entries this day")
                            .font(.floCaption)
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.top, FloSpacing.xs)
                    }
                }
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.vertical, FloSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.emotion.rawValue) on \(entry.formattedDate). \(total > 1 ? "\(total) entries this day. " : "")Tap to open.")
    }

    private func emptyCard(date: Date) -> some View {
        let isFuture = date > calendar.startOfDay(for: Date())
        return ZStack(alignment: .topLeading) {
            Color.white

            VStack(alignment: .leading, spacing: 0) {
                Text(weekdayString(date).uppercased())
                    .font(.floLabel)
                    .foregroundColor(.floGray)
                    .tracking(3)

                Text(dateString(date))
                    .font(.custom("LUNARY free", size: 40))
                    .foregroundColor(.floCharcoal)
                    .padding(.top, FloSpacing.xxs)

                Spacer()

                VStack(alignment: .leading, spacing: FloSpacing.md) {
                    Image(systemName: "leaf")
                        .font(.system(size: 36))
                        .foregroundColor(.floSage.opacity(0.6))

                    Text(isFuture ? "Not yet." : "Nothing logged.")
                        .font(.floDisplaySmall)
                        .foregroundColor(.floCharcoal)

                    Text(isFuture
                         ? "This day hasn't happened yet."
                         : "Tap to look back on this day.")
                        .font(.floBodyMedium)
                        .foregroundColor(.floGray)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.vertical, FloSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: FloRadius.xl, style: .continuous)
                .stroke(Color.floGray.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isFuture ? "Future day" : "No entries") on \(longDateString(date)).")
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
