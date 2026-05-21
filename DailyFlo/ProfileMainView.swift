//
//  ProfileMainView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import Supabase
import SwiftUI

// MARK: - Profile Main View
struct ProfileMainView: View {
    @State private var selectedTab: ProfileTab = .cycle
    @State private var hasAppeared = false
    @State private var showConnect = false
    @State private var showAccountSettings = false
    @State private var showSignOutConfirm = false
    @State private var showComingSoon = false
    @State private var isSigningOut = false
    @State private var signOutErrorMessage: String?

    @State private var profile: UserProfileRow?
    @State private var profileEmail: String?
    @State private var isLoadingProfile = false
    @State private var profileLoadFailed = false

    private let cycleManager = CycleManager.shared

    private var displayName: String {
        if let name = profile?.displayName, !name.isEmpty { return name }
        let fallback = cycleManager.userName
        if !fallback.isEmpty && fallback != "Friend" { return fallback }
        if let email = profileEmail, let local = email.split(separator: "@").first {
            return String(local)
        }
        return "Friend"
    }

    private var userName: String { displayName }
    private var currentPhase: String { cycleManager.currentPhaseLabel }
    private var nextPeriodDate: String { cycleManager.nextPeriodFormatted }

    enum ProfileTab: String, CaseIterable {
        case cycle = "CYCLE"
        case sync = "SYNC"
        case settings = "SETTINGS"
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

                // Tab selector
                tabSelector
                    .fadeIn(delay: hasAppeared ? 0 : 0.2)

                // Bottom divider line
                Rectangle()
                    .fill(Color(hex: "707070"))
                    .frame(height: 1)

