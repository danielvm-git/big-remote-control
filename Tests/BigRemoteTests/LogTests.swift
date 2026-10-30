// story: e12s01
import CryptoKit
import Foundation
import Testing

@Suite("Structured log")
struct LogTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let moment = Date(timeIntervalSince1970: 1_793_232_000) // 2026-10-29T00:00:00Z

    @Test func lineIsOneJSONObjectWithSortedKeys() throws {
        let entry = LogFormat.entry(
            level: .info, category: .pairing, message: "token.saved\nsecond line", tv: "duid-1", device: "mac",
            fields: ["b": "2", "a": "1"], date: moment
        )
        let line = LogFormat.line(entry)
        #expect(!line.contains("\n"))
        let json = try #require(JSONValue.parse(line))
        #expect(json["level"] == "info")
        #expect(json["category"] == "pairing")
        #expect(json["device"] == "mac")
        #expect(json["tv"] == "duid-1")
        #expect(json["ts"] == "2026-10-29T00:00:00.000Z")
        #expect(json["fields"]?["a"] == "1")
        #expect(line.range(of: "\"a\"")!.lowerBound < line.range(of: "\"b\"")!.lowerBound)
    }

    @Test func secretFieldsAreNeverWritten() {
        let entry = LogFormat.entry(
            level: .info, category: .pairing, message: "x", device: "ios",
            fields: ["token": "12345678", "client-key": "abc", "PIN": "0420", "Cookie": "auth=zzz", "code": "KEY_VOLUP"]
        )
        #expect(entry.fields["token"] == "<redacted>")
        #expect(entry.fields["client-key"] == "<redacted>")
        #expect(entry.fields["PIN"] == "<redacted>")
        #expect(entry.fields["Cookie"] == "<redacted>")
        #expect(entry.fields["code"] == "KEY_VOLUP")
    }

    @Test func socketURLsInErrorTextLoseTheirToken() {
        let text = "failed wss://192.168.1.20:8002/api/v2/channels/samsung.remote.control?name=QmlnIFJlbW90ZQ%3D%3D&token=12345678"
        let clean = LogRedactor.scrub(text)
        #expect(!clean.contains("12345678"))
        #expect(clean.contains("token=<redacted>"))
        #expect(clean.contains("name=QmlnIFJlbW90ZQ%3D%3D"))
        #expect(LogRedactor.scrub("Set-Cookie: auth=abc123def; Path=/") == "Set-Cookie: auth=<redacted>; Path=/")
        #expect(LogRedactor.scrub("pinging the tv") == "pinging the tv")
    }

    /// Keyed fingerprints: stable per key, different per token, and not the plain hash of the token,
    /// so an 8-digit token cannot be recovered from a log without the device's key (ADR 0009).
    @Test func fingerprintNeedsTheDeviceKey() {
        let key = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)
        let first = LogRedactor.fingerprint("12345678", key: key)
        #expect(first.count == 8)
        #expect(first == LogRedactor.fingerprint("12345678", key: key))
        #expect(first != LogRedactor.fingerprint("12345679", key: key))
        #expect(first != LogRedactor.fingerprint("12345678", key: other))
        let plain = SHA256.hash(data: Data("12345678".utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        #expect(first != plain)
        #expect(!first.contains("12345678"))
    }

    @Test func fileNamesSortByDayThenPart() {
        let first = LogFiles.name(for: moment, calendar: utc)
        let second = LogFiles.name(for: moment, part: 1, calendar: utc)
        let next = LogFiles.name(for: moment.addingTimeInterval(86_400), calendar: utc)
        #expect(first == "bigremote-20261029-00.jsonl")
        #expect([next, second, first].sorted() == [first, second, next])
    }

    @Test func latestPartOnlyLooksAtToday() {
        let names = [
            "bigremote-20261028-03.jsonl", "bigremote-20261029-00.jsonl", "bigremote-20261029-02.jsonl", "notes.txt",
        ]
        #expect(LogFiles.latestPart(in: names, for: moment, calendar: utc) == 2)
        #expect(LogFiles.latestPart(in: [], for: moment, calendar: utc) == 0)
    }

    @Test func retentionDeletesOnlyTheOldestLogs() {
        let names = (1...20).map { String(format: "bigremote-202610%02d-00.jsonl", $0) } + ["other.txt"]
        let doomed = LogFiles.namesToDelete(names, keep: 14)
        #expect(doomed.count == 6)
        #expect(doomed.first == "bigremote-20261001-00.jsonl")
        #expect(doomed.last == "bigremote-20261006-00.jsonl")
        #expect(!doomed.contains("other.txt"))
        #expect(LogFiles.namesToDelete(Array(names.prefix(5)), keep: 14).isEmpty)
    }
}
