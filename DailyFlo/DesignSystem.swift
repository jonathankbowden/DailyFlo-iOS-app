//
//  DesignSystem.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI
import UIKit

// MARK: - Colors
extension Color {
    // Primary brand colors
    static let floSage = Color(hex: "8BA888")           // Main sage green
    static let floTeal = Color(hex: "5B7B7A")           // Darker teal for accents
    static let floMint = Color(hex: "B8D4B8")           // Light mint for backgrounds

    // Neutral colors
    static let floCream = Color(hex: "FAF9F6")          // Warm white background
    static let floCharcoal = Color(hex: "2D2D2D")       // Dark text
    static let floGray = Color(hex: "6B7280")           // Secondary text
    static let floLightGray = Color(hex: "E5E5E5")      // Borders and dividers

    // Phase colors (for cycle tracking) — no pinks/yellows per product rule.
    static let phaseMenstrual = Color(hex: "6FA98C")    // Deeper mint-green
    static let phaseFollicular = Color(hex: "8BA888")   // Sage green
    static let phaseOvulation = Color(hex: "8FB9C2")    // Dusty teal-blue
    static let phaseLuteal = Color(hex: "7BA3B5")       // Soft blue

    // Emotion colors (Chip Dodd framework)
    static let emotionGlad = Color(hex: "8BA888")       // Green
    static let emotionSad = Color(hex: "7BA3B5")        // Blue
    static let emotionAngry = Color(hex: "C97C7C")      // Red
    static let emotionFear = Color(hex: "9B8BB5")       // Purple

    // Activity indicator dot colors
    static let dotJournaled = Color(hex: "40676E")      // Dark teal - journaling
    static let dotFeelings = Color(hex: "000000")       // Black - selected feelings
    static let dotMeditated = Color(hex: "BFD7DB")      // Light mint - meditated

    // Semantic colors
    static let floSuccess = Color(hex: "4CAF50")        // Success green
    static let floWarning = Color(hex: "FF9800")        // Warning orange
    static let floError = Color(hex: "F44336")          // Error red

    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
extension Font {
    // Display/Headers - Lunary font
    static let floDisplayLarge = Font.custom("LUNARY free", size: 34).weight(.regular)
    static let floDisplayMedium = Font.custom("LUNARY free", size: 28).weight(.regular)
    static let floDisplaySmall = Font.custom("LUNARY free", size: 22).weight(.regular)

    // Body text - system font for readability with optimized line height
    static let floBodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    static let floBodyMedium = Font.system(size: 15, weight: .regular, design: .default)
    static let floBodySmall = Font.system(size: 13, weight: .regular, design: .default)

    // Labels and buttons
    static let floLabel = Font.system(size: 12, weight: .medium, design: .default)
    static let floButton = Font.system(size: 16, weight: .semibold, design: .default)

    // Caption for small annotations
    static let floCaption = Font.system(size: 11, weight: .regular, design: .default)

    // Serif font for elegant headings
    static func floSerif(size: CGFloat) -> Font {
        Font.custom("Times New Roman", size: size)
    }
}


// MARK: - Spacing (8pt grid system for pixel-perfect alignment)
struct FloSpacing {
    static let xxs: CGFloat = 2  // Micro spacing
    static let xs: CGFloat = 4   // Extra small
    static let sm: CGFloat = 8   // Small
    static let md: CGFloat = 16  // Medium (base unit)
    static let lg: CGFloat = 24  // Large
    static let xl: CGFloat = 32  // Extra large
    static let xxl: CGFloat = 48 // Extra extra large
    static let xxxl: CGFloat = 64 // Maximum spacing
}

// MARK: - Corner Radius
struct FloRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999
}

// MARK: - Shadows
struct FloShadow {
    static let small = Shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    static let medium = Shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    static let large = Shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
    static let elevated = Shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - Icon Names (SF Symbols)
struct FloIcons {
    static let calendar = "calendar"
    static let device = "rectangle.portrait"
    static let person = "person"
    static let pause = "pause.circle"
    static let plus = "plus"
}

// MARK: - Animation Presets
struct FloAnimation {
    // Spring animations for natural feel
    static let springGentle = Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    static let springBouncy = Animation.spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0)
    static let springSnappy = Animation.spring(response: 0.3, dampingFraction: 0.85, blendDuration: 0)

