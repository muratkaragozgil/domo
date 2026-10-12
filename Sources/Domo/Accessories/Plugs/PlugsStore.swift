import Foundation
import Observation

nonisolated struct Outlet: Identifiable, Equatable, Sendable {
    let channel: Int
    var isOn: Bool
    var id: Int { channel }
}

/// One Meross strip or plug. Channel 0 on a strip switches every outlet at
/// once, so it's kept apart from the individual outlets.
nonisolated struct PowerStrip: Identifiable, Equatable, Sendable {
    let id: String
    var host: String
    let model: String
    var outlets: [Outlet]
    var hasMasterSwitch: Bool

    var displayModel: String { model.uppercased().replacingOccurrences(of: "FC", with: "F") }

    /// Most Meross strips put their USB ports on the last channel.
    func isUSB(_ outlet: Outlet) -> Bool {
        hasMasterSwitch && outlets.count == 5 && outlet.channel == outlets.last?.channel
    }
}

/// Meross plugs on the local network. No token: they're found by sweeping
/// the subnet once, then remembered by their UUID.
@Observable
final class PlugsStore {
    enum Status: Equatable {
        case searching
        case connected
        case failed(String)
    }

    private(set) var strips: [PowerStrip] = []
    private(set) var status: Status = .searching
    private(set) var notice: String?
    private(set) var hasLoaded = false
    private var names: [String: String]

    private var pollTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    private var ignoreStateUntil: [String: Date] = [:]
    private var isPanelOpen = false

    private static let namesKey = "plugs.names"
    private static let hostsKey = "plugs.hosts"

    init() {
        names = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        startPolling()
    }

    /// Fixed sample data for `--snapshot`; never touches the network.
    init(demo: Bool) {
        names = ["a": "Desk", "a.1": "Monitor", "a.2": "Lamp", "a.3": "Speakers", "b": "Living Room", "b.1": "TV", "b.2": "Router"]
        strips = [
            PowerStrip(id: "a", host: "", model: "msp844", outlets: [1, 2, 3, 4, 5].map { Outlet(channel: $0, isOn: $0 != 3) }, hasMasterSwitch: true),
            PowerStrip(id: "b", host: "", model: "mss425fc", outlets: [1, 2, 3, 4, 5].map { Outlet(channel: $0, isOn: $0 < 3) }, hasMasterSwitch: true),
        ]
        status = .connected
        hasLoaded = true
    }

    // MARK: - Names

    func name(of strip: PowerStrip) -> String {
        names[strip.id] ?? strip.displayModel
    }

    func name(of outlet: Outlet, in strip: PowerStrip) -> String {
        names["\(strip.id).\(outlet.channel)"] ?? (strip.isUSB(outlet) ? "USB" : "Outlet \(outlet.channel)")
    }

    func rename(_ strip: PowerStrip, to name: String) {
        setName(name, for: strip.id)
    }

    func rename(_ outlet: Outlet, in strip: PowerStrip, to name: String) {
        setName(name, for: "\(strip.id).\(outlet.channel)")
    }

    private func setName(_ name: String, for key: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[key] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(names, forKey: Self.namesKey)
    }

    // MARK: - Lifecycle

    func panelDidOpen() {
        isPanelOpen = true
        if Date.now.timeIntervalSince(lastRefresh) > 10 { startPolling() }
    }

    func panelDidClose() {
        isPanelOpen = false
    }

