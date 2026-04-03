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
