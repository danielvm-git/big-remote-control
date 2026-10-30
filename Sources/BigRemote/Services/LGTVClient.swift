// story: e10s02 e10s03
import Foundation

/// Controls one LG webOS TV over SSAP (`wss://<ip>:3001/`). Pairing: the TV
/// shows an accept prompt once and returns a `client-key`, saved in
/// `TokenStore`. Buttons go over a second socket from `getPointerInputSocket`.
actor LGTVClient: NamedAppLauncher {
    nonisolated let tvID: String
    var ip: String
    let tokens = TokenStore()
    let main = WebOSSocket()
    let input = WebOSSocket()
    let onUpdate: @Sendable (TVClientUpdate) -> Void

    var registered = false
    var connectJob: Task<Void, Error>?
    var registerWaiter: CheckedContinuation<String, Error>?
    var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    var nextID = 1
    var apps: [TVAppEntry] = []
    var keyQueue: Task<Void, Never>?

    init(tv: TVDevice, onUpdate: @escaping @Sendable (TVClientUpdate) -> Void) {
        self.tvID = tv.id
        self.ip = tv.ip
        self.onUpdate = onUpdate
    }

    func update(ip newIP: String, isFrame _: Bool) async {
        guard newIP != ip else { return }
        ip = newIP
        await disconnectAll()
    }

    func disconnectAll() async {
        await main.close()
        await input.close()
        closed()
    }

    func forgetPairing() async {
        tokens.setToken(nil, for: tvID)
        await disconnectAll()
    }

    // MARK: - Connection and pairing

    func pair() async throws {
        try await ensureConnected()
    }

    func ensureConnected() async throws {
        if registered, await main.isOpen { return }
        if let running = connectJob { return try await running.value }
        let job = Task { try await self.connect() }
        connectJob = job
        defer { connectJob = nil }
        try await job.value
    }

    private func connect() async throws {
        guard let url = WebOSPayloads.mainURL(ip: ip) else { throw TVError.invalidAddress }
        let key = tokens.token(for: tvID)
        onUpdate(.link(key == nil ? .awaitingApproval : .connecting))
        Log.info(.pairing, "lg.connect.start", tv: tvID, ["ip": ip, "keyFingerprint": Log.fingerprint(key)])
        await main.open(
            url: url,
            onMessage: { [weak self] text in await self?.handle(text) },
            onClose: { [weak self] in await self?.closed() }
        )
        do {
            // The accept prompt waits for the user; a known key answers at once.
            let newKey = try await withTimeout(.seconds(key == nil ? 60 : 10)) {
                try await self.sendRegister(key: key)
            } onTimeout: {
                await self.finishRegister(.failure(TVError.timeout))
            }
            if newKey != key { tokens.setToken(newKey, for: tvID) }
            registered = true
            Log.info(.pairing, "lg.register.ok", tv: tvID, [
                "keyFingerprint": Log.fingerprint(newKey), "keyChanged": "\(newKey != key)",
            ])
            onUpdate(.link(.connected))
        } catch {
            Log.warning(.pairing, "lg.connect.failed", tv: tvID, [
                "error": error.localizedDescription, "hadKey": "\(key != nil)",
            ])
            await main.close()
            registerWaiter = nil
            onUpdate(.link(key == nil ? .needsPairing : .failed(error.localizedDescription)))
            throw error
        }
    }

    private func sendRegister(key: String?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            registerWaiter = continuation
            Task {
                do {
                    try await main.send(try WebOSPayloads.register(clientKey: key))
                } catch {
                    finishRegister(.failure(error))
                }
            }
        }
    }

    private func finishRegister(_ result: Result<String, Error>) {
        registerWaiter?.resume(with: result)
        registerWaiter = nil
    }

    private func handle(_ text: String) {
        guard let message = try? WebOSPayloads.parse(text), let id = message.id else { return }
        if id == WebOSPayloads.registerID {
            switch message.type {
            case "registered":
                if let key = message.payload["client-key"]?.stringValue { finishRegister(.success(key)) }
            case "error":
                Log.warning(.pairing, "lg.register.refused", tv: tvID, ["error": message.error ?? ""])
                finishRegister(.failure(TVError.webOS(message.error ?? "pareamento recusado")))
            default:
                break // "response" with pairingType PROMPT: the prompt is on screen.
            }
            return
        }
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if message.type == "error" {
            Log.warning(.command, "lg.request.error", tv: tvID, ["id": id, "error": message.error ?? ""])
            continuation.resume(throwing: TVError.webOS(message.error ?? "erro"))
        } else {
            continuation.resume(returning: message.payload)
        }
    }

    private func closed() {
        Log.info(.link, "lg.closed", tv: tvID)
        registered = false
        apps = []
        finishRegister(.failure(TVError.notConnected))
        for continuation in pending.values { continuation.resume(throwing: TVError.notConnected) }
        pending = [:]
        onUpdate(.link(.idle))
    }

    /// One SSAP request; the reply payload or `TVError.webOS`.
    @discardableResult
    func request(_ uri: String, _ payload: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await ensureConnected()
        let id = String(nextID)
        nextID += 1
        let text = try WebOSPayloads.request(id: id, uri: uri, payload: payload)
        return try await withTimeout(.seconds(10)) {
            try await self.awaitReply(id: id, sending: text)
        } onTimeout: {
            await self.failPending(id, TVError.timeout)
        }
    }

    private func awaitReply(id: String, sending text: String) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await main.send(text)
                } catch {
                    failPending(id, error)
                }
            }
        }
    }

    private func failPending(_ id: String, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func withTimeout<T: Sendable>(
        _ limit: Duration,
        _ body: @escaping @Sendable () async throws -> T,
        onTimeout: @escaping @Sendable () async -> Void
    ) async throws -> T {
        let timer = Task {
            try await Task.sleep(for: limit)
            await onTimeout()
        }
        defer { timer.cancel() }
        return try await body()
    }

    // MARK: - Keys

    func sendKey(_ code: String) async throws {
        guard RemoteKey.isAllowed(code) else { throw TVError.blockedKey(code) }
        guard let name = WebOSPayloads.buttonName(for: code) else { throw TVError.keyUnsupported(code) }
        try await enqueue {
            try await self.ensureInput()
            Log.info(.command, "lg.button", tv: self.tvID, ["name": name])
            try await self.input.send(WebOSPayloads.button(name))
            try await Task.sleep(for: RemoteKey.pacing(after: code))
        }
    }

    /// The pointer socket has no press/release: a hold is one click.
    func holdKey(_ code: String, seconds _: Double) async throws {
        try await sendKey(code)
    }

    private func ensureInput() async throws {
        if await input.isOpen { return }
        let reply = try await request("com.webos.service.networkinput/getPointerInputSocket")
        guard let path = reply["socketPath"]?.stringValue, let url = URL(string: path) else {
            throw TVError.webOS("sem socket de entrada")
        }
        await input.open(url: url, onMessage: { _ in }, onClose: {})
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

    func findApp(named name: String) async throws -> TVAppEntry? {
        if apps.isEmpty {
            apps = WebOSPayloads.apps(from: try await request("com.webos.applicationManager/listLaunchPoints"))
        }
        return TVAppEntry.match(name, in: apps)
    }

    func launchApp(named name: String) async throws {
        guard let app = try await findApp(named: name) else { throw TVError.appNotInstalled(name) }
        try await launch(id: app.id)
    }

    func launch(id: String) async throws {
        Log.info(.command, "app.launch", tv: tvID, ["id": id])
        try await request("system.launcher/launch", ["id": .string(id)])
    }

    /// `replace` swaps the field text, so live typing can resend the whole string.
    func sendText(_ text: String, submit: Bool) async throws {
        try await request("com.webos.service.ime/insertText", ["text": .string(text), "replace": true])
        if submit { try await request("com.webos.service.ime/sendEnterKey") }
    }

    /// The TV may close the socket before it answers, so the reply is not awaited.
    func powerOff() async throws {
        Log.info(.power, "power.off", tv: tvID)
        try await ensureConnected()
        try await main.send(try WebOSPayloads.request(id: "power_off", uri: "system/turnOff"))
    }

    /// Works only while the socket is still up (screen off). From real
    /// standby the TV wakes by Wake-on-LAN.
    func wakeFromStandby() async throws {
        Log.info(.power, "wake.request", tv: tvID)
        try await request("system/turnOn")
    }
}
