//
//  SupporterHomeView.swift
//  DailyFlo
//
//  The supporter-side home. Internal naming uses tracker/supporter; UI copy
//  never says "tracker" — the supporter sees themselves as "you" and the
//  person they're supporting as "her" (name-first where possible).
//
//  Day 12 of the 30-for-30 (Sept 2026): renders from a `SupporterSnapshot`
//  loaded through the permission-gated `supporter_snapshot` RPC. The phase
//  is computed here with the same math the tracker's own screens use, so
//  both phones agree on the day and the phase. The June mock fixture is
//  gone; previews use `SupporterContext.preview`.
//

import Supabase
import SwiftUI

// MARK: - Supporter context (the shape supporter screens render from)

/// What the supporter home needs to render, derived from a snapshot.
struct SupporterContext: Equatable {
    let trackerName: String
    /// `nil` when the tracker hasn't shared their phase, or hasn't logged
    /// a period yet. The screen explains which.
    let phase: CyclePhase?
    let cycleDay: Int?
    let canViewPhase: Bool

    var supportTips: [String] {
        phase.map(SupporterTips.tips(for:)) ?? []
    }

    init(trackerName: String, phase: CyclePhase?, cycleDay: Int?, canViewPhase: Bool) {
        self.trackerName = trackerName
        self.phase = phase
        self.cycleDay = cycleDay
        self.canViewPhase = canViewPhase
    }

    init(snapshot: SupporterSnapshot) {
        let trimmed = snapshot.trackerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            trackerName: trimmed.isEmpty ? "Your partner" : trimmed,
            phase: snapshot.currentPhase,
            cycleDay: snapshot.currentCycleDay,
            canViewPhase: snapshot.canViewPhase
        )
    }

    static let preview = SupporterContext(
        trackerName: "Sarah",
        phase: .follicular,
        cycleDay: 9,
        canViewPhase: true
    )
}

// MARK: - Support tips

/// Partner-facing guidance per phase. Warm, practical, never clinical.
/// Brittany owns the voice here; copy edits are welcome.
enum SupporterTips {
    static func tips(for phase: CyclePhase) -> [String] {
        switch phase {
        case .menstrual:
            return [
                "Energy is at its lowest this week — rest is productive right now.",
                "Warmth, quiet, and a low-key evening go a long way.",
                "Take something off her plate without being asked."
            ]
        case .follicular:
            return [
                "Energy is rising this week — a great time to plan something active together.",
                "She may feel more social and optimistic right now.",
                "Small encouragements go a long way in this phase."
            ]
        case .ovulation:
            return [
                "She's likely at her most confident and connected this week.",
                "A good week for a real conversation or a date night.",
                "Match her energy — she'll want to be out and about."
            ]
        case .luteal:
            return [
                "Energy tapers as the week goes on — patience matters most now.",
                "Small comforts land bigger than big gestures.",
                "If she's quieter than usual, that's the phase, not you."
            ]
        }
    }
}

// MARK: - Supporter home

struct SupporterHomeView: View {
    private enum LoadState: Equatable {
        case loading
        case loaded(SupporterContext)
        case notConnected
        case failed(String)
    }

    /// Injected for previews and screenshots; `nil` loads from the DB.
    var previewContext: SupporterContext? = nil

