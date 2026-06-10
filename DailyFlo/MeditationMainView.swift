//
//  MeditationMainView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Meditation Duration
enum MeditationDuration: Int, CaseIterable, Identifiable {
    case five = 5
    case fifteen = 15
    case sixty = 60

    var id: Int { rawValue }

    var displayText: String {
        "\(rawValue) MIN"
    }

    var seconds: Int {
        rawValue * 60
    }
}

// MARK: - Meditation Session
//
// A theme. Each session ships ONE looping audio track (its `_05min` MP3 or
// a synth fallback). Duration is no longer a per-session property — the
// user picks the session length at runtime via the 5/15/60 tab on the
// main view, and the player times out and fades the loop at that mark.
struct MeditationSession: Identifiable {
    let id = UUID()
    let title: String
    let phase: CyclePhase
    /// Displayed background. By convention the `_a` variant of the theme.
    let imageName: String
    /// All three theme variants (`_a`/`_b`/`_c`), wired for the future
    /// collectible gallery. The active surface uses `imageName` (== `_a`).
    let collectibleImages: [String]
    /// Bundled MP3 looped during the session. `nil` falls back to the
    /// `AmbientAudioEngine` synth for `ambientSound`.
    let audioFileName: String?
    /// Synth fallback used when `audioFileName` is `nil`.
    var ambientSound: AmbientSoundType = .warmDrone
    var isFavorite: Bool = false
}

// MARK: - Player Request
//
// Atomic carrier for the data the player needs. Bundling session + duration
// into a single Identifiable item used by `.fullScreenCover(item:)` keeps
// them in lock-step at present time — previously two separate @State
// properties (selectedSession + activeDuration) were read inside the
// cover's content closure, and SwiftUI's update batching let the cover
// present with last frame's `activeDuration` (always .five), so tapping
// a card on the 15 or 60 tab still opened the 5-min variant.
struct PlayerRequest: Identifiable {
    let id = UUID()
    let session: MeditationSession
    let duration: MeditationDuration
}

// MARK: - Main Meditation View
struct MeditationMainView: View {
    @State private var selectedDuration: MeditationDuration = .five
    /// Atomic carrier for the player presentation. Setting this triggers
    /// the cover; the cover reads session + duration from the same struct
    /// instance so they can't drift.
    @State private var playerRequest: PlayerRequest?
    @State private var hasAppeared = false

    private var userName: String { CycleManager.shared.userName }

    // MARK: - Carousel geometry (Summer-2026-Build Figma node 3:4144, 414pt frame)
    //
    // Each column shows ~9pt of the neighbouring column at its edge,
    // separated by a 24pt gutter. Side margin = peek + gutter so the
    // middle column peeks symmetrically on both sides; first/last
    // columns show empty margin on the outer side instead.
    private let columnPeek: CGFloat = 9
    private let columnGutter: CGFloat = 24
    private var columnSideMargin: CGFloat { columnPeek + columnGutter }
    /// Opacity for non-centered columns. Driven by .scrollTransition so
    /// the dim animates smoothly with the swipe gesture rather than
    /// snapping at the rest position. 0.2 = Figma; raise to taste if
    /// the peek feels too faint live.
    private let peekingColumnOpacity: CGFloat = 0.2

    /// Two-way binding for `.scrollPosition(id:)`. Reads/writes the same
    /// `selectedDuration` state the tab strip drives so a tap on a tab
    /// scrolls to that column and a swipe updates the active tab. The
    /// FloHaptics tick only fires for user-driven changes — programmatic
    /// writes from tab taps already produce their own selection haptic.
    private var durationScrollBinding: Binding<Int?> {
        Binding(
            get: { selectedDuration.rawValue },
            set: { newValue in
                guard let raw = newValue,
                      let duration = MeditationDuration(rawValue: raw),
                      duration != selectedDuration else { return }
                FloHaptics.selection()
                selectedDuration = duration
            }
        )
    }

