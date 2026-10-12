import SwiftUI

enum Theme {
    static let panel = Color(white: 0.055)
    static let surface = Color.white.opacity(0.06)
    static let surfaceHover = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.08)
    static let radius: CGFloat = 14

    /// Each mode gets one accent; it tints the slider, mode icon and AC light.
    static func tint(for mode: String) -> Color {
        switch mode {
        case "HEAT": Color(red: 1.0, green: 0.62, blue: 0.30)
        case "AIR_DRY": Color(red: 0.38, green: 0.86, blue: 0.80)
        case "FAN", "AIR_CLEAN": Color(red: 0.78, green: 0.82, blue: 0.88)
        case "AUTO": Color(red: 0.72, green: 0.62, blue: 1.0)
        default: Color(red: 0.42, green: 0.74, blue: 1.0)
        }
    }

    /// Critically damped by default; nothing in this panel earns a bounce.
    static func spring(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0)
    }
}

enum ACText {
    static func mode(_ mode: String) -> String {
        switch mode {
        case "COOL": "Cool"
        case "HEAT": "Heat"
        case "AIR_DRY": "Dry"
        case "FAN", "AIR_CLEAN": "Fan"
        case "AUTO": "Auto"
        case "ENERGY_SAVING": "Energy saver"
        default: humanize(mode)
        }
    }

    static func modeSymbol(_ mode: String) -> String {
        switch mode {
        case "HEAT": "sun.max"
        case "AIR_DRY": "drop"
        case "FAN", "AIR_CLEAN": "fan"
        case "AUTO": "arrow.triangle.2.circlepath"
        default: "snowflake"
        }
    }

    static func fan(_ speed: String) -> String {
        switch speed {
        case "AUTO": "Auto"
        case "LOW", "LOW_MID": speed == "LOW" ? "Low" : "Low–Mid"
        case "MID": "Medium"
        case "MID_HIGH": "Mid–High"
        case "HIGH": "High"
        case "POWER": "Turbo"
        case "SLOW": "Quiet"
        case "NATURE": "Natural"
        default: humanize(speed)
        }
    }

    static func sleep(_ hours: Int) -> String {
        hours == 0 ? "Off" : "\(hours) h"
    }

    private static func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
    }
}

enum TemperatureText {
    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Press feedback on pointer-down: a small, fast scale.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The rounded dark "chip" every control sits on.
struct SurfaceBackground: View {
    var radius: CGFloat = Theme.radius
    var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(isHovered ? Theme.surfaceHover : Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline)
            }
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
