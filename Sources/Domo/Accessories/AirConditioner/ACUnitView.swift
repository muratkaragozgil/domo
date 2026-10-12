import AppKit
import SwiftUI

/// The actual unit on the wall: LG AC18BH (Artcool Mirror, black).
/// Power is shown, not animated for show: the unit brightens and a glow in
/// the mode's color appears under the vent, as if air were coming out.
struct ACUnitView: View {
    let isOn: Bool
    let tint: Color

    private static let photo: NSImage? = Bundle.main
        .url(forResource: "ac18bh", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    private let width: CGFloat = 268

    var body: some View {
        ZStack {
            // Wall wash: lifts a black unit off a black panel.
            Ellipse()
                .fill(.white.opacity(0.07))
                .frame(width: width + 40, height: 110)
                .blur(radius: 28)

            // Air leaving the vent, tinted by mode. Only while running.
            Ellipse()
                .fill(tint.opacity(0.6))
                .frame(width: width * 0.7, height: 22)
                .blur(radius: 16)
                .offset(y: 50)
                .opacity(isOn ? 1 : 0)

            if let photo = Self.photo {
                Image(nsImage: photo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .brightness(isOn ? 0 : -0.06)
                    .saturation(isOn ? 1 : 0.6)
            } else {
                Image(systemName: "air.conditioner.horizontal")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 108)
        .animation(Theme.easeOut(0.3), value: isOn)
        .animation(Theme.ease(0.3), value: tint)
        .accessibilityHidden(true)
    }
}
