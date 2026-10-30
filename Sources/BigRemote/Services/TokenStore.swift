import Foundation

/// Pairing tokens, one per TV id. Kept in UserDefaults: a TV token only
/// works on the LAN for that one TV, and the Keychain would prompt on every
/// ad-hoc-signed rebuild. The SmartThings token goes to the Keychain.
struct TokenStore: Sendable {
    private static let prefix = "tvToken."

    /// Samsung tokens belong to one client name, so their key carries it; Sony (PIN)
    /// and LG (client-key) use the TV id alone.
    static func key(for tv: TVDevice) -> String {
        tv.vendor == .samsung ? samsungKey(tvID: tv.id) : tv.id
    }

    static func samsungKey(tvID: String) -> String {
        "\(tvID)|\(RemotePayloads.clientName)"
    }

    func token(for tvID: String) -> String? {
        UserDefaults.standard.string(forKey: Self.prefix + tvID)
    }

    /// Every write is logged with its caller: this is what shows who cleared a token
    /// when a TV asks to pair again.
    func setToken(_ token: String?, for tvID: String, file: StaticString = #fileID, line: UInt = #line) {
        Log.info(.pairing, token == nil ? "token.cleared" : "token.saved", tv: tvID, [
            "caller": "\(file):\(line)",
            "previous": Log.fingerprint(UserDefaults.standard.string(forKey: Self.prefix + tvID)),
            "new": Log.fingerprint(token),
        ])
        if let token {
            UserDefaults.standard.set(token, forKey: Self.prefix + tvID)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.prefix + tvID)
        }
    }
}
