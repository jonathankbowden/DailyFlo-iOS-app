//
//  ConnectView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import Supabase
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
    /// False when `name` is the "Your partner" fallback, so sentence copy
    /// can lowercase it.
    var hasName: Bool = true
}

extension Partner {
    /// Builds the card model for the other party of a live relationship.
    /// Phase and countdown are placeholders until Day 12 reads the tracker's
    /// real cycle through the permission-gated RLS path.
    init(relationship: PartnerRelationship, viewerId: UUID?) {
        let trimmed = relationship.partnerDisplayName(viewedBy: viewerId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Your partner" : trimmed
        // U+FE0E forces the text-style glyph so the heart takes the white
        // foreground like initials do, instead of rendering as a red emoji.
        let initials = trimmed.isEmpty
            ? "♥\u{FE0E}"
            : trimmed.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        self.init(
            name: name,
            initials: initials,
            currentPhase: .follicular,
            daysUntilNextPhase: 0,
            avatarColor: .floSage,
            hasName: !trimmed.isEmpty
        )
    }
}

// MARK: - Main Connect View
struct ConnectMainView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var partnerManager = PartnerManager.shared
    @State private var connectionStatus: ConnectionStatus = .notConnected
    @State private var showInviteSheet = false
    @State private var showShareSheet = false
    @State private var showPartnerOptions = false
    @State private var showSyncInfo = false
    @State private var inviteCode = ""
    @State private var isAcceptingCode = false
    @State private var acceptErrorMessage: String?
    /// Set when this session accepted a code, so closing Connect refreshes
    /// the profile role and the root can re-route a new supporter.
    @State private var didAcceptThisSession = false
    @FocusState private var codeFieldFocused: Bool

    private let cycleManager = CycleManager.shared

    private var currentUserId: UUID? {
        SupabaseClient.shared.auth.currentSession?.user.id
    }

    /// The other party of the active relationship, from the signed-in user's
    /// point of view. `nil` until `PartnerManager.refresh()` finds a row.
    private var connectedPartner: Partner? {
        partnerManager.activeRelationship.map { Partner(relationship: $0, viewerId: currentUserId) }
    }

