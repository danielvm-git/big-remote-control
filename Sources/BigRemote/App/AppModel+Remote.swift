// story: e01s02 e01s03 e02s01
import AppKit
import Foundation

/// Remote keys, pairing, app launch, text input and favourites.
extension AppModel {
    func press(_ key: RemoteKey) { pressCode(key.rawValue) }

    func pressCode(_ code: String) {
        run {
            let tv = try self.requireTV()
            try await self.client(for: tv).sendKey(code)
        }
    }

    /// KEY_PLAY and KEY_PAUSE alternate; there is no universal toggle key.
    func playPause() {
        playToggle.toggle()
        press(playToggle ? .play : .pause)
    }

    func pair(_ tv: TVDevice) {
        run {
            try await self.client(for: tv).pair()
            self.show("“\(tv.name)” pareada.")
        }
    }

    func forgetPairing(_ tv: TVDevice) {
        resolvedAppIDs[tv.id] = nil
        if let client = clients[tv.id] { Task { await client.forgetPairing() } } else { TokenStore().setToken(nil, for: tv.id) }
        show("Pareamento de “\(tv.name)” apagado.")
    }

    func hasToken(_ tv: TVDevice) -> Bool { TokenStore().token(for: tv.id) != nil }

    func launch(_ app: TVApp) {
        run {
            let tv = try self.requireTV()
            let client = try self.client(for: tv)
            let appID = try await self.resolveAppID(app, on: tv)
            try await client.launchApp(appID, type: app.launchType)
        }
    }

    /// Picks the first of [appID] + alternateIDs that `GET
    /// /api/v2/applications/<id>` reports installed (cached per TV). The WS
    /// launch gives no error for a missing app, so this is the only check.
    /// When REST cannot answer (error, not 404), the preferred ID is used.
    func resolveAppID(_ app: TVApp, on tv: TVDevice) async throws -> String {
        if let cached = resolvedAppIDs[tv.id]?[app.appID] { return cached }
        var allNotFound = true
        for id in [app.appID] + app.alternateIDs {
            do {
                if try await rest.appStatus(ip: tv.ip, appID: id) != nil {
                    resolvedAppIDs[tv.id, default: [:]][app.appID] = id
                    return id
                }
            } catch {
                allNotFound = false
            }
        }
        // Native Tizen apps (e.g. org.tizen.browser) may be unknown to REST.
        if allNotFound, app.launchType == .deepLink { throw TVError.appNotInstalled(app.name) }
        return app.appID
    }

    /// Debounced live typing: sends the whole string each time (replace).
    /// An empty string is sent too (once), so deleting everything clears the TV field.
    func typeLive(_ text: String) {
        textDebounce?.cancel()
        if text.isEmpty && lastLiveText.isEmpty { return }
        textDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.lastLiveText = text
            self.run {
                let tv = try self.requireTV()
                try await self.client(for: tv).sendText(text, submit: false)
            }
        }
    }

    func submitText(_ text: String) {
        textDebounce?.cancel()
        lastLiveText = text
        run {
            let tv = try self.requireTV()
            try await self.client(for: tv).sendText(text, submit: true)
        }
    }

    // MARK: - Favourites

    func isFavorite(_ app: TVApp) -> Bool { favoriteAppIDs.contains(app.appID) }

    func toggleFavorite(_ app: TVApp) {
        if let index = favoriteAppIDs.firstIndex(of: app.appID) {
            favoriteAppIDs.remove(at: index)
        } else {
            favoriteAppIDs.append(app.appID)
        }
    }

    /// Read-only REST probe: is the app installed on the selected TV?
    func probe(_ app: TVApp) async -> String {
        guard let tv = selectedTV else { return "sem TV" }
        for id in [app.appID] + app.alternateIDs {
            do {
                if let status = try await rest.appStatus(ip: tv.ip, appID: id) {
                    resolvedAppIDs[tv.id, default: [:]][app.appID] = id
                    return "instalado (\(id))" + (status.running == true ? ", rodando" : "")
                }
            } catch {
                return error.localizedDescription
            }
        }
        return "não instalado"
    }
}
