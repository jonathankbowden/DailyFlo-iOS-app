//
//  SignUpView.swift
//  DailyFlo
//
//  Mirror of SignInView: the same floating-card layout with a nature
//  image strip, "Create Account:" header, social providers, email +
//  Continue, and a "Already have an account? Log in" link that pops
//  back to SignInView through the NavigationStack.
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
    @Environment(\.dismiss) private var dismiss

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
    // Same wordmark stack above the card so the pair feels coherent —
    // "Welcome to: Daily FLO" reads the same on both screens.
    private var brandingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Text("FLO")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.floCharcoal)
                    .tracking(3)
            }
            .padding(.top, FloSpacing.md)

            Text("Welcome to:")
                .font(.floSerif(size: 36))
                .foregroundColor(.floCharcoal)
                .padding(.top, FloSpacing.md)
                .accessibilityAddTraits(.isHeader)

            Text("Daily")
                .font(.floSerif(size: 72))
                .foregroundColor(.floCharcoal)
                .padding(.top, -8)

            Text("FLO")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.floCharcoal)
                .tracking(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to Daily Flo")
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

            VStack(alignment: .leading, spacing: FloSpacing.lg) {
                Text("Create Account:")
                    .font(.floSerif(size: 36))
                    .foregroundColor(.floCharcoal)
                    .accessibilityAddTraits(.isHeader)

                socialButtons
                orDivider
                emailSection

                Divider()
                    .padding(.top, FloSpacing.sm)

                backToLogInLink
            }
            .padding(FloSpacing.lg)
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
                        Text("CREATE ACCOUNT")
                            .font(.floButton)
                            .tracking(2)
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
            .accessibilityLabel("Create account")
            .accessibilityHint(isEmailValid ? "Create your DailyFLO account with this email" : "Enter your email to create an account")
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
