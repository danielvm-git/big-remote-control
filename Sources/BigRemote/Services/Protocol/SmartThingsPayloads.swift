import Foundation

/// SmartThings REST shapes (docs 7).
enum SmartThingsPayloads {
    static func commandBody(capability: String, command: String, arguments: [JSONValue] = [], component: String = "main") -> String {
        let command: JSONValue = .object([
            "component": .string(component),
            "capability": .string(capability),
            "command": .string(command),
            "arguments": .array(arguments),
        ])
        return JSONValue.object(["commands": .array([command])]).jsonString()
    }
}

struct STDevice: Codable, Hashable, Identifiable, Sendable {
    struct OCF: Codable, Hashable, Sendable {
        var mnmo: String?
        var n: String?
    }
    var deviceId: String
    var label: String?
    var name: String?
    var deviceTypeName: String?
    var ocf: OCF?

    var id: String { deviceId }
    var displayName: String { label ?? name ?? deviceId }
}

struct STDeviceList: Decodable, Sendable {
    struct Links: Decodable, Sendable {
        struct Link: Decodable, Sendable { var href: String? }
        var next: Link?
    }
    var items: [STDevice]
    var _links: Links?
}

/// A `{id, name}` option from a `supported*Map` attribute.
struct STOption: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
}

/// Parsed `GET /devices/{id}/status`.
struct STDeviceStatus: Sendable, Equatable {
    var raw: JSONValue

    private var main: JSONValue? { raw["components"]?["main"] }

    func value(_ capability: String, _ attribute: String) -> JSONValue? {
        main?[capability]?[attribute]?["value"]
    }

    var disabledCapabilities: Set<String> {
        Set((value("custom.disabledCapabilities", "disabledCapabilities")?.arrayValue ?? []).compactMap(\.stringValue))
    }

    func supports(_ capability: String) -> Bool {
        main?[capability] != nil && !disabledCapabilities.contains(capability)
    }

    var switchOn: Bool? {
        value("switch", "switch")?.stringValue.map { $0 == "on" }
    }

    var volume: Int? { value("audioVolume", "volume")?.intValue }

    var muted: Bool? { value("audioMute", "mute")?.stringValue.map { $0 == "muted" } }

    private func options(_ capability: String, map: String, list: String) -> [STOption] {
        if let entries = value(capability, map)?.arrayValue, !entries.isEmpty {
            return entries.compactMap { entry in
                guard let id = entry["id"]?.stringValue else { return nil }
                let name = entry["name"]?.stringValue ?? id
                return STOption(id: id, name: name.isEmpty ? id : name)
            }
        }
        return (value(capability, list)?.arrayValue ?? []).compactMap(\.stringValue).map { STOption(id: $0, name: $0) }
    }

    /// Picture modes: the command takes the `name`.
    var pictureModes: [STOption] {
        guard supports("custom.picturemode") else { return [] }
        return options("custom.picturemode", map: "supportedPictureModesMap", list: "supportedPictureModes")
    }
    var pictureMode: String? { value("custom.picturemode", "pictureMode")?.stringValue }

    /// Sound modes: the command takes the `name`.
    var soundModes: [STOption] { supports("custom.soundmode") ? options("custom.soundmode", map: "supportedSoundModesMap", list: "supportedSoundModes") : [] }
    var soundMode: String? { value("custom.soundmode", "soundMode")?.stringValue }

    /// Inputs: `samsungvd.mediaInputSource` takes the `id`; falls back to `mediaInputSource`.
    var inputSourceCapability: String? {
        if supports("samsungvd.mediaInputSource") { return "samsungvd.mediaInputSource" }
        if supports("mediaInputSource") { return "mediaInputSource" }
        return nil
    }

    var inputSources: [STOption] {
        guard let cap = inputSourceCapability else { return [] }
        return options(cap, map: "supportedInputSourcesMap", list: "supportedInputSources")
    }

    var inputSource: String? {
        guard let cap = inputSourceCapability else { return nil }
        return value(cap, "inputSource")?.stringValue
    }
}
