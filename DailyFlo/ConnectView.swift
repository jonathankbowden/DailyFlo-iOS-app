//
//  ConnectView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI
import UIKit

// MARK: - Connection Status
enum ConnectionStatus {
    case notConnected
    case pendingInvite
    case connected
}

// MARK: - Partner Model
struct Partner: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let currentPhase: CyclePhase
    let daysUntilNextPhase: Int
    let avatarColor: Color
}

// MARK: - Main Connect View
struct ConnectMainView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var partnerManager = PartnerManager.shared
    @State private var connectionStatus: ConnectionStatus = .notConnected
    @State private var showInviteSheet = false
    @State private var showShareSheet = false
    @State private var showSyncInfo = false
    @State private var inviteCode = ""

    // Sample connected partner (would come from database)
    private let samplePartner = Partner(
        name: "Sarah",
        initials: "SB",
        currentPhase: .follicular,
        daysUntilNextPhase: 5,
        avatarColor: Color(hex: "E8B86D")
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Color.floCream.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: FloSpacing.xl) {
                        // Header
                        headerView

                        // Connection content based on status
                        switch connectionStatus {
                        case .notConnected:
                            notConnectedView
                        case .pendingInvite:
                            pendingInviteView
                        case .connected:
                            connectedView
                        }

                        // Cycle sync info
                        cycleSyncInfoCard

                        Spacer()
                            .frame(height: 120)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                }
            }
            .sheet(isPresented: $showInviteSheet, onDismiss: syncStatusWithInvitation) {
                InvitePartnerSheet()
            }
            .sheet(isPresented: $showShareSheet) {
                if let invitation = partnerManager.pendingInvitation {
                    InviteShareSheet(invitation: invitation) { _ in
                        showShareSheet = false
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showSyncInfo) {
                CycleSyncInfoSheet()
            }
            .task {
                // Pending state comes from the `invitations` table. Connected
                // state still reads the sample partner until Day 11 wires
                // partner_relationships.
                await partnerManager.refresh()
                syncStatusWithInvitation()
            }
        }
    }

    /// An open invitation row is what "pending" means, whether it was just
    /// created in the invite sheet or found on launch. Never demotes a
    /// connected state.
    private func syncStatusWithInvitation() {
        if connectionStatus == .notConnected, partnerManager.pendingInvitation != nil {
            connectionStatus = .pendingInvite
        }
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: FloSpacing.xs) {
            HStack {
                Text("Connect")
                    .font(.floDisplayLarge)
                    .foregroundColor(.floCharcoal)

                Spacer()

                Button(action: {
                    FloHaptics.light()
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.floGray.opacity(0.5))
                }
                .floHitTarget()
                .accessibilityLabel("Close")
            }

            Text("Share your cycle with loved ones")
                .font(.floBodyMedium)
                .foregroundColor(.floGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FloSpacing.lg)
    }

    // MARK: - Not Connected View
    private var notConnectedView: some View {
        VStack(spacing: FloSpacing.lg) {
            // Illustration
            ZStack {
                Circle()
                    .fill(Color.floSage.opacity(0.1))
                    .frame(width: 160, height: 160)

                Image(systemName: "person.2.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.floSage)
            }
            .padding(.vertical, FloSpacing.lg)

            VStack(spacing: FloSpacing.sm) {
                Text("Invite Your Partner")
                    .font(.floDisplaySmall)
                    .foregroundColor(.floCharcoal)

                Text("Help your partner understand your cycle and support you better through each phase.")
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, FloSpacing.md)
            }

            // Invite button
            Button(action: {
                FloHaptics.medium()
                showInviteSheet = true
            }) {
                HStack(spacing: FloSpacing.sm) {
                    Image(systemName: "paperplane.fill")
                    Text("Send Invite")
                }
                .font(.floButton)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FloSpacing.md)
                .background(Color.floSage)
                .cornerRadius(FloRadius.full)
            }

            // Enter code option
            VStack(spacing: FloSpacing.sm) {
                Text("Or enter an invite code")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)

                HStack(spacing: FloSpacing.sm) {
                    TextField("Enter code", text: $inviteCode)
                        .font(.floBodyMedium)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(FloRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: FloRadius.md)
                                .stroke(Color.floGray.opacity(0.3), lineWidth: 1)
                        )

                    Button(action: {
                        FloHaptics.success()
                        // Validate and connect
                        if !inviteCode.isEmpty {
                            connectionStatus = .connected
                        }
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.floSage)
                    }
                    .floHitTarget()
                }
            }
            .padding(.top, FloSpacing.md)
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: - Pending Invite View
    private var pendingInviteView: some View {
        VStack(spacing: FloSpacing.lg) {
            // Animated waiting indicator
            ZStack {
                Circle()
                    .stroke(Color.floSage.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.floSage, lineWidth: 4)
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "clock")
                    .font(.system(size: 32))
                    .foregroundColor(.floSage)
            }

            VStack(spacing: FloSpacing.sm) {
                Text("Invite Sent!")
                    .font(.floDisplaySmall)
                    .foregroundColor(.floCharcoal)

                Text("Waiting for your partner to accept the invitation.")
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
                    .multilineTextAlignment(.center)
            }

            if let invitation = partnerManager.pendingInvitation {
                InviteCodeBadge(code: invitation.code)
            }

            // Share the same code again — never mints a new one.
            Button(action: {
                FloHaptics.light()
                showShareSheet = true
            }) {
                HStack(spacing: FloSpacing.xs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Invite Again")
                }
                .font(.floButton)
                .foregroundColor(.floSage)
            }
            .floHitTarget()
            .disabled(partnerManager.pendingInvitation == nil)

            #if DEBUG
            // Demo: Skip to connected — DEBUG only, never ships in Release.
            Button(action: {
                connectionStatus = .connected
            }) {
                Text("(Demo: Show Connected)")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
            }
            #endif
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: - Connected View
    private var connectedView: some View {
        VStack(spacing: FloSpacing.lg) {
            // Partner card
            HStack(spacing: FloSpacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(samplePartner.avatarColor)
                        .frame(width: 60, height: 60)

                    Text(samplePartner.initials)
                        .font(.floDisplaySmall)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    HStack {
                        Text(samplePartner.name)
                            .font(.floBodyLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(.floCharcoal)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.floSage)
                    }

                    Text("Connected")
                        .font(.floBodySmall)
                        .foregroundColor(.floSage)
                }

                Spacer()

                // More options
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundColor(.floGray)
                }
                .floHitTarget()
            }
            .padding(FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)

            // Your current phase (shared with partner)
            VStack(alignment: .leading, spacing: FloSpacing.md) {
                Text("SHARING WITH \(samplePartner.name.uppercased())")
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floGray)
                    .tracking(1)

                // Current phase card
                HStack {
                    VStack(alignment: .leading, spacing: FloSpacing.xs) {
                        Text("Your Current Phase")
                            .font(.floBodySmall)
                            .foregroundColor(.floGray)

                        Text("Follicular Phase")
                            .font(.floDisplaySmall)
                            .foregroundColor(.floCharcoal)

                        Text("High energy • Days 6-13")
                            .font(.floBodySmall)
                            .foregroundColor(.floSage)
                    }

                    Spacer()

                    // Phase indicator
                    ZStack {
                        Circle()
                            .fill(Color.phaseFollicular.opacity(0.2))
                            .frame(width: 64, height: 64)

                        Text("02")
                            .font(.floDisplaySmall)
                            .foregroundColor(.phaseFollicular)
                    }
                }
                .padding(FloSpacing.md)
                .background(Color.floMint.opacity(0.3))
                .cornerRadius(FloRadius.lg)
            }

            // What partner sees
            VStack(alignment: .leading, spacing: FloSpacing.sm) {
                Text("WHAT \(samplePartner.name.uppercased()) SEES")
                    .font(.floLabel)
                    .fontWeight(.medium)
                    .foregroundColor(.floGray)
                    .tracking(1)

                VStack(spacing: FloSpacing.xs) {
                    infoRow(icon: "calendar", text: "Your current phase and duration")
                    infoRow(icon: "heart", text: "How to best support you")
                    infoRow(icon: "bell", text: "Phase change notifications")
                }
            }
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: FloSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.floSage)
                .frame(width: 24)

            Text(text)
                .font(.floBodySmall)
                .foregroundColor(.floCharcoal)

            Spacer()
        }
        .padding(.vertical, FloSpacing.xs)
    }

    // MARK: - Cycle Sync Info Card
    private var cycleSyncInfoCard: some View {
        Button(action: {
            showSyncInfo = true
        }) {
            HStack(spacing: FloSpacing.md) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.floSage)

                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    Text("About Cycle Sync")
                        .font(.floBodyMedium)
                        .fontWeight(.medium)
                        .foregroundColor(.floCharcoal)

                    Text("Learn how sharing helps relationships")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.floGray)
            }
            .padding(FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Invite Code Badge
/// The shareable code with a one-tap copy. Used in the invite sheet and in the
/// pending state so the tracker can re-share without minting a new code.
struct InviteCodeBadge: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: FloSpacing.sm) {
            Text(code)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.floSage)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.floSage.opacity(0.1))
                .cornerRadius(FloRadius.md)
                .accessibilityLabel("Invite code \(code.map(String.init).joined(separator: " "))")

            Button(action: copy) {
                HStack(spacing: FloSpacing.xs) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy Code")
                }
                .font(.floBodyMedium)
                .foregroundColor(.floSage)
            }
            .floHitTarget()
        }
    }

    private func copy() {
        UIPasteboard.general.string = code
        FloHaptics.success()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

// MARK: - Invite Partner Sheet
/// Creates (or reuses) the tracker's open invitation on appear and shows the
/// code. "Share Code" opens the system share sheet with a ready-to-send
/// message; once the tracker actually sends it, this sheet closes and
/// ConnectMainView shows the pending state. Cancelling the share sheet keeps
/// the tracker here so they can copy the code or try another app instead.
struct InvitePartnerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var invitation: PartnerInvitation?
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: FloSpacing.xl) {
                // Illustration
                ZStack {
                    Circle()
                        .fill(Color.floSage.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.floSage)
                }
                .padding(.top, FloSpacing.xl)

                VStack(spacing: FloSpacing.sm) {
                    Text("Invite Your Partner")
                        .font(.floDisplaySmall)
                        .foregroundColor(.floCharcoal)

                    Text("They'll be able to see your cycle phases and get tips on how to support you.")
                        .font(.floBodyMedium)
                        .foregroundColor(.floGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, FloSpacing.lg)
                }

                codeSection
                    .padding(.horizontal, FloSpacing.lg)

                Spacer()

                // Share button — enabled once a real code exists
                Button(action: {
                    FloHaptics.medium()
                    showShareSheet = true
                }) {
                    HStack(spacing: FloSpacing.sm) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Code")
                    }
                    .font(.floButton)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(invitation == nil ? Color.floSage.opacity(0.4) : Color.floSage)
                    .cornerRadius(FloRadius.full)
                }
                .disabled(invitation == nil)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.xl)
            }
            .sheet(isPresented: $showShareSheet) {
                if let invitation {
                    InviteShareSheet(invitation: invitation) { sent in
                        if sent {
                            // Closing this sheet takes the share sheet with it;
                            // ConnectMainView then flips to the pending state.
                            FloHaptics.success()
                            dismiss()
                        } else {
                            showShareSheet = false
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .background(Color.floCream)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.floGray)
                }
            }
            .task { await createInvitation() }
        }
    }

    @ViewBuilder
    private var codeSection: some View {
        VStack(spacing: FloSpacing.md) {
            Text("Your invite code:")
                .font(.floBodyMedium)
                .foregroundColor(.floGray)

            if let invitation {
                InviteCodeBadge(code: invitation.code)

                Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.floBodySmall)
                    .foregroundColor(.floError)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task { await createInvitation() }
                }
                .font(.floButton)
                .foregroundColor(.floSage)
                .floHitTarget()
            } else {
                ProgressView()
                    .tint(.floSage)
                    .frame(height: 72)
            }
        }
    }

    private func createInvitation() async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            invitation = try await PartnerManager.shared.ensurePendingInvitation()
        } catch {
            errorMessage = (error as? PartnerError)?.errorDescription
                ?? "Couldn't create an invite code. Check your connection and try again."
        }
    }
}

