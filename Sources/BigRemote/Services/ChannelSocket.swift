import Foundation

/// One WebSocket to one TV channel. Handles the connect handshake
/// (`ms.channel.connect`, optional `ms.channel.ready`) with a hard deadline,
/// then forwards every event in order.
actor ChannelSocket {
    typealias EventHandler = @Sendable (ChannelEvent) async -> Void
    typealias CloseHandler = @Sendable () async -> Void

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    /// The socket that is still in its handshake (not yet in `task`).
    private var pending: URLSessionWebSocketTask?
    /// The close handler of the open connection. `disconnect()` calls it.
    private var closeHandler: CloseHandler?
    /// Incremented by every `disconnect()`. A `connect()` that sees a new
    /// value after its handshake was superseded and must not install itself.
    private var generation = 0

    init(session: URLSession = LANSession.shared) {
        self.session = session
    }

    var isOpen: Bool { task != nil }

    private enum Outcome: Sendable {
        case connected(String?)
        case timedOut
    }

    /// Opens the socket and waits for the handshake. Returns the token from
    /// `ms.channel.connect` (if any).
    func connect(
        url: URL,
        waitForReady: Bool,
        timeout: Duration,
        onEvent: @escaping EventHandler,
        onClose: @escaping CloseHandler
    ) async throws -> String? {
        teardown(notify: false)
        let myGeneration = generation
        let task = session.webSocketTask(with: url)
        // Art content lists can exceed the 1 MB default.
        task.maximumMessageSize = 64 * 1024 * 1024
        pending = task
        task.resume()

        let outcome: Outcome
        do {
            outcome = try await Self.raceHandshake(task, waitForReady: waitForReady, timeout: timeout)
        } catch {
            if pending === task { pending = nil }
            task.cancel(with: .goingAway, reason: nil)
            // A disconnect() during the handshake cancelled this socket.
            if generation != myGeneration { throw CancellationError() }
            throw error
        }
        if pending === task { pending = nil }

        guard generation == myGeneration else {
            task.cancel(with: .goingAway, reason: nil)
            throw CancellationError()
        }
        guard case .connected(let token) = outcome else {
            task.cancel(with: .goingAway, reason: nil)
            throw TVError.timeout
        }

        self.task = task
        closeHandler = onClose
        startReceiveLoop(task, onEvent: onEvent)
        return token
    }

    /// Handshake against a hard deadline: whichever finishes first wins.
    private static func raceHandshake(
        _ task: URLSessionWebSocketTask,
        waitForReady: Bool,
        timeout: Duration
    ) async throws -> Outcome {
        try await withThrowingTaskGroup(of: Outcome.self) { group in
            group.addTask {
                .connected(try await ChannelSocket.handshake(task, waitForReady: waitForReady))
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .timedOut
            }
            guard let first = try await group.next() else { return .timedOut }
            if case .timedOut = first {
                // Unblocks the pending receive() in the handshake child.
                task.cancel(with: .goingAway, reason: nil)
            }
            group.cancelAll()
            return first
        }
    }

    /// Forwards every non-ignored event in order until the socket closes.
    private func startReceiveLoop(_ task: URLSessionWebSocketTask, onEvent: @escaping EventHandler) {
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    if let event = ChannelSocket.parse(message), !ChannelEvent.ignored.contains(event.name) {
                        await onEvent(event)
                    }
                } catch {
                    break
                }
            }
            await self?.didClose(task)
        }
    }

    private static func handshake(_ task: URLSessionWebSocketTask, waitForReady: Bool) async throws -> String? {
        var connected = false
        var token: String?
        while true {
            let message = try await task.receive()
            guard let event = parse(message) else { continue }
            switch event.name {
            case "ms.channel.connect":
                connected = true
                token = event.token
                if !waitForReady { return token }
            case "ms.channel.ready":
                if connected || !waitForReady { return token }
            case "ms.channel.unauthorized":
                throw TVError.unauthorized
            case "ms.channel.timeOut":
                throw TVError.channelTimeOut
            default:
                continue
            }
        }
    }

    private static func parse(_ message: URLSessionWebSocketTask.Message) -> ChannelEvent? {
        switch message {
        case .string(let text):
            return ChannelEvent.parse(text)
        case .data(let data):
            return ChannelEvent.parse(String(decoding: data, as: UTF8.self))
        @unknown default:
            return nil
        }
    }

    /// The receive loop ended on its own (TV closed the socket or it failed).
    /// After `disconnect()` the task is already gone and this does nothing.
    private func didClose(_ closed: URLSessionWebSocketTask) async {
        guard task === closed else { return }
        task = nil
        receiveLoop = nil
        let handler = closeHandler
        closeHandler = nil
        await handler?()
    }

    func send(_ text: String) async throws {
        guard let task else { throw TVError.notConnected }
        do {
            try await task.send(.string(text))
        } catch {
            disconnect()
            throw TVError.socket(error.localizedDescription)
        }
    }

    /// Closes the open socket (and calls its close handler) and cancels a
    /// connect that is still in its handshake.
    func disconnect() {
        teardown(notify: true)
    }

    private func teardown(notify: Bool) {
        generation += 1
        pending?.cancel(with: .goingAway, reason: nil)
        pending = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        let hadTask = task != nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let handler = closeHandler
        closeHandler = nil
        if notify, hadTask, let handler { Task { await handler() } }
    }
}