                // Tab content
                ScrollView {
                    VStack(spacing: 0) {
                        switch selectedTab {
                        case .cycle:
                            cycleTabContent
                        case .sync:
                            syncTabContent
                        case .settings:
                            settingsTabContent
                        }
                    }
                    .padding(.bottom, 140) // Space for tab bar
                }
                .background(Color(hex: "F8F8F8"))
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
        .task {
            await loadProfile()
        }
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This feature will be available in a future update.")
        }
        .alert("Sign out of DailyFLO?", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) { performSignOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to access your cycle and journal.")
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

    // MARK: - Profile loading
    private func loadProfile() async {
        let auth = SupabaseClient.shared.auth
        guard let user = auth.currentSession?.user else {
            profileLoadFailed = true
            return
        }

        await MainActor.run {
            profileEmail = user.email
            isLoadingProfile = true
            profileLoadFailed = false
        }

        do {
            let row: UserProfileRow = try await SupabaseClient.shared
                .from("profiles")
                .select("display_name, life_stage, timezone, temperature_unit")
                .eq("user_id", value: user.id)
                .single()
                .execute()
                .value

            await MainActor.run {
                profile = row
                isLoadingProfile = false
            }
        } catch {
            // Profile row may not exist yet (e.g., trigger hasn't run) — fall back
            // gracefully to email-derived display and don't block the UI.
            await MainActor.run {
                profileLoadFailed = true
                isLoadingProfile = false
            }
        }
    }

    // MARK: - Sign Out
    private func performSignOut() {
        guard !isSigningOut else { return }
        FloHaptics.medium()
        isSigningOut = true

        Task { @MainActor in
            defer { isSigningOut = false }
            do {
                try await SupabaseClient.shared.auth.signOut()
                // App-level auth listener will transition to .signIn
            } catch {
                FloHaptics.error()
                signOutErrorMessage = "Couldn't sign out. \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { signOutErrorMessage = nil }
                }
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            // Profile/partner icon
            Image("partner")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.floCharcoal)
                .accessibilityLabel("Profile")

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

            VStack(alignment: .leading, spacing: 4) {
                // Current phase
                Text(currentPhase)
                    .font(.floLabel)
                    .fontWeight(.bold)
                    .foregroundColor(.floCharcoal)
                    .tracking(2)

                // Next period
                Text("Next Period: \(nextPeriodDate)")
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.sm)
        .padding(.bottom, FloSpacing.sm)
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        let allTabs = ProfileTab.allCases
        return HStack(spacing: 0) {
            ForEach(Array(allTabs.enumerated()), id: \.element) { index, tab in
                Button(action: {
                    FloHaptics.selection()
                    withAnimation(FloAnimation.springSnappy) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.floLabel)
                        .fontWeight(.medium)
                        .foregroundColor(.floCharcoal)
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.sm)
                        .background(selectedTab == tab ? Color.floMint.opacity(0.5) : Color.clear)
                        .cornerRadius(FloRadius.sm)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])

                // Divider between tabs - hide when adjacent tab is selected
                if index < allTabs.count - 1 {
                    let nextTab = allTabs[index + 1]
                    if selectedTab != tab && selectedTab != nextTab {
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

    // MARK: - Cycle Tab Content
    private var cycleTabContent: some View {
        let cl = cycleManager.cycleLength
        let pl = cycleManager.periodLength
        let ovDays = 3
        let follDays = max(1, cl - 14 - 2 - pl)
        let lutDays = max(1, cl - (pl + follDays + ovDays))

        return VStack(spacing: FloSpacing.md) {
            let stats: [(String, String, String)] = [
                ("01", "CYCLE", "tracked so far."),
                (String(format: "%02d", cl), "DAYS", "in your cycle."),
                (String(format: "%02d", follDays), "DAYS", "avg Follicular phase."),
                (String(format: "%02d", ovDays), "DAYS", "avg Ovulation phase."),
                (String(format: "%02d", lutDays), "DAYS", "avg Luteal phase."),
                (String(format: "%02d", pl), "DAYS", "avg Menstrual phase.")
            ]
            ForEach(Array(stats.enumerated()), id: \.offset) { index, data in
                cycleStatCard(value: data.0, unit: data.1, description: data.2)
                    .fadeIn(delay: hasAppeared ? 0 : 0.25 + Double(index) * 0.05)
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.lg)
    }

    private func cycleStatCard(value: String, unit: String, description: String) -> some View {
        HStack(spacing: FloSpacing.md) {
            // Value and unit
            HStack(alignment: .firstTextBaseline, spacing: FloSpacing.xs) {
                Text(value)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.floCharcoal)

                Text(unit)
                    .font(.floCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(.floCharcoal)
                    .tracking(1)
            }
            .frame(width: 120, alignment: .leading)

            // Description in serif font
            Text(description)
                .font(.floSerif(size: 18))
                .foregroundColor(.floCharcoal)

            Spacer()
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
    }

    // MARK: - Sync Tab Content
    private var syncTabContent: some View {
        VStack(spacing: FloSpacing.lg) {
            // Connect CTA
            VStack(spacing: FloSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.floSage.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "person.2.circle")
                        .font(.system(size: 44))
                        .foregroundColor(.floSage)
                }

                Text("Share Your Cycle")
                    .font(.floDisplaySmall)
                    .foregroundColor(.floCharcoal)

                Text("Help your partner understand your cycle and support you through each phase.")
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, FloSpacing.lg)

                Button(action: {
                    FloHaptics.medium()
                    showConnect = true
                }) {
                    HStack(spacing: FloSpacing.sm) {
                        Image(systemName: "paperplane.fill")
                        Text("Connect a Partner")
                    }
                    .font(.floButton)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FloSpacing.md)
                    .background(Color.floSage)
                    .cornerRadius(FloRadius.full)
                }
                .padding(.horizontal, FloSpacing.lg)
            }
            .padding(.vertical, FloSpacing.xl)
            .fadeIn(delay: hasAppeared ? 0 : 0.25)

            // Phase notification card
            PhaseNotificationCard(
                phaseName: cycleManager.currentPhase.name.replacingOccurrences(of: " Phase", with: ""),
                description: "Notify your partner over email when your \(cycleManager.currentPhase.name.replacingOccurrences(of: " Phase", with: "")) phase begins. They will be given helpful information about this phase."
            )
            .padding(.horizontal, FloSpacing.lg)
            .fadeIn(delay: hasAppeared ? 0 : 0.3)
        }
        .padding(.top, FloSpacing.lg)
        .fullScreenCover(isPresented: $showConnect) {
            ConnectMainView()
        }
    }

    // MARK: - Settings Tab Content
    private var settingsTabContent: some View {
        VStack(spacing: FloSpacing.md) {
            // Account info card
            VStack(alignment: .leading, spacing: FloSpacing.sm) {
                HStack(spacing: FloSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.floSage.opacity(0.2))
                            .frame(width: 48, height: 48)

                        if isLoadingProfile && profile == nil {
                            FloLoadingIndicator(size: 20, color: .floSage, lineWidth: 2)
                        } else {
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.floDisplaySmall)
                                .foregroundColor(.floSage)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.floBodyLarge)
                            .fontWeight(.medium)
                            .foregroundColor(.floCharcoal)

                        if let email = profileEmail, !email.isEmpty {
                            Text(email)
                                .font(.floBodySmall)
                                .foregroundColor(.floGray)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Day \(cycleManager.currentDayOfCycle) of \(cycleManager.cycleLength)")
                                .font(.floBodySmall)
                                .foregroundColor(.floGray)
                        }
                    }

                    Spacer()
                }
            }
            .padding(FloSpacing.lg)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)
            .shadow(color: FloShadow.small.color, radius: FloShadow.small.radius, x: 0, y: FloShadow.small.y)
            .fadeIn(delay: hasAppeared ? 0 : 0.25)

