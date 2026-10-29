import Foundation

/// An app that can be launched on the TV (docs/PROTOCOL.md 3.3).
struct TVApp: Codable, Hashable, Identifiable, Sendable {
    enum LaunchType: String, Codable, CaseIterable, Sendable {
        case deepLink = "DEEP_LINK"
        case nativeLaunch = "NATIVE_LAUNCH"
    }

    var id: String { appID }
    var name: String
    var appID: String
    var launchType: LaunchType
    var symbol: String
    /// Other IDs to try when the first is not installed.
    var alternateIDs: [String]
    /// True when the ID is only community-reported.
    var uncertain: Bool

    init(name: String, appID: String, launchType: LaunchType = .deepLink, symbol: String = "app", alternateIDs: [String] = [], uncertain: Bool = false) {
        self.name = name
        self.appID = appID
        self.launchType = launchType
        self.symbol = symbol
        self.alternateIDs = alternateIDs
        self.uncertain = uncertain
    }

    static let catalog: [TVApp] = [
        TVApp(name: "Netflix", appID: "3201907018807", symbol: "n.square.fill", alternateIDs: ["11101200001"]),
        TVApp(name: "YouTube", appID: "111299001912", symbol: "play.rectangle.fill"),
        TVApp(name: "Prime Video", appID: "3201910019365", symbol: "p.square.fill", alternateIDs: ["3201512006785"]),
        TVApp(name: "Globoplay", appID: "3201908019022", symbol: "g.circle.fill", uncertain: true),
        TVApp(name: "Disney+", appID: "3201901017640", symbol: "sparkles.tv", alternateIDs: ["3202204027038", "3202009021709"]),
        TVApp(name: "HBO Max", appID: "3202301029760", symbol: "m.square.fill", alternateIDs: ["3201601007230"]),
        TVApp(name: "Spotify", appID: "3201606009684", symbol: "music.note"),
        TVApp(name: "Apple TV", appID: "3201807016597", symbol: "appletv.fill"),
        TVApp(name: "Paramount+", appID: "3202110025305", symbol: "mountain.2.fill", alternateIDs: ["3201710014981"], uncertain: true),
        TVApp(name: "Pluto TV", appID: "3201808016802", symbol: "globe.americas.fill", uncertain: true),
        TVApp(name: "Plex", appID: "3201512006963", symbol: "film.stack"),
        TVApp(name: "Twitch", appID: "3202203026841", symbol: "gamecontroller.fill", uncertain: true),
        // org.tizen.browser is 404 on the 2024 Frame; 3202010022079 is the installed "Browser".
        TVApp(name: "Internet", appID: "3202010022079", symbol: "safari", alternateIDs: ["org.tizen.browser", "3201907018784"]),
        TVApp(name: "Privacidade", appID: "3201909019271", symbol: "hand.raised.fill", uncertain: true),
        TVApp(name: "Telecine", appID: "3201604009182", symbol: "popcorn.fill", uncertain: true),
    ]

    static let defaultFavoriteIDs = ["3201907018807", "111299001912", "3201910019365", "3201901017640", "3202301029760", "3201606009684"]

    static func find(_ appID: String, in extra: [TVApp] = []) -> TVApp? {
        (extra + catalog).first { $0.appID == appID || $0.alternateIDs.contains(appID) }
    }
}