    // Easing animations
    static let easeOutQuick = Animation.easeOut(duration: 0.2)
    static let easeOutMedium = Animation.easeOut(duration: 0.35)
    static let easeOutSlow = Animation.easeOut(duration: 0.5)

    static let easeInOutQuick = Animation.easeInOut(duration: 0.2)
    static let easeInOutMedium = Animation.easeInOut(duration: 0.35)
    static let easeInOutSlow = Animation.easeInOut(duration: 0.5)

    // Interactive animations
    static let buttonPress = Animation.easeOut(duration: 0.1)
    static let tabSwitch = Animation.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)
    static let cardExpand = Animation.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0)
    static let fadeIn = Animation.easeOut(duration: 0.25)

    // Staggered animation helper
    static func stagger(index: Int, baseDelay: Double = 0.05) -> Animation {
        Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
            .delay(Double(index) * baseDelay)
    }
}

// MARK: - Haptic Feedback
struct FloHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    // Convenience methods
    static func light() { impact(.light) }
    static func medium() { impact(.medium) }
    static func heavy() { impact(.heavy) }
    static func success() { notification(.success) }
    static func warning() { notification(.warning) }
    static func error() { notification(.error) }
}

// MARK: - View Modifiers

// Card style modifier
struct FloCardStyle: ViewModifier {
    var padding: CGFloat = FloSpacing.lg
    var cornerRadius: CGFloat = FloRadius.lg
    var shadowStyle: FloShadow.Shadow = FloShadow.medium

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.white)
            .cornerRadius(cornerRadius)
            .shadow(
                color: shadowStyle.color,
                radius: shadowStyle.radius,
                x: shadowStyle.x,
                y: shadowStyle.y
            )
    }
}

extension View {
    func floCard(
        padding: CGFloat = FloSpacing.lg,
        cornerRadius: CGFloat = FloRadius.lg,
        shadow: FloShadow.Shadow = FloShadow.medium
    ) -> some View {
        modifier(FloCardStyle(padding: padding, cornerRadius: cornerRadius, shadowStyle: shadow))
    }

    func floCardSubtle(padding: CGFloat = FloSpacing.md) -> some View {
        modifier(FloCardStyle(padding: padding, cornerRadius: FloRadius.md, shadowStyle: FloShadow.small))
    }
}

// Button press effect modifier
struct FloPressedStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var opacity: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? opacity : 1.0)
            .animation(FloAnimation.buttonPress, value: configuration.isPressed)
    }
}

// Primary button style
struct FloPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.floButton)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FloSpacing.md)
            .background(isDisabled ? Color.floGray.opacity(0.5) : Color.floSage)
            .cornerRadius(FloRadius.full)
            .scaleEffect(configuration.isPressed && !isDisabled ? 0.97 : 1.0)
            .opacity(configuration.isPressed && !isDisabled ? 0.9 : 1.0)
            .animation(FloAnimation.buttonPress, value: configuration.isPressed)
    }
}

// Secondary button style
struct FloSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.floButton)
            .foregroundColor(.floSage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, FloSpacing.md)
            .background(Color.white)
            .cornerRadius(FloRadius.full)
            .overlay(
                RoundedRectangle(cornerRadius: FloRadius.full)
                    .stroke(Color.floSage, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(FloAnimation.buttonPress, value: configuration.isPressed)
    }
}

