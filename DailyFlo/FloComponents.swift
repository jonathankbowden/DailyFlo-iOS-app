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
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.floDeepTeal)
            }
            Text(title.uppercased())
                .font(.system(size: 11.5, weight: .black))
                .tracking(2.8)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 47)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.floButtonFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.floInk, lineWidth: 1.5)
        )
        .floShadow(FloShadow.button)
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
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .medium))
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

// MARK: - Rules

/// 1pt #EDEDED hairline.
struct FloHairline: View {
    var body: some View {
        Rectangle().fill(Color.floHairline).frame(height: 1)
    }
}

/// 1.5pt #707070 rule.
struct FloRuleLine: View {
    var body: some View {
        Rectangle().fill(Color.floRule).frame(height: 1.5)
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
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.floInk)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white))
            .floShadow(FloShadow.medium)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}
