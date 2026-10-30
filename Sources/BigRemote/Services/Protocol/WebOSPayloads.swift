// story: e10s01
import Foundation

/// LG webOS SSAP over WebSocket (`wss://<ip>:3001/`), plus the pointer
/// input socket for buttons. Pure, no I/O (docs/PROTOCOL.md 12). Shapes
/// follow aiowebostv, the library behind the Home Assistant integration.
enum WebOSPayloads {
    struct Message: Sendable, Equatable {
        var id: String?
        var type: String
        var payload: JSONValue
        var error: String?
    }

    /// webOS 2022+ refuses ws://3000; wss://3001 works on every version we target.
    static func mainURL(ip: String) -> URL? {
        guard NetworkAddress.ipv4Octets(ip) != nil else { return nil }
        return URL(string: "wss://\(ip):3001/")
    }

    static let registerID = "register_0"

    private static let permissions: [String] = [
        "APP_TO_APP", "CLOSE", "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
        "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TEXT", "CONTROL_INPUT_TV", "CONTROL_MOUSE_AND_KEYBOARD",
        "CONTROL_POWER", "LAUNCH", "LAUNCH_WEBAPP", "READ_APP_STATUS", "READ_CURRENT_CHANNEL",
        "READ_INPUT_DEVICE_LIST", "READ_INSTALLED_APPS", "READ_NETWORK_STATE", "READ_POWER_STATE",
        "READ_RUNNING_APPS", "READ_TV_CHANNEL_LIST", "WRITE_NOTIFICATION_TOAST",
    ]

    /// Without a key the TV shows an accept prompt and later sends `registered`
    /// with a `client-key`. With the saved key it registers at once.
    static func register(clientKey: String?) throws -> String {
        var payload: [String: JSONValue] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": .object([
                "appVersion": "1.1",
                "manifestVersion": 1,
                "permissions": .array(permissions.map(JSONValue.string)),
            ]),
        ]
        if let clientKey { payload["client-key"] = .string(clientKey) }
        return try encode(.object(["type": "register", "id": .string(registerID), "payload": .object(payload)]))
    }

    static func request(id: String, uri: String, payload: [String: JSONValue] = [:]) throws -> String {
        try encode(.object([
            "id": .string(id),
            "type": "request",
            "uri": .string("ssap://\(uri)"),
            "payload": .object(payload),
        ]))
    }

    /// Text frame for the pointer input socket.
    static func button(_ name: String) -> String {
        "type:button\nname:\(name)\n\n"
    }

    /// Samsung `KEY_*` code (what the UI and presets store) -> webOS button.
    static func buttonName(for keyCode: String) -> String? {
        if keyCode.hasPrefix("KEY_"), keyCode.count == 5, let digit = keyCode.last, digit.isNumber {
            return String(digit)
        }
        return buttonMap[keyCode]
    }

    private static let buttonMap: [String: String] = [
        "KEY_POWER": "POWER", "KEY_VOLUP": "VOLUMEUP", "KEY_VOLDOWN": "VOLUMEDOWN", "KEY_MUTE": "MUTE",
        "KEY_UP": "UP", "KEY_DOWN": "DOWN", "KEY_LEFT": "LEFT", "KEY_RIGHT": "RIGHT", "KEY_ENTER": "ENTER",
        "KEY_RETURN": "BACK", "KEY_EXIT": "EXIT", "KEY_HOME": "HOME", "KEY_MENU": "MENU",
        "KEY_TOOLS": "QMENU", "KEY_INFO": "INFO", "KEY_GUIDE": "GUIDE", "KEY_SOURCE": "INPUT_HUB",
        "KEY_HDMI": "INPUT_HUB", "KEY_CHUP": "CHANNELUP", "KEY_CHDOWN": "CHANNELDOWN", "KEY_CH_LIST": "LIST",
        "KEY_PLAY": "PLAY", "KEY_PAUSE": "PAUSE", "KEY_STOP": "STOP", "KEY_FF": "FASTFORWARD",
        "KEY_REWIND": "REWIND", "KEY_RED": "RED", "KEY_GREEN": "GREEN", "KEY_YELLOW": "YELLOW",
        "KEY_BLUE": "BLUE", "KEY_CAPTION": "CC",
    ]

    /// Ids can arrive as numbers; they are normalised to strings.
    static func parse(_ text: String) throws -> Message {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        return Message(
            id: json["id"]?.stringValue,
            type: json["type"]?.stringValue ?? "",
            payload: json["payload"] ?? .object([:]),
            error: json["error"]?.stringValue
        )
    }

    /// `com.webos.applicationManager/listLaunchPoints`.
    static func apps(from payload: JSONValue) -> [TVAppEntry] {
        (payload["launchPoints"]?.arrayValue ?? []).compactMap { entry in
            guard let title = entry["title"]?.stringValue, let id = entry["id"]?.stringValue else { return nil }
            return TVAppEntry(title: title, id: id)
        }
    }

    /// `GET https://<ip>:3001/` answers "Hello world" while the TV is on.
    static func deviceInfo(ip: String, body: String) -> DeviceInfo? {
        guard body.localizedCaseInsensitiveContains("hello world") else { return nil }
        return DeviceInfo(
            ip: ip, name: "LG \(ip)", modelName: nil, model: nil, powerState: "on", isFrame: false,
            tokenAuthSupport: false, imeSyncedSupport: false, wifiMac: nil, networkType: nil, duid: nil,
            resolution: nil, language: nil, apiVersion: nil, isSamsungTV: false, support: [:], brand: .lg
        )
    }

    private static func encode(_ value: JSONValue) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
