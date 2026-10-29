import Foundation

/// Pairing tokens, one per TV id. Kept in UserDefaults: a TV token only
/// works on the LAN for that one TV, and the Keychain would prompt on every
/// ad-hoc-signed rebuild. The SmartThings token goes to the Keychain.
struct TokenStore: Sendable {
    private static let prefix = "tvToken."

    func token(for tvID: String) -> String? {
        UserDefaults.standard.string(forKey: Self.prefix + tvID)
    }

    func setToken(_ token: String?, for tvID: String) {
        if let token {
            UserDefaults.standard.set(token, forKey: Self.prefix + tvID)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.prefix + tvID)
        }
    }
}
