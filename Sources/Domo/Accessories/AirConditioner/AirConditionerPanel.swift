import AppKit
import ServiceManagement
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
                ErrorView(message: message) { store.reload() }
            } else {
                header
                ACUnitView(isOn: store.isOn, tint: tint)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                controls
                    .redacted(reason: store.hasLoaded ? [] : .placeholder)
            }
            footer
                .padding(.top, 18)
        }
        .padding(20)
        .frame(width: 400)
        .background { background }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.panelDidOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            store.panelDidClose()
        }
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
                .animation(.easeOut(duration: 0.2), value: store.temperatureRange)
            }
            .padding(.top, 14)
            .opacity(store.canSetTemperature ? 1 : 0.35)
            .allowsHitTesting(store.canSetTemperature)
            .animation(.easeOut(duration: 0.2), value: store.canSetTemperature)
            .help(store.canSetTemperature ? "" : "Fan mode has no temperature to set")

            tiles
                .padding(.top, 18)
        }
        // Off: keep everything visible but clearly asleep, and not clickable.
        .opacity(store.isOn ? 1 : 0.4)
        .allowsHitTesting(store.isOn && store.hasLoaded)
        .animation(.easeOut(duration: 0.2), value: store.isOn)
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

    private var footer: some View {
        HStack {
            Label(statusText, systemImage: statusSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: statusText)
                .lineLimit(1)

            Spacer()

            SettingsMenu(
                deviceName: store.deviceName,
                modelName: store.modelName,
                onRefresh: { store.reload() },
                onChangeToken: { isEditingToken = true }
            )
        }
    }

    private var background: some View {
        ZStack {
            Theme.panel
            // A faint wash of the mode's color, only while running.
            RadialGradient(
                colors: [tint.opacity(store.isOn ? 0.14 : 0), .clear],
                center: .top, startRadius: 10, endRadius: 260
            )
            .animation(.easeInOut(duration: 0.4), value: store.isOn)
            .animation(.easeInOut(duration: 0.4), value: store.mode)
        }
        .ignoresSafeArea()
    }

    // MARK: - Status

    private var statusText: String {
        if let notice = store.notice { return notice }
        if store.reportsError { return "AC reports an error" }
        switch store.status {
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .failed(let message): return message
        }
    }

    private var statusSymbol: String {
        if store.notice != nil || store.reportsError { return "exclamationmark.triangle" }
        return switch store.status {
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.shield"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        if store.notice != nil || store.reportsError { return .orange }
        return switch store.status {
        case .failed: .orange
        default: .secondary
        }
    }
}

private struct SettingsMenu: View {
    let deviceName: String
    let modelName: String
    let onRefresh: () -> Void
    let onChangeToken: () -> Void

    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Section(modelName.isEmpty ? deviceName : "\(deviceName) · \(modelName)") {
                Button("Refresh Now", action: onRefresh)
                    .keyboardShortcut("r")
                Button("Change Token…", action: onChangeToken)
                Toggle("Open at Login", isOn: $opensAtLogin)
            }
            Divider()
            Button("Quit Domo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle(scale: 0.9))
        .menuIndicator(.hidden)
        .accessibilityLabel("Settings")
        .onChange(of: opensAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                opensAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// Couldn't reach LG before the first load (offline, rate-limited…).
private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "air.conditioner.horizontal")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 17, weight: .semibold))
            Text("Check that this Mac is online. Domo retries on its own every few minutes.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background { SurfaceBackground(radius: 8) }
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
