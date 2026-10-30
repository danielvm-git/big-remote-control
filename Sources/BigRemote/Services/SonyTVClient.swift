// story: e09s02 e09s03
import Foundation

/// Controls one Sony BRAVIA over `/sony/*` (JSON-RPC) and IRCC on port 80.
/// Pairing: the TV shows a PIN; the PIN is saved in `TokenStore` and every
/// `actRegister` with it returns a fresh `auth` cookie (as pybravia does).
actor SonyTVClient: NamedAppLauncher {
    nonisolated let tvID: String
    var ip: String
    let tokens = TokenStore()
    let api = SonyRESTClient()
    let onUpdate: @Sendable (TVClientUpdate) -> Void

    var cookie: String?
    /// IRCC name -> code, from `getRemoteControllerInfo`.
    var commands: [String: String] = [:]
    var apps: [TVAppEntry] = []
    var lastIRCC: ContinuousClock.Instant?
    var keyQueue: Task<Void, Never>?

    init(tv: TVDevice, onUpdate: @escaping @Sendable (TVClientUpdate) -> Void) {
        self.tvID = tv.id
        self.ip = tv.ip
        self.onUpdate = onUpdate
    }

    func update(ip newIP: String, isFrame _: Bool) async {
        guard newIP != ip else { return }
        ip = newIP
        commands = [:]
        await disconnectAll()
    }

    /// Drops the cookie and the app list; the next command authenticates again.
    func disconnectAll() async {
        cookie = nil
        apps = []
    }

    func forgetPairing() async {
        tokens.setToken(nil, for: tvID)
        await disconnectAll()
        onUpdate(.link(.idle))
    }

    // MARK: - Pairing

    /// Signs in with the saved PIN, or asks the TV to show a new PIN.
    func pair() async throws {
        if tokens.token(for: tvID) != nil { return try await authenticate() }
        try await requestPIN()
    }

    /// `actRegister` without credentials: the TV shows a PIN and answers 401.
    func requestPIN() async throws {
        onUpdate(.link(.awaitingApproval))
        Log.info(.pairing, "sony.pin.requested", tv: tvID, ["ip": ip])
        do {
            let reply = try await api.call(ip: ip, service: "accessControl", body: SonyPayloads.register())
            // 200 without a PIN: authentication is off on this TV.
            cookie = SonyPayloads.authCookie(fromSetCookie: reply.setCookie)
            onUpdate(.link(.connected))
        } catch TVError.sonyAuthRequired {
            Log.info(.pairing, "sony.pin.shown", tv: tvID)
        } catch {
            onUpdate(.link(.failed(error.localizedDescription)))
            throw error
        }
    }

    func confirmPIN(_ raw: String) async throws {
        guard let pin = SonyPayloads.normalizedPIN(raw) else { throw TVError.invalidPIN }
        Log.info(.pairing, "sony.pin.submitted", tv: tvID)
        try await register(pin: pin)
        tokens.setToken(pin, for: tvID)
    }

    private func authenticate() async throws {
        guard let pin = tokens.token(for: tvID) else {
            onUpdate(.link(.needsPairing))
            throw TVError.sonyNeedsPIN
        }
        do {
            try await register(pin: pin)
        } catch TVError.sonyPINRejected {
            // The TV forgot this client (removed from its device list).
            tokens.setToken(nil, for: tvID)
            throw TVError.sonyPINRejected
        }
    }

    private func register(pin: String) async throws {
        onUpdate(.link(.connecting))
        Log.info(.pairing, "sony.register.start", tv: tvID)
        do {
            let reply = try await api.call(
                ip: ip, service: "accessControl", body: SonyPayloads.register(),
                authorization: SonyPayloads.basicAuth(pin: pin)
            )
            guard let auth = SonyPayloads.authCookie(fromSetCookie: reply.setCookie) else { throw TVError.sonyAuthRequired }
            cookie = auth
            Log.info(.pairing, "sony.register.ok", tv: tvID, ["cookieFingerprint": Log.fingerprint(auth)])
            onUpdate(.link(.connected))
        } catch TVError.sonyAuthRequired {
            Log.warning(.pairing, "sony.register.rejected", tv: tvID)
            onUpdate(.link(.needsPairing))
            throw TVError.sonyPINRejected
        } catch {
            onUpdate(.link(.failed(error.localizedDescription)))
            throw error
        }
    }

    /// Authenticated JSON-RPC call; renews the cookie once when it expired.
    @discardableResult
    private func authorized(_ service: String, _ body: Data) async throws -> [JSONValue] {
        if cookie == nil { try await authenticate() }
        do {
            return try await api.call(ip: ip, service: service, body: body, cookie: cookie).result
        } catch TVError.sonyAuthRequired {
            Log.warning(.pairing, "sony.cookie.expired", tv: tvID)
            cookie = nil
            try await authenticate()
            return try await api.call(ip: ip, service: service, body: body, cookie: cookie).result
        }
    }

    // MARK: - Keys

    func sendKey(_ code: String) async throws {
        guard RemoteKey.isAllowed(code) else { throw TVError.blockedKey(code) }
        guard let name = SonyPayloads.commandName(for: code) else { throw TVError.keyUnsupported(code) }
        try await enqueue { try await self.sendCommand(name) }
    }

    /// IRCC has no press/release: a hold is one click.
    func holdKey(_ code: String, seconds _: Double) async throws {
        try await sendKey(code)
    }

    private func sendCommand(_ name: String) async throws {
        if commands.isEmpty {
            let info = try await api.call(ip: ip, service: "system", body: SonyPayloads.call("getRemoteControllerInfo"))
            commands = SonyPayloads.commands(from: info.result)
        }
        guard let code = commands[name] else { throw TVError.keyUnsupported(name) }
        if cookie == nil { try await authenticate() }
        // After ~10 min idle some BRAVIAs drop the first IRCC silently
        // (pybravia, python-bravia-tv#15): send an empty one first.
        if lastIRCC.map({ ContinuousClock.now - $0 > .seconds(600) }) ?? true {
            try? await api.ircc(ip: ip, code: "", cookie: cookie)
        }
        Log.info(.command, "ircc", tv: tvID, ["name": name])
        do {
            try await api.ircc(ip: ip, code: code, cookie: cookie)
        } catch TVError.sonyAuthRequired {
            Log.warning(.pairing, "sony.cookie.expired", tv: tvID)
            cookie = nil
            try await authenticate()
            try await api.ircc(ip: ip, code: code, cookie: cookie)
        }
        lastIRCC = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(["Home", "Input", "Exit"].contains(name) ? 500 : 150))
    }

    /// Runs `body` after every earlier queued key job, so keys keep their order.
    private func enqueue(_ body: @escaping @Sendable () async throws -> Void) async throws {
        let previous = keyQueue
        let job = Task {
            await previous?.value
            try await body()
        }
        keyQueue = Task { _ = try? await job.value }
        try await job.value
    }

    // MARK: - Apps, text, power

    /// Matches a catalogue name ("Netflix") against the TV's app titles.
    func findApp(named name: String) async throws -> TVAppEntry? {
        if apps.isEmpty {
            apps = SonyPayloads.apps(from: try await authorized("appControl", SonyPayloads.call("getApplicationList")))
        }
        return TVAppEntry.match(name, in: apps)
    }

    func launchApp(named name: String) async throws {
        guard let app = try await findApp(named: name) else { throw TVError.appNotInstalled(name) }
        try await launch(id: app.id)
    }

    func launch(id uri: String) async throws {
        Log.info(.command, "app.launch", tv: tvID, ["uri": uri])
        try await authorized("appControl", SonyPayloads.call("setActiveApp", params: [.object(["uri": .string(uri)])]))
    }

    /// Fills the focused text field; `submit` then presses Confirm.
    func sendText(_ text: String, submit: Bool) async throws {
        try await authorized("appControl", SonyPayloads.call("setTextForm", params: [.string(text)]))
        if submit { try await sendKey(RemoteKey.enter.rawValue) }
    }

    func powerOff() async throws {
        Log.info(.power, "power.off", tv: tvID)
        try await authorized("system", SonyPayloads.call("setPowerStatus", params: [.object(["status": false])]))
    }

    /// `setPowerStatus true` needs "Remote start"; the IRCC WakeUp is a fallback.
    func wakeFromStandby() async throws {
        Log.info(.power, "wake.request", tv: tvID)
        do {
            try await authorized("system", SonyPayloads.call("setPowerStatus", params: [.object(["status": true])]))
        } catch {
            try await enqueue { try await self.sendCommand("WakeUp") }
        }
    }
}
