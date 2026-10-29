// story: e06s01
import AppKit
import Foundation

/// Optional SmartThings cloud integration.
extension AppModel {
    func smartThingsClient() -> SmartThingsClient? {
        guard smartThingsConfigured else { return nil }
        if smartThingsToken == nil { smartThingsToken = keychain.string(for: Self.smartThingsAccount) }
        guard let token = smartThingsToken, !token.isEmpty else { return nil }
        return SmartThingsClient(token: token)
    }

    func saveSmartThingsToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard keychain.set(trimmed, for: Self.smartThingsAccount) else {
            stError = "Não foi possível salvar no Keychain."
            return
        }
        smartThingsToken = trimmed
        smartThingsConfigured = true
        settings.smartThingsConfigured = true
        loadSmartThingsDevices()
    }

    func clearSmartThingsToken() {
        keychain.set(nil, for: Self.smartThingsAccount)
        smartThingsToken = nil
        smartThingsConfigured = false
        settings.smartThingsConfigured = false
        stDevices = []
        stStatus = [:]
        stError = nil
    }

    func loadSmartThingsDevices() {
        guard let st = smartThingsClient() else { return }
        stLoading = true
        Task {
            defer { self.stLoading = false }
            do {
                let devices = try await st.devices()
                self.stDevices = devices
                self.stError = nil
                self.autoMapSmartThings(devices)
            } catch {
                self.stError = error.localizedDescription
            }
        }
    }

    /// Maps unmapped TVs by model name (ocf.mnmo) or label.
    private func autoMapSmartThings(_ devices: [STDevice]) {
        for index in tvs.indices where tvs[index].smartThingsDeviceID == nil {
            let tv = tvs[index]
            let match = devices.first { device in
                if let model = tv.modelName, let mnmo = device.ocf?.mnmo,
                   mnmo.localizedCaseInsensitiveContains(model) || model.localizedCaseInsensitiveContains(mnmo) {
                    return true
                }
                return device.displayName.localizedCaseInsensitiveCompare(tv.name) == .orderedSame
            }
            if let match { tvs[index].smartThingsDeviceID = match.deviceId }
        }
    }

    func mapSmartThings(tvID: String, deviceID: String?) {
        guard let index = tvs.firstIndex(where: { $0.id == tvID }) else { return }
        tvs[index].smartThingsDeviceID = deviceID
    }

    func refreshSmartThingsStatus(for tv: TVDevice) {
        guard let st = smartThingsClient(), let deviceID = tv.smartThingsDeviceID else { return }
        Task {
            do {
                self.stStatus[tv.id] = try await st.status(deviceID: deviceID)
                self.stError = nil
            } catch {
                self.stError = error.localizedDescription
            }
        }
    }

    func smartThingsAvailable(for tv: TVDevice) -> Bool {
        smartThingsConfigured && tv.smartThingsDeviceID != nil
    }

    func sendSmartThings(_ capability: String, _ command: String, _ arguments: [JSONValue] = []) {
        guard let tv = selectedTV else { return }
        run {
            guard let st = self.smartThingsClient(), let deviceID = tv.smartThingsDeviceID else {
                throw TVError.smartThingsUnavailable
            }
            try await st.send(deviceID: deviceID, capability: capability, command: command, arguments: arguments)
            // ACCEPTED is not done: re-read after a short delay.
            try await Task.sleep(for: .milliseconds(1500))
            self.refreshSmartThingsStatus(for: tv)
        }
    }
}