// MARK: - Invite Share Sheet
/// The system share sheet (Messages, Mail, WhatsApp, AirDrop, Copy…) carrying
/// the invite message. SwiftUI's `ShareLink` gives no completion callback, and
/// we need one to know whether the invite actually went out, so this wraps
/// `UIActivityViewController` directly.
struct InviteShareSheet: UIViewControllerRepresentable {
    let invitation: PartnerInvitation
    /// Called once with `true` when the tracker completed a share action, or
    /// `false` when they dismissed the picker without sending. The caller
    /// owns dismissal so nested sheets never race each other.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let message = invitation.shareMessage(senderName: Self.senderName)
        let controller = UIActivityViewController(activityItems: [message], applicationActivities: nil)
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .print,
            .saveToCameraRoll,
            .markupAsPDF
        ]
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    /// The tracker's chosen name, or "" when we only have the placeholder.
    /// Mirrors ProfileMainView: a name is never derived from an email.
    private static var senderName: String {
        let cached = CycleManager.shared.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cached.isEmpty || cached == "Friend") ? "" : cached
    }
}

// MARK: - Cycle Sync Info Sheet
struct CycleSyncInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FloSpacing.xl) {
                    // Hero image
                    ZStack {
                        RoundedRectangle(cornerRadius: FloRadius.xl)
                            .fill(
                                LinearGradient(
                                    colors: [Color.floMint, Color.floSage.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 180)

                        VStack {
                            Image(systemName: "figure.2.and.child.holdinghands")
                                .font(.system(size: 48))
                                .foregroundColor(.floSage)

                            Text("Better Together")
                                .font(.floDisplaySmall)
                                .foregroundColor(.floCharcoal)
                        }
                    }
                    .padding(.horizontal, FloSpacing.lg)

                    VStack(alignment: .leading, spacing: FloSpacing.lg) {
                        Text("Why Share Your Cycle?")
                            .font(.floDisplaySmall)
                            .foregroundColor(.floCharcoal)

                        Text("Understanding your menstrual cycle helps partners provide better support throughout the month. When your loved ones know what phase you're in, they can:")
                            .font(.floBodyMedium)
                            .foregroundColor(.floGray)

                        benefitRow(
                            icon: "heart.fill",
                            title: "Be More Supportive",
                            description: "Know when you might need extra care or space"
                        )

                        benefitRow(
                            icon: "calendar",
                            title: "Plan Together",
                            description: "Schedule activities when your energy is highest"
                        )

                        benefitRow(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: "Communicate Better",
                            description: "Understand mood changes and needs"
                        )

                        benefitRow(
                            icon: "lock.shield.fill",
                            title: "Privacy First",
                            description: "You control what information is shared"
                        )
                    }
                    .padding(.horizontal, FloSpacing.lg)

                    Spacer()
                        .frame(height: FloSpacing.xxl)
                }
                .padding(.top, FloSpacing.lg)
            }
            .background(Color.floCream)
            .navigationTitle("Cycle Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.floSage)
                }
            }
        }
    }

    private func benefitRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: FloSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.floSage)
                .frame(width: 32, height: 32)
                .background(Color.floSage.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                Text(title)
                    .font(.floBodyLarge)
                    .fontWeight(.medium)
                    .foregroundColor(.floCharcoal)

                Text(description)
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
            }
        }
    }
}

#Preview("Connect - Not Connected") {
    ConnectMainView()
}
