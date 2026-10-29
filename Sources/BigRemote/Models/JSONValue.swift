import Foundation

/// A small dynamic JSON value. Used for SmartThings arguments, art channel
/// payloads (which are JSON strings inside JSON) and preset arguments.
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Valor JSON inválido")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    /// String form for scalars (numbers become their decimal text).
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value):
            if value.rounded() == value, abs(value) < 1e15 { return String(Int(value)) }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return value.lowercased() == "true" ? true : (value.lowercased() == "false" ? false : nil)
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Parses JSON text. Returns nil when the text is not JSON.
    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Compact JSON text with sorted keys (stable output for tests).
    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Converts a token the user typed in the preset editor:
    /// `15` -> int, `1.5` -> double, `true`/`false` -> bool,
    /// `"7"` (quoted) -> string "7", anything else -> string.
    static func fromUserToken(_ raw: String) -> JSONValue {
        let token = raw.trimmingCharacters(in: .whitespaces)
        if token.count >= 2, token.hasPrefix("\""), token.hasSuffix("\"") {
            return .string(String(token.dropFirst().dropLast()))
        }
        if token == "true" { return .bool(true) }
        if token == "false" { return .bool(false) }
        if let integer = Int(token) { return .int(integer) }
        if token.contains("."), let decimal = Double(token) { return .double(decimal) }
        return .string(token)
    }

    /// Inverse of `fromUserToken` for display in the editor.
    var userToken: String {
        switch self {
        case .string(let value):
            if Int(value) != nil || Double(value) != nil || value == "true" || value == "false" { return "\"\(value)\"" }
            return value
        default: return stringValue ?? jsonString()
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}
