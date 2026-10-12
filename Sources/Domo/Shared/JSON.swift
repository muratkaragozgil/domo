import Foundation

/// Loosely typed JSON. ThinQ profiles and states differ per model, so the
/// app reads them by key instead of decoding into fixed structs.
nonisolated enum JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    subscript(key: String) -> JSON? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    var string: String? { if case .string(let s) = self { s } else { nil } }
    var double: Double? { if case .number(let n) = self { n } else { nil } }
    var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    var array: [JSON]? { if case .array(let a) = self { a } else { nil } }
    var object: [String: JSON]? { if case .object(let o) = self { o } else { nil } }
}

nonisolated extension JSON: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // ThinQ rejects 23.0 where it expects an integer.
            if value.rounded() == value, abs(value) < 1e15 {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

nonisolated extension JSON: ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral,
    ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral
{
    init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    init(arrayLiteral elements: JSON...) { self = .array(elements) }
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
}
