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
    let duration: MeditationDuration
    let imageName: String  // Asset image name
    var isFavorite: Bool = false
    var ambientSound: AmbientSoundType = .warmDrone
}

// MARK: - Main Meditation View
struct MeditationMainView: View {
    @State private var selectedDuration: MeditationDuration = .five
    @State private var selectedSession: MeditationSession?
    @State private var hasAppeared = false

    private var userName: String { CycleManager.shared.userName }

    // Sample meditation sessions with actual images
    @State private var sessions: [MeditationSession] = [
        MeditationSession(
            title: "A NEW DAY",
            duration: .five,
            imageName: "sunsetrocks",
            ambientSound: .warmDrone
        ),
        MeditationSession(
            title: "KEEP MOVING",
            duration: .five,
            imageName: "starynight",
            ambientSound: .nightAmbience
        ),
        MeditationSession(
            title: "OCEAN CALM",
            duration: .sixty,
            imageName: "surfer",
            isFavorite: true,
            ambientSound: .oceanWaves
        ),
        MeditationSession(
            title: "FOREST WALK",
            duration: .fifteen,
            imageName: "fisherman",
            ambientSound: .forestBreeze
        ),
        MeditationSession(
            title: "NIGHT SKY",
            duration: .fifteen,
            imageName: "nightsky",
            ambientSound: .softChimes
        ),
        MeditationSession(
            title: "WAVE CRASH",
            duration: .sixty,
            imageName: "wavecrash",
            isFavorite: true,
            ambientSound: .gentleRain
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
    @State private var audioEngine = AmbientAudioEngine()
    @State private var hasStarted = false

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

            // Subtle vignette (ignores safe area)
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.3)],
                center: .center,
                startRadius: 200,
                endRadius: 500
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
            audioEngine.stop()
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
                audioEngine.stop()
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
            // Start or resume ambient audio
            if audioEngine.currentSound == nil {
                audioEngine.play(sound: session.ambientSound)
            } else {
                audioEngine.resume()
            }
        } else {
            stopTimer()
            stopPulseAnimation()
            audioEngine.pause()
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
                audioEngine.stop()
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
            title: "A NEW DAY",
            duration: .five,
            imageName: "sunsetrocks"
        ),
        onDismiss: {},
        onFavorite: {}
    )
}
