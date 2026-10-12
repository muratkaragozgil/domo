import Foundation
import Observation
import os

struct Meal: Identifiable, Equatable {
    let id: Int
    let hour: Int
    let minute: Int
    let portions: Int

    var time: String { String(format: "%02d:%02d", hour, minute) }
    var minuteOfDay: Int { hour * 60 + minute }
}

enum FoodLevel: Int {
    case normal = 0, low = 1, empty = 2

    var title: String {
        switch self {
        case .normal: "Normal"
        case .low: "Low"
        case .empty: "Empty"
        }
    }
}

/// Xiaomi Smart Pet Food Feeder (mmgg.feeder.fi1), spoken to over the LAN.
/// Finds itself by broadcasting a hello and keeping whichever device the
/// token unlocks, so the repo never hardcodes an IP.
@Observable
final class CatFeederStore {
    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    enum FeedState: Equatable {
        case idle, feeding, fed
    }

    static let portionRange = 1...10
    private static let log = Logger(subsystem: "com.muratkaragozgil.domo", category: "feeder")

    private(set) var status: Status = .connecting
    private(set) var notice: String?
    private(set) var hasLoaded = false
    private(set) var needsToken = false

    private(set) var foodLevel: FoodLevel = .normal
    private(set) var hasFault = false
    private(set) var desiccantDays: Int?
    private(set) var meals: [Meal] = []
    private(set) var isScheduleOn = true

    private(set) var portions = 1
    private(set) var feedState: FeedState = .idle
    /// Bumps on every confirmed feed; the view drops kibble when it changes.
    private(set) var feedCount = 0

    private var device: MiioDevice?
    private var pollTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    private var lastScheduleRead = Date.distantPast
    private var isPanelOpen = false

    init() {
        startPolling()
    }

    /// Fixed sample data for `--snapshot`; never touches the network.
    init(demo: Bool) {
        hasLoaded = true
        status = .connected
        meals = [(8, 0, 2), (10, 0, 1), (12, 0, 2), (14, 0, 2), (17, 0, 2), (19, 0, 1), (21, 0, 2)]
            .enumerated().map { Meal(id: $0.offset, hour: $0.element.0, minute: $0.element.1, portions: $0.element.2) }
        desiccantDays = 0
    }

    var nextMeal: Meal? {
        guard isScheduleOn, !meals.isEmpty else { return nil }
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let minute = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        return meals.first { $0.minuteOfDay > minute } ?? meals.first
    }

    var dailyPortions: Int { meals.reduce(0) { $0 + $1.portions } }

    // MARK: - Lifecycle

    func panelDidOpen() {
        isPanelOpen = true
        if Date.now.timeIntervalSince(lastRefresh) > 15 { startPolling() }
    }

    func panelDidClose() {
        isPanelOpen = false
    }