    /// The full 10-theme library. Each theme has an `_a`/`_b`/`_c`
    /// background set; the active surface uses `_a` and the rest are
    /// wired through `collectibleImages` for the future gallery. The
    /// five themes that ship with bundled MP3s loop the real file;
    /// the other five drop to the `AmbientAudioEngine` synth.
    @State private var sessions: [MeditationSession] = [
        // Menstrual
        MeditationSession(
            title: "MIST",
            phase: .menstrual,
            imageName: "medbg_mist_a",
            collectibleImages: ["medbg_mist_a", "medbg_mist_b", "medbg_mist_c"],
            audioFileName: "mist_05min",
            ambientSound: .gentleRain
        ),
        MeditationSession(
            title: "NIGHT SKY",
            phase: .menstrual,
            imageName: "medbg_nightsky_a",
            collectibleImages: ["medbg_nightsky_a", "medbg_nightsky_b", "medbg_nightsky_c"],
            audioFileName: "nightsky_05min",
            ambientSound: .nightAmbience
        ),
        MeditationSession(
            title: "STILLWATER",
            phase: .menstrual,
            imageName: "medbg_stillwater_a",
            collectibleImages: ["medbg_stillwater_a", "medbg_stillwater_b", "medbg_stillwater_c"],
            audioFileName: "stillwater_05min",
            ambientSound: .warmDrone
        ),
        // Follicular
        MeditationSession(
            title: "CANOPY",
            phase: .follicular,
            imageName: "medbg_canopy_a",
            collectibleImages: ["medbg_canopy_a", "medbg_canopy_b", "medbg_canopy_c"],
            audioFileName: "canopy_05min",
            ambientSound: .forestBreeze
        ),
        MeditationSession(
            title: "OPEN HILLS",
            phase: .follicular,
            imageName: "medbg_openhills_a",
            collectibleImages: ["medbg_openhills_a", "medbg_openhills_b", "medbg_openhills_c"],
            audioFileName: "openhills_05min",
            ambientSound: .forestBreeze
        ),
        // Ovulation
        MeditationSession(
            title: "GOLDEN HOUR",
            phase: .ovulation,
            imageName: "medbg_goldenhour_a",
            collectibleImages: ["medbg_goldenhour_a", "medbg_goldenhour_b", "medbg_goldenhour_c"],
            audioFileName: "goldenhour_05min",
            ambientSound: .softChimes
        ),
        MeditationSession(
            title: "OCEAN",
            phase: .ovulation,
            imageName: "medbg_ocean_a",
            collectibleImages: ["medbg_ocean_a", "medbg_ocean_b", "medbg_ocean_c"],
            audioFileName: "ocean_05min",
            ambientSound: .oceanWaves
        ),
        // Luteal
        MeditationSession(
            title: "STORM",
            phase: .luteal,
            imageName: "medbg_storm_a",
            collectibleImages: ["medbg_storm_a", "medbg_storm_b", "medbg_storm_c"],
            audioFileName: "storm_05min",
            ambientSound: .gentleRain
        ),
        MeditationSession(
            title: "FOREST",
            phase: .luteal,
            imageName: "medbg_forest_a",
            collectibleImages: ["medbg_forest_a", "medbg_forest_b", "medbg_forest_c"],
            audioFileName: "forest_05min",
            ambientSound: .forestBreeze
        ),
        MeditationSession(
            title: "SOLITUDE",
            phase: .luteal,
            imageName: "medbg_solitude_a",
            collectibleImages: ["medbg_solitude_a", "medbg_solitude_b", "medbg_solitude_c"],
            audioFileName: "solitude_05min",
            ambientSound: .warmDrone
        )
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .fadeIn(delay: hasAppeared ? 0 : 0.1)

                // Greeting section
                greetingSection
                    .fadeIn(delay: hasAppeared ? 0 : 0.15)

                // Top divider line
                Rectangle()
                    .fill(Color(hex: "E5E5E5"))
                    .frame(height: 1)
                    .padding(.top, FloSpacing.lg)

                // Duration filter tabs
                durationTabs
                    .fadeIn(delay: hasAppeared ? 0 : 0.2)

                // Bottom divider line
                Rectangle()
                    .fill(Color(hex: "707070"))
                    .frame(height: 1)

                // Three columns (5/15/60) as a peeking horizontal carousel:
                // each column snaps to a leading-aligned position with the
                // adjacent column showing ~9pt at the edge and a 24pt gutter
                // between columns. Sized with containerRelativeFrame so the
                // math follows the actual scroll-container width on any
                // device. .scrollTransition fades non-centered columns to
                // `peekingColumnOpacity` smoothly during the swipe;
                // .scrollPosition + selectedDuration keeps the tab strip
                // above in lock-step with the active column.
                //
                // Viewport bounds: the ScrollView's top edge IS the dark
                // divider above (this is the last item in the parent VStack
                // with no spacer between), and `.ignoresSafeArea(.bottom)`
                // extends its bottom edge to the screen bottom so cards
                // visibly scroll behind the tab bar. The ScrollView's own
                // frame is therefore the clip mask the design calls for —
                // no shadow ever shows above the divider, and cards can
                // pass under the nav.
                ScrollView(.horizontal) {
                    LazyHStack(spacing: columnGutter) {
                        ForEach(MeditationDuration.allCases) { duration in
                            MeditationColumn(
                                duration: duration,
                                sessions: sessions,
                                hasAppeared: hasAppeared,
                                onPlay: { session, duration in
                                    FloHaptics.medium()
                                    playerRequest = PlayerRequest(
                                        session: session,
                                        duration: duration
                                    )
                                },
                                onFavorite: { session in
                                    FloHaptics.selection()
                                    toggleFavorite(session)
                                }
                            )
                            // `width` here is already the post-contentMargins
                            // container width, so use it unchanged. The visible
                            // peek emerges naturally from the geometry:
                            //   contentMargin (33) − gutter (24) = 9pt of the
                            // adjacent column showing at each edge.
                            .containerRelativeFrame(.horizontal) { width, _ in
                                width
                            }
                            // Per-item scroll phase (-1 leading … 0 centered
                            // … +1 trailing) drives the dim. `.interactive`
                            // updates phase.value continuously during the
                            // swipe so opacity tracks the gesture rather
                            // than snapping at the rest position.
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                let distance = min(1.0, abs(phase.value))
                                let opacity = 1.0 - (1.0 - peekingColumnOpacity) * distance
                                return content.opacity(opacity)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, columnSideMargin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: durationScrollBinding)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .fullScreenCover(item: $playerRequest) { req in
            MeditationPlayerView(
                session: req.session,
                duration: req.duration,
                onDismiss: { playerRequest = nil },
                onFavorite: { toggleFavorite(req.session) }
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            // Pause icon
            Image("pause")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.floCharcoal)
                .accessibilityLabel("Meditation")

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
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            // Large greeting in Lunary font
            Text("Hello, \(userName)!")
                .font(.custom("LUNARY free", size: 36))
                .foregroundColor(.floCharcoal)
                .accessibilityAddTraits(.isHeader)

            // Subtitle
            Text("LET'S TAKE A PAUSE")
                .font(.floLabel)
                .fontWeight(.bold)
                .foregroundColor(.floCharcoal)
                .tracking(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.sm)
        .padding(.bottom, FloSpacing.sm)
    }

    // MARK: - Duration Tabs
    private var durationTabs: some View {
        let allDurations = MeditationDuration.allCases
        return HStack(spacing: 0) {
            ForEach(Array(allDurations.enumerated()), id: \.element.id) { index, duration in
                Button(action: {
                    FloHaptics.selection()
                    withAnimation(FloAnimation.springSnappy) {
                        selectedDuration = duration
                    }
                }) {
                    Text(duration.displayText)
                        .font(.floLabel)
                        .fontWeight(.medium)
                        .foregroundColor(.floCharcoal)
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.sm)
                        .background(selectedDuration == duration ? Color.floMint.opacity(0.5) : Color.clear)
                        .cornerRadius(FloRadius.sm)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(duration.rawValue) minute meditations")
                .accessibilityAddTraits(selectedDuration == duration ? [.isSelected] : [])

                // Divider between tabs - hide when adjacent tab is selected
                if index < allDurations.count - 1 {
                    let nextDuration = allDurations[index + 1]
                    if selectedDuration != duration && selectedDuration != nextDuration {
                        Rectangle()
                            .fill(Color.floGray.opacity(0.3))
                            .frame(width: 1, height: 20)
                    }
                }
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.sm)
    }

    private func toggleFavorite(_ session: MeditationSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            withAnimation(FloAnimation.springSnappy) {
                sessions[index].isFavorite.toggle()
            }
        }
    }
}

// MARK: - Meditation Column
//
// A single duration's vertical scroll of theme cards. Extracted so the
// parent can present three columns inside a paged TabView bound to
// `selectedDuration` — tapping a duration tab and swiping the columns
// both update the same binding.
private struct MeditationColumn: View {
    let duration: MeditationDuration
    let sessions: [MeditationSession]
    let hasAppeared: Bool
    /// Column hands its own duration back so the parent's PlayerRequest
    /// captures the column-render duration, not whatever selectedDuration
    /// happens to read at tap time (which could be mid-swipe).
    let onPlay: (MeditationSession, MeditationDuration) -> Void
    let onFavorite: (MeditationSession) -> Void

    /// Vertical gap between stacked cards in a column (Figma spec, 28pt).
    private static let cardSpacing: CGFloat = 28
    /// Breathing room between the dark divider and the first card.
    private static let topGap: CGFloat = 21

    var body: some View {
        ScrollView {
            // Cards fill the column width edge-to-edge — no horizontal
            // padding here. The column's outer width already comes from
            // the parent's contentMargins + containerRelativeFrame.
            //
            // Top padding lives on the LazyVStack itself rather than as
            // .contentMargins(.top) on the ScrollView because the
            // horizontal parent ScrollView's content-area math doesn't
            // propagate vertical content margins down into nested
            // vertical ScrollViews — the gap silently disappeared
            // there. Padding on the stack is direct and reliable.
            //
            // Bottom padding is sized to clear the floating tab bar
            // (88pt frame + safe area + a small cushion) so the last
            // card can be scrolled fully above the nav while still
            // passing under it.
            LazyVStack(spacing: Self.cardSpacing) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    MeditationCard(
                        session: session,
                        displayDuration: duration,
                        onPlay: { onPlay(session, duration) },
                        onFavorite: { onFavorite(session) }
                    )
                    .fadeIn(delay: hasAppeared ? 0 : 0.25 + Double(index) * 0.1)
                }
            }
            .padding(.top, Self.topGap)
            .padding(.bottom, 140)
        }
    }
}

// MARK: - Meditation Card
//
// Width-driven card sized from the column it sits inside; height
// follows from a 347:435 (≈4:5) aspect ratio per the Summer-2026-Build
// Figma. No fixed heights anywhere — the column geometry alone decides
// how tall a card is.
//
// Layout pattern: a Color.clear base carries the aspectRatio (the only
// thing in SwiftUI with truly no intrinsic size, so .aspectRatio binds
// reliably). The image + scrim ride on `.background`, the title /
// underline / numeral overlay sits in `.overlay(alignment: .topLeading)`,
// and the centered play glyph sits in a separate `.overlay`. Wrapping
// the whole thing in `.clipShape` rounds the corners; `.shadow` paints
// FloShadow.large underneath — a faint, even drop applied uniformly to
// every card. Active vs peeking dimming happens at the column level via
// .scrollTransition, NOT by varying the shadow.
//
// Architectural rule: the play Button and the favorite Button are
// SIBLINGS, not nested. A Button placed inside another Button's label
// breaks the outer button's tap on iOS — taps land on neither button
// reliably — so the play action never fires. Here, the card-as-Button
// sits at the base of an outer ZStack and the heart sits as a sibling
// overlay. The play Button's label contains zero interactive
// descendants. One tap anywhere on the card = onPlay; one tap on the
// heart = onFavorite, never the other way around.
struct MeditationCard: View {
    let session: MeditationSession
    let displayDuration: MeditationDuration
    let onPlay: () -> Void
    let onFavorite: () -> Void

