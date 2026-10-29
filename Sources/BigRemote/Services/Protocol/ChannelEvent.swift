import Foundation

/// One frame received on a channel: `{"event":"...","data":...,"from":"..."}`.
struct ChannelEvent: Sendable, Equatable {
    var name: String
    var data: JSONValue?
    var from: String?

    static func parse(_ text: String) -> ChannelEvent? {
        guard let root = JSONValue.parse(text), let name = root["event"]?.stringValue else { return nil }
        return ChannelEvent(name: name, data: root["data"], from: root["from"]?.stringValue)
    }

    /// `ms.channel.connect` token: a numeric string or a JSON number.
    var token: String? {
        guard let value = data?["token"], let text = value.stringValue, !text.isEmpty else { return nil }
        return text
    }

    /// Startup noise to ignore (docs 2.2).
    static let ignored: Set<String> = ["ed.edenTV.update", "ms.voiceApp.hide"]
}
