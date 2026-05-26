//
//  SignInView.swift
//  DailyFlo
//
//  Patreon-style: social providers first, email + password below.
//

import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Supabase
import SwiftUI

struct SignInView: View {
    @Binding var isSignedIn: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var isShowingPassword = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @State private var currentNonce: String?

    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    brandingSection
                        .fadeIn(delay: hasAppeared ? 0 : 0.1)

                    Image("treetops")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 74)
                        .clipped()
                        .padding(.horizontal, FloSpacing.lg)
                        .fadeIn(delay: hasAppeared ? 0 : 0.2)

                    VStack(spacing: FloSpacing.lg) {
                        socialSignInButtons
                            .fadeIn(delay: hasAppeared ? 0 : 0.3)

                        orDivider
                            .fadeIn(delay: hasAppeared ? 0 : 0.35)

                        emailPasswordForm
                            .fadeIn(delay: hasAppeared ? 0 : 0.4)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.xl)
                    .padding(.bottom, FloSpacing.xxl)
                }
            }
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Branding
    private var brandingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Text("FLO")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.floCharcoal)
                    .tracking(3)
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.xl)

            Text("Welcome to:")
                .font(.floSerif(size: 36))
                .foregroundColor(.floCharcoal)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.md)
                .accessibilityAddTraits(.isHeader)

            Text("Daily")
                .font(.floSerif(size: 72))
                .foregroundColor(.floCharcoal)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, -8)

            Text("FLO")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.floCharcoal)
                .tracking(3)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.bottom, FloSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to Daily Flo")
    }

    // MARK: - Social (Patreon pattern: Apple, Google — stacked)
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

    // MARK: - Email + Password (handles both sign up and sign in)
    private var emailPasswordForm: some View {
        VStack(alignment: .leading, spacing: FloSpacing.lg) {
            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                Text("Email address")
                    .font(.floBodyMedium)
                    .foregroundColor(.floCharcoal)

                TextField("example@gmail.com", text: $email)
                    .font(.floBodyMedium)
                    .foregroundColor(.floCharcoal)
                    .padding()
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
                    .accessibilityLabel("Email address")
            }
            .animation(FloAnimation.easeOutQuick, value: focusedField)

            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                Text("Password")
                    .font(.floBodyMedium)
                    .foregroundColor(.floCharcoal)

                HStack {
                    Group {
                        if isShowingPassword {
                            TextField("password", text: $password)
                        } else {
                            SecureField("password", text: $password)
                        }
                    }
                    .font(.floBodyMedium)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit {
                        if isFormValid { submitEmailPassword() }
                    }

                    Button(action: {
                        FloHaptics.light()
                        isShowingPassword.toggle()
                    }) {
                        Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                            .foregroundColor(.floGray)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel(isShowingPassword ? "Hide password" : "Show password")
                }
                .padding()
                .background(Color.white)
                .cornerRadius(FloRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: FloRadius.md)
                        .stroke(
                            focusedField == .password ? Color.floSage : Color.floGray.opacity(0.3),
                            lineWidth: focusedField == .password ? 2 : 1
                        )
                )
                .textContentType(.password)
            }
            .animation(FloAnimation.easeOutQuick, value: focusedField)

            Button(action: {}) {
                Text("Forgot your password?")
                    .font(.floBodySmall)
                    .foregroundColor(.floSage)
                    .underline()
            }
            .accessibilityLabel("Forgot your password")

            Button(action: submitEmailPassword) {
                HStack(spacing: FloSpacing.sm) {
                    if isLoading {
                        FloLoadingIndicator(size: 20, color: .white, lineWidth: 2)
                    } else {
                        Text("CONTINUE")
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
            .animation(FloAnimation.easeOutQuick, value: isFormValid)
            .accessibilityLabel("Continue")
            .accessibilityHint(isFormValid ? "Double tap to continue with email" : "Enter email and password to continue")
        }
    }

    // MARK: - Validation
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        email.contains("@")
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

            focusedField = nil
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

        focusedField = nil
        isLoading = true

        let rawNonce = Self.randomNonceString()
        let hashedNonce = Self.sha256(rawNonce)

        Task { @MainActor in
            defer { isLoading = false }
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: nil,
                    nonce: hashedNonce
                )

                guard let idToken = result.user.idToken?.tokenString else {
                    FloHaptics.error()
                    presentError("Google Sign In didn't return a valid token. Please try again.")
                    return
                }

                _ = try await SupabaseClient.shared.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .google,
                        idToken: idToken,
                        nonce: rawNonce
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

    // MARK: - Email + Password submission
    private func submitEmailPassword() {
        guard isFormValid else { return }

        FloHaptics.light()
        focusedField = nil
        isLoading = true

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = password

        Task { @MainActor in
            defer { isLoading = false }
            do {
                try await signUpOrSignIn(email: trimmedEmail, password: pw)
                FloHaptics.success()
                withAnimation(FloAnimation.easeOutMedium) {
                    isSignedIn = true
                }
            } catch {
                FloHaptics.error()
                presentError(friendlyMessage(for: error))
            }
        }
    }

    private func signUpOrSignIn(email: String, password: String) async throws {
        let auth = SupabaseClient.shared.auth
        do {
            _ = try await auth.signUp(email: email, password: password)
        } catch let AuthError.api(_, errorCode, _, _) where errorCode == .userAlreadyExists {
            _ = try await auth.signIn(email: email, password: password)
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .invalidCredentials:
                return "That email and password didn't match. Try again."
            case .weakPassword:
                return "Please choose a stronger password."
            default:
                return authError.message
            }
        }
        return error.localizedDescription
    }

    // MARK: - Error toast
    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
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

#Preview {
    SignInView(isSignedIn: .constant(false))
}
