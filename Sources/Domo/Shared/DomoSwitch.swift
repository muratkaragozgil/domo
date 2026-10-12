import AppKit
import SwiftUI

/// Domo's own switch, drawn to sit in a dark panel instead of AppKit's
/// small grey one.
///
/// Feel: the knob stretches toward its travel the moment it's pressed
/// (feedback on press, not release), then springs across with a little
/// give. A light haptic tick lands on the same frame as the change.
/// Reduce Motion swaps the slide for a short cross-fade.
struct DomoSwitch: View {
    enum Style: CaseIterable {
        /// Familiar green, as on iPhone.
        case green
        /// White when on, quiet when off; no color competing with the icons.
        case mono
        /// Cool blue with a soft glow, matching the AC's cooling tint.
        case glow
    }

    let label: String
    let isOn: Bool
    var style: Style = .defaultStyle
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size = CGSize(width: 42, height: 25)
    private let inset: CGFloat = 2.5

    var body: some View {
        let knob = size.height - inset * 2

        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(track)
                .overlay { Capsule().strokeBorder(trackEdge, lineWidth: 0.5) }
                .shadow(color: glow, radius: 8)

            Capsule()
                .fill(knobFill)
                .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5).blendMode(.plusLighter) }
                .frame(width: knob + (isPressed ? 6 : 0), height: knob)
                .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1.5)
                .padding(inset)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { value in
                    isPressed = false
                    // Releasing outside the switch cancels, as with any button.
                    if CGRect(origin: .zero, size: size).insetBy(dx: -8, dy: -8).contains(value.location) { flip() }
                }
        )
        .animation(reduceMotion ? Theme.ease(0.15) : .spring(duration: 0.28, bounce: 0.12), value: isOn)
        .animation(Theme.easeOut(0.12), value: isPressed)
        .animation(Theme.ease(0.2), value: style)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { flip() }
    }

    private func flip() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        action()
    }

    private var track: AnyShapeStyle {
        switch (style, isOn) {
        case (.green, true):
            AnyShapeStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.86, blue: 0.42), Color(red: 0.16, green: 0.74, blue: 0.33)],
                                         startPoint: .top, endPoint: .bottom))
        case (.mono, true):
            AnyShapeStyle(Color(white: 0.93))
        case (.glow, true):
            AnyShapeStyle(LinearGradient(colors: [Color(red: 0.45, green: 0.77, blue: 1.0), Color(red: 0.25, green: 0.56, blue: 0.98)],
                                         startPoint: .top, endPoint: .bottom))
        case (_, false):
            AnyShapeStyle(Color.white.opacity(0.1))
        }
    }

    private var trackEdge: Color {
        isOn ? .white.opacity(style == .mono ? 0 : 0.18) : .white.opacity(0.12)
    }

    private var knobFill: AnyShapeStyle {
        switch (style, isOn) {
        case (.mono, true): AnyShapeStyle(Color(white: 0.1))
        case (_, true): AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.92)], startPoint: .top, endPoint: .bottom))
        case (_, false): AnyShapeStyle(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.66)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var glow: Color {
        guard isOn else { return .clear }
        return switch style {
        case .glow: Color(red: 0.35, green: 0.65, blue: 1.0).opacity(0.45)
        case .green: Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.25)
        case .mono: .clear
        }
    }
}

extension DomoSwitch.Style {
    static let defaultStyle: Self = .green
}
