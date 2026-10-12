import AppKit
import SwiftUI

/// The feeder (Xiaomi's product shot) with kibble that drops into the bowl
/// each time a feed is confirmed.
///
/// Motion: feedback, a few times a day. Each piece fades in fast
/// (ease-out 80ms) and falls from under the hopper into the bowl
/// (ease-in-out 280ms), staggered 50ms; they rest a moment and fade out.
/// Transform and opacity only. Reduce Motion skips the drop entirely; the
/// button's checkmark still confirms.
struct FeederIllustration: View {
    let feedCount: Int
    let portions: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kibble: [Kibble] = []

    private static let photo: NSImage? = Bundle.main
        .url(forResource: "xiaomi-feeder", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    private let height: CGFloat = 168
    private var width: CGFloat { height * 557 / 640 }

    var body: some View {
        ZStack {
            // Wall wash and a contact shadow, so a white feeder sits in a dark panel.
            Ellipse()
                .fill(.white.opacity(0.06))
                .frame(width: width * 1.9, height: height * 0.9)
                .blur(radius: 30)
            Ellipse()
                .fill(.black.opacity(0.5))
                .frame(width: width * 1.05, height: 12)
                .blur(radius: 8)
                .offset(y: height / 2 - 2)

            ZStack(alignment: .topLeading) {
                if let photo = Self.photo {
                    Image(nsImage: photo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: width, height: height)
                } else {
                    Image(systemName: "cat")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                        .frame(width: width, height: height)
                }

                ForEach(kibble) { piece in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.74, green: 0.5, blue: 0.29), Color(red: 0.47, green: 0.28, blue: 0.14)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: piece.size.width, height: piece.size.height)
                        .rotationEffect(piece.rotation)
                        .position(x: piece.start.x * width, y: piece.start.y * height)
                        .offset(piece.hasLanded
                                ? CGSize(width: (piece.end.x - piece.start.x) * width, height: (piece.end.y - piece.start.y) * height)
                                : .zero)
                        .opacity(piece.isVisible ? 1 : 0)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(height: height + 14)
        .accessibilityHidden(true)
        .onChange(of: feedCount) { drop() }
    }

    private func drop() {
        guard !reduceMotion else { return }
        let pieces = (0..<min(4 + portions * 2, 10)).map { _ in Kibble.random() }
        kibble.append(contentsOf: pieces)
        for (index, piece) in pieces.enumerated() {
            let delay = Double(index) * 0.05
            withAnimation(Theme.easeOut(0.08).delay(delay)) { update(piece.id) { $0.isVisible = true } }
            withAnimation(Theme.easeInOut(0.28).delay(delay)) { update(piece.id) { $0.hasLanded = true } }
        }
        let settled = Double(pieces.count) * 0.05 + 0.28 + 0.9
        Task {
            try? await Task.sleep(for: .seconds(settled))
            withAnimation(Theme.easeOut(0.2)) {
                for piece in pieces { update(piece.id) { $0.isVisible = false } }
            }
            try? await Task.sleep(for: .seconds(0.25))
            let ids = Set(pieces.map(\.id))
            kibble.removeAll { ids.contains($0.id) }
        }
    }

    private func update(_ id: UUID, _ change: (inout Kibble) -> Void) {
        if let index = kibble.firstIndex(where: { $0.id == id }) { change(&kibble[index]) }
    }
}

private struct Kibble: Identifiable {
    let id = UUID()
    /// Normalized to the photo: under the hopper's front edge…
    let start: CGPoint
    /// …into the bowl, spreading toward its front.
    let end: CGPoint
    let size: CGSize
    let rotation: Angle
    var isVisible = false
    var hasLanded = false

    static func random() -> Kibble {
        Kibble(
            start: CGPoint(x: .random(in: 0.47...0.56), y: 0.7),
            end: CGPoint(x: .random(in: 0.2...0.5), y: .random(in: 0.786...0.804)),
            size: CGSize(width: .random(in: 4.5...6), height: .random(in: 3.5...4.5)),
            rotation: .degrees(.random(in: -40...40))
        )
    }
}
