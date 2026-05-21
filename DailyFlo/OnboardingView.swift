//
//  OnboardingView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/3/26.
//

import SwiftUI

// MARK: - Onboarding Data Model
struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let imageName: String?
    let inputType: OnboardingInputType
}

enum OnboardingInputType {
    case none
    case textField(placeholder: String, keyboardType: UIKeyboardType)
    case datePicker
    case numberPicker(range: ClosedRange<Int>, unit: String)
    case multiSelect(options: [String])
    case singleSelect(options: [String])
}

// MARK: - Main Onboarding View
struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var currentPage = 0
    @State private var userName = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var lastPeriodDate = Date()
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @State private var selectedGoals: Set<String> = []
    @State private var selectedSymptoms: Set<String> = []
    @State private var isTransitioning = false
    @State private var showValidationError = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Welcome to\nDailyFlo",
            subtitle: "Your personal cycle companion for mind, body, and soul wellness.",
            imageName: nil,
            inputType: .none
        ),
        OnboardingPage(
            id: 1,
            title: "What's your name?",
            subtitle: "We'll personalize your experience.",
            imageName: nil,
            inputType: .textField(placeholder: "Enter your name", keyboardType: .default)
        ),
        OnboardingPage(
            id: 2,
            title: "When were you\nborn?",
            subtitle: "DailyFlo is for ages 13 and up.",
            imageName: nil,
            inputType: .datePicker
        ),
        OnboardingPage(
            id: 3,
            title: "When did your\nlast period start?",
            subtitle: "This helps us calculate your cycle phases.",
            imageName: nil,
            inputType: .datePicker
        ),
        OnboardingPage(
            id: 4,
            title: "How long is your\ntypical cycle?",
            subtitle: "From the first day of one period to the first day of the next.",
            imageName: nil,
            inputType: .numberPicker(range: 21...35, unit: "days")
        ),
        OnboardingPage(
            id: 5,
            title: "How many days does\nyour period last?",
            subtitle: "This helps us track your menstrual phase.",
            imageName: nil,
            inputType: .numberPicker(range: 3...7, unit: "days")
        ),
        OnboardingPage(
            id: 6,
            title: "What are your\nwellness goals?",
            subtitle: "Select all that apply.",
            imageName: nil,
            inputType: .multiSelect(options: [
                "Track my cycle",
                "Understand my moods",
                "Optimize my energy",
                "Plan for fertility",
                "Manage PMS symptoms",
                "Mindfulness & meditation"
            ])
        ),
        OnboardingPage(
            id: 7,
            title: "Any symptoms you'd\nlike to track?",
            subtitle: "We'll remind you to log these.",
            imageName: nil,
            inputType: .multiSelect(options: [
                "Cramps",
                "Bloating",
                "Headaches",
                "Mood changes",
                "Fatigue",
                "Breast tenderness",
                "Acne",
                "Back pain"
            ])
        ),
        OnboardingPage(
            id: 8,
            title: "Your Four Phases",
            subtitle: "Your cycle has 4 distinct phases, each with unique characteristics.",
            imageName: nil,
            inputType: .none
        ),
        OnboardingPage(
            id: 9,
            title: "You're all set!",
            subtitle: "Let's begin your journey to cycle-synced living.",
            imageName: nil,
            inputType: .none
        )
    ]

    /// Age in whole years, used for the 13+ gate on page 2.
    private var ageInYears: Int {
        let comps = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
        return comps.year ?? 0
    }

    var body: some View {
        ZStack {
            // Background
            Color.floCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator
                    .padding(.top, FloSpacing.lg)
                    .padding(.bottom, FloSpacing.md)

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages) { page in
                        OnboardingPageView(
                            page: page,
                            userName: $userName,
                            birthDate: $birthDate,
                            lastPeriodDate: $lastPeriodDate,
                            cycleLength: $cycleLength,
                            periodLength: $periodLength,
                            selectedGoals: $selectedGoals,
                            selectedSymptoms: $selectedSymptoms,
                            showValidationError: $showValidationError
                        )
                        .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(FloAnimation.springGentle, value: currentPage)

                // Navigation buttons
                navigationButtons
                    .padding(.bottom, FloSpacing.xxl)
            }
        }
        .dismissKeyboardOnTap()
    }

    // MARK: - Progress Indicator
    private var progressIndicator: some View {
        HStack(spacing: FloSpacing.xs) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index <= currentPage ? Color.floSage : Color.floGray.opacity(0.25))
                    .frame(width: index == currentPage ? 28 : 8, height: 8)
                    .animation(FloAnimation.springSnappy, value: currentPage)
            }
        }
        .padding(.horizontal, FloSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(currentPage + 1) of \(pages.count)")
    }

    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: FloSpacing.md) {
            // Back button (hidden on first page)
            if currentPage > 0 {
                Button(action: goBack) {
                    HStack(spacing: FloSpacing.xs) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Back")
                    }
                    .font(.floButton)
                    .foregroundColor(.floGray)
                    .padding(.horizontal, FloSpacing.lg)
                    .padding(.vertical, FloSpacing.md)
                }
                .buttonStyle(.floPressed)
                .accessibilityLabel("Go back to previous step")
            } else {
                Spacer()
            }

            Spacer()

            // Next/Done button
            Button(action: goNext) {
                HStack(spacing: FloSpacing.xs) {
                    Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .font(.floButton)
                .foregroundColor(.white)
                .padding(.horizontal, FloSpacing.xl)
                .padding(.vertical, FloSpacing.md)
                .background(canProceed ? Color.floSage : Color.floGray.opacity(0.4))
                .clipShape(Capsule())
                .shadow(color: canProceed ? Color.floSage.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.floPressed)
            .disabled(!canProceed || isTransitioning)
            .accessibilityLabel(currentPage == pages.count - 1 ? "Complete setup and get started" : "Continue to next step")
        }
        .padding(.horizontal, FloSpacing.lg)
    }

    // MARK: - Validation
    private var canProceed: Bool {
        switch pages[currentPage].inputType {
        case .textField:
            return !userName.trimmingCharacters(in: .whitespaces).isEmpty
        case .datePicker:
            // Birth-date page enforces the 13+ gate. Last-period page (id 3) is unrestricted.
            if currentPage == 2 {
                return ageInYears >= 13
            }
            return true
        case .multiSelect:
            if currentPage == 6 {
                return !selectedGoals.isEmpty
            }
            return true // Symptoms are optional
        default:
            return true
        }
    }

    // MARK: - Navigation Actions
    private func goBack() {
        guard currentPage > 0, !isTransitioning else { return }
        FloHaptics.light()
        isTransitioning = true
        withAnimation(FloAnimation.springGentle) {
            currentPage -= 1
        }
        showValidationError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isTransitioning = false
        }
    }

    private func goNext() {
        guard !isTransitioning else { return }

        if !canProceed {
            showValidationError = true
            FloHaptics.warning()
            return
        }

        FloHaptics.light()
        isTransitioning = true
        showValidationError = false

        if currentPage < pages.count - 1 {
            withAnimation(FloAnimation.springGentle) {
                currentPage += 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isTransitioning = false
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        FloHaptics.success()

        // Save user preferences to UserDefaults. These also serve as the local
        // cache for CycleManager / ProfileMainView. The pending flag tells
        // CycleManager's auth observer to upsert this payload to Supabase the
        // moment the user actually signs in.
        UserDefaults.standard.set(userName.trimmingCharacters(in: .whitespaces), forKey: "userName")
        UserDefaults.standard.set(birthDate, forKey: "birthDate")
        UserDefaults.standard.set(lastPeriodDate, forKey: "lastPeriodDate")
        UserDefaults.standard.set(cycleLength, forKey: "cycleLength")
        UserDefaults.standard.set(periodLength, forKey: "periodLength")
        UserDefaults.standard.set(Array(selectedGoals), forKey: "selectedGoals")
        UserDefaults.standard.set(Array(selectedSymptoms), forKey: "selectedSymptoms")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "pendingOnboardingPayload")

        withAnimation(FloAnimation.easeOutMedium) {
            isOnboardingComplete = true
        }
    }
}

