//
//  SplashView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Splash Greeting
struct SplashGreeting {
    let text: String
    let imageName: String

    static let greetings: [SplashGreeting] = [
        SplashGreeting(text: "Oh good.\nIt's you.", imageName: "rivertrees"),
        SplashGreeting(text: "Oh, there\nyou are.", imageName: "starynight"),
        SplashGreeting(text: "Hey there\nbeautiful.", imageName: "caves"),
        SplashGreeting(text: "Yep.\nI see you.", imageName: "sunsetrocks"),
        SplashGreeting(text: "Okay good.\nLet's get started.", imageName: "greencliff"),
        SplashGreeting(text: "There\nyou are.", imageName: "treetops"),
        SplashGreeting(text: "Always good\nto see you.", imageName: "nightsky"),
        SplashGreeting(text: "Let's soak\nit in.", imageName: "wavecrash"),
        SplashGreeting(text: "You are\na light.", imageName: "treepath"),
    ]

    static var random: SplashGreeting {
        greetings.randomElement() ?? greetings[0]
    }
}

// MARK: - Splash View
struct SplashView: View {
    let greeting: SplashGreeting
    let onTapAdvance: (() -> Void)?

    init(greeting: SplashGreeting = .random, onTapAdvance: (() -> Void)? = nil) {
        self.greeting = greeting
        self.onTapAdvance = onTapAdvance
    }

    // Phase 1: Black screen with logo
    @State private var dailyOpacity: Double = 0
    @State private var dailyOffset: CGFloat = 12
    @State private var floOpacity: Double = 0

    // Phase 2: Nature image with greeting
    @State private var showPhaseTwo = false
    @State private var imageOpacity: Double = 0
    @State private var imageScale: CGFloat = 1.0
    @State private var greetingOpacity: Double = 0
    @State private var greetingOffset: CGFloat = 20
    @State private var floMarkOpacity: Double = 0
    @State private var tapHintOpacity: Double = 0
    @State private var canTapToAdvance = false

    var body: some View {
        ZStack {
            // PHASE 1: Black background with logo
            phase1View
                .opacity(showPhaseTwo ? 0 : 1)

            // PHASE 2: Nature image with greeting
            phase2View
                .opacity(showPhaseTwo ? 1 : 0)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            if canTapToAdvance {
                FloHaptics.light()
                onTapAdvance?()
            }
        }
        .onAppear {
            startAnimationSequence()
        }
    }

    // MARK: - Phase 1: Brand Logo (left-aligned, ~40% from top)
    private var phase1View: some View {
        ZStack {
            Color.black

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 6) {
                    // "Daily" in large elegant Lunary
                    Text("Daily")
                        .font(.custom("LUNARY free", size: 62))
                        .foregroundColor(.white)
                        .opacity(dailyOpacity)
                        .offset(y: dailyOffset)

                    // "FLO" in small tracked uppercase
                    Text("FLO")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.white.opacity(0.85))
                        .tracking(5)
                        .opacity(floOpacity)
                }
                .padding(.leading, geo.safeAreaInsets.leading + 36)
                .frame(width: geo.size.width, alignment: .leading)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily Flo")
    }

    // MARK: - Phase 2: Nature Greeting
    private var phase2View: some View {
        ZStack {
            // Full-bleed nature image with slow Ken Burns zoom
            GeometryReader { imgGeo in
                Image(greeting.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(imageScale)
                    .opacity(imageOpacity)
                    .frame(width: imgGeo.size.width, height: imgGeo.size.height)
                    .clipped()
            }

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
            .opacity(imageOpacity)

            // Content — use GeometryReader for proportional positioning
            GeometryReader { geo in
                ZStack {
                    // FLO mark top-right
                    VStack {
                        HStack {
                            Spacer()
                            Text("FLO")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.white.opacity(0.85))
                                .tracking(5)
                                .opacity(floMarkOpacity)
                        }
                        .padding(.trailing, 28)
                        .padding(.top, 60)

                        Spacer()
                    }

                    // Greeting text — left-aligned, positioned at ~40% from top
                    VStack(alignment: .leading) {
                        Text(greeting.text)
                            .font(.custom("LUNARY free", size: 58))
                            .foregroundColor(.white)
                            .lineSpacing(8)
                            .opacity(greetingOpacity)
                            .offset(y: greetingOffset)
                            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
                    }
                    .frame(width: geo.size.width, alignment: .leading)
                    .padding(.leading, geo.safeAreaInsets.leading + 100)
                    .padding(.trailing, 40)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.42)

                    // TAP TO ADVANCE hint at bottom
                    VStack {
                        Spacer()
                        Text("TAP TO ADVANCE")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(3)
                            .opacity(tapHintOpacity)
                            .padding(.bottom, 50)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(greeting.text.replacingOccurrences(of: "\n", with: " "))
    }

    // MARK: - Animation Sequence
    private func startAnimationSequence() {
        // ═══ PHASE 1: Black screen with logo (0 – 2.2s) ═══

        // "Daily" fades in and rises gently
        withAnimation(.easeOut(duration: 1.2)) {
            dailyOpacity = 1
            dailyOffset = 0
        }

        // "FLO" fades in after Daily settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.8)) {
                floOpacity = 1
            }
        }

        // ═══ PHASE 2: Crossfade to nature image (2.2s+) ═══

        // Slow crossfade to nature image
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 1.4)) {
                showPhaseTwo = true
                imageOpacity = 1
            }

            // Start very slow Ken Burns zoom
            withAnimation(.easeInOut(duration: 10.0)) {
                imageScale = 1.08
            }
        }

        // FLO mark fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeOut(duration: 1.0)) {
                floMarkOpacity = 1
            }
        }

        // Greeting text rises in — slow and luxurious
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            withAnimation(.easeOut(duration: 1.4)) {
                greetingOpacity = 1
                greetingOffset = 0
            }
        }

        // TAP TO ADVANCE hint fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            canTapToAdvance = true
            withAnimation(.easeOut(duration: 0.8)) {
                tapHintOpacity = 1
            }
        }
    }
}

#Preview("Splash - Full Sequence") {
    SplashView()
}