// Tertiary/ghost button style
struct FloTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.floButton)
            .foregroundColor(.floSage)
            .padding(.vertical, FloSpacing.sm)
            .padding(.horizontal, FloSpacing.md)
            .background(configuration.isPressed ? Color.floSage.opacity(0.1) : Color.clear)
            .cornerRadius(FloRadius.sm)
            .animation(FloAnimation.buttonPress, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FloPrimaryButtonStyle {
    static var floPrimary: FloPrimaryButtonStyle { FloPrimaryButtonStyle() }
    static func floPrimary(disabled: Bool) -> FloPrimaryButtonStyle { FloPrimaryButtonStyle(isDisabled: disabled) }
}

extension ButtonStyle where Self == FloSecondaryButtonStyle {
    static var floSecondary: FloSecondaryButtonStyle { FloSecondaryButtonStyle() }
}

extension ButtonStyle where Self == FloTertiaryButtonStyle {
    static var floTertiary: FloTertiaryButtonStyle { FloTertiaryButtonStyle() }
}

extension ButtonStyle where Self == FloPressedStyle {
    static var floPressed: FloPressedStyle { FloPressedStyle() }
}

// MARK: - Hit Target (Tap Area)

/// Guarantees a reliable, fully hit-testable tap area without changing appearance.
///
/// - Enforces the Apple HIG minimum **44×44pt** touch target. Content stays visually
///   centered, so a small glyph doesn't move — only the invisible tappable frame grows.
/// - Applies `contentShape(Rectangle())` so the **entire frame** is tappable, not just
///   the label text/glyph pixels (the root cause of "only the text is tappable").
/// - Optionally expands to full width for buttons the design lays out edge-to-edge.
///
/// This is purely additive: no background, color, font, or visible layout change to the
/// control. Pressed/disabled *visuals* remain owned by the button's own `ButtonStyle`
/// (e.g. `.floPrimary`); this modifier only affects hit area. `.disabled(true)` still
/// correctly suppresses taps — SwiftUI removes the view from hit testing regardless of
/// `contentShape`, so a disabled control does not become tappable.
///
/// Apply it to the `Button` (or the button's `label`) at the call site:
/// ```swift
/// Button { … } label: { Image(systemName: "xmark") }
///     .buttonStyle(.floPressed)
///     .floHitTarget()               // icon/small button → 44×44 min
///
/// Button("Continue") { … }
///     .buttonStyle(.floPrimary)
///     .floHitTargetFullWidth()      // edge-to-edge, 44pt min height
/// ```
struct FloHitTarget: ViewModifier {
    var fullWidth: Bool = false
    var minSize: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: fullWidth ? nil : minSize,
                maxWidth: fullWidth ? .infinity : nil,
                minHeight: minSize
            )
            .contentShape(Rectangle())
    }
}

extension View {
    /// Standard tappable control: enforces a min 44×44pt touch target and makes the whole
    /// frame hit-testable. Use for icon buttons and any small/short control.
    func floHitTarget(minSize: CGFloat = 44) -> some View {
        modifier(FloHitTarget(fullWidth: false, minSize: minSize))
    }

    /// Full-width tappable control: spans the available width, keeps a min 44pt height, and
    /// makes the whole frame hit-testable. Use where the design calls for edge-to-edge buttons.
    func floHitTargetFullWidth(minSize: CGFloat = 44) -> some View {
        modifier(FloHitTarget(fullWidth: true, minSize: minSize))
    }
}

// MARK: - Shimmer Loading Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: phase * geometry.size.width * 2 - geometry.size.width)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Fade In Animation
struct FadeInModifier: ViewModifier {
    @State private var isVisible = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .onAppear {
                withAnimation(FloAnimation.easeOutMedium.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }
}

// MARK: - Scale Fade In Animation
struct ScaleFadeInModifier: ViewModifier {
    @State private var isVisible = false
    let delay: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : scale)
            .onAppear {
                withAnimation(FloAnimation.springGentle.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func scaleFadeIn(delay: Double = 0, from scale: CGFloat = 0.9) -> some View {
        modifier(ScaleFadeInModifier(delay: delay, scale: scale))
    }
}

// MARK: - Haptic Tap Modifier
extension View {
    func hapticTap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                FloHaptics.impact(style)
            }
        )
    }
}

// MARK: - Accessibility
extension View {
    func floAccessibility(
        label: String,
        hint: String? = nil,
        traits: AccessibilityTraits = []
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(traits)
    }

    func floAccessibilityButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Loading Indicator
struct FloLoadingIndicator: View {
    @State private var isAnimating = false
    var size: CGFloat = 24
    var color: Color = .floSage
    var lineWidth: CGFloat = 3

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Divider
struct FloDivider: View {
    var color: Color = Color.floGray.opacity(0.3)
    var thickness: CGFloat = 1

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: thickness)
    }
}

