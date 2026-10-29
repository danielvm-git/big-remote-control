import Foundation

/// Art channel (`com.samsung.art-app`) envelopes (docs 6.2-6.4).
enum ArtPayloads {
    /// Builds `ms.channel.emit` / `art_app_request` with `data` as a JSON string.
    /// `id` and `request_id` are both set to `id`.
    static func request(_ name: String, params: [String: JSONValue] = [:], id: String) throws -> String {
        var inner = params
        inner["request"] = .string(name)
        inner["id"] = .string(id)
        inner["request_id"] = .string(id)
        let data = JSONValue.object(inner).jsonString()
        return try RemotePayloads.encode(
            RemotePayloads.EmitMessage(params: .init(event: "art_app_request", to: "host", data: .string(data)))
        )
    }

    /// The inner message of a `d2d_service_message` (its `data` is a JSON string).
    static func innerMessage(_ event: ChannelEvent) -> JSONValue? {
        guard event.name == "d2d_service_message", let data = event.data else { return nil }
        switch data {
        case .string(let text): return JSONValue.parse(text)
        case .object: return data
        default: return nil
        }
    }

    /// Correlation id of a reply: `request_id`, falling back to `id`.
    static func requestID(of message: JSONValue) -> String? {
        message["request_id"]?.stringValue ?? message["id"]?.stringValue
    }

    /// Art mode from `artmode_status` / `art_mode_changed` (`value` or `status`).
    static func artModeValue(of message: JSONValue) -> Bool? {
        guard let sub = message["event"]?.stringValue,
              sub == "artmode_status" || sub == "art_mode_changed" || sub == "set_artmode_status"
        else { return nil }
        let raw = message["value"]?.stringValue ?? message["status"]?.stringValue
        switch raw?.lowercased() {
        case "on": return true
        case "off": return false
        default: return nil
        }
    }

    /// Decodes a field that is itself a JSON string (e.g. `content_list`).
    static func nested(_ message: JSONValue, _ key: String) -> JSONValue? {
        guard let value = message[key] else { return nil }
        if case .string(let text) = value { return JSONValue.parse(text) ?? value }
        return value
    }
}
