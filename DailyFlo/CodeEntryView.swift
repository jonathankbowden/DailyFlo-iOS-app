//
//  CodeEntryView.swift
//  DailyFlo
//
//  Step 2 of the passwordless email flow. The user just received a
//  6-digit OTP via Resend SMTP; this screen captures it, calls
//  auth.verifyOTP(email:token:type:.email), and on success establishes
//  the Supabase session. Includes a 60-second "Resend code" cooldown
//  and a "Use a different email" affordance that pops back to the
//  auth screen.
//

import Supabase
import SwiftUI

struct CodeEntryView: View {
    let email: String
    @Binding var isSignedIn: Bool
    let onUseDifferentEmail: () -> Void

    private static let codeLength: Int = 6
    private static let cooldownStart: Int = 60

    @State private var code: String = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var resendCooldown: Int = cooldownStart
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: FloSpacing.xl) {
                    brandingSection
                        .fadeIn(delay: hasAppeared ? 0 : 0.05)

                    codeCard
                        .fadeIn(delay: hasAppeared ? 0 : 0.1)

                    differentEmailLink
                        .fadeIn(delay: hasAppeared ? 0 : 0.2)
                }
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.lg)
                .padding(.bottom, FloSpacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)

            if showError {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .floToast(.error)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, FloSpacing.xxl)
                }
                .animation(FloAnimation.springGentle, value: showError)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                hasAppeared = true
                codeFieldFocused = true
            }
            startCooldown()
        }
    }

    // MARK: - Branding (matches SignInView)
    private var brandingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily")
                .font(.custom("LUNARY free", size: 72))
                .foregroundColor(.floCharcoal)

            Text("FLO")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.floCharcoal)
                .tracking(3)
        }
        .padding(.top, FloSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily Flo")
    }

    // MARK: - Code card
    private var codeCard: some View {
        VStack(spacing: 0) {
            Image("medbg_stillwater_a")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: FloSpacing.lg) {
                VStack(alignment: .leading, spacing: FloSpacing.xs) {
                    Text("Check your email")
                        .font(.custom("LUNARY free", size: 28))
                        .foregroundColor(.floCharcoal)
                        .accessibilityAddTraits(.isHeader)

                    Text("We sent a 6-digit code to")
                        .font(.floBodyMedium)
                        .foregroundColor(.floGray)

                    Text(email)
                        .font(.floBodyMedium.weight(.medium))
                        .foregroundColor(.floCharcoal)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                codeInputArea
                    .padding(.top, FloSpacing.sm)

                resendRow
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.xl)
            .padding(.bottom, FloSpacing.lg)
        }
        .background(Color.white)
        .cornerRadius(FloRadius.xl)
        .shadow(
            color: FloShadow.medium.color,
            radius: FloShadow.medium.radius,
            x: FloShadow.medium.x,
            y: FloShadow.medium.y
        )
    }

    // MARK: - Code input
    //
    // A single invisible TextField captures the keyboard input; the six
    // visible cells just slice characters out of that string. Tapping
    // anywhere on the cell row focuses the hidden field. On the 6th
    // digit we auto-submit so the user doesn't have to look for a
    // button. textContentType(.oneTimeCode) lets iOS auto-fill the
    // code from the SMS/Mail picker bar.
    private var codeInputArea: some View {
        ZStack(alignment: .leading) {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFieldFocused)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityLabel("6-digit code")
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.prefix(Self.codeLength).filter { $0.isNumber })
                    if digits != newValue {
                        code = digits
                        return
                    }
                    if digits.count == Self.codeLength, !isVerifying {
                        submitCode()
                    }
                }

            HStack(spacing: FloSpacing.sm) {
                ForEach(0..<Self.codeLength, id: \.self) { index in
                    codeCell(at: index)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isVerifying { codeFieldFocused = true }
            }
        }
    }

    private func codeCell(at index: Int) -> some View {
        let digit: String = {
            guard index < code.count else { return "" }
            let i = code.index(code.startIndex, offsetBy: index)
            return String(code[i])
        }()
        let isNext = (code.count == index) && codeFieldFocused
        return Text(digit)
            .font(.custom("LUNARY free", size: 26))
            .foregroundColor(.floCharcoal)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white)
            .cornerRadius(FloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.md)
                    .stroke(
                        isNext ? Color.floSage : Color.floGray.opacity(0.3),
                        lineWidth: isNext ? 2 : 1
                    )
            )
            .accessibilityHidden(true)
    }

    // MARK: - Resend row
    private var resendRow: some View {
        HStack {
            if resendCooldown > 0 {
                Text("Resend code in \(resendCooldown)s")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
            } else {
                Button(action: resendCode) {
                    HStack(spacing: FloSpacing.xs) {
                        if isResending {
                            FloLoadingIndicator(size: 14, color: .floCharcoal, lineWidth: 1.5)
                        }
                        Text("Resend code")
                            .underline()
                    }
                    .font(.floBodySmall.weight(.medium))
                    .foregroundColor(.floCharcoal)
                }
                .disabled(isResending)
                .accessibilityLabel("Resend code")
            }
            Spacer()
            if isVerifying {
                FloLoadingIndicator(size: 18, color: .floCharcoal, lineWidth: 2)
            }
        }
    }

    // MARK: - "Use a different email"
    private var differentEmailLink: some View {
        HStack {
            Spacer()
            Button {
                FloHaptics.light()
                codeFieldFocused = false
                onUseDifferentEmail()
            } label: {
                Text("Use a different email")
                    .font(.floBodyMedium)
                    .foregroundColor(.floCharcoal)
                    .underline()
            }
            .accessibilityLabel("Use a different email")
            .accessibilityHint("Returns to the sign-in screen")
            Spacer()
        }
        .padding(.top, FloSpacing.xs)
    }

    // MARK: - Cooldown timer
    //
    // Each Task spawned by startCooldown keeps the most recent cooldown
    // value alive; older tasks observe resendCooldown == 0 on their
    // next tick and exit, so we don't end up with overlapping timers.
    private func startCooldown() {
        resendCooldown = Self.cooldownStart
        Task { @MainActor in
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if resendCooldown > 0 { resendCooldown -= 1 } else { return }
            }
        }
    }

    // MARK: - Verify
    private func submitCode() {
        guard !isVerifying else { return }
        codeFieldFocused = false
        isVerifying = true
        FloHaptics.light()

        let token = code
        let emailCopy = email

        #if DEBUG
        print("[CodeEntryView] verifyOTP starting — email=\(emailCopy), token.count=\(token.count)")
        #endif

        Task { @MainActor in
            defer { isVerifying = false }
            do {
                _ = try await SupabaseClient.shared.auth.verifyOTP(
                    email: emailCopy,
                    token: token,
                    type: .email
                )
                #if DEBUG
                print("[CodeEntryView] verifyOTP OK — session established")
                #endif
                FloHaptics.success()
                withAnimation(FloAnimation.easeOutMedium) {
                    isSignedIn = true
                }
            } catch {
                #if DEBUG
                print("[CodeEntryView] verifyOTP FAILED — \(type(of: error)): \(error)")
                #endif
                FloHaptics.error()
                presentError(friendlyVerifyError(for: error))
                code = ""
                codeFieldFocused = true
            }
        }
    }

    // MARK: - Resend
    private func resendCode() {
        guard !isResending, resendCooldown == 0 else { return }
        isResending = true
        FloHaptics.light()

        let emailCopy = email

        #if DEBUG
        print("[CodeEntryView] resend signInWithOTP — email=\(emailCopy)")
        #endif

        Task { @MainActor in
            defer { isResending = false }
            do {
                try await SupabaseClient.shared.auth.signInWithOTP(
                    email: emailCopy,
                    shouldCreateUser: true
                )
                #if DEBUG
                print("[CodeEntryView] resend OK")
                #endif
                FloHaptics.success()
                code = ""
                codeFieldFocused = true
                startCooldown()
            } catch {
                #if DEBUG
                print("[CodeEntryView] resend FAILED — \(type(of: error)): \(error)")
                #endif
                FloHaptics.error()
                presentError(friendlyVerifyError(for: error))
            }
        }
    }

    // MARK: - Friendly error mapping
    private func friendlyVerifyError(for error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.message
        }
        return error.localizedDescription
    }

    private func presentError(_ message: String) {
        errorMessage = message
        withAnimation { showError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showError = false }
        }
    }
}

#Preview {
    NavigationStack {
        CodeEntryView(
            email: "test+alias@example.com",
            isSignedIn: .constant(false),
            onUseDifferentEmail: {}
        )
    }
}
