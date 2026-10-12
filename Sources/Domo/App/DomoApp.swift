import SwiftUI

@main
struct DomoApp: App {
    // Snapshot and diagnostic runs get inert demo stores: no polling, and
    // nothing written to the real app's preferences.
    @State private var climate = DomoApp.isTool ? AirConditionerStore(demo: true) : AirConditionerStore()
    @State private var feeder = DomoApp.isTool ? CatFeederStore(demo: true) : CatFeederStore()
    @State private var plugs = DomoApp.isTool ? PlugsStore(demo: true) : PlugsStore()

    private static let isTool = CommandLine.arguments.contains {
        ["--snapshot", "--icon", "--feeder-status", "--plugs-status"].contains($0)
    }

    init() {
        if CommandLine.arguments.contains("--feeder-status") {
            Task {
                await FeederDiagnostics.run()
                exit(0)
            }
        } else if CommandLine.arguments.contains("--plugs-status") {
            Task {
                await PlugsDiagnostics.run()
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
                .environment(plugs)
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
