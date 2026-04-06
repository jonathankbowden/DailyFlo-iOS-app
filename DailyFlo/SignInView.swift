//
//  SignInView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Binding var isSignedIn: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var isShowingPassword = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            // Background
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Top branding section matching Figma: "Welcome to: Daily FLO"
                    brandingSection
                        .fadeIn(delay: hasAppeared ? 0 : 0.1)

                    // Photo banner
                    Image("treetops")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 74)
                        .clipped()
                        .padding(.horizontal, FloSpacing.lg)
                        .fadeIn(delay: hasAppeared ? 0 : 0.2)

                    // Log In form area
                    VStack(spacing: FloSpacing.lg) {
                        // Sign in form
                        signInForm
                            .fadeIn(delay: hasAppeared ? 0 : 0.3)

                        // Or divider
                        orDivider
                            .fadeIn(delay: hasAppeared ? 0 : 0.35)

                        // Social sign in buttons
                        socialSignInButtons
                            .fadeIn(delay: hasAppeared ? 0 : 0.4)
                    }
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.top, FloSpacing.xl)
                    .padding(.bottom, FloSpacing.xxl)
                }
            }
            .dismissKeyboardOnTap()

            // Error toast
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

    // MARK: - Branding Section (matches Figma: Welcome to: / Daily / FLO)
    private var brandingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FLO top-right
            HStack {
                Spacer()
                Text("FLO")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.floCharcoal)
                    .tracking(3)
            }
            .padding(.horizontal, FloSpacing.lg)
            .padding(.top, FloSpacing.xl)

            // Welcome to:
            Text("Welcome to:")
                .font(.floSerif(size: 36))
                .foregroundColor(.floCharcoal)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.md)
                .accessibilityAddTraits(.isHeader)

            // Daily (large serif)
            Text("Daily")
                .font(.floSerif(size: 72))
                .foregroundColor(.floCharcoal)
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, -8)

            // FLO (bold)
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

    // MARK: - Sign In Form (matches Figma: Log In header, Google, email, password, forgot, LOGIN, create)
    private var signInForm: some View {
        VStack(alignment: .leading, spacing: FloSpacing.lg) {
            // "Log In:" header
            Text("Log In:")
                .font(.floSerif(size: 22))
                .foregroundColor(.floCharcoal)

            // Google sign in button (first, per Figma)
            Button(action: {
                FloHaptics.light()
                signInWithGoogle()
            }) {
                HStack(spacing: FloSpacing.md) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.floCharcoal)
                        .cornerRadius(FloRadius.sm)

                    Text("Log in with Google+")
                        .font(.floBodyMedium)
                        .foregroundColor(.floCharcoal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, FloSpacing.xs)
                .padding(.horizontal, FloSpacing.sm)
                .background(Color.white)
                .cornerRadius(FloRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: FloRadius.md)
                        .stroke(Color.floGray.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.floPressed)
            .accessibilityLabel("Sign in with Google")

            // Divider
            Rectangle()
                .fill(Color.floGray.opacity(0.2))
                .frame(height: 1)

            // Email field
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
                    .onSubmit {
                        focusedField = .password
                    }
                    .accessibilityLabel("Email address")
            }
            .animation(FloAnimation.easeOutQuick, value: focusedField)

            // Password field
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
                        if isFormValid {
                            signIn()
                        }
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

            // Forgot password link
            Button(action: {}) {
                Text("Forgot your password?")
                    .font(.floBodySmall)
                    .foregroundColor(.floSage)
                    .underline()
            }
            .accessibilityLabel("Forgot your password")

            // LOGIN button (black, per Figma)
            Button(action: signIn) {
                HStack(spacing: FloSpacing.sm) {
                    if isLoading {
                        FloLoadingIndicator(size: 20, color: .white, lineWidth: 2)
                    } else {
                        Text("LOGIN")
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
            .accessibilityLabel("Login")
            .accessibilityHint(isFormValid ? "Double tap to sign in" : "Enter email and password to sign in")
        }
    }

    // MARK: - Validation
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        email.contains("@")
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

    // MARK: - Social Sign In Buttons
    private var socialSignInButtons: some View {
        VStack(spacing: FloSpacing.md) {
            // Sign in with Apple
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success:
                    FloHaptics.success()
                    withAnimation(FloAnimation.easeOutMedium) {
                        isSignedIn = true
                    }
                case .failure:
                    FloHaptics.error()
                    errorMessage = "Apple Sign In failed. Please try again."
                    showErrorTemporarily()
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .cornerRadius(FloRadius.md)
            .accessibilityLabel("Sign in with Apple")

            // Create account / Skip for demo
            Button(action: {
                FloHaptics.light()
                withAnimation(FloAnimation.easeOutMedium) {
                    isSignedIn = true
                }
            }) {
                Text("Create account")
                    .font(.floBodyMedium)
                    .foregroundColor(.floSage)
                    .underline()
            }
            .buttonStyle(.floPressed)
            .accessibilityHint("Skip sign in and continue as guest")
        }
    }

    // MARK: - Actions
    private func signIn() {
        guard isFormValid else { return }

        FloHaptics.light()
        focusedField = nil
        isLoading = true

        // Simulate sign in delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            FloHaptics.success()
            withAnimation(FloAnimation.easeOutMedium) {
                isSignedIn = true
            }
        }
    }

    private func signInWithGoogle() {
        // In a real app, implement Google Sign In
        withAnimation(FloAnimation.easeOutMedium) {
            isSignedIn = true
        }
    }

    private func showErrorTemporarily() {
        showError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showError = false
            }
        }
    }
}

#Preview {
    SignInView(isSignedIn: .constant(false))
}
