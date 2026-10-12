import SwiftUI

@main
struct DomoApp: App {
    @State private var store = AirConditionerStore()

    init() {
        if let snapshot = Snapshot.request {
            Task { Snapshot.run(path: snapshot.path, isOn: snapshot.isOn) }
        } else if let iconPath = Snapshot.iconRequest {
            Task { Snapshot.renderIcon(to: iconPath) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            AirConditionerPanel()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Icon plus the set temperature while running; just the outline when off.
private struct MenuBarLabel: View {
    let store: AirConditionerStore

    var body: some View {
        if store.isOn {
            Text("\(Image(systemName: "air.conditioner.horizontal.fill")) \(TemperatureText.number(store.targetTemperature))°")
        } else {
            Image(systemName: "air.conditioner.horizontal")
        }
    }
}
