import AppKit
import SwiftUI

/// The menu bar window: accessory switcher on top, the chosen panel below.
/// Switching swaps content instantly; the window resizes to fit, and
/// animating a window's height would only stutter.
struct RootPanel: View {
    var forcedSelection: AccessoryKind?
    var startsEditingToken = false

    @Environment(AirConditionerStore.self) private var climate
    @Environment(CatFeederStore.self) private var feeder
    @AppStorage("selectedAccessory") private var storedSelection: AccessoryKind = .climate

    private var selection: AccessoryKind { forcedSelection ?? storedSelection }

    var body: some View {
        VStack(spacing: 0) {
            AccessorySwitcher(selection: Binding(get: { selection }, set: { storedSelection = $0 }))
                .padding(.bottom, 16)

            switch selection {
            case .climate:
                AirConditionerPanel(isEditingToken: startsEditingToken)
            case .feeder:
                CatFeederPanel(isEditingToken: startsEditingToken)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background {
            ZStack {
                Theme.panel
                switch selection {
                case .climate:
                    AirConditionerPanel.wash(for: climate)
                case .feeder:
                    RadialGradient(colors: [CatFeederPanel.accent.opacity(0.08), .clear],
                                   center: .top, startRadius: 10, endRadius: 260)
                }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            climate.panelDidOpen()
            feeder.panelDidOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            climate.panelDidClose()
            feeder.panelDidClose()
        }
    }
}