    func reload() {
        device = nil
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval: Duration = self?.isPanelOpen == true ? .seconds(30) : .seconds(600)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func refresh() async {
        do {
            let device = try await currentDevice()
            let values = try await device.properties([(2, 1), (2, 6), (5, 5), (11, 2)])
            apply(values)
            if Date.now.timeIntervalSince(lastScheduleRead) > 600 {
                meals = try await Self.readSchedule(from: device)
                lastScheduleRead = .now
            }
            lastRefresh = .now
            status = .connected
            hasLoaded = true
            needsToken = false
        } catch is CancellationError {
            return
        } catch let error as MiioError {
            Self.log.error("Feeder refresh failed: \(error.localizedDescription, privacy: .public)")
            switch error {
            case .invalidToken, .wrongToken: needsToken = true
            case .noReply, .notFound: device = nil // the IP may have changed; look again next time
            default: break
            }
            status = .failed(error.localizedDescription)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func currentDevice() async throws -> MiioDevice {
        if let device { return device }
        let cipher = try MiioCipher(tokenHex: FeederConfig.token())
        if let host = FeederConfig.cachedHost {
            let cached = MiioDevice(host: host, cipher: cipher)
            if let model = (try? await cached.call("miIO.info", timeout: .seconds(2)))?["model"]?.string, model.hasPrefix("mmgg.feeder") {
                device = cached
                return cached
            }
        }
        let found = try await Self.find(cipher: cipher)
        FeederConfig.cachedHost = found.host
        device = found
        return found
    }

    /// The feeder is whichever device on the network the token decrypts.
    static func find(cipher: MiioCipher) async throws -> MiioDevice {
        for host in try await MiioTransport.discover() {
            let candidate = MiioDevice(host: host, cipher: cipher)
            if let model = (try? await candidate.call("miIO.info", timeout: .seconds(1.5)))?["model"]?.string,
               model.hasPrefix("mmgg.feeder") {
                return candidate
            }
        }
        throw MiioError.notFound
    }

    /// The plan comes back as "id,hour,minute,portions,status" groups, five
    /// slots per page; unused slots are 255s.
    static func readSchedule(from device: MiioDevice) async throws -> [Meal] {
        var meals: [Meal] = []
        for page in 0...1 {
            let result = try await device.action(siid: 5, aiid: 6, arguments: [(piid: 11, value: .number(Double(page)))])
            let numbers = (result["out"]?.array?.first?["value"]?.string ?? "")
                .split(separator: ",").compactMap { Int($0) }
            for start in stride(from: 0, to: numbers.count - 4, by: 5) {
                let (id, hour, minute, portions) = (numbers[start], numbers[start + 1], numbers[start + 2], numbers[start + 3])
                guard hour < 24, minute < 60, (1...30).contains(portions) else { continue }
                meals.append(Meal(id: id, hour: hour, minute: minute, portions: portions))
            }
        }
        return meals.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    private func apply(_ values: [String: JSON]) {
        if let fault = values["2.1"]?.double { hasFault = fault == 3 || fault == 5 }
        if let level = values["2.6"]?.double { foodLevel = FoodLevel(rawValue: Int(level)) ?? .normal }
        if let plan = values["5.5"]?.double { isScheduleOn = plan == 1 }
        if let days = values["11.2"]?.double { desiccantDays = Int(days) }
    }

    // MARK: - Commands

    func setPortions(_ value: Int) {
        portions = min(max(value, Self.portionRange.lowerBound), Self.portionRange.upperBound)
    }

    /// Never retried automatically: a retry after a silent success feeds twice.
    func feed() {
        guard feedState == .idle, let device else { return }
        let portions = self.portions
        feedState = .feeding
        Task {
            do {
                _ = try await device.action(siid: 2, aiid: 1, arguments: [(piid: 5, value: .number(Double(portions)))])
                feedCount += 1
                feedState = .fed
                try? await Task.sleep(for: .seconds(1.8))
                if feedState == .fed { feedState = .idle }
            } catch {
                feedState = .idle
                flash(error)
            }
        }
    }

    func setSchedule(on: Bool) {
        guard let device, on != isScheduleOn else { return }
        isScheduleOn = on
        Task {
            do {
                try await device.setProperty(siid: 5, piid: 5, value: .number(on ? 1 : 0))
            } catch {
                isScheduleOn = !on
                flash(error)
            }
        }
    }

    /// After a new desiccant pack goes in, restart its 30-day countdown.
    func resetDesiccant() {
        guard let device else { return }
        let previous = desiccantDays
        desiccantDays = 30
        Task {
            do {
                _ = try await device.action(siid: 11, aiid: 1)
                if let days = try await device.properties([(11, 2)])["11.2"]?.double { desiccantDays = Int(days) }
            } catch {
                desiccantDays = previous
                flash(error)
            }
        }
    }

    /// Checks the token by finding a feeder it unlocks, then saves it.
    func connect(token raw: String) async -> String? {
        do {
            let cipher = try MiioCipher(tokenHex: raw)
            let found = try await Self.find(cipher: cipher)
            try FeederConfig.save(token: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            FeederConfig.cachedHost = found.host
            device = found
        } catch {
            return error.localizedDescription
        }
        needsToken = false
        status = .connecting
        startPolling()
        return nil
    }

    private func flash(_ error: any Error) {
        notice = error.localizedDescription
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// Token in ~/.config/xiaomi-feeder/token (owner-only); last known IP in defaults.
nonisolated enum FeederConfig {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/xiaomi-feeder", directoryHint: .isDirectory)
    static var tokenURL: URL { directory.appending(path: "token") }

    static func token() throws -> String {
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty
        else { throw MiioError.invalidToken }
        return token
    }

    static func save(token: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.removeItem(at: tokenURL)
        guard manager.createFile(atPath: tokenURL.path, contents: Data((token + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static var cachedHost: String? {
        get { UserDefaults.standard.string(forKey: "catFeeder.host") }
        set { UserDefaults.standard.set(newValue, forKey: "catFeeder.host") }
    }
}

/// `Domo --feeder-status`: discovery and a read-only status check, no UI.
enum FeederDiagnostics {
    static func run() async {
        do {
            let cipher = try MiioCipher(tokenHex: FeederConfig.token())
            let started = ContinuousClock.now
            let device = try await CatFeederStore.find(cipher: cipher)
            print("found:", device.host, "in", ContinuousClock.now - started)
            let info = try await device.call("miIO.info")
            print("model:", info["model"]?.string ?? "?", "fw:", info["fw_ver"]?.string ?? "?")
            let values = try await device.properties([(2, 1), (2, 6), (5, 5), (11, 2)])
            print("properties:", values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.double.map { String(Int($0)) } ?? "?")" }.joined(separator: " "))
            let meals = try await CatFeederStore.readSchedule(from: device)
            print("meals:", meals.map { "\($0.time)×\($0.portions)" }.joined(separator: ", "))
        } catch {
            print("error:", error.localizedDescription)
        }
    }
}
