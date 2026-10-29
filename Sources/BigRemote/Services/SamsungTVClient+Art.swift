// story: e03s01 e03s02
import Foundation

/// The Frame art channel (`com.samsung.art-app`, docs/PROTOCOL.md 6).
extension SamsungTVClient {
    // MARK: - Art channel

    private func ensureArt() async throws {
        guard isFrame else { throw TVError.notFrame }
        if let until = artBlockedUntil, ContinuousClock.now < until { throw TVError.artUnavailable }
        if await art.isOpen { return }
        if let running = artConnect { return try await running.value }
        let job = Task { try await self.openArt() }
        artConnect = job
        defer { artConnect = nil }
        try await job.value
    }

    private func openArt() async throws {
        // 2024 Frames show no Allow prompt on the art channel:
        // pair on the remote channel first and reuse that token.
        if tokens.token(for: tvID) == nil { try await ensureRemote() }
        let token = tokens.token(for: tvID)
        guard let url = RemotePayloads.channelURL(ip: ip, channel: .art, token: token) else {
            throw TVError.invalidAddress
        }
        do {
            let newToken = try await art.connect(
                url: url,
                waitForReady: true,
                timeout: .seconds(15),
                onEvent: { [weak self] event in await self?.handleArtEvent(event) },
                onClose: { [weak self] in await self?.artClosed() }
            )
            if token == nil, let newToken { tokens.setToken(newToken, for: tvID) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await registerArtMiss()
            throw error
        }
    }

    private func artClosed() {
        failAllPendingArt(TVError.notConnected)
        onUpdate(.artMode(nil))
    }

    /// Sends one art request and waits for the reply with the same request_id.
    /// `countMissOnTimeout: false` keeps a timeout out of the back-off count.
    func artRequest(
        _ name: String,
        params: [String: JSONValue] = [:],
        timeout: Duration = .seconds(8),
        countMissOnTimeout: Bool = true,
        onRegister: (@Sendable (String) async -> Void)? = nil
    ) async throws -> JSONValue {
        try await ensureArt()
        let id = UUID().uuidString.lowercased()
        let payload = try ArtPayloads.request(name, params: params, id: id)
        let socket = art
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            Task {
                self.registerArt(id, continuation)
                await onRegister?(id)
                do {
                    try await socket.send(payload)
                } catch {
                    self.resolveArt(id, .failure(error))
                    return
                }
                try? await Task.sleep(for: timeout)
                await self.artTimedOut(id, countMiss: countMissOnTimeout)
            }
        }
    }

    private func registerArt(_ id: String, _ continuation: CheckedContinuation<JSONValue, Error>) {
        pendingArt[id] = continuation
    }

    private func resolveArt(_ id: String, _ result: Result<JSONValue, Error>) {
        guard let continuation = pendingArt.removeValue(forKey: id) else { return }
        if case .success = result {
            artMisses = 0
            artBackoff = .seconds(30)
        }
        continuation.resume(with: result)
    }

    private func artTimedOut(_ id: String, countMiss: Bool) async {
        guard let continuation = pendingArt.removeValue(forKey: id) else { return }
        continuation.resume(throwing: TVError.timeout)
        if countMiss { await registerArtMiss() }
    }

    /// After 3 unanswered requests: close and back off 30 s, doubling to 4 min.
    private func registerArtMiss() async {
        artMisses += 1
        guard artMisses >= 3 else { return }
        artMisses = 0
        artBlockedUntil = ContinuousClock.now + artBackoff
        artBackoff = min(artBackoff * 2, .seconds(240))
        await art.disconnect()
        failAllPendingArt(TVError.artUnavailable)
    }

    func failAllPendingArt(_ error: Error) {
        let pending = pendingArt
        pendingArt.removeAll()
        for continuation in pending.values { continuation.resume(throwing: error) }
    }

