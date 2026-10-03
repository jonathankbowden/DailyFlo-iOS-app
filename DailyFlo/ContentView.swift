//
//  ContentView.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

struct ContentView: View {
    // Tabs, left to right: 0=Calendar, 1=Journal, [+ FAB], 2=Profile, 3=Pause.
    // Calendar is the default tab on launch — it's the app's home screen.
    @State private var selectedTab = 0
    @State private var showJournalEntry = false

    // Single Pro gate for the whole app. Entitlement is checked once, here at
    // the top level, right after onboarding/sign-in land the user on the tabs —
    // never per feature. `hasEvaluatedProGate` keeps it to one evaluation per
    // launch. Day 5 moves this gate to the end of onboarding; keeping it as one
    // modifier on the tab container is what makes that move a lift-and-shift.
    private let subs = SubscriptionManager.shared
    @State private var showProGate = false
    @State private var hasEvaluatedProGate = false

    var body: some View {
        // Root GeometryReader reads the device's real bottom safe-area inset
        // (don't hardcode 34) so the bar can extend its background through it.
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            ZStack {
                // Main content
                TabView(selection: $selectedTab) {
                    CalendarView()
                        .tag(0)

                    JournalView()
                        .tag(1)

                    ProfileMainView()
                        .tag(2)

                    MeditationView()
                        .tag(3)
                }

                // Custom bottom bar with the center + cutout, pinned to the
                // bottom. Its background extends through the bottom safe area.
                VStack {
                    Spacer()
                    FloTabBar(selectedTab: $selectedTab, bottomInset: bottomInset) {
                        showJournalEntry = true
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sheet(isPresented: $showJournalEntry) {
            JournalEntryView(
                journalManager: JournalManager.shared,
                onDismiss: {
                    showJournalEntry = false
                }
            )
        }
        .task {
            await evaluateProGate()
        }
        .onChange(of: subs.isPro) { _, isPro in
            // Purchased or restored while the gate is up — drop it immediately.
            if isPro { showProGate = false }
        }
        .sheet(isPresented: $showProGate) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    /// Resolves entitlement once per launch and presents the paywall when the
    /// user has neither an active subscription nor an active trial. In
    /// RevenueCat an in-progress free trial keeps the entitlement `isActive`,
    /// so `isPro` is true throughout the trial — this gate only fires once the
    /// trial has lapsed (or was never started). We refresh CustomerInfo first
    /// so a Pro/trial user never sees the paywall flash before state settles.
    private func evaluateProGate() async {
        guard !hasEvaluatedProGate else { return }
        hasEvaluatedProGate = true
        await subs.refreshCustomerInfo()
        if !subs.isPro {
            showProGate = true
        }
    }

}

// MARK: - Custom Tab Bar Button Style
struct TabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(FloAnimation.buttonPress, value: configuration.isPressed)
    }
}

// MARK: - Bottom bar

/// The charcoal bottom bar as a single filled shape with a circular cutout
/// around the center +. The notch is concave (page background shows through
/// the ring), and each shoulder — where the flat top meets the cutout — is
/// rounded with a small fillet arc tangent to both the top edge and the
/// cutout circle, so the transition reads smooth on any background.
///
/// Coordinates are in the shape's own rect: `minY` is the bar's top edge and
/// the cutout circle's center sits `plusCenterAboveTop` *above* it.
struct FloTabBarShape: Shape {
    var cutoutRadius: CGFloat          // 44.5 → 89pt diameter
    var filletRadius: CGFloat          // ~8pt shoulder fillet
    var plusCenterAboveTop: CGFloat    // + center is this far above the top edge

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = rect.minY
        let cx = rect.midX
        // Cutout circle center, above the top edge.
        let center = CGPoint(x: cx, y: top - plusCenterAboveTop)
        let R = cutoutRadius
        let f = filletRadius

        // Fillet circle: tangent to the top edge from inside the bar (center at
        // y = top + f) and externally tangent to the cutout circle
        // (center-to-center distance = R + f). Solve for its horizontal offset.
        let d = R + f
        let dy = f + plusCenterAboveTop          // fillet center y − cutout center y
        let dx = (d * d - dy * dy).squareRoot()  // horizontal offset from cx

        // Shoulder points where the fillet meets the flat top edge.
        let leftShoulderTop = CGPoint(x: cx - dx, y: top)
        let rightShoulderTop = CGPoint(x: cx + dx, y: top)

        // Fillet circle centers.
        let leftFillet = CGPoint(x: cx - dx, y: top + f)
        let rightFillet = CGPoint(x: cx + dx, y: top + f)

        // Tangent points where each fillet meets the cutout circle: along the
        // line from the cutout center toward the fillet center, R out.
        let ux = dx / d, uy = dy / d
        let leftTangent = CGPoint(x: center.x - R * ux, y: center.y + R * uy)
        let rightTangent = CGPoint(x: center.x + R * ux, y: center.y + R * uy)

        func angle(of point: CGPoint, from c: CGPoint) -> Angle {
            .radians(atan2(point.y - c.y, point.x - c.x))
        }

        // Outline, left → right across the top, dipping through the cutout.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: leftShoulderTop)
        path.addArc(center: leftFillet, radius: f,
                    startAngle: angle(of: leftShoulderTop, from: leftFillet),
                    endAngle: angle(of: leftTangent, from: leftFillet),
                    clockwise: false)
        path.addArc(center: center, radius: R,
                    startAngle: angle(of: leftTangent, from: center),
                    endAngle: angle(of: rightTangent, from: center),
                    clockwise: true)
        path.addArc(center: rightFillet, radius: f,
                    startAngle: angle(of: rightTangent, from: rightFillet),
                    endAngle: angle(of: rightShoulderTop, from: rightFillet),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Bottom navigation bar: Calendar · Journal · + · Profile · Pause. The +
/// triggers a new entry for today via `onPlus`; the four tabs drive
/// `selectedTab`. Built on `FloTabBarShape` so the cutout works on any
/// background. All measurements are the Figma "01 Calendar" reference values;
/// horizontal positions are derived from the live width (five equal columns),
/// never a hardcoded screen size.
struct FloTabBar: View {
    @Binding var selectedTab: Int
    /// Device bottom safe-area inset. The bar's content lives in the top
    /// `barHeight` points (where the icons/capsule sit); the charcoal
    /// background is extended by this inset so the Shape reaches the physical
    /// screen edge instead of stopping above the home indicator.
    var bottomInset: CGFloat = 0
    let onPlus: () -> Void

    // Reference measurements (points), bar-top relative.
    private let barHeight: CGFloat = 122
    private let plusDiameter: CGFloat = 72
    private let cutoutRadius: CGFloat = 44.5     // 89pt diameter → 8.5pt ring
    private let plusCenterAboveTop: CGFloat = 6
    private let filletRadius: CGFloat = 8
    private let iconSize: CGFloat = 24
    private let iconTop: CGFloat = 33            // icon center below the bar top
    private let capsuleTop: CGFloat = 112        // capsule center below the bar top
    private let capsuleSize = CGSize(width: 32, height: 6)

    @State private var plusScale: CGFloat = 1.0

    // Tab tag → column index in the five-column layout (column 2 is the +).
    private struct Tab: Identifiable {
        let tag: Int
        let column: Int
        let icon: String
        let label: String
        var id: Int { tag }
    }

    private let tabs: [Tab] = [
        Tab(tag: 0, column: 0, icon: "calendar", label: "Calendar, view your cycle"),
        Tab(tag: 1, column: 1, icon: "journal", label: "Journal, view your entries"),
        Tab(tag: 2, column: 3, icon: "partner", label: "Profile, your account and settings"),
        Tab(tag: 3, column: 4, icon: "pause", label: "Pause, guided meditation sessions")
    ]

    private func columnCenterX(_ column: Int, width: CGFloat) -> CGFloat {
        width * (CGFloat(column) + 0.5) / 5
    }

    private func column(forTag tag: Int) -> Int {
        tabs.first(where: { $0.tag == tag })?.column ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .topLeading) {
                FloTabBarShape(
                    cutoutRadius: cutoutRadius,
                    filletRadius: filletRadius,
                    plusCenterAboveTop: plusCenterAboveTop
                )
                .fill(Color.floCharcoal)

                // Sliding sage capsule under the selected tab.
                Capsule()
                    .fill(Color.floSage)
                    .frame(width: capsuleSize.width, height: capsuleSize.height)
                    .position(
                        x: columnCenterX(column(forTag: selectedTab), width: width),
                        y: capsuleTop
                    )
                    .animation(FloAnimation.tabSwitch, value: selectedTab)

                // Tab buttons.
                ForEach(tabs) { tab in
                    tabButton(tab, width: width)
                }

                // Center + button, its center 6pt above the bar's top edge.
                plusButton
                    .position(x: width / 2, y: -plusCenterAboveTop)
            }
        }
        .frame(height: barHeight + bottomInset)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }

    private func tabButton(_ tab: Tab, width: CGFloat) -> some View {
        let columnWidth = width / 5
        let isSelected = selectedTab == tab.tag
        return Button {
            guard selectedTab != tab.tag else { return }
            FloHaptics.selection()
            withAnimation(FloAnimation.tabSwitch) {
                selectedTab = tab.tag
            }
        } label: {
            ZStack {
                Color.clear
                Image(tab.icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundColor(isSelected ? .white : .floGray)
                    .position(x: columnWidth / 2, y: iconTop)
            }
            .frame(width: columnWidth, height: barHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabBarButtonStyle())
        .frame(width: columnWidth, height: barHeight)
        .position(x: columnCenterX(tab.column, width: width), y: barHeight / 2)
        .animation(FloAnimation.tabSwitch, value: isSelected)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var plusButton: some View {
        Button {
            FloHaptics.medium()
            withAnimation(FloAnimation.springBouncy) { plusScale = 0.9 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(FloAnimation.springBouncy) { plusScale = 1.0 }
            }
            onPlus()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.floSage)
                    .frame(width: plusDiameter, height: plusDiameter)
                Image(systemName: "plus")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(plusScale)
        }
        .accessibilityLabel("New entry")
        .accessibilityHint("Logs a journal entry for today")
    }
}

// MARK: - Tab Views

struct JournalView: View {
    var body: some View {
        JournalBaseView()
    }
}

/// Pause tab entry. The meditation player opens directly — Pro access is no
/// longer checked here. Entitlement is gated once at the top level (see the
/// `evaluateProGate` modifier on `ContentView`), so by the time the user can
/// reach this tab the single launch-level check has already run.
struct MeditationView: View {
    var body: some View {
        MeditationMainView()
    }
}

#Preview {
    ContentView()
}

#Preview("Bottom bar") {
    struct Demo: View {
        @State private var tab = 0
        var body: some View {
            ZStack {
                Color.floBackground.ignoresSafeArea()
                VStack {
                    Spacer()
                    FloTabBar(selectedTab: $tab) {}
                }
            }
        }
    }
    return Demo()
}
