//
//  FloComponents.swift
//  DailyFlo
//
//  Shared building blocks for the Summer 2026 restyle: the outlined caps
//  action button, the segmented caps tab row, close buttons, rules and the
//  sheet grabber. Values come from the design canvas; colors and shadows are
//  tokens in DesignSystem.swift.
//

import SwiftUI
import UIKit

// MARK: - Shadow helper

extension View {
    /// Applies one of the `FloShadow` presets.
    func floShadow(_ style: FloShadow.Shadow) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Outlined action button

/// The label of an `OutlinedActionButton`, split out so a `ShareLink` or
/// `PhotosPicker` can wear the same look.
struct OutlinedActionLabel: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                FloIcon(icon, size: 18)
                    .foregroundStyle(Color.floDeepTeal)
            }
            Text(title.uppercased())
                .font(.floInter(14, bold: true))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .floButtonShape()
        .contentShape(Rectangle())
    }
}

/// Outlined caps button used for LOG CYCLE, ADD ENTRY, EDIT ENTRY, SHARE and UPDATE.
/// Fills the width it is given; constrain it with `.frame(width:)` where the
/// design calls for a fixed width.
struct OutlinedActionButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            FloHaptics.light()
            action()
        } label: {
            OutlinedActionLabel(title: title, icon: icon)
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel(title.capitalized)
    }
}

// MARK: - Screen header

/// The shared top-of-screen header used by Calendar, Journal, Profile and
/// Pause. One row carries the 24×24 leading tab icon and the FLO wordmark;
/// below it, the display-serif title, an optional tracked uppercase eyebrow,
/// and an optional sentence-case subtitle. All spacing is fixed here so the
/// icon, title, eyebrow and subtitle never shift by a point when the user
/// switches tabs. Values taken from Brittany's "01 Calendar" frame (390pt).
struct ScreenHeader: View {
    let title: String
    var eyebrow: String? = nil
    var subtitle: String? = nil
    let leadingIcon: String
    /// Makes the leading icon tappable (the Calendar uses it to jump to today).
    var onLeadingIconTap: (() -> Void)? = nil

    /// LUNARY 36pt has a 39.6pt line height per Figma (node 2383:2152).
    /// `lineSpacing` only adds gaps *between* wrapped lines, so it's the delta
    /// over the font's own line height — a single-line title is unaffected.
    private var titleLineSpacing: CGFloat {
        let targetLineHeight: CGFloat = 39.6
        let naturalLineHeight = UIFont(name: Font.floSerifFaceName, size: 36)?.lineHeight ?? 36
        return max(0, targetLineHeight - naturalLineHeight)
    }

    private var leadingIconImage: some View {
        Image(leadingIcon)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .foregroundColor(.floCharcoal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon + FLO wordmark on one row.
            HStack {
                if let onLeadingIconTap {
                    Button(action: onLeadingIconTap) { leadingIconImage }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to today")
                } else {
                    leadingIconImage
                }

                Spacer()

                // FLO on any screen goes home to the Calendar (Brittany's review).
                Button {
                    FloHaptics.selection()
                    NotificationCenter.default.post(name: .floShowCalendar, object: nil)
                } label: {
                    Text("FLO")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.floCharcoal)
                        .tracking(3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to calendar")
            }
            .padding(.top, FloSpacing.md)

            // Title — LUNARY 36pt, 39.6pt line height, top 47pt below the row.
            Text(title)
                .font(.floLunary(size: 36))
                .lineSpacing(titleLineSpacing)
                .foregroundColor(.floCharcoal)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 47)

            // Eyebrow — uppercase, tracked, small bold, 17pt below the title.
            if let eyebrow {
                // Figma: Inter Bold 12, black.
                Text(eyebrow.uppercased())
                    .font(.floInter(12, bold: true))
                    .foregroundColor(.black)
                    .padding(.top, 17)
            }

            // Subtitle — sentence case, 18pt below the eyebrow.
            if let subtitle {
                // Figma: Inter 16, black.
                Text(subtitle)
                    .font(.floInter(16))
                    .foregroundColor(.black)
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.screenMargin)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Segmented caps tabs

/// Three-way caps tab row (MIND | BODY | SOUL, 5 MIN | 10 MIN | 60 MIN).
/// A hairline sits above, a heavier rule below, and 2pt black bars divide
/// the options. The selected option gets a small filled block.
struct SegmentedCapsTabs<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var highlight: Color = .floPhaseTab

    var body: some View {
        VStack(spacing: 0) {
            FloHairline()

            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    tab(option)
                    if index < options.count - 1 {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 2, height: 26)
                    }
                }
            }
            .frame(height: 50)

            FloRuleLine()
        }
    }

    private func tab(_ option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            guard !isSelected else { return }
            FloHaptics.selection()
            withAnimation(FloAnimation.springSnappy) { selection = option }
        } label: {
            Text(title(option).uppercased())
                .font(.system(size: 11.5, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Color.black)
                .frame(width: 96, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isSelected ? highlight : Color.clear)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Close buttons

/// Thin sage X used at the top-right of full screens and sheets.
struct SageCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            FloHaptics.light()
            action()
        } label: {
            SageXShape()
                .stroke(Color.floSageX, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.floPressed)
        .floHitTarget()
        .accessibilityLabel("Close")
    }
}

private struct SageXShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// Round outlined X used on floating modal cards.
struct RoundCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            FloHaptics.light()
            action()
        } label: {
            FloIcon("xmark", size: 15)
                .foregroundStyle(Color.black)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white))
                .overlay(Circle().strokeBorder(Color.floInk, lineWidth: 1.5))
        }
        .buttonStyle(.floPressed)
        .floHitTarget()
        .accessibilityLabel("Close")
    }
}

