//
//  HomeView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 3/23/26.
//

import SwiftUI
import PhotosUI

struct HomeView: View {
    let greeting: SplashGreeting
    var animateFromSplash: Bool
    /// When true, render as content-only (no GeometryReader/ScrollView/full-bleed
    /// background) so this view can be embedded inside a parent ScrollView —
    /// e.g. the Profile tab that stacks Home + ProfileMainView in one scroll.
    var isEmbedded: Bool = false

    init(greeting: SplashGreeting = .random, animateFromSplash: Bool = false, isEmbedded: Bool = false) {
        self.greeting = greeting
        self.animateFromSplash = animateFromSplash
        self.isEmbedded = isEmbedded
    }

    @State private var hasAppeared = false
    @State private var showJournalEntry = false
    @State private var showMeditation = false
    @State private var showPhaseDetail = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil
    @State private var showPhotoJournal = false

    private let cycleManager = CycleManager.shared

    var body: some View {
        Group {
            if isEmbedded {
                dashboardContent
            } else {
                GeometryReader { outerGeo in
                    ZStack {
                        Color.floCream.ignoresSafeArea()

                        ScrollView {
                            VStack(spacing: 0) {
                                heroSection(topInset: outerGeo.safeAreaInsets.top, screenHeight: outerGeo.size.height + outerGeo.safeAreaInsets.top + outerGeo.safeAreaInsets.bottom)

                                todaySection
                                    .padding(.top, FloSpacing.xs)

                                actionWidgets
                                    .padding(.top, FloSpacing.xl)

                                Spacer(minLength: 140)
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
        }
        .onAppear {
            hasAppeared = true
        }
        .sheet(isPresented: $showJournalEntry) {
            JournalEntryView(
                journalManager: JournalManager.shared,
                onDismiss: { showJournalEntry = false }
            )
        }
        .sheet(isPresented: $showPhaseDetail) {
            PhaseDetailView(
                phase: cycleManager.currentPhase,
                onDismiss: { showPhaseDetail = false }
            )
        }
        .sheet(isPresented: $showPhotoJournal) {
            JournalEntryView(
                journalManager: JournalManager.shared,
                onDismiss: { showPhotoJournal = false }
            )
        }
    }

    // MARK: - Embedded content (no outer ScrollView/GeometryReader)
    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: 0) {
            embeddedHero

            todaySection
                .padding(.top, FloSpacing.xs)

            actionWidgets
                .padding(.top, FloSpacing.xl)
        }
    }

    /// Hero with a fixed height for use when nested inside another scroll —
    /// no safe-area-top inset compensation (the parent scroll handles that).
    private var embeddedHero: some View {
        let heroHeight: CGFloat = 280

        return ZStack(alignment: .bottomLeading) {
            Image(greeting.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: heroHeight)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: FloSpacing.md) {
                Text("FLO")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(5)

                Text(greeting.text)
                    .font(.custom("LUNARY free", size: 46))
                    .foregroundColor(.white)
                    .lineSpacing(10)
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 2)
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.bottom, FloSpacing.xxl)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            Color.floCream
                .frame(height: FloRadius.xl)
                .clipShape(
                    RoundedCorner(radius: FloRadius.xl, corners: [.topLeft, .topRight])
                )
        }
    }

    // MARK: - Hero Section
    private func heroSection(topInset: CGFloat, screenHeight: CGFloat) -> some View {
        let heroHeight: CGFloat = 280 + topInset

        return ZStack(alignment: .bottomLeading) {
            // Background image
            Image(greeting.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: heroHeight)
                .clipped()

            // Dark overlay for text legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Greeting text and FLO mark
            VStack(alignment: .leading, spacing: FloSpacing.md) {
                Text("FLO")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(5)

                Text(greeting.text)
                    .font(.custom("LUNARY free", size: 46))
                    .foregroundColor(.white)
                    .lineSpacing(10)
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 2)
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.bottom, FloSpacing.xxl)
        }
        .frame(height: heroHeight)
        .overlay(alignment: .bottom) {
            Color.floCream
                .frame(height: FloRadius.xl)
                .clipShape(
                    RoundedCorner(radius: FloRadius.xl, corners: [.topLeft, .topRight])
                )
        }
    }

    // MARK: - Today Section
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            // Date
            Text(todayDateString.uppercased())
                .font(.floLabel)
                .foregroundColor(.floGray)
                .tracking(2)

            // Phase name and subtitle as a unit
            VStack(alignment: .leading, spacing: FloSpacing.xxs) {
                Text(cycleManager.currentPhase.name)
                    .font(.floDisplayMedium)
                    .foregroundColor(.floCharcoal)

                Text(cycleManager.currentPhase.subtitle)
                    .font(.floLabel)
                    .foregroundColor(.floGray)
                    .tracking(1.5)
            }
            .padding(.vertical, FloSpacing.sm)

