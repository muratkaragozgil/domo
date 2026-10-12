import CommonCrypto
import CryptoKit
import Darwin
import Foundation

/// Xiaomi's local miIO protocol: UDP 54321, AES-128-CBC keyed by the
/// device token, a 32-byte header with an MD5 checksum.
nonisolated enum MiioError: LocalizedError, Equatable {
    case invalidToken
    case notFound
    case noReply
    case wrongToken
    case device(code: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "A token is 32 hex characters"
        case .notFound: "No feeder answered on this network"
        case .noReply: "Feeder didn't answer"
        case .wrongToken: "Token doesn't match this feeder"
        case .device(-9999, _): "Feeder didn't confirm. Check the bowl before trying again."
        case .device(let code, let message): message.isEmpty ? "Feeder error \(code)" : message.capitalizedFirst
        case .transport(let message): message
        }
    }
}

nonisolated struct MiioCipher: Sendable {
    let token: Data
    private let key: Data
    private let iv: Data

    init(tokenHex: String) throws {
        let hex = tokenHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.count == 32, let token = Data(hex: hex) else { throw MiioError.invalidToken }
        self.token = token
        key = Self.md5(token)
        iv = Self.md5(key + token)
    }

    static func md5(_ data: Data) -> Data { Data(Insecure.MD5.hash(data: data)) }

    func encrypt(_ data: Data) -> Data? { crypt(CCOperation(kCCEncrypt), data) }
    func decrypt(_ data: Data) -> Data? { crypt(CCOperation(kCCDecrypt), data) }

    private func crypt(_ operation: CCOperation, _ input: Data) -> Data? {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, kCCKeySizeAES128, ivBytes.baseAddress,
                                inBytes.baseAddress, input.count, out.baseAddress, out.count, &written)
                    }
                }
            }
        }
        return status == kCCSuccess ? output.prefix(written) : nil
    }
}

/// One device, one conversation at a time. The actor keeps the handshake
/// stamp and message IDs consistent across calls.
actor MiioDevice {
    let host: String
    private let cipher: MiioCipher
    private var deviceID: UInt32 = 0
    private var stamp: UInt32 = 0
    private var stampTakenAt = ContinuousClock.now
    private var nextMessageID = Int.random(in: 1...9000)

    init(host: String, cipher: MiioCipher) {
        self.host = host
        self.cipher = cipher
    }

    func call(_ method: String, _ params: JSON = [], timeout: Duration = .seconds(3)) async throws -> JSON {
        if deviceID == 0 || ContinuousClock.now - stampTakenAt > .seconds(60) {
            try await handshake()
        }
        nextMessageID += 1
        let elapsed = UInt32((ContinuousClock.now - stampTakenAt).components.seconds)
        let message: JSON = ["id": .number(Double(nextMessageID)), "method": .string(method), "params": params]
        var payload = try JSONEncoder().encode(message)
        payload.append(0)
        guard let encrypted = cipher.encrypt(payload) else { throw MiioError.transport("Encryption failed") }

        var header = Data([0x21, 0x31])
        header.appendBigEndian(UInt16(32 + encrypted.count))
        header.appendBigEndian(UInt32(0))
        header.appendBigEndian(deviceID)
        header.appendBigEndian(stamp &+ elapsed &+ 1)
        let packet = header + MiioCipher.md5(header + cipher.token + encrypted) + encrypted

        let reply = try await MiioTransport.exchange(packet, with: host, timeout: timeout)
        return try decode(reply)
    }

    /// Reads MIoT properties. Keys come back as "siid.piid".
    func properties(_ pairs: [(siid: Int, piid: Int)]) async throws -> [String: JSON] {
        let params = JSON.array(pairs.map { ["did": .string("\($0.siid)-\($0.piid)"), "siid": .number(Double($0.siid)), "piid": .number(Double($0.piid))] })
        var values: [String: JSON] = [:]
        for item in try await call("get_properties", params).array ?? [] where item["code"]?.double == 0 {
            if let siid = item["siid"]?.double, let piid = item["piid"]?.double {
                values["\(Int(siid)).\(Int(piid))"] = item["value"]
            }
        }
        return values
    }

    func setProperty(siid: Int, piid: Int, value: JSON) async throws {
        let result = try await call("set_properties", [["did": "set", "siid": .number(Double(siid)), "piid": .number(Double(piid)), "value": value]])
        if let code = result.array?.first?["code"]?.double, code != 0 {
            throw MiioError.device(code: Int(code), message: "")
        }
    }

    /// Runs a MIoT action. Arguments are `{piid, value}` pairs: this feeder
    /// ignores bare values and times out.
    func action(siid: Int, aiid: Int, arguments: [(piid: Int, value: JSON)] = []) async throws -> JSON {
        let args = JSON.array(arguments.map { ["piid": .number(Double($0.piid)), "value": $0.value] })
        let result = try await call("action", ["did": .string("call-\(siid)-\(aiid)"), "siid": .number(Double(siid)), "aiid": .number(Double(aiid)), "in": args], timeout: .seconds(6))
        if let code = result["code"]?.double, code != 0 {
            throw MiioError.device(code: Int(code), message: "")
        }
        return result
    }

    private func handshake() async throws {
        let reply = try await MiioTransport.exchange(MiioTransport.hello, with: host, timeout: .seconds(2))
        guard let hello = MiioTransport.parseHello(reply) else { throw MiioError.noReply }
        deviceID = hello.deviceID
        stamp = hello.stamp
        stampTakenAt = .now
    }

    private func decode(_ packet: Data) throws -> JSON {
        guard packet.count > 32 else { throw MiioError.noReply }
        let header = packet.prefix(16)
        let checksum = packet.subdata(in: 16..<32)
        let body = packet.subdata(in: 32..<packet.count)
        guard MiioCipher.md5(header + cipher.token + body) == checksum else { throw MiioError.wrongToken }
        guard var plain = cipher.decrypt(body) else { throw MiioError.wrongToken }
        while plain.last == 0 { plain.removeLast() }
        let json = try JSONDecoder().decode(JSON.self, from: plain)
        if let error = json["error"] {
            throw MiioError.device(code: Int(error["code"]?.double ?? 0), message: error["message"]?.string ?? "")
        }
        return json["result"] ?? .null
    }
}

