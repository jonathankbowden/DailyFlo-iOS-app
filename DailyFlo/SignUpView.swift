//
//  SignUpView.swift
//  DailyFlo
//
//  Patreon-style: social providers first, then email.
//

import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @Binding var isSignedIn: Bool
    @State private var email = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        ZStack {
            Color.floCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: FloSpacing.xl) {
                    Spacer(minLength: FloSpacing.xxxl)

                    logo
                        .fadeIn(delay: hasAppeared ? 0 : 0.1)

                    header
                        .fadeIn(delay: hasAppeared ? 0 : 0.2)

                    VStack(spacing: FloSpacing.md) {
                        socialButtons
                            .fadeIn(delay: hasAppeared ? 0 : 0.3)

                        orDivider
                            .fadeIn(delay: hasAppeared ? 0 : 0.35)

                        emailSection
                            .fadeIn(delay: hasAppeared ? 0 : 0.4)
                    }
                    .padding(.horizontal, FloSpacing.lg)

                    helpLink
                        .fadeIn(delay: hasAppeared ? 0 : 0.5)

                    Spacer(minLength: FloSpacing.lg)

                    termsText
                        .fadeIn(delay: hasAppeared ? 0 : 0.55)
                        .padding(.horizontal, FloSpacing.xl)
                        .padding(.bottom, FloSpacing.xl)
                }
                .frame(maxWidth: .infinity)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Logo / wordmark
    private var logo: some View {
        VStack(spacing: FloSpacing.xs) {
            Text("Daily")
                .font(.floSerif(size: 44))
                .foregroundColor(.floCharcoal)
            Text("FLO")
                .font(.system(size: 14, weight: .black))
                .tracking(4)
                .foregroundColor(.floCharcoal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily Flo")
        .accessibilityAddTraits(.isHeader)
    }

    private var header: some View {
        Text("Log in or sign up")
            .font(.floSerif(size: 22))
            .foregroundColor(.floCharcoal)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Social (Patreon pattern: stacked, equal weight)
    private var socialButtons: some View {
        VStack(spacing: FloSpacing.sm) {
            socialButton(
                icon: "g.circle.fill",
                label: "Continue with Google",
                action: { continueWithProvider("Google") }
            )
            .accessibilityLabel("Continue with Google")

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
            .signInWithAppleButtonStyle(.whiteOutline)
            .frame(height: 52)
            .cornerRadius(FloRadius.md)
            .accessibilityLabel("Continue with Apple")

            socialButton(
                icon: "f.circle.fill",
                label: "Continue with Facebook",
                action: { continueWithProvider("Facebook") }
            )
            .accessibilityLabel("Continue with Facebook")
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

    // MARK: - Email + continue (Patreon: single field then Continue)
    private var emailSection: some View {
        VStack(spacing: FloSpacing.sm) {
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
                .submitLabel(.continue)
                .onSubmit {
                    if isEmailValid { continueWithEmail() }
                }
                .animation(FloAnimation.easeOutQuick, value: emailFocused)
                .accessibilityLabel("Email")

            Button(action: continueWithEmail) {
                HStack(spacing: FloSpacing.sm) {
                    if isLoading {
                        FloLoadingIndicator(size: 20, color: .white, lineWidth: 2)
                    } else {
                        Text("Continue")
                            .font(.floButton)
                    }
                }
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
            .accessibilityHint(isEmailValid ? "Continue with email" : "Enter your email to continue")
        }
    }

    private var helpLink: some View {
        Button(action: {}) {
            Text("Need help signing in?")
                .font(.floBodySmall)
                .foregroundColor(.floSage)
        }
        .accessibilityLabel("Need help signing in")
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

    // MARK: - Actions
    private func continueWithEmail() {
        guard isEmailValid else { return }
        FloHaptics.light()
        emailFocused = false
        isLoading = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isLoading = false
            FloHaptics.success()
            completeSignIn()
        }
    }

    private func continueWithProvider(_ provider: String) {
        completeSignIn()
    }

    private func completeSignIn() {
        withAnimation(FloAnimation.easeOutMedium) {
            isSignedIn = true
        }
    }

    private func showErrorTemporarily() {
        showError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showError = false }
        }
    }
}

#Preview {
    SignUpView(isSignedIn: .constant(false))
}
