import SwiftUI

struct AirConditionerPanel: View {
    @Environment(AirConditionerStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var isEditingToken = false

    private var tint: Color { Theme.tint(for: store.mode) }

    var body: some View {
        VStack(spacing: 0) {
            if store.needsToken || isEditingToken {
                ThinQTokenView(canCancel: !store.needsToken) { isEditingToken = false }
            } else if !store.hasLoaded, case .failed(let message) = store.status {
                ConnectionErrorView(
                    systemImage: "air.conditioner.horizontal",
                    message: message,
                    detail: "Check that this Mac is online. Domo retries on its own every few minutes.",
                    onRetry: store.reload
                )
            } else {
                header
                ACUnitView(isOn: store.isOn, tint: tint)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                controls
                    .redacted(reason: store.hasLoaded ? [] : .placeholder)
            }
            PanelFooter(status: status, menuTitle: menuTitle, onRefresh: store.reload) {
                isEditingToken = true
            }
            .padding(.top, 18)
        }
    }

    /// A faint wash of the mode's color behind the panel, only while running.
    static func wash(for store: AirConditionerStore) -> some View {
        RadialGradient(
            colors: [Theme.tint(for: store.mode).opacity(store.isOn ? 0.14 : 0), .clear],
            center: .top, startRadius: 10, endRadius: 260
        )
        .animation(Theme.ease(0.3), value: store.isOn)
        .animation(Theme.ease(0.3), value: store.mode)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(.secondary)
                Text("Room")
                    .foregroundStyle(.secondary)
                Text(store.roomTemperature.map { "\(TemperatureText.number($0))°C" } ?? "—")
                    .fontWeight(.semibold)
                    .contentTransition(.numericText(value: store.roomTemperature ?? 0))
                    .animation(Theme.spring(reduceMotion), value: store.roomTemperature)
            }
            .font(.system(size: 15))
            .accessibilityElement(children: .combine)

            Spacer()

            PowerButton(isOn: store.isOn, tint: tint) {
                store.setPower(!store.isOn)
            }
            .disabled(!store.hasLoaded)
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(TemperatureText.number(store.targetTemperature))
                        .font(.system(size: 64, weight: .semibold))
                        .tracking(-2)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: store.targetTemperature))
                    Text("°C")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .animation(Theme.spring(reduceMotion), value: store.targetTemperature)
                .accessibilityElement(children: .combine)

                Spacer()

                if store.supportsEco {
                    PillToggle(title: "Eco Mode", systemImage: "leaf", isOn: store.isEcoOn) { store.setEco(!store.isEcoOn) }
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    StepButton(systemImage: "minus", label: "Cooler") { store.nudgeTemperature(by: -1) }
                        .disabled(store.targetTemperature <= store.temperatureRange.lowerBound)
                    TemperatureSlider(
                        value: store.targetTemperature,
                        range: store.temperatureRange,
                        step: store.temperatureStep,
                        tint: tint,
                        onChange: { store.previewTargetTemperature($0) },
                        onCommit: { store.setTargetTemperature($0, after: .milliseconds(150)) }
                    )
                    .frame(height: 44)
                    StepButton(systemImage: "plus", label: "Warmer") { store.nudgeTemperature(by: 1) }
                        .disabled(store.targetTemperature >= store.temperatureRange.upperBound)
                }
                HStack {
                    Text("\(TemperatureText.number(store.temperatureRange.lowerBound))°")
                    Spacer()
                    Text("\(TemperatureText.number(store.temperatureRange.upperBound))°")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 56)
                .contentTransition(.numericText())
                .animation(Theme.easeOut(0.2), value: store.temperatureRange)
            }
            .padding(.top, 14)
            .opacity(store.canSetTemperature ? 1 : 0.35)
            .allowsHitTesting(store.canSetTemperature)
            .animation(Theme.easeOut(0.2), value: store.canSetTemperature)
            .help(store.canSetTemperature ? "" : "Fan mode has no temperature to set")

            tiles
                .padding(.top, 18)
        }
        // Off: keep everything visible but clearly asleep, and not clickable.
        .opacity(store.isOn ? 1 : 0.4)
        .allowsHitTesting(store.isOn && store.hasLoaded)
        .animation(Theme.easeOut(0.2), value: store.isOn)
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            ControlTile(
                title: "Mode",
                value: ACText.mode(store.mode),
                systemImage: ACText.modeSymbol(store.mode),
                iconTint: tint,
                options: store.modes.map { .init(id: $0, title: ACText.mode($0)) },
                selection: store.mode,
                onSelect: store.setMode
            )
            ControlTile(
                title: "Fan speed",
                value: ACText.fan(store.fanSpeed),
                systemImage: "fan",
                options: store.fanSpeeds.map { .init(id: $0, title: ACText.fan($0)) },
                selection: store.fanSpeed,
                onSelect: store.setFanSpeed
            )
            ControlTile(
                title: "Sleep",
                value: store.sleepRemaining ?? ACText.sleep(store.sleepHours),
                systemImage: store.sleepHours > 0 ? "moon.fill" : "moon",
                options: store.sleepOptions.map { .init(id: String($0), title: ACText.sleep($0)) },
                selection: String(store.sleepHours),
                onSelect: { store.setSleep(hours: Int($0) ?? 0) }
            )
            ControlTile(
                title: "Airflow",
                value: store.airflow.title,
                systemImage: "wind",
                options: store.airflowOptions.map { .init(id: $0.rawValue, title: $0.title) },
                selection: store.airflow.rawValue,
                onSelect: { store.setAirflow(Airflow(rawValue: $0) ?? .off) }
            )
        }
    }

    // MARK: - Status

    private var menuTitle: String {
        store.modelName.isEmpty ? store.deviceName : "\(store.deviceName) · \(store.modelName)"
    }

    private var status: StatusLine {
        if let notice = store.notice { return .warning(notice) }
        if store.reportsError { return .warning("AC reports an error") }
        return switch store.status {
        case .connecting: .connecting
        case .connected: .connected
        case .failed(let message): .warning(message)
        }
    }
}