    @State private var loadState: LoadState = .loading
    @State private var showSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var signOutErrorMessage: String?

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FloSpacing.xl) {
                    switch loadState {
                    case .loading:
                        loadingBlock
                    case .loaded(let context):
                        header(context)
                        if let phase = context.phase, let day = context.cycleDay {
                            phaseCard(context, phase: phase, day: day)
                            supportTipsSection(context, phase: phase)
                        } else {
                            phaseUnavailableCard(context)
                        }
                    case .notConnected:
                        notConnectedBlock
                    case .failed(let message):
                        failedBlock(message)
                    }
                    signOutButton
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.xl)
                .padding(.bottom, FloSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
        }
        .task { await load() }
        .alert("Sign out of DailyFLO?", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) { performSignOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to access your supporter view.")
        }
        .overlay(alignment: .bottom) {
            if let message = signOutErrorMessage {
                Text(message)
                    .floToast(.error)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, FloSpacing.xxl)
                    .animation(FloAnimation.springGentle, value: signOutErrorMessage)
            }
        }
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        if let previewContext {
            loadState = .loaded(previewContext)
            return
        }
        do {
            if let snapshot = try await PartnerManager.shared.loadSupporterSnapshot() {
                withAnimation(.easeInOut(duration: 0.25)) {
                    loadState = .loaded(SupporterContext(snapshot: snapshot))
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    loadState = .notConnected
                }
            }
        } catch {
            loadState = .failed("Couldn't load right now. Pull down to try again.")
        }
    }

    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: FloSpacing.xs) {
            Text("SUPPORTING")
                .font(.floLabel)
                .fontWeight(.semibold)
                .tracking(2)
                .foregroundColor(.floGray)

            FloLoadingIndicator(size: 28, color: .floSage, lineWidth: 3)
                .padding(.top, FloSpacing.md)
        }
        .padding(.top, FloSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
    }

    // MARK: - Header

    private func header(_ context: SupporterContext) -> some View {
        VStack(alignment: .leading, spacing: FloSpacing.xs) {
            Text("SUPPORTING")
                .font(.floLabel)
                .fontWeight(.semibold)
                .tracking(2)
                .foregroundColor(.floGray)

            Text(context.trackerName)
                .font(.floDisplayLarge)
                .foregroundColor(.floCharcoal)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, FloSpacing.lg)
    }

    // MARK: - Phase card

    private func phaseCard(_ context: SupporterContext, phase: CyclePhase, day: Int) -> some View {
        let phaseDisplayName = phase.name.replacingOccurrences(of: " Phase", with: "")

        return HStack(alignment: .top, spacing: FloSpacing.md) {
            // Phase color accent rail
            RoundedRectangle(cornerRadius: 3)
                .fill(phase.color)
                .frame(width: 6)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                Text("THIS WEEK")
                    .font(.floLabel)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundColor(.floGray)

                HStack(alignment: .firstTextBaseline, spacing: FloSpacing.sm) {
                    Text(phaseDisplayName)
                        .font(.floSerif(size: 24))
                        .foregroundColor(.floCharcoal)

                    Text("·")
                        .font(.floSerif(size: 24))
                        .foregroundColor(.floGray)

                    Text("Day \(day)")
                        .font(.floSerif(size: 24))
                        .foregroundColor(.floCharcoal)
                }

                // Subtitles are written in the tracker's voice ("YOUR HIGH
                // HORMONE PHASE"); drop the pronoun for the supporter.
                Text(phase.subtitle.replacingOccurrences(of: "YOUR ", with: "").capitalizedHumanized)
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(FloSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(
            color: FloShadow.small.color,
            radius: FloShadow.small.radius,
            x: FloShadow.small.x,
            y: FloShadow.small.y
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(phaseDisplayName) phase, day \(day)")
    }

    /// Shown when the relationship exists but there's no phase to show:
    /// either the tracker turned phase sharing off, or hasn't logged a
    /// period yet. The copy names which.
    private func phaseUnavailableCard(_ context: SupporterContext) -> some View {
        let message = context.canViewPhase
            ? "\(context.trackerName) hasn't logged a period yet. Her phase will appear here as soon as she does."
            : "\(context.trackerName) isn't sharing her phase right now. You'll see it here if she turns sharing on."

        return infoCard(icon: context.canViewPhase ? "calendar" : "lock", message: message)
    }

    // MARK: - Support tips

    private func supportTipsSection(_ context: SupporterContext, phase: CyclePhase) -> some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("How to support her this week")
                .font(.floDisplaySmall)
                .foregroundColor(.floCharcoal)

            VStack(spacing: FloSpacing.sm) {
                ForEach(Array(context.supportTips.enumerated()), id: \.offset) { _, tip in
                    supportTipRow(tip, phase: phase)
                }
            }
        }
    }

    private func supportTipRow(_ tip: String, phase: CyclePhase) -> some View {
        HStack(alignment: .top, spacing: FloSpacing.md) {
            Circle()
                .fill(phase.color.opacity(0.85))
                .frame(width: 8, height: 8)
                .padding(.top, 8)

            Text(tip)
                .font(.floBodyLarge)
                .foregroundColor(.floCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.md)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(
            color: FloShadow.small.color,
            radius: FloShadow.small.radius,
            x: FloShadow.small.x,
            y: FloShadow.small.y
        )
    }

    // MARK: - Empty and error states

    private var notConnectedBlock: some View {
        VStack(alignment: .leading, spacing: FloSpacing.lg) {
            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                Text("SUPPORTING")
                    .font(.floLabel)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundColor(.floGray)

                Text("No one yet")
                    .font(.floDisplayLarge)
                    .foregroundColor(.floCharcoal)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, FloSpacing.lg)

            infoCard(
                icon: "person.2",
                message: "When your partner sends you an invite code from DailyFLO, enter it on her Connect screen's \"enter an invite code\" step and you'll see her here."
            )
        }
    }

    private func failedBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: FloSpacing.lg) {
            Text("SUPPORTING")
                .font(.floLabel)
                .fontWeight(.semibold)
                .tracking(2)
                .foregroundColor(.floGray)
                .padding(.top, FloSpacing.lg)

            infoCard(icon: "wifi.exclamationmark", message: message)
        }
    }

    private func infoCard(icon: String, message: String) -> some View {
        HStack(alignment: .top, spacing: FloSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.floSage)
                .frame(width: 32, height: 32)
                .background(Color.floSage.opacity(0.1))
                .clipShape(Circle())

            Text(message)
                .font(.floBodyMedium)
                .foregroundColor(.floCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(
            color: FloShadow.small.color,
            radius: FloShadow.small.radius,
            x: FloShadow.small.x,
            y: FloShadow.small.y
        )
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button {
            FloHaptics.light()
            showSignOutConfirm = true
        } label: {
            HStack(spacing: FloSpacing.sm) {
                if isSigningOut {
                    FloLoadingIndicator(size: 18, color: .floError, lineWidth: 2)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18, weight: .medium))
                }
                Text("Sign Out")
                    .font(.floButton)
            }
            .foregroundColor(.floError)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.lg)
                    .stroke(Color.floError.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.floPressed)
        .disabled(isSigningOut)
        .padding(.top, FloSpacing.md)
        .accessibilityLabel("Sign out")
        .accessibilityHint("Sign out of your DailyFLO supporter account")
    }

    private func performSignOut() {
        guard !isSigningOut else { return }
        FloHaptics.medium()
        isSigningOut = true

        Task { @MainActor in
            defer { isSigningOut = false }
            do {
                try await SupabaseClient.shared.auth.signOut()
                // App-level auth listener routes back to sign-in.
            } catch {
                FloHaptics.error()
                signOutErrorMessage = "Couldn't sign out. \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { signOutErrorMessage = nil }
                }
            }
        }
    }
}

// MARK: - String helper

private extension String {
    /// Turns "HIGH ENERGY PHASE" into "High energy phase" for body copy.
    var capitalizedHumanized: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst().lowercased()
    }
}

#Preview("Connected") {
    SupporterHomeView(previewContext: .preview)
}

#Preview("Phase hidden") {
    SupporterHomeView(previewContext: SupporterContext(
        trackerName: "Sarah", phase: nil, cycleDay: nil, canViewPhase: false
    ))
}
