import SwiftUI

@main
struct DomoApp: App {
    @State private var climate = AirConditionerStore()
    @State private var feeder = CatFeederStore()

    init() {
        if CommandLine.arguments.contains("--feeder-status") {
            Task {
                await FeederDiagnostics.run()
                exit(0)
            }
        } else if let snapshot = Snapshot.request {
            Task { Snapshot.run(path: snapshot.path, isOn: snapshot.isOn) }
        } else if let iconPath = Snapshot.iconRequest {
            Task { Snapshot.renderIcon(to: iconPath) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            RootPanel()
                .environment(climate)
                .environment(feeder)
        } label: {
            MenuBarLabel(climate: climate)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The AC and its set temperature while it runs; otherwise just the house.
private struct MenuBarLabel: View {
    let climate: AirConditionerStore

    var body: some View {
        if climate.isOn {
            Text("\(Image(systemName: "air.conditioner.horizontal.fill")) \(TemperatureText.number(climate.targetTemperature))°")
        } else {
            Image(systemName: "house")
        }
    }
}
