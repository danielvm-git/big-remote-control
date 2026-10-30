// story: e09s01
import Foundation

/// Sony BRAVIA REST API: JSON-RPC over `POST http://<ip>/sony/<service>`, plus
/// IRCC (SOAP) for remote keys. Pure, no I/O (docs/PROTOCOL.md 11). Shapes
/// follow pybravia, the library behind the Home Assistant integration.
enum SonyPayloads {
    #if os(iOS)
    static let clientID = "BigRemote:iphone"
    static let nickname = "Big Remote (iPhone)"
    #else
    static let clientID = "BigRemote:mac"
    static let nickname = "Big Remote (Mac)"
    #endif
    static let irccSOAPAction = "\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\""

    static func url(ip: String, service: String) -> URL? {
        guard NetworkAddress.ipv4Octets(ip) != nil else { return nil }
        return URL(string: "http://\(ip)/sony/\(service)")
    }

    static func call(_ method: String, params: [JSONValue] = [], version: String = "1.0") throws -> Data {
        let body: JSONValue = .object([
            "method": .string(method),
            "params": .array(params),
            "id": 1,
            "version": .string(version),
        ])
        return try JSONEncoder().encode(body)
    }

    /// Without credentials the TV shows a PIN and answers 401. With
    /// `basicAuth(pin:)` it answers 200 and sets the `auth` cookie.
    static func register() throws -> Data {
        try call("actRegister", params: [
            .object(["clientid": .string(clientID), "nickname": .string(nickname), "level": "private"]),
            .array([.object(["value": "yes", "function": "WOL"])]),
        ])
    }

    static func basicAuth(pin: String) -> String {
        "Basic " + Data(":\(pin)".utf8).base64EncodedString()
    }

    /// The TV shows a 4-digit PIN.
    static func normalizedPIN(_ raw: String) -> String? {
        let pin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 4, pin.allSatisfy(\.isASCII), pin.allSatisfy(\.isNumber) else { return nil }
        return pin
    }

    /// `auth=<value>` from Set-Cookie. Sony's `Expires` is not RFC-compliant,
    /// so the header is split by hand instead of going through HTTPCookie.
    static func authCookie(fromSetCookie header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let field = part.trimmingCharacters(in: .whitespaces)
            if field.hasPrefix("auth="), field.count > 5 { return field }
        }
        return nil
    }

    /// The `result` array, or the JSON-RPC `error` [code, message] as `TVError.sony`.
    static func result(_ data: Data) throws -> [JSONValue] {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        if let error = json["error"]?.arrayValue {
            throw TVError.sony(error.first?.intValue ?? 0, error.dropFirst().first?.stringValue ?? "")
        }
        return json["result"]?.arrayValue ?? []
    }

    /// IRCC codes are base64; anything else could break the XML.
    static func irccEnvelope(_ code: String) throws -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw TVError.blockedKey(code) }
        let xml = #"<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" "#
            + #"s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>"#
            + #"<u:X_SendIRCC xmlns:u="urn:schemas-sony-com:service:IRCC:1">"#
            + "<IRCCCode>\(code)</IRCCCode></u:X_SendIRCC></s:Body></s:Envelope>"
        return Data(xml.utf8)
    }

    /// Samsung `KEY_*` code (what the UI and presets store) -> Sony IRCC name
    /// from `getRemoteControllerInfo`.
    static func commandName(for keyCode: String) -> String? {
        if keyCode.hasPrefix("KEY_"), keyCode.count == 5, let digit = keyCode.last, digit.isNumber {
            return "Num\(digit)"
        }
        return keyMap[keyCode]
    }

    private static let keyMap: [String: String] = [
        "KEY_POWER": "TvPower", "KEY_VOLUP": "VolumeUp", "KEY_VOLDOWN": "VolumeDown", "KEY_MUTE": "Mute",
        "KEY_UP": "Up", "KEY_DOWN": "Down", "KEY_LEFT": "Left", "KEY_RIGHT": "Right", "KEY_ENTER": "Confirm",
        "KEY_RETURN": "Return", "KEY_EXIT": "Exit", "KEY_HOME": "Home", "KEY_MENU": "ActionMenu",
        "KEY_TOOLS": "Options", "KEY_INFO": "Display", "KEY_GUIDE": "EPG", "KEY_SOURCE": "Input",
        "KEY_HDMI": "Input", "KEY_CHUP": "ChannelUp", "KEY_CHDOWN": "ChannelDown", "KEY_PRECH": "Jump",
        "KEY_PLAY": "Play", "KEY_PAUSE": "Pause", "KEY_STOP": "Stop",
        "KEY_FF": "Forward", "KEY_REWIND": "Rewind", "KEY_RED": "Red", "KEY_GREEN": "Green",
        "KEY_YELLOW": "Yellow", "KEY_BLUE": "Blue", "KEY_PMODE": "PictureMode", "KEY_CAPTION": "SubTitle",
        "KEY_HDMI1": "Hdmi1", "KEY_HDMI2": "Hdmi2", "KEY_HDMI3": "Hdmi3", "KEY_HDMI4": "Hdmi4",
    ]

    /// name -> IRCC code, from `getRemoteControllerInfo` (result[1]).
    static func commands(from result: [JSONValue]) -> [String: String] {
        var commands: [String: String] = [:]
        for entry in result.dropFirst().first?.arrayValue ?? [] {
            if let name = entry["name"]?.stringValue, let value = entry["value"]?.stringValue {
                commands[name] = value
            }
        }
        return commands
    }

    /// `getPowerStatus` "active" = on; "standby" when Remote start keeps the network up.
    static func deviceInfo(ip: String, power: String?, interface: JSONValue?) -> DeviceInfo {
        let model = interface?["modelName"]?.stringValue
        return DeviceInfo(
            ip: ip,
            name: model.map { "Sony \($0)" } ?? "Sony \(ip)",
            modelName: model,
            model: interface?["productName"]?.stringValue,
            powerState: power == "active" ? "on" : "standby",
            isFrame: false,
            tokenAuthSupport: false,
            imeSyncedSupport: false,
            wifiMac: nil,
            networkType: nil,
            duid: nil,
            resolution: nil,
            language: nil,
            apiVersion: interface?["interfaceVersion"]?.stringValue,
            isSamsungTV: false,
            support: [:],
            brand: .sony
        )
    }

    /// `getApplicationList`: the entry id is the app URI.
    static func apps(from result: [JSONValue]) -> [TVAppEntry] {
        (result.first?.arrayValue ?? []).compactMap { entry in
            guard let title = entry["title"]?.stringValue, let uri = entry["uri"]?.stringValue else { return nil }
            return TVAppEntry(title: title, id: uri)
        }
    }
}
