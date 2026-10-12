import CryptoKit
import Foundation

nonisolated enum MerossError: LocalizedError {
    case device(String)

    var errorDescription: String? {
        switch self {
        case .device(let detail): detail.isEmpty ? "The plug rejected the command" : detail
        }
    }
}

/// Meross's local HTTP API: POST /config with a signed header.
/// The signature is md5(messageId + key + timestamp). Plugs that aren't
/// locked to a Meross cloud key accept an empty key.
nonisolated struct MerossClient: Sendable {
    let host: String
    var key = ""

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    func get(_ namespace: String, _ payload: JSON = [:], timeout: TimeInterval = 3) async throws -> JSON {
        try await call("GET", namespace, payload, timeout: timeout)
    }

    func set(_ namespace: String, _ payload: JSON, timeout: TimeInterval = 3) async throws {
        _ = try await call("SET", namespace, payload, timeout: timeout)
    }

    private func call(_ method: String, _ namespace: String, _ payload: JSON, timeout: TimeInterval) async throws -> JSON {
        let messageID = Self.md5Hex(UUID().uuidString)
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let body: JSON = [
            "header": [
                "from": .string("http://\(host)/config"),
                "messageId": .string(messageID),
                "method": .string(method),
                "namespace": .string(namespace),
                "payloadVersion": 1,
                "sign": .string(Self.md5Hex(messageID + key + String(timestamp))),
                "timestamp": .number(Double(timestamp)),
            ],
            "payload": payload,
        ]

        var request = URLRequest(url: URL(string: "http://\(host)/config")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await Self.session.data(for: request)
        let response = try JSONDecoder().decode(JSON.self, from: data)
        if response["header"]?["method"]?.string == "ERROR" {
            throw MerossError.device(response["payload"]?["error"]?["detail"]?.string ?? "")
        }
        return response["payload"] ?? .null
    }

    private static func md5Hex(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
