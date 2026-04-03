//
//  ConnectView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

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
    @State private var connectionStatus: ConnectionStatus = .notConnected
    @State private var showInviteSheet = false
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
            .sheet(isPresented: $showInviteSheet) {
                InvitePartnerSheet(onInviteSent: {
                    showInviteSheet = false
                    connectionStatus = .pendingInvite
                })
            }
            .sheet(isPresented: $showSyncInfo) {
                CycleSyncInfoSheet()
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
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.floGray.opacity(0.5))
                }
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

            // Resend option
            Button(action: {
                showInviteSheet = true
            }) {
                Text("Resend Invite")
                    .font(.floButton)
                    .foregroundColor(.floSage)
            }

            // Demo: Skip to connected
            Button(action: {
                connectionStatus = .connected
            }) {
                Text("(Demo: Show Connected)")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
            }
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

// MARK: - Invite Partner Sheet
struct InvitePartnerSheet: View {
    let onInviteSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var partnerEmail = ""
    @State private var selectedMethod = 0

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

                // Method selector
                Picker("Method", selection: $selectedMethod) {
                    Text("Email").tag(0)
                    Text("Share Link").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, FloSpacing.lg)

                if selectedMethod == 0 {
                    // Email input
                    VStack(alignment: .leading, spacing: FloSpacing.xs) {
                        Text("PARTNER'S EMAIL")
                            .font(.floLabel)
                            .fontWeight(.medium)
                            .foregroundColor(.floGray)
                            .tracking(1)

                        TextField("Enter email", text: $partnerEmail)
                            .font(.floBodyMedium)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(FloRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: FloRadius.md)
                                    .stroke(Color.floGray.opacity(0.3), lineWidth: 1)
                            )
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                } else {
                    // Share link option
                    VStack(spacing: FloSpacing.md) {
                        Text("Your invite code:")
                            .font(.floBodyMedium)
                            .foregroundColor(.floGray)

                        Text("FLO-\(String(format: "%04d", Int.random(in: 1000...9999)))")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.floSage)
                            .padding()
                            .background(Color.floSage.opacity(0.1))
                            .cornerRadius(FloRadius.md)

                        Button(action: {
                            // Copy to clipboard
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Code")
                            }
                            .font(.floBodyMedium)
                            .foregroundColor(.floSage)
                        }
                    }
                }

                Spacer()

                // Send button
                Button(action: onInviteSent) {
                    Text(selectedMethod == 0 ? "Send Invite" : "Share Code")
                        .font(.floButton)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.md)
                        .background(Color.floSage)
                        .cornerRadius(FloRadius.full)
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.xl)
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
        }
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
