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
struct MeditationSession: Identifiable {
    let id = UUID()
    let title: String
    let phase: CyclePhase
    let duration: MeditationDuration
    /// Displayed background. By convention the `_a` variant of the theme.
    let imageName: String
    /// All three theme variants (`_a`/`_b`/`_c`), wired for the future
    /// collectible gallery. The active surface uses `imageName` (== `_a`).
    let collectibleImages: [String]
    /// Bundled MP3 to loop during the session. `nil` falls back to the
    /// `AmbientAudioEngine` synth for `ambientSound`.
    let audioFileName: String?
    /// Synth fallback used when `audioFileName` is `nil`.
    var ambientSound: AmbientSoundType = .warmDrone
    var isFavorite: Bool = false
}

// MARK: - Main Meditation View
struct MeditationMainView: View {
    @State private var selectedDuration: MeditationDuration = .five
    @State private var selectedSession: MeditationSession?
    @State private var hasAppeared = false

    private var userName: String { CycleManager.shared.userName }

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
            duration: .five,
            imageName: "medbg_mist_a",
            collectibleImages: ["medbg_mist_a", "medbg_mist_b", "medbg_mist_c"],
            audioFileName: "mist_05min",
            ambientSound: .gentleRain
        ),
        MeditationSession(
            title: "NIGHT SKY",
            phase: .menstrual,
            duration: .five,
            imageName: "medbg_nightsky_a",
            collectibleImages: ["medbg_nightsky_a", "medbg_nightsky_b", "medbg_nightsky_c"],
            audioFileName: "nightsky_05min",
            ambientSound: .nightAmbience
        ),
        MeditationSession(
            title: "STILLWATER",
            phase: .menstrual,
            duration: .five,
            imageName: "medbg_stillwater_a",
            collectibleImages: ["medbg_stillwater_a", "medbg_stillwater_b", "medbg_stillwater_c"],
            audioFileName: nil,
            ambientSound: .warmDrone
        ),
        // Follicular
        MeditationSession(
            title: "CANOPY",
            phase: .follicular,
            duration: .five,
            imageName: "medbg_canopy_a",
            collectibleImages: ["medbg_canopy_a", "medbg_canopy_b", "medbg_canopy_c"],
            audioFileName: "canopy_05min",
            ambientSound: .forestBreeze
        ),
        MeditationSession(
            title: "OPEN HILLS",
            phase: .follicular,
            duration: .five,
            imageName: "medbg_openhills_a",
            collectibleImages: ["medbg_openhills_a", "medbg_openhills_b", "medbg_openhills_c"],
            audioFileName: nil,
            ambientSound: .forestBreeze
        ),
        // Ovulation
        MeditationSession(
            title: "GOLDEN HOUR",
            phase: .ovulation,
            duration: .five,
            imageName: "medbg_goldenhour_a",
            collectibleImages: ["medbg_goldenhour_a", "medbg_goldenhour_b", "medbg_goldenhour_c"],
            audioFileName: nil,
            ambientSound: .softChimes
        ),
        MeditationSession(
            title: "OCEAN",
            phase: .ovulation,
            duration: .five,
            imageName: "medbg_ocean_a",
            collectibleImages: ["medbg_ocean_a", "medbg_ocean_b", "medbg_ocean_c"],
            audioFileName: "ocean_05min",
            ambientSound: .oceanWaves
        ),
        // Luteal
        MeditationSession(
            title: "STORM",
            phase: .luteal,
            duration: .five,
            imageName: "medbg_storm_a",
            collectibleImages: ["medbg_storm_a", "medbg_storm_b", "medbg_storm_c"],
            audioFileName: "storm_05min",
            ambientSound: .gentleRain
        ),
        MeditationSession(
            title: "FOREST",
            phase: .luteal,
            duration: .five,
            imageName: "medbg_forest_a",
            collectibleImages: ["medbg_forest_a", "medbg_forest_b", "medbg_forest_c"],
            audioFileName: nil,
            ambientSound: .forestBreeze
        ),
        MeditationSession(
            title: "SOLITUDE",
            phase: .luteal,
            duration: .five,
            imageName: "medbg_solitude_a",
            collectibleImages: ["medbg_solitude_a", "medbg_solitude_b", "medbg_solitude_c"],
            audioFileName: nil,
            ambientSound: .warmDrone
        )
    ]

    var filteredSessions: [MeditationSession] {
        sessions.filter { $0.duration == selectedDuration }
    }

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

                // Meditation cards
                ScrollView {
                    LazyVStack(spacing: FloSpacing.lg) {
                        ForEach(Array(filteredSessions.enumerated()), id: \.element.id) { index, session in
                            MeditationCard(
                                session: session,
                                onPlay: {
                                    FloHaptics.medium()
                                    selectedSession = session
                                },
                                onFavorite: {
                                    FloHaptics.selection()
                                    toggleFavorite(session)
                                }
                            )
                            .fadeIn(delay: hasAppeared ? 0 : 0.25 + Double(index) * 0.1)
                        }
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.lg)
                    .padding(.bottom, 140)
                }
            }
        }
        .fullScreenCover(item: $selectedSession) { session in
            MeditationPlayerView(
                session: session,
                onDismiss: { selectedSession = nil },
                onFavorite: { toggleFavorite(session) }
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

// MARK: - Meditation Card
struct MeditationCard: View {
    let session: MeditationSession
    let onPlay: () -> Void
    let onFavorite: () -> Void
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Background image
            Image(session.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 320)
                .clipped()

            // Dark overlay for better text visibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content overlay
            VStack {
                // Top row - title and favorite
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: FloSpacing.sm) {
                        // Title
                        Text(session.title)
                            .font(.floLabel)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .tracking(1)
                            .padding(.bottom, FloSpacing.xs)

                        // Divider line
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 40, height: 1)
                            .padding(.bottom, FloSpacing.xxs)

                        // Duration
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(session.duration.rawValue)")
                                .font(.floSerif(size: 32))
                                .foregroundColor(.white)

                            Text("mins")
                                .font(.floSerif(size: 14))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }

                    Spacer()

                    // Favorite button
                    Button(action: onFavorite) {
                        Image(systemName: session.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 22))
                            .foregroundColor(session.isFavorite ? .phaseMenstrual : .white)
                            .scaleEffect(session.isFavorite ? 1.1 : 1.0)
                    }
                    .buttonStyle(.floPressed)
                    .animation(FloAnimation.springBouncy, value: session.isFavorite)
                    .accessibilityLabel(session.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
                .padding(FloSpacing.lg)

                Spacer()
                    .frame(maxHeight: 16)

                // Play button centered
                Button(action: onPlay) {
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(Color.floSage.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .blur(radius: 10)

                        Circle()
                            .fill(Color.floSage)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.floSage.opacity(0.5), radius: 10, x: 0, y: 4)

                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    }
                }
                .buttonStyle(.floPressed)
                .accessibilityLabel("Play \(session.title) meditation")

                Spacer()
            }
        }
        .frame(height: 320)
        .cornerRadius(FloRadius.lg)
        .shadow(color: FloShadow.large.color, radius: FloShadow.large.radius, x: 0, y: FloShadow.large.y)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(FloAnimation.buttonPress, value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Meditation Player View
struct MeditationPlayerView: View {
    let session: MeditationSession
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

    init(session: MeditationSession, onDismiss: @escaping () -> Void, onFavorite: @escaping () -> Void) {
        self.session = session
        self.onDismiss = onDismiss
        self.onFavorite = onFavorite
        self._timeRemaining = State(initialValue: session.duration.seconds)
    }

    private let ringSize: CGFloat = 140
    private let buttonSize: CGFloat = 72

    var body: some View {
        ZStack {
            // Full-bleed background image (ignores safe area)
            GeometryReader { geo in
                Image(session.imageName)
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
        let totalSeconds = session.duration.seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
                progress = CGFloat(totalSeconds - timeRemaining) / CGFloat(totalSeconds)
            } else {
                FloHaptics.success()
                stopTimer()
                isPlaying = false
                stopPulseAnimation()
                audio.stop()
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
            duration: .five,
            imageName: "medbg_mist_a",
            collectibleImages: ["medbg_mist_a", "medbg_mist_b", "medbg_mist_c"],
            audioFileName: "mist_05min"
        ),
        onDismiss: {},
        onFavorite: {}
    )
}
