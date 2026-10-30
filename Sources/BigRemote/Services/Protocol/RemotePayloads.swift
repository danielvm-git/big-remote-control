import Foundation

enum SamsungChannel: String, Sendable {
    case remote = "samsung.remote.control"
    case art = "com.samsung.art-app"
}

enum KeyCommand: String, Sendable {
    case click = "Click"
    case press = "Press"
    case release = "Release"
}

/// JSON payloads for the `samsung.remote.control` channel (docs 2-4).
enum RemotePayloads {
    /// One name per platform. The TV binds a token to the client name, so a Mac and an
    /// iPhone sharing one name kept invalidating each other's token (ADR 0008).
    /// Changing a name means pairing again: the token key includes it (`TokenStore.samsungKey`).
    #if os(iOS)
    static let clientName = "Big Remote (iPhone)"
    #else
    static let clientName = "Big Remote (Mac)"
    #endif

    /// Standard base64 of the UTF-8 name, percent-encoded for a query value.
    static func encodedName(_ name: String) -> String {
        let b64 = Data(name.utf8).base64EncodedString()
        return percentEncode(b64)
    }

    static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func channelURL(ip: String, channel: SamsungChannel, name: String = clientName, token: String?) -> URL? {
        guard NetworkAddress.ipv4Octets(ip) != nil else { return nil }
        var text = "wss://\(ip):8002/api/v2/channels/\(channel.rawValue)?name=\(encodedName(name))"
        if let token, !token.isEmpty {
            text += "&token=\(percentEncode(token))"
        }
        return URL(string: text)
    }

    struct ControlMessage: Encodable {
        struct Params: Encodable {
            var Cmd: String?
            var DataOfCmd: String?
            var Option: String?
            var TypeOfRemote: String
        }
        var method = "ms.remote.control"
        var params: Params
    }

    struct EmitMessage: Encodable {
        struct Params: Encodable {
            var event: String
            var to: String
            var data: JSONValue?
        }
        var method = "ms.channel.emit"
        var params: Params
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// `{"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"KEY_X","Option":"false","TypeOfRemote":"SendRemoteKey"}}`
    static func key(_ code: String, command: KeyCommand = .click) throws -> String {
        guard RemoteKey.isAllowed(code) else { throw TVError.blockedKey(code) }
        return try encode(ControlMessage(params: .init(Cmd: command.rawValue, DataOfCmd: code, Option: "false", TypeOfRemote: "SendRemoteKey")))
    }

    static func launchApp(_ appID: String, type: TVApp.LaunchType, metaTag: String = "") throws -> String {
        let data: JSONValue = .object([
            "appId": .string(appID),
            "action_type": .string(type.rawValue),
            "metaTag": .string(metaTag),
        ])
        return try encode(EmitMessage(params: .init(event: "ed.apps.launch", to: "host", data: data)))
    }

    static func textReceivedBroadcast() throws -> String {
        try encode(EmitMessage(params: .init(event: "custom.remote.textReceived", to: "broadcast", data: nil)))
    }

    static func inputString(_ text: String) throws -> String {
        let b64 = Data(text.utf8).base64EncodedString()
        return try encode(ControlMessage(params: .init(Cmd: b64, DataOfCmd: "base64", Option: nil, TypeOfRemote: "SendInputString")))
    }

    static func inputEnd() throws -> String {
        try encode(ControlMessage(params: .init(Cmd: nil, DataOfCmd: nil, Option: nil, TypeOfRemote: "SendInputEnd")))
    }
}
