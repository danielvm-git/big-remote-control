// story: e12s01
import CryptoKit
import Foundation

enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug, info, warning, error
}

enum LogCategory: String, Codable, Sendable, CaseIterable {
    case app, pairing, link, command, poll, power, discovery, network
}

/// One JSON line of the log file.
struct LogEntry: Codable, Sendable, Equatable {
    var ts: String
    var level: LogLevel
    var category: LogCategory
    var message: String
    /// "mac" or "ios".
    var device: String
    var tv: String?
    var fields: [String: String]
}

/// Keeps pairing secrets out of the log. A token is only ever logged as a
/// fingerprint: enough to see that it changed, useless for using it.
enum LogRedactor {
    /// Field names whose value is never written (lowercased, "-" and "_" dropped).
    static let secretNames: Set<String> = [
        "token", "pin", "clientkey", "password", "authorization", "cookie", "secret", "psk", "auth",
    ]

    static func isSecretName(_ name: String) -> Bool {
        secretNames.contains(name.lowercased().filter { $0 != "-" && $0 != "_" })
    }

    /// 4 bytes of HMAC-SHA256 under a per-install key, as 8 hex characters. Samsung tokens are 8 digits
    /// and Sony PINs 4, so an unkeyed hash could be reversed by enumeration; the key never leaves the device.
    static func fingerprint(_ secret: String, key: SymmetricKey) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(secret.utf8), using: key)
            .prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Masks `token=...`, `auth=...`, `pin=...` and `psk=...` in free text:
    /// URLSession errors carry the socket URL, and the URL carries the token.
    static func scrub(_ text: String) -> String {
        text.replacing(/(token|auth|pin|psk)=[^&\s"');]+/.ignoresCase()) { "\($0.output.1)=<redacted>" }
    }
}

enum LogFormat {
    static func entry(
        level: LogLevel,
        category: LogCategory,
        message: String,
        tv: String? = nil,
        device: String,
        fields: [String: String] = [:],
        date: Date = Date()
    ) -> LogEntry {
        var safe: [String: String] = [:]
        for (name, value) in fields {
            safe[name] = LogRedactor.isSecretName(name) ? "<redacted>" : LogRedactor.scrub(value)
        }
        return LogEntry(
            ts: date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
            level: level,
            category: category,
            message: LogRedactor.scrub(message),
            device: device,
            tv: tv,
            fields: safe
        )
    }

    /// One line, sorted keys, no trailing newline (JSON escapes newlines inside strings).
    static func line(_ entry: LogEntry) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(entry)) ?? Data(), as: UTF8.self)
    }
}

/// File naming and retention: one file per local day (`bigremote-20261029-00.jsonl`),
/// a new part when a file passes `maxBytes`, the newest `keepFiles` kept.
enum LogFiles {
    static let prefix = "bigremote-"
    static let suffix = ".jsonl"
    static let maxBytes = 5_000_000
    static let keepFiles = 14

    static func name(for date: Date, part: Int = 0, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return prefix + day + "-" + String(format: "%02d", part) + suffix
    }

    static func isLogName(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix(suffix)
    }

    /// Highest part already on disk for the day of `date` (0 when none).
    static func latestPart(in names: [String], for date: Date, calendar: Calendar = .current) -> Int {
        let dayPrefix = String(name(for: date, calendar: calendar).dropLast(suffix.count + 2))
        let parts = names.compactMap { name -> Int? in
            guard name.hasPrefix(dayPrefix), name.hasSuffix(suffix) else { return nil }
            return Int(name.dropFirst(dayPrefix.count).dropLast(suffix.count))
        }
        return parts.max() ?? 0
    }

    /// Oldest names beyond `keep` (names sort by date, then part).
    static func namesToDelete(_ names: [String], keep: Int = keepFiles) -> [String] {
        let logs = names.filter(isLogName).sorted()
        return logs.count > keep ? Array(logs.prefix(logs.count - keep)) : []
    }
}
