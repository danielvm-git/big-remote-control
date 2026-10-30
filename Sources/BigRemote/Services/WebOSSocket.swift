// story: e10s02
import Foundation

/// One plain text WebSocket (webOS main or pointer input socket). Unlike
/// `ChannelSocket` it has no handshake of its own: `LGTVClient` runs the
/// SSAP register exchange over it.
actor WebOSSocket {
    typealias MessageHandler = @Sendable (String) async -> Void
    typealias CloseHandler = @Sendable () async -> Void

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?

    init(session: URLSession = LANSession.shared) {
        self.session = session
    }

    var isOpen: Bool { task != nil }

    func open(url: URL, onMessage: @escaping MessageHandler, onClose: @escaping CloseHandler) {
        close()
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 8 * 1024 * 1024
        self.task = task
        task.resume()
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let message = try? await task.receive() else { break }
                switch message {
                case .string(let text): await onMessage(text)
                case .data(let data): await onMessage(String(decoding: data, as: UTF8.self))
                @unknown default: continue
                }
            }
            if await self?.forget(task) == true { await onClose() }
        }
    }

    func send(_ text: String) async throws {
        guard let task else { throw TVError.notConnected }
        do {
            try await task.send(.string(text))
        } catch {
            close()
            throw TVError.socket(error.localizedDescription)
        }
    }

    func close() {
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// True when `closed` was still the open socket (it closed on its own).
    private func forget(_ closed: URLSessionWebSocketTask) -> Bool {
        guard task === closed else { return false }
        task = nil
        receiveLoop = nil
        return true
    }
}