    /// Width:height ratio for the card frame — locked to the Figma
    /// design's 347:435 reference. Card height = card width × 435/347.
    private static let aspectWidth: CGFloat = 347
    private static let aspectHeight: CGFloat = 435

    private var displayedImageName: String {
        imageVariant(for: displayDuration, in: session)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // BASE LAYER — single Button covering the whole card. Label
            // contains only non-interactive views.
            Button(action: onPlay) {
                Color.clear
                    .aspectRatio(Self.aspectWidth / Self.aspectHeight, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            Image(displayedImageName)
                                .resizable()
                                .scaledToFill()
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.5), location: 0.0),
                                    .init(color: .clear,              location: 0.4),
                                    .init(color: .clear,              location: 0.75),
                                    .init(color: .black.opacity(0.2), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    )
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: FloSpacing.sm) {
                            Text(session.title)
                                .font(.floLabel)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .tracking(1)
                                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)

                            Rectangle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 40, height: 1)

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(displayDuration.rawValue)")
                                    .font(.floSerif(size: 32))
                                    .foregroundColor(.white)
                                Text("mins")
                                    .font(.floSerif(size: 14))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                        }
                        .padding(FloSpacing.lg)
                    }
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.white.opacity(0.15), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                            .accessibilityHidden(true)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FloRadius.lg))
                    .shadow(
                        color: FloShadow.large.color,
                        radius: FloShadow.large.radius,
                        x: FloShadow.large.x,
                        y: FloShadow.large.y
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel("Play \(session.title) meditation, \(displayDuration.rawValue) minutes")

            // SIBLING LAYER — heart sits on top, NOT inside the play Button.
            // Its tap is captured by SwiftUI's hit-testing before falling
            // through to the card button below.
            Button(action: onFavorite) {
                Image(systemName: session.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundColor(session.isFavorite ? .phaseMenstrual : .white)
                    .scaleEffect(session.isFavorite ? 1.1 : 1.0)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.floPressed)
            .padding(FloSpacing.md)
            .animation(FloAnimation.springBouncy, value: session.isFavorite)
            .accessibilityLabel(session.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
    }
}

/// Picks the duration-mapped photo variant from a session's collectible set.
/// Used by both the card list and the player so the surface stays
/// consistent with what the user tapped.
private func imageVariant(for duration: MeditationDuration, in session: MeditationSession) -> String {
    let index: Int
    switch duration {
    case .five: index = 0
    case .fifteen: index = 1
    case .sixty: index = 2
    }
    if session.collectibleImages.indices.contains(index) {
        return session.collectibleImages[index]
    }
    return session.imageName
}

// MARK: - Meditation Player View
//
// The session supplies the theme (background + audio source). `duration`
// drives the countdown ring, the timer label, and the natural end-of-
// session fade — the audio track itself loops indefinitely, so picking
// 60 min just keeps the same loop running for 60 min before bleeding out.
struct MeditationPlayerView: View {
    let session: MeditationSession
    let duration: MeditationDuration
    let onDismiss: () -> Void
    let onFavorite: () -> Void

    @State private var isPlaying = false
    @State private var progress: CGFloat = 0.0
    @State private var timeRemaining: Int
    @State private var timer: Timer?
    @State private var imageScale: CGFloat = 1.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    @State private var showControls = true
    @State private var audio = MeditationAudioController()
    @State private var hasStarted = false
    @State private var hasStartedAudio = false

    /// Fade duration applied when the session timer runs out — long enough
    /// that the loop tapers gently rather than cutting off.
    private let naturalEndFade: Double = 4.0

    init(session: MeditationSession, duration: MeditationDuration, onDismiss: @escaping () -> Void, onFavorite: @escaping () -> Void) {
        self.session = session
        self.duration = duration
        self.onDismiss = onDismiss
        self.onFavorite = onFavorite
        self._timeRemaining = State(initialValue: duration.seconds)
    }

    private let ringSize: CGFloat = 140
    private let buttonSize: CGFloat = 72

    /// Use the same `_a`/`_b`/`_c` variant the tapped card showed, so the
    /// player surface visually matches the card the user selected.
    private var displayedImageName: String {
        imageVariant(for: duration, in: session)
    }

    var body: some View {
        ZStack {
            // Full-bleed background image (ignores safe area)
            GeometryReader { geo in
                Image(displayedImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(imageScale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            // Subtle top-and-bottom dark gradient so title/timer stay
            // legible regardless of which background image is loaded.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content (respects safe area)
            VStack(spacing: 0) {
                topBar
                    .padding(.top, FloSpacing.sm)

                Spacer()

                centerPlayControl

                Spacer()

                // Time remaining at very bottom
                Text(formattedTime)
                    .font(.system(size: 18, weight: .black))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    .padding(.bottom, FloSpacing.md)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 30.0)) {
                imageScale = 1.08
            }
            if !hasStarted {
                hasStarted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    togglePlayPause()
                }
            }
        }
        .onDisappear {
            stopTimer()
            audio.stop()
        }
    }

    private var formattedTime: String {
        let mins = timeRemaining / 60
        let secs = timeRemaining % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button(action: {
                FloHaptics.light()
                stopTimer()
                audio.stop()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial.opacity(0.6))
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel("Close player")

            Spacer()

            Button(action: {
                FloHaptics.selection()
                onFavorite()
            }) {
                Image(systemName: session.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(session.isFavorite ? .phaseMenstrual : .white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial.opacity(0.6))
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .buttonStyle(.floPressed)
            .animation(FloAnimation.springBouncy, value: session.isFavorite)
            .accessibilityLabel(session.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, FloSpacing.lg)
    }

    // MARK: - Center Play Control
    private var centerPlayControl: some View {
        ZStack {
            // Pulsating outer glow when playing
            if isPlaying {
                Circle()
                    .fill(Color.white.opacity(pulseOpacity * 0.05))
                    .frame(width: ringSize + 50, height: ringSize + 50)
                    .scaleEffect(pulseScale)
            }

            // Ring track -- translucent white
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 5)
                .frame(width: ringSize, height: ringSize)

            // Progress ring -- solid white arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .shadow(color: .white.opacity(0.4), radius: 4, x: 0, y: 0)
                .animation(.linear(duration: 1), value: progress)

            // Play/Pause button
            Button(action: togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.floSage)
                        .frame(width: buttonSize, height: buttonSize)
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)

                    Image(systemName: isPlaying ? "pause" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel(isPlaying ? "Pause meditation" : "Play meditation")
        }
    }

    // MARK: - Controls
    private func togglePlayPause() {
        FloHaptics.medium()
        isPlaying.toggle()

        if isPlaying {
            startTimer()
            startPulseAnimation()
            // First press kicks off real-file or synth playback via the
            // unified controller; subsequent presses resume after pause.
            if !hasStartedAudio {
                hasStartedAudio = true
                audio.play(session: session)
            } else {
                audio.resume()
            }
        } else {
            stopTimer()
            stopPulseAnimation()
            audio.pause()
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
            pulseOpacity = 0.3
        }
    }

    private func stopPulseAnimation() {
        withAnimation(.easeOut(duration: 0.6)) {
            pulseScale = 1.0
            pulseOpacity = 0.6
        }
    }

    private func startTimer() {
        let totalSeconds = duration.seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                    progress = CGFloat(totalSeconds - timeRemaining) / CGFloat(totalSeconds)
                } else {
                    FloHaptics.success()
                    stopTimer()
                    isPlaying = false
                    stopPulseAnimation()
                    // Gentle fade at natural session end (vs. the snappier
                    // 1s fade when the user dismisses).
                    audio.stop(fade: naturalEndFade)
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview("Meditation Main") {
    MeditationMainView()
}

#Preview("Meditation Player") {
    MeditationPlayerView(
        session: MeditationSession(
            title: "MIST",
            phase: .menstrual,
            imageName: "medbg_mist_a",
            collectibleImages: ["medbg_mist_a", "medbg_mist_b", "medbg_mist_c"],
            audioFileName: "mist_05min"
        ),
        duration: .fifteen,
        onDismiss: {},
        onFavorite: {}
    )
}