    /// Forget what we know and sweep the network again.
    func rescan() {
        strips = []
        hasLoaded = false
        status = .searching
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval: Duration = self?.isPanelOpen == true ? .seconds(20) : .seconds(600)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func refresh() async {
        if strips.isEmpty {
            await discover()
            return
        }
        let current = strips
        let results = await withTaskGroup(of: (String, PowerStrip?).self) { group in
            for strip in current {
                group.addTask { (strip.id, await Self.probe(strip.host, timeout: 2)) }
            }
            var results: [String: PowerStrip?] = [:]
            for await (id, strip) in group { results[id] = strip }
            return results
        }
        guard !Task.isCancelled else { return }

        var missing: [String] = []
        for index in strips.indices {
            let id = strips[index].id
            guard let fresh = results[id] ?? nil else {
                missing.append(name(of: strips[index]))
                continue
            }
            if Date.now >= ignoreStateUntil[id, default: .distantPast] {
                strips[index].outlets = fresh.outlets
            }
        }
        lastRefresh = .now
        // A plug that moved to a new IP needs a fresh sweep.
        if missing.count == strips.count {
            await discover()
        } else {
            status = missing.isEmpty ? .connected : .failed("\(missing.joined(separator: ", ")) isn't answering")
        }
    }

    private func discover() async {
        status = .searching
        let cached = UserDefaults.standard.dictionary(forKey: Self.hostsKey) as? [String: String] ?? [:]
        var found = await Self.probeAll(Array(Set(cached.values)), timeout: 2)
        if found.count < cached.count || found.isEmpty {
            found = await Self.probeAll(LocalNetwork.neighborHosts(), timeout: 1.2)
        }
        guard !Task.isCancelled else { return }

        strips = found.sorted { $0.host.compare($1.host, options: .numeric) == .orderedAscending }
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: strips.map { ($0.id, $0.host) }), forKey: Self.hostsKey)
        lastRefresh = .now
        hasLoaded = !strips.isEmpty
        status = strips.isEmpty ? .failed("No Meross plugs found") : .connected
    }

    /// Probes hosts 64 at a time; an empty address times out in ~1s.
    @concurrent
    nonisolated static func probeAll(_ hosts: [String], timeout: TimeInterval) async -> [PowerStrip] {
        await withTaskGroup(of: PowerStrip?.self) { group in
            var pending = hosts.makeIterator()
            for _ in 0..<64 {
                guard let host = pending.next() else { break }
                group.addTask { await probe(host, timeout: timeout) }
            }
            var found: [PowerStrip] = []
            while let result = await group.next() {
                if let strip = result, !found.contains(where: { $0.id == strip.id }) { found.append(strip) }
                if let host = pending.next() { group.addTask { await probe(host, timeout: timeout) } }
            }
            return found
        }
    }

    nonisolated static func probe(_ host: String, timeout: TimeInterval) async -> PowerStrip? {
        guard let payload = try? await MerossClient(host: host).get("Appliance.System.All", timeout: timeout),
              let hardware = payload["all"]?["system"]?["hardware"],
              let uuid = hardware["uuid"]?.string
        else { return nil }

        // Strips report a list; single plugs sometimes a lone object.
        let toggles = payload["all"]?["digest"]?["togglex"]
        let entries = toggles?.array ?? toggles.map { [$0] } ?? []
        let channels = entries.compactMap { entry -> Outlet? in
            guard let channel = entry["channel"]?.double, let onoff = entry["onoff"]?.double else { return nil }
            return Outlet(channel: Int(channel), isOn: onoff == 1)
        }
        guard !channels.isEmpty else { return nil }

        let hasMaster = channels.count > 1 && channels.contains { $0.channel == 0 }
        return PowerStrip(
            id: uuid,
            host: host,
            model: hardware["type"]?.string ?? "meross",
            outlets: hasMaster ? channels.filter { $0.channel != 0 } : channels,
            hasMasterSwitch: hasMaster
        )
    }

    // MARK: - Commands

    func toggle(_ outlet: Outlet, in strip: PowerStrip) {
        setOutlets(in: strip, channel: outlet.channel, on: !outlet.isOn)
    }

    /// Channel 0 on a strip: every outlet at once.
    func setAll(in strip: PowerStrip, on: Bool) {
        setOutlets(in: strip, channel: 0, on: on)
    }

    private func setOutlets(in strip: PowerStrip, channel: Int, on: Bool) {
        guard let index = strips.firstIndex(where: { $0.id == strip.id }) else { return }
        let previous = strips[index].outlets
        for i in strips[index].outlets.indices where channel == 0 || strips[index].outlets[i].channel == channel {
            strips[index].outlets[i].isOn = on
        }
        ignoreStateUntil[strip.id] = .now + 3

        Task {
            do {
                try await MerossClient(host: strip.host).set("Appliance.Control.ToggleX", ["togglex": ["channel": .number(Double(channel)), "onoff": .number(on ? 1 : 0)]])
            } catch {
                if let index = strips.firstIndex(where: { $0.id == strip.id }) { strips[index].outlets = previous }
                flash("\(name(of: strip)): \(error.localizedDescription)")
            }
        }
    }

    private func flash(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// `Domo --plugs-status`: sweep the network and list what answered. Read-only.
enum PlugsDiagnostics {
    static func run() async {
        let started = ContinuousClock.now
        let hosts = LocalNetwork.neighborHosts()
        let strips = await PlugsStore.probeAll(hosts, timeout: 1.2)
        print("swept \(hosts.count) addresses in \(ContinuousClock.now - started), found \(strips.count)")
        for strip in strips {
            let outlets = strip.outlets.map { "\($0.channel):\($0.isOn ? "on" : "off")" }.joined(separator: " ")
            print("- \(strip.displayModel) at \(strip.host) master=\(strip.hasMasterSwitch) \(outlets)")
        }
    }
}
