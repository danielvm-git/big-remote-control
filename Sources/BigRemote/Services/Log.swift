// story: e12s01 e12s02
import Foundation
import CryptoKit
import OSLog

/// App-wide structured log. Call sites are one line and never block: entries go
/// through an ordered stream to one writer task (JSON lines under Application
/// Support, `LogFiles` naming) and are mirrored to `os.Logger` for Console.app.
/// Tokens, PINs and cookies must never be passed in `fields`; log
/// `Log.fingerprint(_:)` instead (`LogRedactor` also masks by name).
enum Log {
    static let device: String = {
        #if os(iOS)
        return "ios"
        #else
        return "mac"
        #endif
    }()

    /// `Application Support/BigRemote/logs` (inside the app container).
    static let directory: URL = {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BigRemote/logs", isDirectory: true)
    }()

    private static let sink = LogSink(directory: directory)

    /// Random 256-bit key kept in UserDefaults on this device only; created on first use.
    private static let fingerprintKey: SymmetricKey = {
        let defaults = UserDefaults.standard
        if let saved = defaults.data(forKey: "logFingerprintKey") { return SymmetricKey(data: saved) }
        let key = SymmetricKey(size: .bits256)
        defaults.set(key.withUnsafeBytes { Data($0) }, forKey: "logFingerprintKey")
        return key
    }()

    /// Stable per device, so one token can be told from another; nil means "no token".
    static func fingerprint(_ secret: String?) -> String {
        guard let secret else { return "none" }
        return LogRedactor.fingerprint(secret, key: fingerprintKey)
    }

    static func debug(_ category: LogCategory, _ message: String, tv: String? = nil, _ fields: [String: String] = [:]) {
        write(.debug, category, message, tv, fields)
    }

    static func info(_ category: LogCategory, _ message: String, tv: String? = nil, _ fields: [String: String] = [:]) {
        write(.info, category, message, tv, fields)
    }

    static func warning(_ category: LogCategory, _ message: String, tv: String? = nil, _ fields: [String: String] = [:]) {
        write(.warning, category, message, tv, fields)
    }

    static func error(_ category: LogCategory, _ message: String, tv: String? = nil, _ fields: [String: String] = [:]) {
        write(.error, category, message, tv, fields)
    }

    private static func write(
        _ level: LogLevel, _ category: LogCategory, _ message: String, _ tv: String?, _ fields: [String: String]
    ) {
        sink.submit(LogFormat.entry(level: level, category: category, message: message, tv: tv, device: device, fields: fields))
    }

    /// Log files on disk, oldest first.
    static func fileURLs() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter(LogFiles.isLogName).sorted().map { directory.appendingPathComponent($0) }
    }

    /// The last three files joined into one temporary file, for sharing. nil when there is no log yet.
    static func exportURL() -> URL? {
        let urls = fileURLs().suffix(3)
        guard !urls.isEmpty else { return nil }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("bigremote-logs.jsonl")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer { try? handle.close() }
        for url in urls {
            if let data = try? Data(contentsOf: url) { try? handle.write(contentsOf: data) }
        }
        return output
    }
}

/// Owns the ordered stream. The writer lives inside the one task that reads it, so it needs no locking.
final class LogSink: Sendable {
    private let continuation: AsyncStream<LogEntry>.Continuation

    init(directory: URL) {
        let (stream, continuation) = AsyncStream<LogEntry>.makeStream()
        self.continuation = continuation
        Task.detached(priority: .utility) {
            let writer = LogWriter(directory: directory)
            for await entry in stream { writer.write(entry) }
        }
    }

    func submit(_ entry: LogEntry) {
        continuation.yield(entry)
    }
}

/// Appends lines to today's file, starts a new part past `LogFiles.maxBytes`,
/// prunes old files. Confined to the `LogSink` task.
final class LogWriter {
    private let directory: URL
    private var handle: FileHandle?
    private var currentDay = ""
    private var bytes = 0
    private var loggers: [LogCategory: Logger] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func write(_ entry: LogEntry) {
        let line = LogFormat.line(entry)
        mirror(entry, line)
        let data = Data((line + "\n").utf8)
        ensureOpen(adding: data.count)
        do {
            try handle?.write(contentsOf: data)
            bytes += data.count
        } catch {
            NSLog("Big Remote: falha ao gravar o log: \(error)")
            handle = nil
        }
    }

    private func mirror(_ entry: LogEntry, _ line: String) {
        let logger = loggers[entry.category] ?? Logger(subsystem: "com.danielvm.BigRemote", category: entry.category.rawValue)
        loggers[entry.category] = logger
        switch entry.level {
        case .debug: logger.debug("\(line, privacy: .public)")
        case .info: logger.info("\(line, privacy: .public)")
        case .warning: logger.warning("\(line, privacy: .public)")
        case .error: logger.error("\(line, privacy: .public)")
        }
    }

    private func ensureOpen(adding size: Int) {
        let now = Date()
        let day = LogFiles.name(for: now)
        if handle != nil, day == currentDay, bytes + size <= LogFiles.maxBytes { return }
        try? handle?.close()
        handle = nil
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        var part = LogFiles.latestPart(in: names, for: now)
        var name = LogFiles.name(for: now, part: part)
        var existing = fileSize(name)
        if existing + size > LogFiles.maxBytes {
            part += 1
            name = LogFiles.name(for: now, part: part)
            existing = 0
        }
        let url = directory.appendingPathComponent(name)
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        guard let opened = try? FileHandle(forWritingTo: url) else { return }
        _ = try? opened.seekToEnd()
        handle = opened
        currentDay = day
        bytes = existing
        for old in LogFiles.namesToDelete(names + [name]) {
            try? manager.removeItem(at: directory.appendingPathComponent(old))
        }
    }

    private func fileSize(_ name: String) -> Int {
        let path = directory.appendingPathComponent(name).path
        return (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    }
}
