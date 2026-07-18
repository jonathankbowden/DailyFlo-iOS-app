//
//  VoiceEntryView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 3/22/26.
//

import SwiftUI
import Speech

/// A zen, full-screen voice journaling experience.
/// The user taps to start speaking, taps again to finish.
/// An on-device model generates a short title from the transcript.
struct VoiceEntryView: View {
    /// Called with (title, body) when the user accepts the entry.
    var onComplete: (_ title: String, _ body: String) -> Void
    var onDismiss: () -> Void

    // MARK: - State

    @State private var speechRecognizer = SpeechRecognizer()
    @State private var phase: Phase = .idle
    @State private var generatedTitle: String = ""
    @State private var distilledBody: String = ""
    @State private var isDistilling: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var permissionDenied: Bool = false

    private enum Phase {
        case idle        // Not yet started
        case listening   // Actively transcribing
        case reviewing   // Done speaking, reviewing transcript + title
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.floGray.opacity(0.3))
                        .frame(width: 36, height: 5)
                    Spacer()
                }
                .padding(.top, FloSpacing.sm)

                if phase == .idle {
                    // Idle: let the idle view manage its own vertical layout
                    mainContent
                        .fadeIn(delay: hasAppeared ? 0 : 0.15)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()

                    // Main content area
                    mainContent
                        .fadeIn(delay: hasAppeared ? 0 : 0.15)

                    Spacer(minLength: FloSpacing.xl)

                    // Bottom action
                    bottomAction
                        .fadeIn(delay: hasAppeared ? 0 : 0.25)
                        .padding(.bottom, FloSpacing.xxl)
                }
            }
            .padding(.horizontal, FloSpacing.lg)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch phase {
        case .idle:
            idleView
        case .listening:
            listeningView
        case .reviewing:
            reviewingView
        }
    }

    // MARK: - Idle (pre-recording)

    private var idleView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 80)

            Text("Speak freely.")
                .font(.floDisplayLarge)
                .foregroundColor(.floCharcoal)
                .padding(.bottom, FloSpacing.lg)

            Text("Tap the circle below to begin.\nWe will listen and capture your thoughts.")
                .font(.floBodyMedium)
                .foregroundColor(.floGray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if permissionDenied {
                Text("Microphone or speech permission was denied.\nPlease enable them in Settings.")
                    .font(.floBodySmall)
                    .foregroundColor(.floError)
                    .multilineTextAlignment(.center)
                    .padding(.top, FloSpacing.sm)
            }

            Spacer()

            micButton {
                await beginListening()
            }

            Spacer()

            Text("Swipe down to cancel")
                .font(.floBodySmall)
                .foregroundColor(.floGray.opacity(0.5))
                .padding(.bottom, 24)
        }
    }

    // MARK: - Listening

    private var listeningView: some View {
        VStack(spacing: FloSpacing.xl) {
            Text("Listening...")
                .font(.floSerif(size: 28))
                .foregroundColor(.floCharcoal)

            // Pulsing mic indicator
            ZStack {
                // Outer pulse rings
                Circle()
                    .fill(Color.floSage.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulseScale)

                Circle()
                    .fill(Color.floSage.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseScale * 0.95)

                // Core mic circle
                Circle()
                    .fill(Color.floSage)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color.floSage.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    pulseScale = 1.15
                }
            }
            .onTapGesture {
                finishListening()
            }

            // Live transcript
            if !speechRecognizer.transcript.isEmpty {
                ScrollView {
                    Text(speechRecognizer.transcript)
                        .font(.floSerif(size: 18))
                        .foregroundColor(.floCharcoal.opacity(0.7))
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .animation(.easeOut(duration: 0.15), value: speechRecognizer.transcript)
                }
                .frame(maxHeight: 200)
                .padding(.horizontal, FloSpacing.md)
            }
        }
    }

    // MARK: - Reviewing

    private var reviewingView: some View {
        VStack(spacing: FloSpacing.xl) {
            // AI-generated title and body
            VStack(spacing: FloSpacing.sm) {
                if isDistilling {
                    HStack(spacing: FloSpacing.sm) {
                        FloLoadingIndicator(size: 16, color: .floSage, lineWidth: 2)
                        Text("Distilling your thoughts...")
                            .font(.floBodySmall)
                            .foregroundColor(.floGray)
                    }
                } else if !generatedTitle.isEmpty {
                    Text(generatedTitle)
                        .font(.floSerif(size: 28))
                        .foregroundColor(.floCharcoal)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(minHeight: 40)
            .animation(FloAnimation.easeOutMedium, value: isDistilling)

            // Divider
            FloDivider()
                .padding(.horizontal, FloSpacing.xxl)

            // Distilled body
            ScrollView {
                Text(isDistilling ? speechRecognizer.transcript : distilledBody)
                    .font(.floSerif(size: 18))
                    .foregroundColor(.floCharcoal)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(FloAnimation.easeOutMedium, value: isDistilling)
            }
            .frame(maxHeight: 280)
            .padding(.horizontal, FloSpacing.sm)
        }
    }

    // MARK: - Bottom Action

    @ViewBuilder
    private var bottomAction: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .listening:
            Button(action: finishListening) {
                Text("Done")
                    .font(.floButton)
                    .foregroundColor(.floSage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.white)
                    .cornerRadius(FloRadius.full)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloRadius.full)
                            .stroke(Color.floSage, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.floPressed)
            .padding(.horizontal, FloSpacing.xl)

        case .reviewing:
            HStack(spacing: FloSpacing.md) {
                // Try again
                Button(action: {
                    FloHaptics.light()
                    resetToIdle()
                }) {
                    Text("Redo")
                        .font(.floButton)
                        .foregroundColor(.floGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.md)
                        .background(Color.white)
                        .cornerRadius(FloRadius.full)
                        .overlay(
                            RoundedRectangle(cornerRadius: FloRadius.full)
                                .stroke(Color.floGray.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.floPressed)

                // Use this
                Button(action: {
                    FloHaptics.success()
                    onComplete(generatedTitle, distilledBody)
                }) {
                    Text("Use This")
                        .font(.floButton)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.md)
                        .background(Color.floSage)
                        .cornerRadius(FloRadius.full)
                        .shadow(color: Color.floSage.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.floPressed)
                .disabled(isDistilling)
                .opacity(isDistilling ? 0.6 : 1.0)
            }
            .padding(.horizontal, FloSpacing.md)
        }
    }

    // MARK: - Mic Button

    private func micButton(action: @escaping () async -> Void) -> some View {
        Button(action: {
            Task { await action() }
        }) {
            ZStack {
                Circle()
                    .fill(Color.floSage.opacity(0.08))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(Color.floSage.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Color.floSage)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color.floSage.opacity(0.3), radius: 10, x: 0, y: 5)
            }
        }
        .buttonStyle(.floPressed)
        .floHitTarget()
        .accessibilityLabel("Start voice recording")
    }

    // MARK: - Actions

    private func beginListening() async {
        permissionDenied = false

        // Request permissions
        let micAccess = await SpeechRecognizer.requestMicrophoneAccess()
        guard micAccess else {
            permissionDenied = true
            return
        }
        let speechStatus = await SpeechRecognizer.requestAuthorization()
        guard speechStatus == .authorized else {
            permissionDenied = true
            return
        }

        FloHaptics.medium()
        withAnimation(FloAnimation.easeOutMedium) {
            phase = .listening
        }
        speechRecognizer.startListening()
    }

    private func finishListening() {
        FloHaptics.light()
        speechRecognizer.stopListening()
        pulseScale = 1.0

        guard !speechRecognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetToIdle()
            return
        }

        withAnimation(FloAnimation.easeOutMedium) {
            phase = .reviewing
        }

        // Distill title and body with AI
        isDistilling = true
        Task {
            let entry = await TitleGenerator.distill(from: speechRecognizer.transcript)
            withAnimation(FloAnimation.easeOutMedium) {
                generatedTitle = entry.title
                distilledBody = entry.body
                isDistilling = false
            }
        }
    }

    private func resetToIdle() {
        withAnimation(FloAnimation.easeOutMedium) {
            phase = .idle
            generatedTitle = ""
            distilledBody = ""
            isDistilling = false
            speechRecognizer.transcript = ""
        }
    }
}

#Preview {
    VoiceEntryView(
        onComplete: { title, body in
            print("Title: \(title), Body: \(body)")
        },
        onDismiss: {}
    )
}