// MARK: - Button shape (Figma "Emotions - button" / "Log Cycle")

/// 44pt tall, 6pt corners, #F8F8F8 fill, 1pt #707070 border, and a flat
/// #ECEFEC plate offset 2pt right and down. The plate is part of the drawing,
/// not a blur shadow, so it stays within "as flat as possible".
struct FloButtonShape: ViewModifier {
    var fill: Color = .floButtonFill

    func body(content: Content) -> some View {
        content
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.floInk, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.floButtonPlate)
                    .offset(x: 2, y: 2)
            )
    }
}

extension View {
    func floButtonShape(fill: Color = .floButtonFill) -> some View {
        modifier(FloButtonShape(fill: fill))
    }
}

// MARK: - Back button

/// Feather arrow-left, black, no circle (Brittany: feather-style, not the
/// filled green circle).
struct FloBackButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            FloHaptics.light()
            action()
        } label: {
            FloIcon("arrow.left", size: 24)
                .foregroundStyle(Color.black)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.floPressed)
        .accessibilityLabel("Back")
    }
}

// MARK: - Rules

/// 1pt #EDEDED hairline.
struct FloHairline: View {
    var body: some View {
        Rectangle().fill(Color.floHairline).frame(height: 1)
    }
}

/// 1pt #707070 rule (Figma "Line 21").
struct FloRuleLine: View {
    var body: some View {
        Rectangle().fill(Color.floRule).frame(height: 1)
    }
}

// MARK: - Sheet chrome

/// Grabber for sheets that hide the system drag indicator.
struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.floLightGray)
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }
}

/// Round white button that overlaps a photo's bottom-right corner. The
/// visible circle is 36pt; the tap area is padded out to 44.
struct RoundPhotoEditLabel: View {
    var icon: String = "square.and.pencil"

    var body: some View {
        FloIcon(icon, size: 16)
            .foregroundStyle(Color.floInk)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

// MARK: - Icons (Feather)

/// Every icon in the app is drawn from the Feather set (feathericons.com, MIT;
/// license in licenses/). Brittany's review, Nov 25.
///
/// Call sites name icons by their old SF Symbol names, so nothing upstream had
/// to change; this maps each to its Feather drawing in
/// Assets.xcassets/Feather (`fi-<name>`, vector, template-rendered, so
/// `.foregroundStyle` tints it). `size` is the icon's square in points. Brand
/// marks with no Feather equivalent (Apple, Google) keep their SF Symbol.
struct FloIcon: View {
    let name: String
    let size: CGFloat?

    init(_ name: String, size: CGFloat? = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if let feather = Self.featherName(for: name) {
            let image = Image("fi-\(feather)")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
            if let size {
                image.frame(width: size, height: size)
            } else {
                image
            }
        } else if let size {
            Image(systemName: name)
                .font(.system(size: size * 0.87))
        } else {
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        }
    }

    static func featherName(for name: String) -> String? {
        sfToFeather[name]
    }

    private static let sfToFeather: [String: String] = [
        "arrow.clockwise.circle": "rotate-cw",
        "arrow.counterclockwise.circle": "rotate-ccw",
        "arrow.left": "arrow-left",
        "arrow.right": "arrow-right",
        "arrow.right.circle.fill": "arrow-right-circle",
        "bell": "bell",
        "book.closed": "book",
        "bubble.left.and.bubble.right.fill": "message-circle",
        "calendar": "calendar",
        "checkmark": "check",
        "checkmark.circle": "check-circle",
        "checkmark.circle.fill": "check-circle",
        "checkmark.seal.fill": "award",
        "chevron.left": "chevron-left",
        "chevron.right": "chevron-right",
        "circle": "circle",
        "clock": "clock",
        "cloud.rain.fill": "cloud-rain",
        "doc.on.doc": "copy",
        "ellipsis": "more-horizontal",
        "exclamationmark.triangle.fill": "alert-triangle",
        "eye": "eye",
        "eye.slash": "eye-off",
        "eye.slash.fill": "eye-off",
        "figure.2.and.child.holdinghands": "users",
        "flame.fill": "zap",
        "hammer.circle": "tool",
        "hand.raised.fill": "shield",
        "heart": "heart",
        "heart.fill": "heart-fill",
        "heart.slash.fill": "heart",
        "heart.text.square": "heart",
        "heart.text.square.fill": "heart",
        "info.circle.fill": "info",
        "leaf": "feather",
        "lock": "lock",
        "lock.fill": "lock",
        "lock.shield.fill": "shield",
        "magnifyingglass": "search",
        "mic": "mic",
        "mic.fill": "mic",
        "moon.stars": "moon",
        "paperplane.fill": "send",
        "pause": "pause",
        "pencil": "edit-2",
        "person": "user",
        "person.2": "users",
        "person.2.circle": "users",
        "person.crop.circle.badge.xmark": "user-x",
        "person.fill": "user",
        "person.fill.questionmark": "user",
        "photo": "image",
        "play.fill": "play-fill",
        "plus": "plus",
        "plus.circle": "plus-circle",
        "rectangle.portrait": "smartphone",
        "rectangle.portrait.and.arrow.right": "log-out",
        "square.and.arrow.up": "share",
        "square.and.pencil": "edit",
        "sun.max.fill": "sun",
        "trash": "trash-2",
        "waveform": "activity",
        "wifi.exclamationmark": "wifi-off",
        "xmark": "x",
        "xmark.circle.fill": "x-circle",
    ]
}
