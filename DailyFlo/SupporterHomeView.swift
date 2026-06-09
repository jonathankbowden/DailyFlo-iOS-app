//
//  SupporterHomeView.swift
//  DailyFlo
//
//  Step 1 of the partner-share build (June 2026): the supporter-side home
//  scaffold. Internal naming uses tracker/supporter; UI copy never says
//  "tracker" — the supporter sees themselves as "you" and the person
//  they're supporting as "her" (name-first where possible).
//
//  This step renders everything from `MockSupporterData`. Step 2 wires
//  real invitations; step 3 swaps the fixture for a `SupporterContext`
//  pulled from the live `partner_relationships` row.
//

import Supabase
import SwiftUI

// MARK: - Supporter context (the shape supporter screens render from)

/// What the supporter home needs to render. Steps 2–4 will produce this
/// from real relationship data; keeping the shape stable here means the
/// view layer doesn't change when the source flips.
struct SupporterContext {
    let trackerName: String
    let phase: CyclePhase
    let cycleDay: Int
    let supportTips: [String]
}

// MARK: - Mock fixture (step 1 only)

enum MockSupporterData {
    static let context = SupporterContext(
        trackerName: "Sarah",
        phase: .follicular,
        cycleDay: 9,
        supportTips: [
            "Energy is rising this week — a great time to plan something active together.",
            "She may feel more social and optimistic right now.",
            "Small encouragements go a long way in this phase."
        ]
    )
}

// MARK: - Supporter home

struct SupporterHomeView: View {
    var context: SupporterContext = MockSupporterData.context

    @State private var showSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var signOutErrorMessage: String?

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FloSpacing.xl) {
                    header
                    phaseCard
                    supportTipsSection
                    signOutButton
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.xl)
                .padding(.bottom, FloSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
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

    // MARK: - Header

    private var header: some View {
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

    private var phaseCard: some View {
        HStack(alignment: .top, spacing: FloSpacing.md) {
            // Phase color accent rail
            RoundedRectangle(cornerRadius: 3)
                .fill(context.phase.color)
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

                    Text("Day \(context.cycleDay)")
                        .font(.floSerif(size: 24))
                        .foregroundColor(.floCharcoal)
                }

                Text(context.phase.subtitle.capitalizedHumanized)
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
        .accessibilityLabel("\(phaseDisplayName) phase, day \(context.cycleDay)")
    }

    /// "Follicular Phase" → "Follicular" for the card headline.
    private var phaseDisplayName: String {
        context.phase.name.replacingOccurrences(of: " Phase", with: "")
    }

    // MARK: - Support tips

    private var supportTipsSection: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("How to support her this week")
                .font(.floDisplaySmall)
                .foregroundColor(.floCharcoal)

            VStack(spacing: FloSpacing.sm) {
                ForEach(Array(context.supportTips.enumerated()), id: \.offset) { _, tip in
                    supportTipRow(tip)
                }
            }
        }
    }

    private func supportTipRow(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: FloSpacing.md) {
            Circle()
                .fill(context.phase.color.opacity(0.85))
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

#Preview {
    SupporterHomeView()
}