// MARK: - Individual Page View
struct OnboardingPageView: View {
    let page: OnboardingPage
    @Binding var userName: String
    @Binding var birthDate: Date
    @Binding var lastPeriodDate: Date
    @Binding var cycleLength: Int
    @Binding var periodLength: Int
    @Binding var selectedGoals: Set<String>
    @Binding var selectedSymptoms: Set<String>
    @Binding var showValidationError: Bool

    @FocusState private var isTextFieldFocused: Bool
    @State private var hasAppeared = false

    /// True when the entered birth date implies an age under 13.
    private var ageGateFailed: Bool {
        let comps = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
        return (comps.year ?? 0) < 13
    }

    var body: some View {
        VStack(spacing: FloSpacing.xl) {
            Spacer()

            // Special layouts for welcome, phases, and completion
            if page.id == 0 {
                welcomeElement
                    .scaleFadeIn(delay: hasAppeared ? 0 : 0.1, from: 0.85)
            } else if page.id == 8 {
                phaseOverviewElement
                    .scaleFadeIn(delay: hasAppeared ? 0 : 0.1, from: 0.95)
            } else if page.id == 9 {
                completionElement
                    .scaleFadeIn(delay: hasAppeared ? 0 : 0.1, from: 0.85)
            }

            // Title
            Text(page.title)
                .font(page.id == 0 ? .floDisplayLarge : .floDisplayMedium)
                .foregroundColor(.floCharcoal)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FloSpacing.lg)
                .fadeIn(delay: hasAppeared ? 0 : 0.15)
                .accessibilityAddTraits(.isHeader)

            // Subtitle
            Text(page.subtitle)
                .font(.floBodyMedium)
                .foregroundColor(.floGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FloSpacing.xl)
                .lineSpacing(4)
                .fadeIn(delay: hasAppeared ? 0 : 0.2)

            // Input area
            inputArea
                .padding(.horizontal, FloSpacing.lg)
                .padding(.top, FloSpacing.md)
                .fadeIn(delay: hasAppeared ? 0 : 0.25)

            Spacer()
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Welcome Element (Logo + Brand)
    @ViewBuilder
    private var welcomeElement: some View {
        VStack(spacing: FloSpacing.md) {
            // App icon
            Image("AppIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.floSage.opacity(0.3), radius: 16, x: 0, y: 8)
        }
        .padding(.bottom, FloSpacing.md)
        .accessibilityHidden(true)
    }

    // MARK: - Phase Overview Element
    @ViewBuilder
    private var phaseOverviewElement: some View {
        VStack(spacing: FloSpacing.sm) {
            ForEach(CyclePhase.allCases, id: \.self) { phase in
                HStack(spacing: FloSpacing.md) {
                    // Phase number circle
                    ZStack {
                        Circle()
                            .fill(phase.color)
                            .frame(width: 44, height: 44)

                        Text(phase.number)
                            .font(.floLabel)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }

                    // Phase info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.name)
                            .font(.floBodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(.floCharcoal)

                        Text(phase.subtitle)
                            .font(.floCaption)
                            .foregroundColor(.floGray)
                            .tracking(0.5)
                    }

                    Spacer()

                    // Day range
                    Text("Days \(phase.dayRange.lowerBound)-\(phase.dayRange.upperBound)")
                        .font(.floCaption)
                        .foregroundColor(.floGray)
                }
                .padding(.horizontal, FloSpacing.md)
                .padding(.vertical, FloSpacing.sm)
                .background(phase.backgroundColor.opacity(0.6))
                .cornerRadius(FloRadius.md)
            }
        }
        .padding(.horizontal, FloSpacing.md)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Completion Element
    @ViewBuilder
    private var completionElement: some View {
        VStack(spacing: FloSpacing.md) {
            // Success checkmark
            ZStack {
                Circle()
                    .fill(Color.floSage.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Color.floSage)
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.floSage.opacity(0.3), radius: 12, x: 0, y: 6)

                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.bottom, FloSpacing.sm)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var inputArea: some View {
        switch page.inputType {
        case .none:
            EmptyView()

        case .textField(let placeholder, let keyboardType):
            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                TextField(placeholder, text: $userName)
                    .font(.floBodyLarge)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(FloRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloRadius.md)
                            .stroke(
                                showValidationError && userName.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.floError
                                    : (isTextFieldFocused ? Color.floSage : Color.floGray.opacity(0.3)),
                                lineWidth: isTextFieldFocused ? 2 : 1
                            )
                    )
                    .keyboardType(keyboardType)
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isTextFieldFocused = false
                    }
                    .accessibilityLabel("Your name")

                if showValidationError && userName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Please enter your name")
                        .font(.floCaption)
                        .foregroundColor(.floError)
                        .padding(.leading, FloSpacing.xs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(FloAnimation.easeOutQuick, value: showValidationError)
            .animation(FloAnimation.easeOutQuick, value: isTextFieldFocused)

        case .datePicker:
            VStack(spacing: FloSpacing.md) {
                DatePicker(
                    "",
                    selection: page.id == 2 ? $birthDate : $lastPeriodDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .accessibilityLabel(page.id == 2 ? "Birth date" : "Last period start date")

                if showValidationError, page.id == 2, ageGateFailed {
                    Text("DailyFlo is for ages 13 and up. Please double-check the date you entered.")
                        .font(.floCaption)
                        .foregroundColor(.floError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, FloSpacing.lg)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(FloAnimation.easeOutQuick, value: showValidationError)

        case .numberPicker(let range, let unit):
            VStack(spacing: FloSpacing.md) {
                Picker("", selection: page.id == 4 ? $cycleLength : $periodLength) {
                    ForEach(range, id: \.self) { num in
                        Text("\(num) \(unit)")
                            .tag(num)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .accessibilityLabel(page.id == 4 ? "Cycle length in days" : "Period length in days")
            }

        case .multiSelect(let options):
            VStack(alignment: .leading, spacing: FloSpacing.xs) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FloSpacing.sm) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        MultiSelectButton(
                            title: option,
                            isSelected: page.id == 6 ? selectedGoals.contains(option) : selectedSymptoms.contains(option),
                            action: {
                                FloHaptics.selection()
                                withAnimation(FloAnimation.springSnappy) {
                                    if page.id == 6 {
                                        if selectedGoals.contains(option) {
                                            selectedGoals.remove(option)
                                        } else {
                                            selectedGoals.insert(option)
                                        }
                                    } else {
                                        if selectedSymptoms.contains(option) {
                                            selectedSymptoms.remove(option)
                                        } else {
                                            selectedSymptoms.insert(option)
                                        }
                                    }
                                }
                            }
                        )
                        .animation(FloAnimation.stagger(index: index), value: page.id)
                    }
                }

                if showValidationError && page.id == 6 && selectedGoals.isEmpty {
                    Text("Please select at least one goal")
                        .font(.floCaption)
                        .foregroundColor(.floError)
                        .padding(.leading, FloSpacing.xs)
                        .padding(.top, FloSpacing.xs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(FloAnimation.easeOutQuick, value: showValidationError)

        case .singleSelect(let options):
            VStack(spacing: FloSpacing.sm) {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        FloHaptics.selection()
                    }) {
                        Text(option)
                            .font(.floBodyMedium)
                            .foregroundColor(.floCharcoal)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(FloRadius.md)
                            .shadow(color: FloShadow.small.color, radius: FloShadow.small.radius, x: 0, y: FloShadow.small.y)
                    }
                    .buttonStyle(.floPressed)
                }
            }
        }
    }
}

// MARK: - Multi-Select Button
struct MultiSelectButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FloSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .floSage : .floGray.opacity(0.5))

                Text(title)
                    .font(.floBodySmall)
                    .foregroundColor(.floCharcoal)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, FloSpacing.md)
            .padding(.vertical, FloSpacing.sm + 2)
            .background(isSelected ? Color.floSage.opacity(0.12) : Color.white)
            .cornerRadius(FloRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.md)
                    .stroke(isSelected ? Color.floSage : Color.floGray.opacity(0.25), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(FloAnimation.springSnappy, value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}