nonisolated enum MiioTransport {
    static let port: UInt16 = 54321
    static let hello = Data([0x21, 0x31, 0x00, 0x20] + Array(repeating: 0xFF, count: 28))

    static func parseHello(_ data: Data) -> (deviceID: UInt32, stamp: UInt32)? {
        guard data.count >= 32, data[data.startIndex] == 0x21, data[data.startIndex + 1] == 0x31 else { return nil }
        let bytes = [UInt8](data)
        let id = bytes[8..<12].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let stamp = bytes[12..<16].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return (id, stamp)
    }

    /// One request, one reply.
    @concurrent
    static func exchange(_ packet: Data, with host: String, timeout: Duration) async throws -> Data {
        guard let reply = try send(packet, to: [host], timeout: timeout, firstOnly: true).first else {
            throw MiioError.noReply
        }
        return reply.data
    }

    /// Says hello to every broadcast address and returns whoever answers.
    @concurrent
    static func discover(timeout: Duration = .seconds(2)) async throws -> [String] {
        let replies = try send(hello, to: broadcastAddresses(), timeout: timeout, firstOnly: false)
        var hosts: [String] = []
        for reply in replies where parseHello(reply.data) != nil && !hosts.contains(reply.host) {
            hosts.append(reply.host)
        }
        return hosts
    }

    private static func send(_ packet: Data, to hosts: [String], timeout: Duration, firstOnly: Bool) throws -> [(host: String, data: Data)] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw MiioError.transport("Couldn't open a socket") }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var tick = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tick, socklen_t(MemoryLayout<timeval>.size))

        for host in hosts {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { continue }
            _ = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var replies: [(String, Data)] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
                }
            }
            guard count > 0 else { continue }
            var name = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &name, socklen_t(name.count))
            replies.append((String(cStringBuffer: name), Data(buffer[0..<count])))
            if firstOnly { break }
        }
        return replies
    }

    /// Broadcast address of every active IPv4 interface (Wi-Fi, Ethernet…).
    private static func broadcastAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return ["255.255.255.255"] }
        defer { freeifaddrs(list) }
        var result: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let broadcast = entry.pointee.ifa_dstaddr
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(broadcast, socklen_t(broadcast.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let name = String(cStringBuffer: host)
                if !result.contains(name) { result.append(name) }
            }
        }
        return result.isEmpty ? ["255.255.255.255"] : result
    }
}

nonisolated extension Data {
    init?(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

nonisolated extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

nonisolated extension String {
    /// A C string held in a fixed-size buffer, up to its terminating NUL.
    init(cStringBuffer buffer: [CChar]) {
        self.init(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
