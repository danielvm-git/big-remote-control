import Foundation

/// Accepts the TV's self-signed TLS certificate, but only for hosts that are
/// private LAN IPv4 addresses (10/8, 172.16/12, 192.168/16). Every other
/// host gets the system's default validation.
final class LANTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              NetworkAddress.isPrivateIPv4(space.host),
              let trust = space.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

enum LANSession {
    /// Shared session for TV WebSockets (wss on 8002) and TV REST.
    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: LANTrustDelegate(), delegateQueue: nil)
    }()
}
