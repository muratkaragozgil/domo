import AppKit
import Foundation
import Observation
import os

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
    /// Icons picked by hand; everything else follows the outlet's name.
    private var icons: [String: String]

    private var pollTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    private var ignoreStateUntil: [String: Date] = [:]
    private var isPanelOpen = false

    private static let log = Logger(subsystem: "com.muratkaragozgil.domo", category: "plugs")
    private static let namesKey = "plugs.names"
    private static let iconsKey = "plugs.icons"
    private static let hostsKey = "plugs.hosts"

    init() {
        names = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        icons = UserDefaults.standard.dictionary(forKey: Self.iconsKey) as? [String: String] ?? [:]
        startPolling()
    }

    /// Fixed sample data for `--snapshot`; never touches the network.
    init(demo: Bool) {
        names = [
            "a": "Living Room", "a.1": "Subwoofer", "a.2": "PlayStation", "a.3": "Sound Bar", "a.4": "TV",
            "b": "Office", "b.1": "Speakers", "b.2": "Desk", "b.3": "Desk Light", "b.4": "Monitor", "b.5": "USB-C",
        ]
        icons = [:]
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

    func icon(of outlet: Outlet, in strip: PowerStrip) -> OutletIcon {
        icons["\(strip.id).\(outlet.channel)"].flatMap(OutletIcon.init(rawValue:))
            ?? .guess(for: name(of: outlet, in: strip), isUSB: strip.isUSB(outlet))
    }

    /// `nil` goes back to picking the icon from the name.
    func setIcon(_ icon: OutletIcon?, for outlet: Outlet, in strip: PowerStrip) {
        icons["\(strip.id).\(outlet.channel)"] = icon?.rawValue
        UserDefaults.standard.set(icons, forKey: Self.iconsKey)
    }

    func hasCustomIcon(_ outlet: Outlet, in strip: PowerStrip) -> Bool {
        icons["\(strip.id).\(outlet.channel)"] != nil
    }

    /// Bumped when a picture changes, so tiles reload it.
    private(set) var photoRevision = 0

    /// A picture of the actual device, if one was chosen; it wins over the icon.
    func photo(of outlet: Outlet, in strip: PowerStrip) -> NSImage? {
        _ = photoRevision
        return OutletImages.image(for: "\(strip.id).\(outlet.channel)")
    }

    func choosePhoto(for outlet: Outlet, in strip: PowerStrip) {
        if OutletImages.choose(for: "\(strip.id).\(outlet.channel)", title: name(of: outlet, in: strip)) {
            photoRevision += 1
        }
    }

    func removePhoto(for outlet: Outlet, in strip: PowerStrip) {
        OutletImages.remove(for: "\(strip.id).\(outlet.channel)")
        photoRevision += 1
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
        // Nothing answered (offline, or Local Network access not granted yet):
        // keep the remembered addresses for the next try.
        Self.log.notice("Discovery found \(found.count, privacy: .public) strip(s), \(cached.count, privacy: .public) remembered")
        guard !found.isEmpty else {
            status = .failed("No Meross plugs found")
            return
        }

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
