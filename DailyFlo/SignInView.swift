//
//  SignInView.swift
//  DailyFlo
//
//  Unified auth: one screen for new and returning users. Three paths,
//  same outcome (a Supabase session):
//
//    - Sign in with Apple   (real OIDC via Supabase signInWithIdToken)
//    - Continue with Google (real OIDC via Supabase signInWithIdToken)
//    - Email + 6-digit code (auth.signInWithOTP → push CodeEntryView
//                            → auth.verifyOTP)
//
//  Password sign-in survives behind a low-prominence "Use a password
//  instead" link for App Review's demo account, but is hidden from the
//  primary flow. There is no separate sign-up screen — `shouldCreateUser`
//  is left at the SDK default (true) so a fresh address gets a user row
//  and the auth.users trigger seeds a profiles row (default role=tracker)
//  on the server. CycleManager picks it up on the next auth state change.
//

import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Supabase
import SwiftUI

// Routes pushed onto the auth NavigationStack.
private enum AuthRoute: Hashable {
    case codeEntry(email: String)
}

struct SignInView: View {
    @Binding var isSignedIn: Bool

    // Main form state
    @State private var email = ""
    @State private var isLoading = false           // any auth action in flight
    @State private var isSendingOtp = false        // CONTINUE button spinner
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @State private var currentNonce: String?
    @State private var path: [AuthRoute] = []
    @State private var showPasswordSheet = false

    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.floCream.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: FloSpacing.xl) {
                        brandingSection
                            .fadeIn(delay: hasAppeared ? 0 : 0.1)

                        signInCard
                            .fadeIn(delay: hasAppeared ? 0 : 0.2)

                        usePasswordLink
                            .fadeIn(delay: hasAppeared ? 0 : 0.3)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.lg)
                    .padding(.bottom, FloSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnTap()

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
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .codeEntry(let email):
                    CodeEntryView(
                        email: email,
                        isSignedIn: $isSignedIn,
                        onUseDifferentEmail: {
                            if !path.isEmpty { path.removeLast() }
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordSignInSheet(isSignedIn: $isSignedIn)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Floating card
    private var signInCard: some View {
        VStack(spacing: 0) {
            cardHeaderImage

            VStack(alignment: .leading, spacing: FloSpacing.lg) {
                socialSignInButtons
                orDivider
                emailContinueForm
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

    private var cardHeaderImage: some View {
        Image("medbg_canopy_a")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }

    // MARK: - Branding
    //
    // Just the "Daily" + "FLO" wordmark lockup. The greeting line and
    // the top-right corner marker were removed so the page leads with
    // the brand alone; the lockup sits a touch lower from the safe-area
    // edge to give it breathing room above the card.
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

    // MARK: - Social
    private var socialSignInButtons: some View {
        VStack(spacing: FloSpacing.sm) {
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .cornerRadius(FloRadius.md)
            .disabled(isLoading)
            .accessibilityLabel("Sign in with Apple")

            socialButton(
                icon: "g.circle.fill",
                label: "Continue with Google",
                action: { signInWithGoogle() }
            )
            .accessibilityLabel("Continue with Google")
        }
    }

    private func socialButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            FloHaptics.light()
            action()
        }) {
            HStack(spacing: FloSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.floCharcoal)
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(.floButton)
                    .foregroundColor(.floCharcoal)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white)
            .cornerRadius(FloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.md)
                    .stroke(Color.floGray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.floPressed)
        .disabled(isLoading)
    }

    // MARK: - Or Divider
    private var orDivider: some View {
        HStack(spacing: FloSpacing.md) {
            Rectangle()
                .fill(Color.floGray.opacity(0.25))
                .frame(height: 1)

            Text("OR")
                .font(.floLabel)
                .foregroundColor(.floGray)
                .tracking(1)

            Rectangle()
                .fill(Color.floGray.opacity(0.25))
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Email + CONTINUE (passwordless OTP)
    private var emailContinueForm: some View {
        VStack(spacing: FloSpacing.md) {
            TextField("Email", text: $email)
                .font(.floBodyMedium)
                .foregroundColor(.floCharcoal)
                .padding(.horizontal, FloSpacing.md)
                .frame(height: 52)
                .background(Color.white)
                .cornerRadius(FloRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: FloRadius.md)
                        .stroke(
                            emailFocused ? Color.floSage : Color.floGray.opacity(0.3),
                            lineWidth: emailFocused ? 2 : 1
                        )
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .focused($emailFocused)
                .submitLabel(.go)
                .onSubmit {
                    if isEmailValid { sendOtp() }
                }
                .animation(FloAnimation.easeOutQuick, value: emailFocused)
                .accessibilityLabel("Email")

            Button(action: sendOtp) {
                HStack(spacing: FloSpacing.sm) {
                    if isSendingOtp {
                        FloLoadingIndicator(size: 20, color: .white, lineWidth: 2)
                    } else {
                        Text("CONTINUE")
                            .tracking(2)
                    }
                }
                .font(.floButton)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isEmailValid ? Color.floCharcoal : Color.floGray.opacity(0.4))
                .cornerRadius(FloRadius.md)
            }
            .buttonStyle(.floPressed)
            .disabled(!isEmailValid || isLoading)
            .animation(FloAnimation.easeOutQuick, value: isEmailValid)
            .accessibilityLabel("Continue")
            .accessibilityHint(isEmailValid ? "Send a 6-digit code to this email" : "Enter your email to continue")
        }
    }

    // MARK: - "Use a password instead" (low-prominence, App Review demo)
    private var usePasswordLink: some View {
        HStack {
            Spacer()
            Button {
                FloHaptics.light()
                emailFocused = false
                showPasswordSheet = true
            } label: {
                Text("Use a password instead")
                    .font(.floBodySmall)
                    .foregroundColor(.floGray)
                    .underline()
            }
            .floHitTarget()
            .accessibilityLabel("Use a password instead")
            .accessibilityHint("Opens the email and password sign-in form")
            Spacer()
        }
        .padding(.top, FloSpacing.xs)
    }

    // MARK: - Validation
    private var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.contains("@") && trimmed.contains(".")
    }

    // MARK: - OTP send
    //
    // signInWithOTP with shouldCreateUser: true (the SDK default) covers
    // both sign-in and sign-up — Supabase creates the auth.users row on
    // first request and the table's trigger seeds the matching profiles
    // row. The user then gets the 6-digit code (when the email template
    // includes `{{ .Token }}`) and is dropped on CodeEntryView.
    private func sendOtp() {
        guard isEmailValid, !isLoading else { return }
        FloHaptics.light()
        emailFocused = false
        isLoading = true
        isSendingOtp = true

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        print("[SignInView] auth.signInWithOTP starting — email=\(trimmedEmail)")
        #endif

        Task { @MainActor in
            defer {
                isLoading = false
                isSendingOtp = false
            }
            do {
                try await SupabaseClient.shared.auth.signInWithOTP(
                    email: trimmedEmail,
                    shouldCreateUser: true
                )
                #if DEBUG
                print("[SignInView] signInWithOTP OK — pushing CodeEntryView")
                #endif
                FloHaptics.success()
                path.append(.codeEntry(email: trimmedEmail))
            } catch {
                #if DEBUG
                print("[SignInView] signInWithOTP FAILED — \(type(of: error)): \(error)")
                #endif
                FloHaptics.error()
                presentError(friendlyOtpSendError(for: error))
            }
        }
    }

    // MARK: - Apple Sign In
    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                FloHaptics.error()
                presentError("Apple Sign In didn't return a valid token. Please try again.")
                return
            }

            emailFocused = false
            isLoading = true

            Task { @MainActor in
                defer { isLoading = false }
                do {
                    _ = try await SupabaseClient.shared.auth.signInWithIdToken(
                        credentials: OpenIDConnectCredentials(
                            provider: .apple,
                            idToken: idToken,
                            nonce: nonce
                        )
                    )
                    FloHaptics.success()
                    withAnimation(FloAnimation.easeOutMedium) {
                        isSignedIn = true
                    }
                } catch {
                    FloHaptics.error()
                    presentError("Apple Sign In failed. \(error.localizedDescription)")
                }
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            FloHaptics.error()
            presentError("Apple Sign In failed. Please try again.")
        }
    }

    // MARK: - Google Sign In
    private func signInWithGoogle() {
        guard let presenter = Self.topViewController() else {
            FloHaptics.error()
            presentError("Couldn't open Google Sign In. Please try again.")
            return
        }

        emailFocused = false
        isLoading = true

        // GoogleSignIn-iOS 7.1.0 doesn't expose a nonce parameter on signIn,
        // so we don't bind one here. Supabase still verifies the ID token's
        // signature, audience, issuer, and expiry — nonce is the optional
        // replay-prevention layer and `OpenIDConnectCredentials.nonce` is
        // documented as optional.
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: nil
                )

                guard let idToken = result.user.idToken?.tokenString else {
                    FloHaptics.error()
                    presentError("Google Sign In didn't return a valid token. Please try again.")
                    return
                }

                _ = try await SupabaseClient.shared.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .google,
                        idToken: idToken
                    )
                )

                FloHaptics.success()
                withAnimation(FloAnimation.easeOutMedium) {
                    isSignedIn = true
                }
            } catch {
                // User-cancelled is silent; everything else surfaces a toast.
                if (error as NSError).code == GIDSignInError.canceled.rawValue { return }
                FloHaptics.error()
                presentError("Google Sign In failed. \(error.localizedDescription)")
            }
        }
    }

    /// Walks the active window scene to find the topmost presented controller —
    /// the right anchor for GIDSignIn's presentation sheet from SwiftUI.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? scenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return nil }

        var vc = window.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    // MARK: - Friendly error mapping
    private func friendlyOtpSendError(for error: Error) -> String {
        if let authError = error as? AuthError {
            // Most common cases: 429 rate limit, captcha required, server
            // down. Use the raw server message rather than guessing — it
            // describes the underlying issue accurately.
            return authError.message
        }
        return error.localizedDescription
    }

    // MARK: - Error toast
    private func presentError(_ message: String) {
        errorMessage = message
        withAnimation { showError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showError = false }
        }
    }

    // MARK: - Nonce helpers (Apple Sign In via Supabase)
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "Unable to generate nonce: \(status)")
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Password sign-in sheet
//
// Sign-in only — no sign-up via password. Lives behind the "Use a
// password instead" link as a back door for App Review's demo
// credentials, never the primary flow.
private struct PasswordSignInSheet: View {
    @Binding var isSignedIn: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isShowingPassword = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        email.contains("@")
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FloSpacing.lg) {
                    HStack {
                        Capsule()
                            .fill(Color.floGray.opacity(0.3))
                            .frame(width: 36, height: 5)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, FloSpacing.sm)

                    Text("Log in with password")
                        .font(.custom("LUNARY free", size: 32))
                        .foregroundColor(.floCharcoal)
                        .padding(.top, FloSpacing.md)
                        .accessibilityAddTraits(.isHeader)

                    Text("For App Review and existing accounts with a password set up.")
                        .font(.floBodySmall)
                        .foregroundColor(.floGray)

                    formFields
                        .padding(.top, FloSpacing.md)

                    Button(action: submit) {
                        HStack(spacing: FloSpacing.sm) {
                            if isLoading {
                                FloLoadingIndicator(size: 20, color: .white, lineWidth: 2)
                            } else {
                                Text("LOG IN")
                                    .tracking(2)
                            }
                        }
                        .font(.floButton)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FloSpacing.md)
                        .background(isFormValid ? Color.floCharcoal : Color.floGray.opacity(0.4))
                        .cornerRadius(FloRadius.md)
                    }
                    .buttonStyle(.floPressed)
                    .disabled(isLoading || !isFormValid)
                    .accessibilityLabel("Log in")
                }
                .padding(.horizontal, FloSpacing.lg)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            TextField("Email", text: $email)
                .font(.floBodyMedium)
                .padding(.horizontal, FloSpacing.md)
                .frame(height: 52)
                .background(Color.white)
                .cornerRadius(FloRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: FloRadius.md)
                        .stroke(
                            focusedField == .email ? Color.floSage : Color.floGray.opacity(0.3),
                            lineWidth: focusedField == .email ? 2 : 1
                        )
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            HStack {
                Group {
                    if isShowingPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .font(.floBodyMedium)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    if isFormValid { submit() }
                }

                Button {
                    FloHaptics.light()
                    isShowingPassword.toggle()
                } label: {
                    Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                        .foregroundColor(.floGray)
                        .frame(width: 24, height: 24)
                }
                .floHitTarget()
                .accessibilityLabel(isShowingPassword ? "Hide password" : "Show password")
            }
            .padding(.horizontal, FloSpacing.md)
            .frame(height: 52)
            .background(Color.white)
            .cornerRadius(FloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.md)
                    .stroke(
                        focusedField == .password ? Color.floSage : Color.floGray.opacity(0.3),
                        lineWidth: focusedField == .password ? 2 : 1
                    )
            )
        }
        .animation(FloAnimation.easeOutQuick, value: focusedField)
    }

    private func submit() {
        guard isFormValid else { return }
        FloHaptics.light()
        focusedField = nil
        isLoading = true

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = password

        #if DEBUG
        print("[PasswordSignInSheet] auth.signIn starting — email=\(trimmedEmail)")
        #endif

        Task { @MainActor in
            defer { isLoading = false }
            do {
                _ = try await SupabaseClient.shared.auth.signIn(
                    email: trimmedEmail,
                    password: pw
                )
                #if DEBUG
                print("[PasswordSignInSheet] auth.signIn OK")
                #endif
                FloHaptics.success()
                withAnimation(FloAnimation.easeOutMedium) {
                    isSignedIn = true
                }
                dismiss()
            } catch {
                #if DEBUG
                print("[PasswordSignInSheet] auth.signIn FAILED — \(type(of: error)): \(error)")
                #endif
                FloHaptics.error()
                if let authError = error as? AuthError, authError.errorCode == .invalidCredentials {
                    presentError("That email and password didn't match. Try again.")
                } else if let authError = error as? AuthError {
                    presentError(authError.message)
                } else {
                    presentError(error.localizedDescription)
                }
            }
        }
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
    SignInView(isSignedIn: .constant(false))
}
