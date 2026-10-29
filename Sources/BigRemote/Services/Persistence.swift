import Foundation

/// Presets as JSON in Application Support/Big Remote/presets.json.
struct PresetStore: Sendable {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "Big Remote", directoryHint: .isDirectory)
    }

    static var fileURL: URL { directory.appending(path: "presets.json") }

    func load() -> [Preset] {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return Preset.examples }
        do {
            return try JSONDecoder().decode([Preset].self, from: data)
        } catch {
            // Keep the broken file for the user to fix; run with the examples.
            let backup = Self.directory.appending(path: "presets.invalid.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: Self.fileURL, to: backup)
            return Preset.examples
        }
    }

    func save(_ presets: [Preset]) {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(presets).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Big Remote: falha ao salvar presets: \(error)")
        }
    }
}

/// Small settings in UserDefaults.
struct SettingsStore {
    private let defaults = UserDefaults.standard

    var tvs: [TVDevice] {
        get {
            guard let data = defaults.data(forKey: "tvs"),
                  let list = try? JSONDecoder().decode([TVDevice].self, from: data) else { return [] }
            return list
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "tvs") }
    }

    var selectedTVID: String? {
        get { defaults.string(forKey: "selectedTVID") }
        nonmutating set { defaults.set(newValue, forKey: "selectedTVID") }
    }

    var favoriteAppIDs: [String] {
        get { defaults.stringArray(forKey: "favoriteAppIDs") ?? TVApp.defaultFavoriteIDs }
        nonmutating set { defaults.set(newValue, forKey: "favoriteAppIDs") }
    }

    var customApps: [TVApp] {
        get {
            guard let data = defaults.data(forKey: "customApps"),
                  let list = try? JSONDecoder().decode([TVApp].self, from: data) else { return [] }
            return list
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "customApps") }
    }

    /// Set once a SmartThings token was saved, so the app does not touch the
    /// Keychain at launch for users without SmartThings.
    var smartThingsConfigured: Bool {
        get { defaults.bool(forKey: "smartThingsConfigured") }
        nonmutating set { defaults.set(newValue, forKey: "smartThingsConfigured") }
    }
}
