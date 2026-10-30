// story: e09s02 e09s03
import Foundation

/// Sony BRAVIA pairing (PIN on the TV screen) and app probing by title.
extension AppModel {
    /// The TV shows a 4-digit PIN; the user types it in Settings.
    func requestSonyPIN(_ tv: TVDevice) {
        run {
            try await self.sonyClient(for: tv).requestPIN()
            self.show("Digite o PIN que apareceu em “\(tv.name)”.")
        }
    }

    func confirmSonyPIN(_ pin: String, for tv: TVDevice) {
        run {
            try await self.sonyClient(for: tv).confirmPIN(pin)
            self.show("“\(tv.name)” pareada.")
        }
    }

    /// Read-only: is a catalogue app on the TV's app list (Sony, LG)?
    func probeByTitle(_ app: TVApp, on tv: TVDevice) async -> String {
        do {
            guard let found = try await namedAppClient(for: tv)?.findApp(named: app.name) else { return "não instalado" }
            return "instalado (\(found.title))"
        } catch {
            return error.localizedDescription
        }
    }
}
