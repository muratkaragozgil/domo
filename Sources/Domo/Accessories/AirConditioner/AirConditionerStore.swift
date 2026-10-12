import Foundation
import Observation

enum Airflow: String, CaseIterable, Identifiable {
    case off, vertical, horizontal, both

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Fixed"
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        case .both: "Both"
        }
    }
    var swingsVertically: Bool { self == .vertical || self == .both }
    var swingsHorizontally: Bool { self == .horizontal || self == .both }
}

/// Holds the AC's state, mirrors it from the ThinQ cloud, and sends commands
/// optimistically: the UI changes first, and rolls back if LG rejects it.
@Observable
final class AirConditionerStore {
    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    private(set) var status: Status = .connecting
    /// A short-lived error from a command, shown in place of the status.
    private(set) var notice: String?
    private(set) var hasLoaded = false
    /// No token yet, or LG rejected the one we have.
    private(set) var needsToken = false
    private(set) var deviceName = "Air Conditioner"
    private(set) var modelName = ""

    private(set) var isOn = false
    private(set) var roomTemperature: Double?
    private(set) var targetTemperature: Double = 23

    private(set) var mode = "COOL"
    private(set) var modes: [String] = []
    private(set) var fanSpeed = "AUTO"
    private(set) var fanSpeeds: [String] = []
    private(set) var isEcoOn = false
    private(set) var supportsEco = false
    /// 0 means the sleep timer is off.
    private(set) var sleepHours = 0
    /// Time left on a running sleep timer, as LG reports it.
    private(set) var sleepRemaining: String?
    private(set) var sleepOptions: [Int] = []
    private(set) var airflow: Airflow = .off
    private(set) var airflowOptions: [Airflow] = []
    private(set) var reportsError = false

    /// Writable range per mode (cool 18–30, heat 16–30 on most LG units).
    private var temperatureRanges: [String: TemperatureRange] = [:]
    private var fallbackRange = TemperatureRange(min: 16, max: 30, step: 1)

    var temperatureRange: ClosedRange<Double> { currentRange.min...currentRange.max }
    var temperatureStep: Double { currentRange.step }
    /// Fan mode only moves air; there's no set point to change.
    var canSetTemperature: Bool { mode != "FAN" && mode != "AIR_CLEAN" }
    private var currentRange: TemperatureRange { temperatureRanges[mode] ?? fallbackRange }

    private var client: ThinQClient?
    private var deviceID: String?
    private var windKey = "windStrength"
    private var supportsVerticalSwing = false
    private var supportsHorizontalSwing = false

    private var pollTask: Task<Void, Never>?
    private var temperatureCommit: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    /// The cloud lags a few seconds behind a command; don't let a poll undo it.
    private var ignoreStateUntil = Date.distantPast
    private var isPanelOpen = false

    init() {
        startPolling()
    }

    /// Fixed sample data for `--snapshot`; never talks to LG.
    init(demo isOn: Bool) {
        hasLoaded = true
        status = .connected
        deviceName = "Living Room"
        self.isOn = isOn
        roomTemperature = 26
        targetTemperature = 23
        modes = ["COOL", "AIR_DRY", "FAN", "AUTO", "HEAT"]
        fanSpeeds = ["LOW", "MID", "HIGH", "AUTO"]
        supportsEco = true
        sleepOptions = [0, 1, 2, 4, 8]
        airflowOptions = [.off, .vertical, .horizontal, .both]
        airflow = .vertical
    }

    // MARK: - Lifecycle

    func panelDidOpen() {
        isPanelOpen = true
        if Date.now.timeIntervalSince(lastRefresh) > 15 { startPolling() }
    }

    func panelDidClose() {
        isPanelOpen = false
    }