    /// True when the signed-in user is the one sharing their cycle. A
    /// supporter who opens Connect sees the relationship from their side.
    private var isViewerTracker: Bool {
        guard let relationship = partnerManager.activeRelationship else { return true }
        return relationship.isTracker(currentUserId)
    }

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
                            if let partner = connectedPartner {
                                connectedView(for: partner)
                            } else {
                                notConnectedView
                            }
                        }

                        // Cycle sync info
                        cycleSyncInfoCard

                        Spacer()
                            .frame(height: 120)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                }
            }
            .sheet(isPresented: $showInviteSheet, onDismiss: syncStatus) {
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
            .sheet(isPresented: $showPartnerOptions, onDismiss: syncStatus) {
                if let relationship = partnerManager.activeRelationship {
                    PartnerOptionsSheet(
                        relationship: relationship,
                        isTracker: isViewerTracker,
                        partnerName: connectedPartner.map { $0.hasName ? $0.name : "your partner" } ?? "your partner"
                    )
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showSyncInfo) {
                CycleSyncInfoSheet()
            }
            .task {
                // Both states come from the DB: `partner_relationships` for
                // connected, `invitations` for pending.
                await partnerManager.refresh()
                syncStatus()
            }
        }
    }

    /// The DB decides the state: an active relationship means connected, an
    /// open invitation means pending, otherwise not connected.
    private func syncStatus() {
        let next: ConnectionStatus
        if partnerManager.activeRelationship != nil {
            next = .connected
        } else if partnerManager.pendingInvitation != nil {
            next = .pendingInvite
        } else {
            next = .notConnected
        }
        guard next != connectionStatus else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            connectionStatus = next
        }
    }

    // MARK: - Accept a code

    /// Six code characters after the prefix; the server re-validates.
    private var canSubmitCode: Bool {
        PartnerManager.normalizeCode(inviteCode).count == "FLO-".count + 6
    }

    /// Calls the `accept_invitation` RPC and, on success, lands on the
    /// connected state with the tracker's real name.
    private func acceptCode() {
        guard canSubmitCode, !isAcceptingCode else { return }
        isAcceptingCode = true
        acceptErrorMessage = nil
        codeFieldFocused = false

        Task {
            defer { isAcceptingCode = false }
            do {
                _ = try await partnerManager.acceptInvitation(code: inviteCode)
                didAcceptThisSession = true
                inviteCode = ""
                FloHaptics.success()
                syncStatus()
            } catch {
                FloHaptics.error()
                acceptErrorMessage = (error as? PartnerError)?.errorDescription
                    ?? "Couldn't connect right now. Check your connection and try again."
            }
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
                    if didAcceptThisSession, let userId = currentUserId {
                        // Accepting settled profiles.role server-side. Pull it
                        // now, on the way out, so the root re-routes a new
                        // supporter to their home without yanking this screen
                        // away mid-celebration.
                        Task { await CycleManager.shared.refresh(userId: userId) }
                    }
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

            // Enter code option — the supporter side of the invite.
            VStack(spacing: FloSpacing.sm) {
                Text("Or enter an invite code")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)

                HStack(spacing: FloSpacing.sm) {
                    TextField("FLO-A3K2M7", text: $inviteCode)
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .foregroundColor(.floCharcoal)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .focused($codeFieldFocused)
                        .onSubmit(acceptCode)
                        .onChange(of: inviteCode) { _, _ in acceptErrorMessage = nil }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(FloRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: FloRadius.md)
                                .stroke(acceptErrorMessage == nil ? Color.floGray.opacity(0.3) : Color.floError, lineWidth: 1)
                        )
                        .disabled(isAcceptingCode)

                    Button(action: acceptCode) {
                        if isAcceptingCode {
                            ProgressView()
                                .tint(.floSage)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(canSubmitCode ? .floSage : .floSage.opacity(0.4))
                        }
                    }
                    .floHitTarget()
                    .disabled(!canSubmitCode || isAcceptingCode)
                    .accessibilityLabel("Connect with code")
                }

                if let acceptErrorMessage {
                    Text(acceptErrorMessage)
                        .font(.floBodySmall)
                        .foregroundColor(.floError)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .padding(.top, FloSpacing.md)
            .animation(.easeInOut(duration: 0.2), value: acceptErrorMessage)
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
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: - Connected View
    /// Renders the live relationship. A tracker sees what they're sharing;
    /// a supporter sees whose cycle they're following.
    private func connectedView(for partner: Partner) -> some View {
        VStack(spacing: FloSpacing.lg) {
            // Partner card
            HStack(spacing: FloSpacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(partner.avatarColor)
                        .frame(width: 60, height: 60)

                    Text(partner.initials)
                        .font(.floDisplaySmall)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    HStack {
                        Text(partner.name)
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

                // Sharing switch + disconnect
                Button(action: {
                    FloHaptics.light()
                    showPartnerOptions = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundColor(.floGray)
                }
                .floHitTarget()
                .accessibilityLabel("Partner options")
            }
            .padding(FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)

            if isViewerTracker {
                // Your current phase (shared with partner) — the tracker's own
                // cycle math, the same numbers the Calendar tab shows.
                VStack(alignment: .leading, spacing: FloSpacing.md) {
                    Text("SHARING WITH \(partner.name.uppercased())")
                        .font(.floLabel)
                        .fontWeight(.medium)
                        .foregroundColor(.floGray)
                        .tracking(1)

                    currentPhaseCard
                }

                // What partner sees
                VStack(alignment: .leading, spacing: FloSpacing.sm) {
                    Text("WHAT \(partner.name.uppercased()) SEES")
                        .font(.floLabel)
                        .fontWeight(.medium)
                        .foregroundColor(.floGray)
                        .tracking(1)

                    VStack(spacing: FloSpacing.xs) {
                        if partnerManager.activeRelationship?.sharesCurrentPhase ?? false {
                            infoRow(icon: "calendar", text: "Your current phase and duration")
                            infoRow(icon: "heart", text: "How to best support you")
                        } else {
                            infoRow(icon: "eye.slash", text: "Your phase is hidden right now")
                        }
                        infoRow(icon: "bell", text: "Phase change notifications")
                    }
                }
            } else {
                // Supporter's view of the same relationship.
                VStack(alignment: .leading, spacing: FloSpacing.sm) {
                    Text("WHAT YOU SEE")
                        .font(.floLabel)
                        .fontWeight(.medium)
                        .foregroundColor(.floGray)
                        .tracking(1)

                    VStack(spacing: FloSpacing.xs) {
                        infoRow(icon: "calendar", text: "\(partner.name)'s current phase and duration")
                        infoRow(icon: "heart", text: "How to best support \(partner.name)")
                        infoRow(icon: "bell", text: "Phase change notifications")
                    }
                }
            }
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    /// The tracker's current phase, from `CycleManager`.
    private var currentPhaseCard: some View {
        let phase = cycleManager.currentPhase
        let day = cycleManager.currentDayOfCycle
        let energy = phase.subtitle.lowercased().replacingOccurrences(of: "your ", with: "")

        return HStack {
            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                Text("Your Current Phase")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)

                Text(phase.name)
                    .font(.floDisplaySmall)
                    .foregroundColor(.floCharcoal)

                Text("\(energy.prefix(1).uppercased() + energy.dropFirst()) • Day \(day)")
                    .font(.floBodySmall)
                    .foregroundColor(.floSage)
            }

            Spacer()

            // Phase indicator
            ZStack {
                Circle()
                    .fill(phase.color.opacity(0.2))
                    .frame(width: 64, height: 64)

                Text(phase.number)
                    .font(.floDisplaySmall)
                    .foregroundColor(phase.color)
            }
        }
        .padding(FloSpacing.md)
        .background(Color.floMint.opacity(0.3))
        .cornerRadius(FloRadius.lg)
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

// MARK: - Partner Options Sheet
/// Behind the "…" on the connected card. A tracker can switch phase sharing
/// off and on; either side can disconnect. Every change goes to the server
/// first and the card re-reads the row, so nothing here is local-only.
struct PartnerOptionsSheet: View {
    let relationship: PartnerRelationship
    let isTracker: Bool
    let partnerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var sharesPhase: Bool
    /// What the server currently holds. A revert after a failed save sets
    /// the switch back to this, and `onChange` ignores that revert.
    @State private var savedSharesPhase: Bool
    @State private var isSaving = false
    @State private var showDisconnectConfirm = false
    @State private var isDisconnecting = false
    @State private var errorMessage: String?

    init(relationship: PartnerRelationship, isTracker: Bool, partnerName: String) {
        self.relationship = relationship
        self.isTracker = isTracker
        self.partnerName = partnerName
        _sharesPhase = State(initialValue: relationship.sharesCurrentPhase)
        _savedSharesPhase = State(initialValue: relationship.sharesCurrentPhase)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: FloSpacing.lg) {
                if isTracker {
                    sharingCard
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.floBodySmall)
                        .foregroundColor(.floError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, FloSpacing.lg)
                }

                Spacer()

                disconnectButton
            }
            .padding(.top, FloSpacing.lg)
            .padding(.bottom, FloSpacing.xl)
            .background(Color.floCream)
            .navigationTitle(isTracker ? "Sharing" : "Supporting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.floSage)
                }
            }
            .alert(disconnectTitle, isPresented: $showDisconnectConfirm) {
                Button("Disconnect", role: .destructive) { performDisconnect() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(disconnectMessage)
            }
        }
    }

    // MARK: Sharing

    private var sharingCard: some View {
        VStack(alignment: .leading, spacing: FloSpacing.sm) {
            Toggle(isOn: $sharesPhase) {
                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    Text("Share my current phase")
                        .font(.floBodyLarge)
                        .fontWeight(.medium)
                        .foregroundColor(.floCharcoal)

                    Text(sharesPhase
                         ? "\(partnerName) can see which phase you're in and how to support you."
                         : "\(partnerName) sees that you're connected, but not your phase.")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(.floSage)
            .disabled(isSaving || isDisconnecting)
            .onChange(of: sharesPhase) { _, new in
                guard new != savedSharesPhase, !isSaving else { return }
                save(new)
            }
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .padding(.horizontal, FloSpacing.lg)
    }

    private func save(_ enabled: Bool) {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await PartnerManager.shared.setSharesCurrentPhase(enabled, for: relationship)
                savedSharesPhase = enabled
                FloHaptics.selection()
            } catch {
                FloHaptics.error()
                sharesPhase = savedSharesPhase
                errorMessage = (error as? PartnerError)?.errorDescription
                    ?? "Couldn't save that right now. Check your connection and try again."
            }
        }
    }

    // MARK: Disconnect

    private var disconnectTitle: String {
        isTracker ? "Disconnect from \(partnerName)?" : "Stop supporting \(partnerName)?"
    }

    private var disconnectMessage: String {
        isTracker
            ? "\(partnerName) will no longer see your cycle. You can send a new invite any time."
            : "You'll no longer see \(partnerName)'s cycle. You can reconnect with a new invite code."
    }

    private var disconnectButton: some View {
        Button(action: {
            FloHaptics.medium()
            showDisconnectConfirm = true
        }) {
            HStack(spacing: FloSpacing.sm) {
                if isDisconnecting {
                    ProgressView().tint(.floError)
                } else {
                    Image(systemName: "person.crop.circle.badge.xmark")
                }
                Text(isTracker ? "Disconnect" : "Stop Supporting")
                    .font(.floButton)
            }
            .foregroundColor(.floError)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.full)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.full)
                    .stroke(Color.floError.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isDisconnecting || isSaving)
        .padding(.horizontal, FloSpacing.lg)
    }

    private func performDisconnect() {
        isDisconnecting = true
        errorMessage = nil
        Task {
            defer { isDisconnecting = false }
            do {
                try await PartnerManager.shared.disconnect(relationship)
                FloHaptics.success()
                dismiss()
            } catch {
                FloHaptics.error()
                errorMessage = (error as? PartnerError)?.errorDescription
                    ?? "Couldn't disconnect right now. Check your connection and try again."
            }
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