    private func handleArtEvent(_ event: ChannelEvent) {
        guard let message = ArtPayloads.innerMessage(event) else { return }
        let sub = message["event"]?.stringValue ?? ""

        if let mode = ArtPayloads.artModeValue(of: message) {
            onUpdate(.artMode(mode))
            // Some firmware changes mode and only sends a push, no correlated reply.
            if let set = pendingArtModeSet, set.on == mode, sub != "set_artmode_status" {
                pendingArtModeSet = nil
                resolveArt(set.id, .success(message))
            }
        }
        if sub == "go_to_standby" { onUpdate(.goingToStandby) }
        if sub.localizedCaseInsensitiveContains("wakeup") {
            Task { _ = try? await self.artModeStatus() }
        }

        if let id = ArtPayloads.requestID(of: message), pendingArt[id] != nil {
            if sub == "error" {
                let code = message["error_code"]?.stringValue ?? "?"
                resolveArt(id, .failure(TVError.artError(code)))
            } else {
                resolveArt(id, .success(message))
            }
        }
    }

    // MARK: - Art helpers

    @discardableResult
    func artModeStatus() async throws -> Bool? {
        let reply = try await artRequest("get_artmode_status")
        let mode = ArtPayloads.artModeValue(of: reply)
            ?? (reply["value"]?.stringValue).map { $0 == "on" }
        onUpdate(.artMode(mode))
        return mode
    }

    /// The upstream libraries disagree on whether a correlated reply comes
    /// (NickWaterton's async_art does not wait for one). So: a matching
    /// mode push also counts as success, and a timeout does not count toward
    /// the back-off; it is confirmed with `get_artmode_status` instead.
    func setArtMode(_ on: Bool) async throws {
        do {
            _ = try await artRequest(
                "set_artmode_status",
                params: ["value": .string(on ? "on" : "off")],
                countMissOnTimeout: false,
                onRegister: { [weak self] id in await self?.setPendingArtModeSet(id: id, on: on) }
            )
            clearPendingArtModeSet()
        } catch TVError.timeout {
            clearPendingArtModeSet()
            let mode = try? await artModeStatus()
            guard mode == on else { throw TVError.timeout }
        } catch {
            clearPendingArtModeSet()
            throw error
        }
        onUpdate(.artMode(on))
    }

    private func setPendingArtModeSet(id: String, on: Bool) {
        pendingArtModeSet = (id, on)
    }

    private func clearPendingArtModeSet() {
        pendingArtModeSet = nil
    }

    func artAPIVersion() async throws -> String? {
        var reply: JSONValue
        do {
            reply = try await artRequest("api_version")
        } catch TVError.artError {
            reply = try await artRequest("get_api_version")
        }
        let version = reply["version"]?.stringValue
        if let version { onUpdate(.artAPIVersion(version)) }
        return version
    }

    /// Sent as a string ("0"..."10"), like the other art setters and the
    /// values from get_artmode_settings. If the TV answers with an error,
    /// retries once with an integer. Not yet verified on these TVs.
    func setArtBrightness(_ value: Int) async throws {
        do {
            _ = try await artRequest("set_brightness", params: ["value": .string(String(value))])
        } catch TVError.artError {
            _ = try await artRequest("set_brightness", params: ["value": .int(value)])
        }
    }

    /// Motion timer: "off", "5", "15", "30", "60", "120", "240".
    func setMotionTimer(_ value: String) async throws {
        _ = try await artRequest("set_motion_timer", params: ["value": .string(value)])
    }

    /// Called by the poller when REST says the TV is on. Opens the art socket
    /// only when a token exists (no surprise Allow popup) and keeps it open
    /// to receive `art_mode_changed` pushes.
    func startArtMonitoring() async {
        guard isFrame, tokens.token(for: tvID) != nil else { return }
        if let until = artBlockedUntil, ContinuousClock.now < until { return }
        if await art.isOpen { return }
        _ = try? await artModeStatus()
        if !askedArtVersion {
            askedArtVersion = true
            _ = try? await artAPIVersion()
        }
    }
}
