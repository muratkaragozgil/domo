import Foundation

/// Minimal client for LG's official ThinQ Connect API
/// (same endpoints as LG's `thinqconnect` SDK).
nonisolated struct ThinQClient: Sendable {
    struct Device: Sendable, Identifiable {
        let id: String
        let alias: String
        let type: String
        let model: String
    }

    let token: String
    let clientID: String
    var country = "TR"
    /// Turkey is served by the EIC (Europe) region.
    var baseURL = URL(string: "https://api-eic.lgthinq.com/")!

    private static let apiKey = "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3"

    func devices() async throws -> [Device] {
        let response = try await request("GET", "devices")
        return (response.array ?? []).compactMap { item in
            guard let id = item["deviceId"]?.string else { return nil }
            let info = item["deviceInfo"]
            return Device(
                id: id,
                alias: info?["alias"]?.string ?? "Air Conditioner",
                type: info?["deviceType"]?.string ?? "",
                model: info?["modelName"]?.string ?? ""
            )
        }
    }

    func profile(of deviceID: String) async throws -> JSON {
        try await request("GET", "devices/\(deviceID)/profile")
    }

    func state(of deviceID: String) async throws -> JSON {
        try await request("GET", "devices/\(deviceID)/state")
    }

    func control(_ deviceID: String, _ payload: JSON) async throws {
        _ = try await request("POST", "devices/\(deviceID)/control", body: payload, conditional: true)
    }

    private func request(_ method: String, _ path: String, body: JSON? = nil, conditional: Bool = false) async throws -> JSON {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(country, forHTTPHeaderField: "x-country")
        request.setValue(Self.messageID(), forHTTPHeaderField: "x-message-id")
        request.setValue(clientID, forHTTPHeaderField: "x-client-id")
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("OP", forHTTPHeaderField: "x-service-phase")
        if conditional {
            request.setValue("true", forHTTPHeaderField: "x-conditional-control")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONDecoder().decode(JSON.self, from: data)) ?? .null
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ThinQError.api(
                code: json["error"]?["code"]?.string ?? "\(status)",
                message: json["error"]?["message"]?.string ?? HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }
        return json["response"] ?? .null
    }

    /// 22-char URL-safe base64 of a random UUID, as the API expects.
    private static func messageID() -> String {
        let uuid = UUID().uuid
        let bytes = withUnsafeBytes(of: uuid) { Data($0) }
        return String(
            bytes.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .prefix(22)
        )
    }
}

nonisolated enum ThinQError: LocalizedError, Equatable {
    case missingToken
    case noAirConditioner
    case api(code: String, message: String)

    /// Errors only a new token can fix.
    var needsNewToken: Bool {
        switch self {
        case .missingToken: true
        // 1309 (HTTP 401) is what LG actually returns for a bad or revoked token.
        case .api(let code, _): ["1103", "1218", "1302", "1309", "401"].contains(code)
        case .noAirConditioner: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "No ThinQ token found"
        case .noAirConditioner:
            "No air conditioner on this account"
        case .api(let code, let message):
            switch code {
            case "1103", "1218", "1302", "1309", "401": "Token is invalid or expired"
            case "1222": "Air conditioner is offline"
            case "1306": "Too many requests, try again shortly"
            case "2304": "Turn the AC on first"
            case "2305": "Not available in this mode"
            case "2209", "2210", "2212": "AC is busy, try again"
            default: message.isEmpty ? "Error \(code)" : message
            }
        }
    }
}

/// Token and client ID live next to each other in ~/.config/lg-thinq.
nonisolated enum ThinQConfig {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/lg-thinq", directoryHint: .isDirectory)
    static var tokenURL: URL { directory.appending(path: "token") }
    private static var clientIDURL: URL { directory.appending(path: "client_id") }

    static func client() throws -> ThinQClient {
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty
        else { throw ThinQError.missingToken }
        return client(token: token)
    }

    static func client(token: String) -> ThinQClient {
        ThinQClient(token: token, clientID: clientID())
    }

    /// Owner-only file in an owner-only folder, created with those permissions
    /// so the token is never briefly world-readable.
    static func save(token: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.removeItem(at: tokenURL)
        guard manager.createFile(atPath: tokenURL.path, contents: Data((token + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// LG asks for one stable random ID per client; creating many gets you blocked.
    private static func clientID() -> String {
        if let existing = try? String(contentsOf: clientIDURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? id.write(to: clientIDURL, atomically: true, encoding: .utf8)
        return id
    }
}