            // Day of cycle and next period
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(cycleManager.currentDayOfCycle)")
                        .font(.floBodyLarge)
                        .fontWeight(.semibold)
                        .foregroundColor(.floCharcoal)
                    Text("of your cycle")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cycleManager.daysUntilNextPeriod) days")
                        .font(.floBodyLarge)
                        .fontWeight(.semibold)
                        .foregroundColor(.floCharcoal)
                    Text("until next period")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, FloSpacing.sm)
            }
            .padding(.top, FloSpacing.xs)

        }
        .padding(.horizontal, FloSpacing.lg)
    }

    // MARK: - Phase Tip Card
    private var phaseTipCard: some View {
        Button {
            FloHaptics.light()
            showPhaseDetail = true
        } label: {
            HStack(spacing: FloSpacing.md) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.floSage)

                Text(tipForCurrentPhase)
                    .font(.floBodySmall)
                    .foregroundColor(.floCharcoal)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.floGray)
            }
            .padding(FloSpacing.md)
            .background(Color.floMint.opacity(0.45))
            .cornerRadius(FloRadius.md)
        }
        .buttonStyle(.floPressed)
    }

    // MARK: - Action Widgets
    private var actionWidgets: some View {
        VStack(spacing: FloSpacing.md) {
            // Phase tip card
            phaseTipCard
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.lg)

            // Section header
            HStack {
                Text("Today")
                    .font(.floDisplaySmall)
                    .foregroundColor(.floCharcoal)
                Spacer()
            }
            .padding(.horizontal, FloSpacing.lg)

            // Widget grid - 2 half-width + 1 full-width pattern
            VStack(spacing: FloSpacing.md) {
                // Row 1: Two half-width cards
                HStack(spacing: FloSpacing.md) {
                    // Add a Photo
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ActionCard(
                            icon: "camera.fill",
                            title: "Add a Photo",
                            subtitle: "Capture your day",
                            color: Color.phaseLuteal,
                            bgColor: Color(hex: "E8EAF0"),
                            isHalf: true
                        )
                    }
                    .buttonStyle(.floPressed)
                    .onChange(of: selectedPhoto) { _, newItem in
                        if newItem != nil {
                            showPhotoJournal = true
                        }
                    }

                    // Add a Feeling
                    Button {
                        FloHaptics.medium()
                        showJournalEntry = true
                    } label: {
                        ActionCard(
                            icon: "heart.fill",
                            title: "Add a Feeling",
                            subtitle: "How are you?",
                            color: Color.phaseMenstrual,
                            bgColor: Color(hex: "F5E6E6"),
                            isHalf: true
                        )
                    }
                    .buttonStyle(.floPressed)
                }
                .padding(.horizontal, FloSpacing.lg)

                // Row 2: Full-width journal card
                Button {
                    FloHaptics.medium()
                    showJournalEntry = true
                } label: {
                    ActionCardWide(
                        icon: "book.fill",
                        title: "Record a Journal Entry",
                        subtitle: "Write, speak, or reflect on your day",
                        color: Color.phaseLuteal,
                        bgColor: Color(hex: "E8EEF2")
                    )
                }
                .buttonStyle(.floPressed)
                .padding(.horizontal, FloSpacing.lg)

                // Row 3: Two half-width cards
                HStack(spacing: FloSpacing.md) {
                    // Meditate
                    Button {
                        FloHaptics.medium()
                        showMeditation = true
                    } label: {
                        ActionCard(
                            icon: "wind",
                            title: "Meditate",
                            subtitle: "Find your calm",
                            color: Color.phaseOvulation,
                            bgColor: Color(hex: "FDF4E7"),
                            isHalf: true
                        )
                    }
                    .buttonStyle(.floPressed)

                    // Learn About Phase
                    Button {
                        FloHaptics.light()
                        showPhaseDetail = true
                    } label: {
                        ActionCard(
                            icon: "sparkles",
                            title: "Your Phase",
                            subtitle: "Mind, body, soul",
                            color: Color.floSage,
                            bgColor: Color(hex: "EAF3EC"),
                            isHalf: true
                        )
                    }
                    .buttonStyle(.floPressed)
                }
                .padding(.horizontal, FloSpacing.lg)
            }
        }
    }

    // MARK: - Helpers

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    private var tipForCurrentPhase: String {
        switch cycleManager.currentPhase {
        case .menstrual:
            return "Rest is productive right now. Honor your body's need to slow down and recharge."
        case .follicular:
            return "Your energy is rising. This is a great time for new projects and creative thinking."
        case .ovulation:
            return "Communication peaks now. Great time for important conversations and connections."
        case .luteal:
            return "You may feel more detail-oriented. A good time to finish projects and organize."
        }
    }
}

// MARK: - Action Card (Half Width)
struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let bgColor: Color
    let isHalf: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FloSpacing.sm) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }

            Spacer(minLength: FloSpacing.sm)

            // Title
            Text(title)
                .font(.floBodyMedium)
                .fontWeight(.semibold)
                .foregroundColor(.floCharcoal)
                .lineLimit(1)

            // Subtitle
            Text(subtitle)
                .font(.floCaption)
                .foregroundColor(.floGray)
                .lineLimit(1)
        }
        .padding(FloSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .background(bgColor)
        .cornerRadius(FloRadius.lg)
    }
}

// MARK: - Action Card Wide (Full Width)
struct ActionCardWide: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let bgColor: Color

    var body: some View {
        HStack(spacing: FloSpacing.md) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                Text(title)
                    .font(.floBodyLarge)
                    .fontWeight(.semibold)
                    .foregroundColor(.floCharcoal)

                Text(subtitle)
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.floGray.opacity(0.5))
        }
        .padding(FloSpacing.lg)
        .background(bgColor)
        .cornerRadius(FloRadius.lg)
    }
}

#Preview {
    HomeView()
}