// MARK: - Conditional Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Blur Background
struct FloBlurBackground: View {
    var style: UIBlurEffect.Style = .systemThinMaterial

    var body: some View {
        VisualEffectView(style: style)
            .ignoresSafeArea()
    }
}

struct VisualEffectView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Toast Notification Style
struct FloToastStyle: ViewModifier {
    let type: ToastType

    enum ToastType {
        case success, warning, error, info

        var backgroundColor: Color {
            switch self {
            case .success: return Color.floSuccess
            case .warning: return Color.floWarning
            case .error: return Color.floError
            case .info: return Color.floSage
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    func body(content: Content) -> some View {
        HStack(spacing: FloSpacing.sm) {
            Image(systemName: type.icon)
                .foregroundColor(.white)
            content
                .font(.floBodyMedium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, FloSpacing.lg)
        .padding(.vertical, FloSpacing.md)
        .background(type.backgroundColor)
        .cornerRadius(FloRadius.lg)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func floToast(_ type: FloToastStyle.ToastType) -> some View {
        modifier(FloToastStyle(type: type))
    }
}

// MARK: - Rounded Corner Shape
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Keyboard Dismiss
extension View {
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - Hit Target Debug Overlay (previews only)

/// Tints a control's actual laid-out frame so the tap area is visible during development.
/// Also draws the 44×44pt HIG floor as a dashed guide. Debug aid only — never ship on a
/// real control. Kept `fileprivate` so it can't leak into app code.
private struct HitAreaDebugOverlay: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.floError.opacity(0.18))     // fills the real (hit-testable) frame
            .overlay(
                Rectangle()
                    .strokeBorder(Color.floError.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
            )
            .overlay(
                Rectangle()
                    .strokeBorder(Color.floTeal.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2]))
                    .frame(width: 44, height: 44)         // the HIG 44×44 floor, for comparison
            )
    }
}

private extension View {
    /// Preview-only: visualize the frame this view actually occupies (its tap area).
    func debugHitArea() -> some View { modifier(HitAreaDebugOverlay()) }
}

#Preview("Hit Target — tap area") {
    // Red fill = the frame that is actually hit-testable. Teal dashes = the 44×44 HIG floor.
    VStack(alignment: .leading, spacing: FloSpacing.xl) {

        // Icon buttons — the reported bug vs. the fix.
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("Icon button").font(.floLabel).foregroundColor(.floGray)
            HStack(spacing: FloSpacing.xxl) {
                VStack(spacing: FloSpacing.sm) {
                    Button { } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.floPressed)
                    .debugHitArea()
                    Text("before").font(.floCaption).foregroundColor(.floGray)
                }
                VStack(spacing: FloSpacing.sm) {
                    Button { } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.floPressed)
                    .floHitTarget()                // ← expands to 44×44, glyph unmoved
                    .debugHitArea()
                    Text("after").font(.floCaption).foregroundColor(.floSage)
                }
            }
        }

        // Small ghost/text button.
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("Ghost button").font(.floLabel).foregroundColor(.floGray)
            HStack(spacing: FloSpacing.xxl) {
                VStack(spacing: FloSpacing.sm) {
                    Button("Skip") { }.buttonStyle(.floTertiary).debugHitArea()
                    Text("before").font(.floCaption).foregroundColor(.floGray)
                }
                VStack(spacing: FloSpacing.sm) {
                    Button("Skip") { }.buttonStyle(.floTertiary).floHitTarget().debugHitArea()
                    Text("after").font(.floCaption).foregroundColor(.floSage)
                }
            }
        }

        // Full-width primary — already fine, shown to confirm no visual change.
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("Full-width button").font(.floLabel).foregroundColor(.floGray)
            Button("Continue") { }
                .buttonStyle(.floPrimary)
                .floHitTargetFullWidth()
                .debugHitArea()
        }

        // Disabled — must NOT become tappable even with the modifier applied.
        VStack(alignment: .leading, spacing: FloSpacing.md) {
            Text("Disabled (still not tappable)").font(.floLabel).foregroundColor(.floGray)
            Button { } label: {
                Image(systemName: "trash").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.floPressed)
            .floHitTarget()
            .disabled(true)
            .debugHitArea()
        }
    }
    .padding(FloSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.floCream)
}



