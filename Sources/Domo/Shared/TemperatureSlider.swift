import AppKit
import SwiftUI

/// Tracks the pointer 1:1 while dragging (no animation), keeps the grab
/// offset so the thumb never jumps under the cursor, and only commits on release.
struct TemperatureSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void

    @State private var isDragging = false
    @State private var grabOffset: CGFloat = 0
    @State private var draggedValue: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let thumbWidth: CGFloat = 26
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumbWidth - inset * 2, 1)
            let thumbX = inset + CGFloat(fraction) * travel

            ZStack(alignment: .leading) {
                SurfaceBackground(radius: 12)

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.06), tint.opacity(0.34)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: thumbX + thumbWidth - inset, height: proxy.size.height - inset * 2)
                    .offset(x: inset)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color(white: 0.95), Color(white: 0.8)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: thumbWidth, height: proxy.size.height - inset * 2)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                    .scaleEffect(isDragging ? 1.06 : 1)
                    .offset(x: thumbX)
            }
            .animation(isDragging ? nil : Theme.spring(reduceMotion), value: value)
            .animation(.easeOut(duration: 0.12), value: isDragging)
            .contentShape(Rectangle())
            .gesture(drag(thumbX: thumbX, travel: travel))
            .animation(.easeInOut(duration: 0.3), value: tint)
        }
        .accessibilityElement()
        .accessibilityLabel("Target temperature")
        .accessibilityValue("\(TemperatureText.number(value)) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(value + step)
            case .decrement: onCommit(value - step)
            @unknown default: break
            }
        }
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func drag(thumbX: CGFloat, travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let thumbCenter = thumbX + thumbWidth / 2
                if !isDragging {
                    isDragging = true
                    // Grabbed the thumb: keep the offset. Clicked the track: jump there.
                    let onThumb = abs(gesture.startLocation.x - thumbCenter) <= thumbWidth / 2 + 4
                    grabOffset = onThumb ? gesture.startLocation.x - thumbCenter : 0
                }
                let center = gesture.location.x - grabOffset
                let position = min(max((center - inset - thumbWidth / 2) / travel, 0), 1)
                let raw = range.lowerBound + Double(position) * (range.upperBound - range.lowerBound)
                let snapped = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                if snapped != (draggedValue ?? value) {
                    draggedValue = snapped
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    onChange(snapped)
                }
            }
            .onEnded { _ in
                isDragging = false
                onCommit(draggedValue ?? value)
                draggedValue = nil
            }
    }
}
