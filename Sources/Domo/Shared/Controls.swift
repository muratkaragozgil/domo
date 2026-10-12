import SwiftUI

struct PowerButton: View {
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(isOn ? tint.opacity(0.22) : Theme.surface)
                        .overlay { Circle().strokeBorder(isOn ? tint.opacity(0.55) : Theme.hairline) }
                        .shadow(color: isOn ? tint.opacity(0.45) : .clear, radius: 10)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .animation(.easeOut(duration: 0.2), value: isOn)
        .help(isOn ? "Turn off" : "Turn on")
        .accessibilityLabel(isOn ? "Turn off" : "Turn on")
    }
}

struct StepButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(Theme.surface)
                        .overlay { Circle().strokeBorder(Theme.hairline) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// A labelled switch on a chip, e.g. Eco Mode. Reusable for any on/off feature.
struct PillToggle: View {
    let title: String
    /// Outline symbol; the filled variant is used while on.
    let systemImage: String
    var tint = Color(red: 0.42, green: 0.85, blue: 0.5)
    let isOn: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .symbolVariant(isOn ? .fill : .none)
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? tint : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                Capsule()
                    .fill(isOn ? tint.opacity(0.85) : Color.white.opacity(0.14))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                            .padding(3)
                    }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 44)
            .background { SurfaceBackground(radius: 12) }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .animation(Theme.spring(reduceMotion), value: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// One of the four tiles. Opens a native menu: familiar, keyboard-navigable,
/// and it never fights the panel for space.
struct ControlTile: View {
    struct Option: Identifiable {
        let id: String
        let title: String
    }

    let title: String
    let value: String
    let systemImage: String
    var iconTint: Color = .primary
    let options: [Option]
    let selection: String
    let onSelect: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    onSelect(option.id)
                } label: {
                    if option.id == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(iconTint)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 24)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                Spacer(minLength: 12)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(value)
                    .transition(.blurReplace)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
            .background { SurfaceBackground(isHovered: isHovered) }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: value)
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle(scale: 0.97))
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
        .disabled(options.isEmpty)
        .opacity(options.isEmpty ? 0.45 : 1)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
