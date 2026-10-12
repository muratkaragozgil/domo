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
        .animation(Theme.easeOut(0.2), value: isOn)
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

/// A labelled on/off chip, e.g. Eco Mode. The whole chip is the click target.
struct PillToggle: View {
    let title: String
    /// Outline symbol; the filled variant is used while on.
    let systemImage: String
    var tint = Color(red: 0.42, green: 0.85, blue: 0.5)
    let isOn: Bool
    let action: () -> Void

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
                // Room for the switch, which sits on top so it gets its own clicks.
                Color.clear.frame(width: 42, height: 1)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 44)
            .background { SurfaceBackground(radius: 12) }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityHidden(true)
        .overlay(alignment: .trailing) {
            DomoSwitch(label: title, isOn: isOn, action: action)
                .padding(.trailing, 10)
        }
        .animation(Theme.ease(0.15), value: isOn)
    }
}


/// What a tile shows: icon, title, value. Shared by every tile flavor so
/// menu tiles and read-only tiles line up exactly.
struct TileContent: View {
    let title: String
    let value: String
    let systemImage: String
    var iconTint: Color = .primary
    var valueTint: Color = .primary
    var showsChevron = true
    var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(iconTint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 24)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 12)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .id(value)
                .transition(.blurReplace)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
        .background { SurfaceBackground(isHovered: isHovered) }
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .animation(Theme.easeOut(0.2), value: value)
        .animation(Theme.ease(0.2), value: valueTint)
    }
}

/// A tile that opens a native menu: familiar, keyboard-navigable, and it
/// never fights the panel for space.
struct MenuTile<MenuContent: View>: View {
    let title: String
    let value: String
    let systemImage: String
    var iconTint: Color = .primary
    var valueTint: Color = .primary
    var isEnabled = true
    @ViewBuilder let menu: () -> MenuContent

    @State private var isHovered = false

    var body: some View {
        Menu {
            menu()
        } label: {
            TileContent(title: title, value: value, systemImage: systemImage, iconTint: iconTint,
                        valueTint: valueTint, isHovered: isHovered)
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle(scale: 0.97))
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// A menu tile whose menu is a single choice from a list.
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

    var body: some View {
        MenuTile(title: title, value: value, systemImage: systemImage, iconTint: iconTint, isEnabled: !options.isEmpty) {
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
        }
    }
}

/// Read-only tile for a reading that can't be changed from here.
struct StatusTile: View {
    let title: String
    let value: String
    let systemImage: String
    var iconTint: Color = .primary
    var valueTint: Color = .primary

    var body: some View {
        TileContent(title: title, value: value, systemImage: systemImage, iconTint: iconTint,
                    valueTint: valueTint, showsChevron: false)
            .accessibilityElement(children: .combine)
    }
}