            // Settings rows
            let settingsItems: [(String, String)] = [
                ("Cycle Settings", "arrow.triangle.2.circlepath.circle"),
                ("Notifications", "bell.circle"),
                ("Privacy", "lock.circle"),
                ("Help & Support", "questionmark.circle"),
                ("About DailyFlo", "info.circle")
            ]
            ForEach(Array(settingsItems.enumerated()), id: \.offset) { index, data in
                settingsRow(title: data.0, icon: data.1)
                    .fadeIn(delay: hasAppeared ? 0 : 0.3 + Double(index) * 0.05)
            }

            // Sign out
            Button(action: {
                FloHaptics.light()
                showSignOutConfirm = true
            }) {
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
            .fadeIn(delay: hasAppeared ? 0 : 0.5)
            .accessibilityLabel("Sign out")
            .accessibilityHint("Sign out of your DailyFLO account")

            // Reset onboarding (for demo/testing)
            Button(action: {
                FloHaptics.medium()
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.removeObject(forKey: "userName")
                UserDefaults.standard.removeObject(forKey: "journal_entries")
                // Force restart on next launch
                exit(0)
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.floGray)

                    Text("Reset App & Onboarding")
                        .font(.floBodyMedium)
                        .foregroundColor(.floGray)

                    Spacer()

                    Text("Demo")
                        .font(.floCaption)
                        .foregroundColor(.floGray.opacity(0.6))
                        .padding(.horizontal, FloSpacing.sm)
                        .padding(.vertical, FloSpacing.xxs)
                        .background(Color.floGray.opacity(0.1))
                        .cornerRadius(FloRadius.full)
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.vertical, FloSpacing.md)
                .background(Color.white)
                .cornerRadius(FloRadius.lg)
            }
            .buttonStyle(.floPressed)
            .fadeIn(delay: hasAppeared ? 0 : 0.55)

            // Version info
            Text("DailyFlo v1.0")
                .font(.floCaption)
                .foregroundColor(.floGray.opacity(0.5))
                .padding(.top, FloSpacing.md)
                .fadeIn(delay: hasAppeared ? 0 : 0.6)
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.top, FloSpacing.lg)
    }

    private func settingsRow(title: String, icon: String) -> some View {
        Button(action: {
            FloHaptics.light()
            showComingSoon = true
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.floCharcoal)

                Text(title)
                    .font(.floBodyMedium)
                    .foregroundColor(.floCharcoal)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.floGray)
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.vertical, FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel(title)
    }
}