    func reload() {
        client = nil
        deviceID = nil
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // Every 30s while you're looking at it, every 5 min for the menu bar.
                let interval: Duration = self?.isPanelOpen == true ? .seconds(30) : .seconds(300)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func refresh() async {
        do {
            if client == nil || deviceID == nil { try await connect() }
            guard let client, let deviceID else { return }
            let state = try await client.state(of: deviceID)
            lastRefresh = .now
            if Date.now >= ignoreStateUntil, temperatureCommit == nil {
                apply(state: state)
            }
            status = .connected
            hasLoaded = true
            needsToken = false
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            status = .failed(error.localizedDescription)
            if let error = error as? ThinQError, error.needsNewToken {
                needsToken = true
                client = nil
                deviceID = nil
            }
        }
    }

    /// Checks the token against LG before saving it, so a typo never
    /// replaces a working token. Returns an error message, or nil on success.
    func connect(token raw: String) async -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "Paste a token first" }
        do {
            let devices = try await ThinQConfig.client(token: token).devices()
            guard devices.contains(where: { $0.type == "DEVICE_AIR_CONDITIONER" }) else {
                return ThinQError.noAirConditioner.localizedDescription
            }
            try ThinQConfig.save(token: token)
        } catch {
            return error.localizedDescription
        }
        needsToken = false
        status = .connecting
        reload()
        return nil
    }

    private func connect() async throws {
        let client = try ThinQConfig.client()
        let devices = try await client.devices()
        guard let device = devices.first(where: { $0.type == "DEVICE_AIR_CONDITIONER" }) else {
            throw ThinQError.noAirConditioner
        }
        let profile = try await client.profile(of: device.id)
        apply(profile: profile)
        deviceName = device.alias
        modelName = device.model
        self.client = client
        deviceID = device.id
    }

    // MARK: - Commands

    func setPower(_ on: Bool) {
        let previous = isOn
        isOn = on
        send(["operation": ["airConOperationMode": .string(on ? "POWER_ON" : "POWER_OFF")]]) {
            $0.isOn = previous
        }
    }

    func setMode(_ newMode: String) {
        guard newMode != mode else { return }
        let previous = mode
        mode = newMode
        send(["airConJobMode": ["currentJobMode": .string(newMode)]]) { $0.mode = previous }
    }

    func setFanSpeed(_ speed: String) {
        guard speed != fanSpeed else { return }
        let previous = fanSpeed
        fanSpeed = speed
        send(["airFlow": .object([windKey: .string(speed)])]) { $0.fanSpeed = previous }
    }

    func setEco(_ on: Bool) {
        let previous = isEcoOn
        isEcoOn = on
        send(["powerSave": ["powerSaveEnabled": .bool(on)]]) { $0.isEcoOn = previous }
    }

    func setSleep(hours: Int) {
        guard hours != sleepHours else { return }
        let previous = (sleepHours, sleepRemaining)
        sleepHours = hours
        sleepRemaining = nil
        // LG only lets you write UNSET; setting hours is what turns the timer on.
        let payload: JSON = hours == 0
            ? ["sleepTimer": ["relativeStopTimer": "UNSET"]]
            : ["sleepTimer": ["relativeHourToStop": .number(Double(hours)), "relativeMinuteToStop": 0]]
        send(payload) { ($0.sleepHours, $0.sleepRemaining) = previous }
    }

    func setAirflow(_ newAirflow: Airflow) {
        guard newAirflow != airflow else { return }
        let previous = airflow
        airflow = newAirflow
        var fields: [String: JSON] = [:]
        if supportsVerticalSwing { fields["rotateUpDown"] = .bool(newAirflow.swingsVertically) }
        if supportsHorizontalSwing { fields["rotateLeftRight"] = .bool(newAirflow.swingsHorizontally) }
        send(["windDirection": .object(fields)]) { $0.airflow = previous }
    }

    /// Live value while the slider is dragged; nothing is sent yet.
    func previewTargetTemperature(_ value: Double) {
        temperatureCommit?.cancel()
        temperatureCommit = nil
        targetTemperature = clamp(value)
        ignoreStateUntil = .now + 10
    }

    /// +/- and slider release land here. Rapid taps coalesce into one command.
    func setTargetTemperature(_ value: Double, after delay: Duration = .milliseconds(450)) {
        let value = clamp(value)
        targetTemperature = value
        ignoreStateUntil = .now + 10
        temperatureCommit?.cancel()
        temperatureCommit = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.temperatureCommit = nil
            do {
                try await self.perform(self.temperaturePayload(value))
            } catch {
                self.flash(error)
            }
        }
    }

    func nudgeTemperature(by steps: Int) {
        setTargetTemperature(targetTemperature + Double(steps) * temperatureStep)
    }

    /// Cool, heat and auto each keep their own set point on LG units.
    private func temperaturePayload(_ value: Double) -> JSON {
        let key = switch mode {
        case "COOL": "coolTargetTemperature"
        case "HEAT": "heatTargetTemperature"
        case "AUTO": "autoTargetTemperature"
        default: ""
        }
        if !key.isEmpty, temperatureRanges[mode] != nil {
            return ["temperatureInUnits": .object([key: .number(value), "unit": "C"])]
        }
        return ["temperature": ["targetTemperature": .number(value)]]
    }

    private func clamp(_ value: Double) -> Double {
        let stepped = (value / temperatureStep).rounded() * temperatureStep
        return min(max(stepped, temperatureRange.lowerBound), temperatureRange.upperBound)
    }

    private func send(_ payload: JSON, rollback: @escaping (AirConditionerStore) -> Void) {
        Task {
            do {
                try await perform(payload)
            } catch {
                rollback(self)
                flash(error)
            }
        }
    }

    private func perform(_ payload: JSON) async throws {
        guard let client, let deviceID else { throw ThinQError.missingToken }
        ignoreStateUntil = .now + 10
        try await client.control(deviceID, payload)
    }

    private func flash(_ error: any Error) {
        notice = error.localizedDescription
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Profile & state mapping

    private func apply(profile raw: JSON) {
        let profile = raw["property"] ?? raw

        let celsiusProfile = celsius(profile["temperatureInUnits"])
        var ranges: [String: TemperatureRange] = [:]
        for (mode, key) in [("COOL", "coolTargetTemperature"), ("HEAT", "heatTargetTemperature"), ("AUTO", "autoTargetTemperature")] {
            if let range = writableRange(celsiusProfile?[key]) { ranges[mode] = range }
        }
        temperatureRanges = ranges
        if let range = writableRange(profile["temperature"]?["targetTemperature"]) {
            fallbackRange = range
        }

        let modeOrder = ["COOL", "HEAT", "AIR_DRY", "FAN", "AUTO"]
        modes = writableEnum(profile["airConJobMode"]?["currentJobMode"])
            .sorted { (modeOrder.firstIndex(of: $0) ?? 99) < (modeOrder.firstIndex(of: $1) ?? 99) }

        // `windStrength` is the list with Auto in it; prefer it over the detailed one.
        windKey = isWritable(profile["airFlow"]?["windStrength"]) ? "windStrength" : "windStrengthDetail"
        let fanOrder = ["AUTO", "NATURE", "SLOW", "LOW", "LOW_MID", "MID", "MID_HIGH", "HIGH", "POWER"]
        fanSpeeds = writableEnum(profile["airFlow"]?[windKey])
            .sorted { (fanOrder.firstIndex(of: $0) ?? 99) < (fanOrder.firstIndex(of: $1) ?? 99) }

        supportsEco = isWritable(profile["powerSave"]?["powerSaveEnabled"])

        // LG publishes no range for the sleep timer, only that hours are writable.
        sleepOptions = isWritable(profile["sleepTimer"]?["relativeHourToStop"]) ? [0, 1, 2, 3, 4, 6, 8] : []

        supportsVerticalSwing = isWritable(profile["windDirection"]?["rotateUpDown"])
        supportsHorizontalSwing = isWritable(profile["windDirection"]?["rotateLeftRight"])
        airflowOptions = [.off]
            + (supportsVerticalSwing ? [.vertical] : [])
            + (supportsHorizontalSwing ? [.horizontal] : [])
            + (supportsVerticalSwing && supportsHorizontalSwing ? [.both] : [])
        if airflowOptions == [.off] { airflowOptions = [] }
    }

    private func apply(state: JSON) {
        if let operation = state["operation"]?["airConOperationMode"]?.string {
            isOn = operation == "POWER_ON"
        }
        if let currentMode = state["airConJobMode"]?["currentJobMode"]?.string {
            mode = currentMode
        }
        if let temperature = celsius(state["temperatureInUnits"] ?? state["temperature"]) {
            roomTemperature = temperature["currentTemperature"]?.double ?? roomTemperature
            if let target = temperature["targetTemperature"]?.double { targetTemperature = target }
        }
        reportsError = state["runState"]?["currentState"]?.string == "ERROR"
        if let speed = state["airFlow"]?[windKey]?.string {
            fanSpeed = speed
        }
        if let eco = state["powerSave"]?["powerSaveEnabled"]?.bool {
            isEcoOn = eco
        }
        if let sleep = state["sleepTimer"] {
            if sleep["relativeStopTimer"]?.string == "SET" {
                let hours = Int(sleep["relativeHourToStop"]?.double ?? 0)
                let minutes = Int(sleep["relativeMinuteToStop"]?.double ?? 0)
                sleepHours = hours + (minutes > 0 ? 1 : 0)
                sleepRemaining = minutes > 0 ? "\(hours) h \(minutes) m" : "\(hours) h"
            } else {
                sleepHours = 0
                sleepRemaining = nil
            }
        }
        if let direction = state["windDirection"] {
            let vertical = direction["rotateUpDown"]?.bool ?? false
            let horizontal = direction["rotateLeftRight"]?.bool ?? false
            airflow = switch (vertical, horizontal) {
            case (true, true): .both
            case (true, false): .vertical
            case (false, true): .horizontal
            case (false, false): .off
            }
        }
    }

    /// `temperatureInUnits` is a list with one entry per unit; pick Celsius.
    private func celsius(_ json: JSON?) -> JSON? {
        if let entries = json?.array {
            return entries.first { $0["unit"]?.string == "C" } ?? entries.first
        }
        return json
    }

    private func isWritable(_ property: JSON?) -> Bool {
        property?["mode"]?.array?.contains(.string("w")) ?? false
    }

    private func writableEnum(_ property: JSON?) -> [String] {
        guard isWritable(property) else { return [] }
        let values = property?["value"]?["w"]?.array ?? property?["value"]?["r"]?.array ?? []
        return values.compactMap(\.string)
    }

    private func writableRange(_ property: JSON?) -> TemperatureRange? {
        guard isWritable(property),
              let range = property?["value"]?["w"] ?? property?["value"]?["r"],
              let lower = range["min"]?.double, let upper = range["max"]?.double, lower < upper
        else { return nil }
        return TemperatureRange(min: lower, max: upper, step: range["step"]?.double ?? 1)
    }
}

struct TemperatureRange: Equatable {
    let min: Double
    let max: Double
    let step: Double
}
