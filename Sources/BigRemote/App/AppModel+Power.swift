// story: e04s01 e04s02
import Foundation

/// Power, wake and Frame Art Mode actions.
extension AppModel {
    func power(_ action: PowerAction) {
        guard let tv = selectedTV else { return show(TVError.noTVSelected.localizedDescription) }
        Log.info(.power, "power.tapped", tv: tv.id, ["action": "\(action)"])
        run { try await self.setPower(action, on: tv) }
    }

    func setPower(_ action: PowerAction, on tv: TVDevice) async throws {
        busyTVIDs.insert(tv.id)
        defer { busyTVIDs.remove(tv.id) }
        let client = try client(for: tv)
        switch action {
        case .off:
            let info = await refresh(tv)
            guard info?.isOn == true else { return } // already off / standby
            // Tested on the 2024 Frame (LS03D): a remote-channel KEY_POWER
            // Press/Release is just a click (TV <-> Art), whatever the hold
            // time, and KEY_POWEROFF is ignored. Only SmartThings turns it off.
            if let st = smartThingsClient(), let deviceID = tv.smartThingsDeviceID {
                try await st.send(deviceID: deviceID, capability: "switch", command: "off")
            } else if tv.isFrame {
                try await samsungClient(for: tv).setArtMode(true)
                show("Sem SmartThings, a The Frame só vai para o Modo Arte. Para desligar de verdade, configure o SmartThings.")
                return
            } else {
                try await client.powerOff()
            }
            var status = statuses[tv.id] ?? TVStatus()
            status.artMode = nil
            status.reachability = .standby
            statuses[tv.id] = status
        case .wake:
            try await wake(tv)
        case .tv, .art:
            let wantArt = action == .art
            if await refresh(tv)?.isOn != true {
                try await wake(tv)
            }
            guard tv.isFrame else {
                if wantArt { throw TVError.notFrame }
                return
            }
            do {
                try await samsungClient(for: tv).setArtMode(wantArt)
            } catch {
                // The art service can lag right after wake-up; retry once.
                try await Task.sleep(for: .seconds(2))
                try await samsungClient(for: tv).setArtMode(wantArt)
            }
        }
    }

    /// Wakes the TV, then waits up to 20 s for REST to report it on.
    /// 1. If REST still answers (PowerState "standby"), a KEY_POWER click on
    ///    the remote channel turns it on. Tested on the 2024 Frame, where
    ///    Wake-on-LAN did not work.
    /// 2. Otherwise Wake-on-LAN, plus SmartThings `switch on` when mapped.
    func wake(_ tv: TVDevice) async throws {
        try await sendWakeSignals(to: tv)
        try await waitUntilOn(tv)
    }

    /// Throws when no wake path could even be attempted.
    private func sendWakeSignals(to tv: TVDevice) async throws {
        var sentSomething = await sendPowerKeyIfStandby(tv)
        var wolError: Error?
        if let mac = tv.mac, !mac.isEmpty {
            do {
                try await WakeOnLANSender.send(mac: mac, ip: tv.ip)
                sentSomething = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // e.g. EPERM under the sandbox: still try the cloud path.
                wolError = error
            }
        }
        if let st = smartThingsClient(), let deviceID = tv.smartThingsDeviceID {
            do {
                try await st.send(deviceID: deviceID, capability: "switch", command: "on")
                sentSomething = true
            } catch {
                if wolError == nil { wolError = error }
            }
        }
        guard sentSomething else { throw wolError ?? TVError.noMAC }
    }

    /// True when the wake command (Samsung KEY_POWER, Sony setPowerStatus)
    /// went out to a TV that REST reports in standby.
    private func sendPowerKeyIfStandby(_ tv: TVDevice) async -> Bool {
        guard let info = await refresh(tv), !info.isOn else { return false }
        return (try? await client(for: tv).wakeFromStandby()) != nil
    }

    private func waitUntilOn(_ tv: TVDevice) async throws {
        for _ in 0..<20 {
            try await Task.sleep(for: .seconds(1))
            guard tvs.contains(where: { $0.id == tv.id }) else { throw TVError.noTVSelected }
            if await refresh(tv)?.isOn == true {
                try await Task.sleep(for: .seconds(1))
                return
            }
        }
        switch tv.vendor {
        case .samsung: throw TVError.wakeFailed
        case .sony: throw TVError.sonyWakeFailed
        case .lg: throw TVError.lgWakeFailed
        }
    }

    func setArtMode(_ on: Bool) {
        guard let tv = selectedTV else { return }
        run {
            if on {
                try await self.setPower(.art, on: tv)
            } else {
                try await self.samsungClient(for: tv).setArtMode(false)
            }
        }
    }

    func refreshArtMode() {
        guard let tv = selectedTV else { return }
        run { try await self.samsungClient(for: tv).artModeStatus() }
    }

    func setArtBrightness(_ value: Int) {
        guard let tv = selectedTV else { return }
        run { try await self.samsungClient(for: tv).setArtBrightness(value) }
    }

    func setMotionTimer(_ value: String) {
        guard let tv = selectedTV else { return }
        run { try await self.samsungClient(for: tv).setMotionTimer(value) }
    }
}
