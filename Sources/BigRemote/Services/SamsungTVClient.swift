// story: e01s01 e01s02 e01s03 e02s01
import Foundation

enum TVClientUpdate: Sendable {
    case link(LinkState)
    case artMode(Bool?)
    case goingToStandby
    case ime(Bool)
    case artAPIVersion(String)
}

/// Owns the remote and art sockets of one TV. Lazily connects on first use
/// and reconnects on the next command after a drop. Keys are sent in order
/// with pacing.
actor SamsungTVClient: TVController {
    nonisolated let tvID: String
    /// `TokenStore` key: TV id plus this platform's client name.
    nonisolated let tokenKey: String
    var ip: String
    var isFrame: Bool
    let tokens = TokenStore()
    let rest = TVRESTClient()
    let remote = ChannelSocket()
    let art = ChannelSocket()
    let onUpdate: @Sendable (TVClientUpdate) -> Void

    var remoteConnect: Task<Void, Error>?
    var artConnect: Task<Void, Error>?
    var keyQueue: Task<Void, Never>?
    var nextKeyAt: ContinuousClock.Instant?

    var pendingArt: [String: CheckedContinuation<JSONValue, Error>] = [:]
    var artMisses = 0
    var artBackoff: Duration = .seconds(30)
    var artBlockedUntil: ContinuousClock.Instant?
    var askedArtVersion = false
    /// Set when the art socket fails to open: background monitoring stops retrying, because
    /// each retry with a stale token can put a pairing prompt on the TV. Cleared by a good
    /// remote or art connect, and by forgetting the pairing.
    var artAutoPaused = false
    /// Open `set_artmode_status` request: an `art_mode_changed` /
    /// `artmode_status` push with this value also completes it.
    var pendingArtModeSet: (id: String, on: Bool)?

    init(tv: TVDevice, onUpdate: @escaping @Sendable (TVClientUpdate) -> Void) {
        self.tvID = tv.id
        self.tokenKey = TokenStore.samsungKey(tvID: tv.id)
        self.ip = tv.ip
        self.isFrame = tv.isFrame
        self.onUpdate = onUpdate
    }

    // MARK: - Configuration

    func update(ip newIP: String, isFrame frame: Bool) async {
        isFrame = frame
        guard newIP != ip else { return }
        ip = newIP
        await disconnectAll()
    }

    func hasToken() -> Bool { tokens.token(for: tokenKey) != nil }

    func forgetPairing() async {
        tokens.setToken(nil, for: tokenKey)
        artAutoPaused = false
        await disconnectAll()
        onUpdate(.link(.idle))
    }

    func disconnectAll() async {
        await remote.disconnect()
        await art.disconnect()
        failAllPendingArt(TVError.notConnected)
    }

    // MARK: - Remote channel

    /// Connects now (used by the "Parear" button).
    func pair() async throws {
        try await ensureRemote()
    }

    func ensureRemote() async throws {
        if await remote.isOpen { return }
        if let running = remoteConnect { return try await running.value }
        let job = Task { try await self.openRemote() }
        remoteConnect = job
        defer { remoteConnect = nil }
        try await job.value
    }

    private func openRemote() async throws {
        let token = tokens.token(for: tokenKey)
        onUpdate(.link(token == nil ? .awaitingApproval : .connecting))
        guard let url = RemotePayloads.channelURL(ip: ip, channel: .remote, token: token) else {
            throw TVError.invalidAddress
        }
        Log.info(.pairing, "remote.connect.start", tv: tvID, [
            "ip": ip,
            "clientName": RemotePayloads.clientName,
            "tokenFingerprint": Log.fingerprint(token),
        ])
        do {
            let newToken = try await remote.connect(
                url: url,
                waitForReady: false,
                timeout: .seconds(token == nil ? 60 : 30),
                onEvent: { [weak self] event in await self?.handleRemoteEvent(event) },
                onClose: { [weak self] in await self?.remoteClosed() }
            )
            Log.info(.pairing, "remote.connect.ok", tv: tvID, [
                "tokenReceived": Log.fingerprint(newToken),
                "sameAsSent": "\(newToken == token)",
            ])
            if let newToken, newToken != token { tokens.setToken(newToken, for: tokenKey) }
            artAutoPaused = false
            onUpdate(.link(.connected))
        } catch is CancellationError {
            // disconnect() ran during the handshake (forget, IP change, removal).
            Log.info(.pairing, "remote.connect.cancelled", tv: tvID)
            onUpdate(.link(.idle))
            throw CancellationError()
        } catch TVError.channelTimeOut {
            Log.warning(.pairing, "remote.connect.timeOut", tv: tvID, [
                "hadToken": "\(token != nil)", "action": "token cleared, the TV must prompt again",
            ])
            tokens.setToken(nil, for: tokenKey)
            onUpdate(.link(.needsPairing))
            throw TVError.channelTimeOut
        } catch TVError.unauthorized {
            Log.warning(.pairing, "remote.connect.unauthorized", tv: tvID, ["hadToken": "\(token != nil)"])
            onUpdate(.link(.denied))
            throw TVError.unauthorized
        } catch {
            Log.error(.pairing, "remote.connect.failed", tv: tvID, ["error": error.localizedDescription])
            onUpdate(.link(.failed(error.localizedDescription)))
            throw error
        }
    }

    private func remoteClosed() {
        Log.info(.link, "remote.closed", tv: tvID)
        onUpdate(.link(.idle))
    }

    private func handleRemoteEvent(_ event: ChannelEvent) {
        Log.debug(.link, "remote.event", tv: tvID, ["name": event.name])
        switch event.name {
        case "ms.remote.imeStart": onUpdate(.ime(true))
        case "ms.remote.imeEnd": onUpdate(.ime(false))
        default: break
        }
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

    private func waitForPacing() async throws {
        if let next = nextKeyAt, ContinuousClock.now < next {
            try await Task.sleep(until: next, clock: .continuous)
        }
    }

    private func rawSendKey(_ code: String, _ command: KeyCommand) async throws {
        try await ensureRemote()
        try await waitForPacing()
        try await remote.send(try RemotePayloads.key(code, command: command))
        nextKeyAt = ContinuousClock.now + RemoteKey.pacing(after: code)
    }

    func sendKey(_ code: String) async throws {
        try await sendKey(code, command: .click)
    }

    func sendKey(_ code: String, command: KeyCommand) async throws {
        guard RemoteKey.isAllowed(code) else { throw TVError.blockedKey(code) }
        Log.info(.command, "key", tv: tvID, ["code": code, "command": "\(command)"])
        try await enqueue { try await self.rawSendKey(code, command) }
    }

    /// Press, wait, Release (e.g. KEY_POWER for 3 s = real off on a Frame).
    func holdKey(_ code: String, seconds: Double) async throws {
        guard RemoteKey.isAllowed(code) else { throw TVError.blockedKey(code) }
        try await enqueue {
            try await self.rawSendKey(code, .press)
            try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            try await self.rawSendKey(code, .release)
        }
    }

    /// REST POST first: on the 2024 Frame `ed.apps.launch` is silently
    /// ignored (no reply, app stays hidden), so a WS send never "fails".
    /// WS is kept as fallback for native IDs that REST does not know.
    func launchApp(_ appID: String, type: TVApp.LaunchType) async throws {
        do {
            try await rest.launchApp(ip: ip, appID: appID)
            Log.info(.command, "app.launch", tv: tvID, ["appID": appID, "via": "rest"])
        } catch {
            Log.warning(.command, "app.launch.rest.failed", tv: tvID, ["appID": appID, "error": error.localizedDescription])
            try await ensureRemote()
            try await remote.send(try RemotePayloads.launchApp(appID, type: type))
        }
    }

    /// Replaces the focused text field with `text` (docs 4).
    func sendText(_ text: String, submit: Bool) async throws {
        Log.info(.command, "text.send", tv: tvID, ["length": "\(text.count)", "submit": "\(submit)"])
        try await enqueue {
            try await self.ensureRemote()
            try await self.remote.send(try RemotePayloads.textReceivedBroadcast())
            try await self.remote.send(try RemotePayloads.inputString(text))
            if submit {
                try await Task.sleep(for: .milliseconds(500))
                try await self.remote.send(try RemotePayloads.inputEnd())
            }
        }
    }

    /// A KEY_POWER click turns on a TV whose REST still answers in standby
    /// (2024 Frame, where Wake-on-LAN did not work).
    func wakeFromStandby() async throws {
        Log.info(.power, "wake.key", tv: tvID)
        try await sendKey(RemoteKey.power.rawValue)
    }

    /// Hold 3 s on a Frame (Home Assistant's real off), click otherwise.
    /// The 2024 Frame treats the hold as a click (TV <-> Art); see AppModel.setPower.
    func powerOff() async throws {
        Log.info(.power, "power.off", tv: tvID, ["isFrame": "\(isFrame)"])
        if isFrame {
            try await holdKey(RemoteKey.power.rawValue, seconds: 3)
        } else {
            try await sendKey(RemoteKey.power.rawValue)
        }
    }
}
