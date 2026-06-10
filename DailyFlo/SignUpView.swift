//
//  SignUpView.swift
//  DailyFlo
//
//  Mirror of SignInView: the same floating-card layout with a nature
//  image strip, social providers, email + password, "CREATE ACCOUNT",
//  and a "Already have an account? Log in" link that pops back to
//  SignInView through the NavigationStack.
//
//  Email signup hits Supabase Auth's signUp(email:password:) directly.
//  With email-confirmation enabled (the default on the project), a
//  successful signUp returns a user with NO session — we surface a
//  "check your inbox" toast and stay on the screen rather than
//  transitioning into the app. Errors get a red toast with a
//  human-readable message so users see when something fails.
//

import Supabase
import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @Binding var isSignedIn: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var isShowingPassword = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var hasAppeared = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: FloSpacing.xl) {
                    brandingSection
                        .fadeIn(delay: hasAppeared ? 0 : 0.1)

                    signUpCard
                        .fadeIn(delay: hasAppeared ? 0 : 0.2)

                    termsText
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

            if showSuccess {
                VStack {
                    Spacer()
                    Text(successMessage)
                        .floToast(.success)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, FloSpacing.xxl)
                }
                .animation(FloAnimation.springGentle, value: showSuccess)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Branding (matches SignInView)
    //
    // Just the "Daily" + "FLO" wordmark lockup, same as SignInView, so
    // the pair feels coherent.
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

    // MARK: - Sign up card
    private var signUpCard: some View {
        VStack(spacing: 0) {
            Image("medbg_openhills_a")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)

            // Card opens straight on the social buttons now that the
            // "Create Account:" title is gone. Extra top padding inside
            // the card keeps the image-to-button gap from feeling tight.
            VStack(alignment: .leading, spacing: FloSpacing.lg) {
                socialButtons
                orDivider
                emailSection

                Divider()
                    .padding(.top, FloSpacing.sm)

                backToLogInLink
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

    private var backToLogInLink: some View {
        HStack(spacing: FloSpacing.xs) {
            Spacer()
            Text("Already have an account?")
                .font(.floBodyMedium)
                .foregroundColor(.floGray)

            Button {
                FloHaptics.light()
                dismiss()
            } label: {
                Text("Log in")
                    .font(.floBodyMedium.weight(.medium))
                    .foregroundColor(.floCharcoal)
                    .underline()
            }
            .accessibilityLabel("Log in")
            .accessibilityHint("Returns to the sign-in screen")
            Spacer()
        }
        .padding(.top, FloSpacing.xs)
    }

    // MARK: - Social (Apple + Google — match SignInView's pair)
    private var socialButtons: some View {
        VStack(spacing: FloSpacing.sm) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success:
                    FloHaptics.success()
                    completeSignIn()
                case .failure:
                    FloHaptics.error()
                    errorMessage = "Apple sign in failed. Please try again."
                    showErrorTemporarily()
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .cornerRadius(FloRadius.md)
            .accessibilityLabel("Continue with Apple")

            socialButton(
                icon: "g.circle.fill",
                label: "Continue with Google",
                action: { continueWithProvider("Google") }
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
    }

    // MARK: - Or divider (lowercase "or" like Patreon)
    private var orDivider: some View {
        HStack(spacing: FloSpacing.md) {
            Rectangle()
                .fill(Color.floGray.opacity(0.25))
                .frame(height: 1)

            Text("or")
                .font(.floBodySmall)
                .foregroundColor(.floGray)

            Rectangle()
                .fill(Color.floGray.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.vertical, FloSpacing.xs)
        .accessibilityHidden(true)
    }

    // MARK: - Email + password + CREATE ACCOUNT
    private var emailSection: some View {
        VStack(spacing: FloSpacing.md) {
            // Email
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
                .animation(FloAnimation.easeOutQuick, value: focusedField)
                .accessibilityLabel("Email")

            // Password
            HStack {
                Group {
                    if isShowingPassword {
                        TextField("Password (min 6 characters)", text: $password)
                    } else {
                        SecureField("Password (min 6 characters)", text: $password)
                    }
                }
                .font(.floBodyMedium)
                .foregroundColor(.floCharcoal)
                .textContentType(.newPassword)
                .autocapitalization(.none)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    if isFormValid { submitSignUp() }
                }

                Button {
                    FloHaptics.light()
                    isShowingPassword.toggle()
                } label: {
                    Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                        .foregroundColor(.floGray)
                        .frame(width: 24, height: 24)
                }
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
            .animation(FloAnimation.easeOutQuick, value: focusedField)

            // Create account
            Button(action: submitSignUp) {
                HStack(spacing: FloSpacing.sm) {
                    if isLoading {
                        FloLoadingIndicator(size: 20, color: .white, lineWidth: 2)
                    } else {
                        Text("CREATE ACCOUNT")
                            .font(.floButton)
                            .tracking(2)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isFormValid ? Color.floCharcoal : Color.floGray.opacity(0.4))
                .cornerRadius(FloRadius.md)
            }
            .buttonStyle(.floPressed)
            .disabled(!isFormValid || isLoading)
            .animation(FloAnimation.easeOutQuick, value: isFormValid)
            .accessibilityLabel("Create account")
            .accessibilityHint(isFormValid ? "Create your DailyFLO account" : "Enter your email and a password of at least six characters")
        }
    }

    private var termsText: some View {
        Text("By signing up, you are creating a Daily Flo account and agree to Daily Flo's Terms and Privacy Policy.")
            .font(.floCaption)
            .foregroundColor(.floGray)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Validation
    private var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.contains("@") && trimmed.contains(".")
    }

    private var isPasswordValid: Bool {
        // Supabase's default minimum is 6 characters; match that here so
        // the client-side gate doesn't reject anything the server accepts.
        password.count >= 6
    }

    private var isFormValid: Bool {
        isEmailValid && isPasswordValid
    }

    // MARK: - Sign up (real Supabase auth.signUp)
    //
    // Replaces the previous fake DispatchQueue sleep. With email
    // confirmation enabled on the project, signUp returns a user with
    // NO session — that's the success path that surfaces the "check
    // your inbox" toast. If confirmation is off (or already done), a
    // session comes back and we transition into the app.
    private func submitSignUp() {
        guard isFormValid else { return }
        FloHaptics.light()
        focusedField = nil
        isLoading = true

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = password

        #if DEBUG
        print("[SignUpView] auth.signUp starting — email=\(trimmedEmail)")
        #endif

        Task { @MainActor in
            defer { isLoading = false }
            do {
                let response = try await SupabaseClient.shared.auth.signUp(
                    email: trimmedEmail,
                    password: pw
                )

                #if DEBUG
                print("[SignUpView] auth.signUp OK — user.id=\(response.user.id), session=\(response.session != nil ? "present" : "nil")")
                #endif

                FloHaptics.success()
                if response.session != nil {
                    // Confirmation disabled — straight into the app.
                    completeSignIn()
                } else {
                    // Confirmation required — user has been created
                    // (you can see them in the Auth dashboard) but they
                    // need to click the email link before signing in.
                    presentSuccess("Check your inbox to confirm your account.")
                }
            } catch {
                #if DEBUG
                print("[SignUpView] auth.signUp FAILED — \(type(of: error)): \(error)")
                #endif
                FloHaptics.error()
                presentError(friendlyMessage(for: error))
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .userAlreadyExists:
                return "An account with that email already exists. Try logging in instead."
            case .weakPassword:
                return "That password is too weak. Try at least 6 characters."
            default:
                return authError.message
            }
        }
        return error.localizedDescription
    }

    private func completeSignIn() {
        withAnimation(FloAnimation.easeOutMedium) {
            isSignedIn = true
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        withAnimation { showError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showError = false }
        }
    }

    private func presentSuccess(_ message: String) {
        successMessage = message
        withAnimation { showSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showSuccess = false }
        }
    }

    // Kept for the SignInWithAppleButton fake-success path until that
    // gets its real Supabase bridge — out of scope for the email-signup
    // fix but still required because the social buttons above call it.
    private func continueWithProvider(_ provider: String) {
        completeSignIn()
    }

    private func showErrorTemporarily() {
        withAnimation { showError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showError = false }
        }
    }
}

#Preview {
    SignUpView(isSignedIn: .constant(false))
}
