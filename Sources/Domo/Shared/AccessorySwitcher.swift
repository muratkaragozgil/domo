import SwiftUI

enum AccessoryKind: String, CaseIterable, Identifiable {
    case climate, feeder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .climate: "Climate"
        case .feeder: "Cat Feeder"
        }
    }

    var systemImage: String {
        switch self {
        case .climate: "air.conditioner.horizontal"
        case .feeder: "cat"
        }
    }
}

/// Segmented switch between accessories, used tens of times a day, so the
/// motion stays small: one 250ms ease-in-out slide.
///
/// The tab-indicator recipe: the row is drawn twice, plain and active, and
/// the active copy is clipped to the selected tab. Text color and highlight
/// change together because they're one layer being revealed, not two colors
/// being interpolated.
struct AccessorySwitcher: View {
    @Binding var selection: AccessoryKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let inset: CGFloat = 3
    private var kinds: [AccessoryKind] { AccessoryKind.allCases }

    var body: some View {
        GeometryReader { proxy in
            let tabWidth = (proxy.size.width - inset * 2) / CGFloat(kinds.count)
            let index = CGFloat(kinds.firstIndex(of: selection) ?? 0)

            ZStack(alignment: .leading) {
                row(isActive: false)
                row(isActive: true)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.13))
                            .padding(inset)
                    }
                    .mask(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .frame(width: tabWidth, height: proxy.size.height - inset * 2)
                            .offset(x: inset + index * tabWidth)
                    }
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : Theme.easeInOut(0.25), value: selection)
        }
        .frame(height: 36)
        .background { SurfaceBackground(radius: 11) }
    }

    private func row(isActive: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(kinds) { kind in
                Button {
                    selection = kind
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == kind ? .isSelected : [])
            }
        }
        .padding(inset)
    }
}