// MARK: - Profile row (maps the columns this view reads from `profiles`)
struct UserProfileRow: Decodable, Equatable {
    let displayName: String
    let lifeStage: String?
    let timezone: String?
    let temperatureUnit: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case lifeStage = "life_stage"
        case timezone
        case temperatureUnit = "temperature_unit"
    }
}

// MARK: - Partner Card
struct PartnerCard: View {
    let name: String
    let email: String
    let isConnected: Bool

    // Placeholder gradient for partner photo
    private var photoGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "5B7B7A"),
                Color(hex: "3A8B8B"),
                Color(hex: "2E6B5E")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Photo section
            ZStack(alignment: .bottomTrailing) {
                photoGradient
                    .frame(width: 280, height: 220)

                // Edit button
                Button(action: {
                    FloHaptics.light()
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                        .foregroundColor(.floGray)
                        .padding(FloSpacing.sm)
                        .background(Color.white.opacity(0.95))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.floPressed)
                .padding(FloSpacing.md)
                .accessibilityLabel("Edit partner photo")
            }

            // Info section
            VStack(spacing: FloSpacing.sm) {
                // Name in serif font
                Text(name)
                    .font(.floSerif(size: 24))
                    .foregroundColor(.floCharcoal)

                // Divider
                FloDivider()
                    .padding(.horizontal, FloSpacing.xl)

                // Partner label and email
                VStack(spacing: 2) {
                    Text("PARTNER")
                        .font(.floCaption)
                        .fontWeight(.semibold)
                        .foregroundColor(.floCharcoal)
                        .tracking(1)

                    Text(email)
                        .font(.floBodySmall)
                        .foregroundColor(.floCharcoal)
                }
            }
            .padding(.vertical, FloSpacing.lg)
            .frame(width: 280)
            .background(Color.white)
        }
        .cornerRadius(FloRadius.lg)
        .shadow(color: FloShadow.medium.color, radius: FloShadow.medium.radius, x: 0, y: FloShadow.medium.y)
    }
}

// MARK: - Add Partner Card
struct AddPartnerCard: View {
    var body: some View {
        Button(action: {
            FloHaptics.light()
        }) {
            VStack {
                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.floGray.opacity(0.5))

                Text("Add Partner")
                    .font(.floBodyMedium)
                    .foregroundColor(.floGray)

                Spacer()
            }
            .frame(width: 150, height: 320)
            .background(Color.white)
            .cornerRadius(FloRadius.lg)
            .shadow(color: FloShadow.small.color, radius: FloShadow.small.radius, x: 0, y: FloShadow.small.y)
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel("Add a partner")
    }
}

// MARK: - Phase Notification Card
struct PhaseNotificationCard: View {
    let phaseName: String
    let description: String
    @State private var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            // Header with checkbox
            HStack(spacing: FloSpacing.sm) {
                Button(action: {
                    FloHaptics.selection()
                    withAnimation(FloAnimation.springSnappy) {
                        isEnabled.toggle()
                    }
                }) {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isEnabled ? .floTeal : .floGray)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(isEnabled ? "Notification enabled" : "Notification disabled")

                // Phase name in serif font
                Text("\(phaseName) phase.")
                    .font(.floSerif(size: 20))
                    .foregroundColor(.floCharcoal)
            }

            // Divider
            FloDivider()

            // Description
            Text(description)
                .font(.floBodySmall)
                .foregroundColor(.floCharcoal)
                .lineSpacing(4)
        }
        .padding(FloSpacing.lg)
        .background(Color.white)
        .cornerRadius(FloRadius.lg)
        .shadow(color: FloShadow.small.color, radius: FloShadow.small.radius, x: 0, y: FloShadow.small.y)
    }
}

#Preview {
    ProfileMainView()
}
