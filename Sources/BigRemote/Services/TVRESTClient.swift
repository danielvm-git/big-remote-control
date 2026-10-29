import Foundation

struct AppStatus: Decodable, Sendable {
    var id: String?
    var name: String?
    var running: Bool?
    var visible: Bool?
    var version: String?
}

/// Plain HTTP on port 8001 (no auth, no popup).
struct TVRESTClient: Sendable {
    private var session: URLSession { LANSession.shared }

    /// Outcome of one `GET /api/v2/`: the info, or the error that kept it away.
    struct InfoResult: Sendable {
        var info: DeviceInfo?
        var error: URLError?

        /// macOS 15+ reports a denied Local Network permission as an
        /// unsatisfied path ("Local network prohibited", -1009) or a
        /// policy-denied NWError (-65570), not as a timeout like an off TV.
        var looksLikeLocalNetworkDenied: Bool {
            guard info == nil, let error else { return false }
            let text = "\(error) \(error.userInfo)".lowercased()
            if text.contains("local network prohibited") || text.contains("policydenied") || text.contains("-65570") { return true }
            return error.code == .notConnectedToInternet
        }
    }

    /// `GET /api/v2/`. Returns nil on timeout or error (= off / deep standby).
    func deviceInfo(ip: String, timeout: TimeInterval = 2.5) async -> DeviceInfo? {
        await fetchDeviceInfo(ip: ip, timeout: timeout).info
    }

    func fetchDeviceInfo(ip: String, timeout: TimeInterval = 2.5) async -> InfoResult {
        guard NetworkAddress.ipv4Octets(ip) != nil,
              let url = URL(string: "http://\(ip):8001/api/v2/") else { return InfoResult() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return InfoResult() }
            return InfoResult(info: try DeviceInfo.decode(data, fallbackIP: ip))
        } catch let error as URLError {
            return InfoResult(error: error)
        } catch {
            return InfoResult()
        }
    }

    /// `GET /api/v2/applications/<id>`. nil = not installed (404).
    func appStatus(ip: String, appID: String) async throws -> AppStatus? {
        let request = try appRequest(ip: ip, appID: appID, method: "GET")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw TVError.http(code) }
        return try JSONDecoder().decode(AppStatus.self, from: data)
    }

    /// `POST /api/v2/applications/<id>` launches the app.
    func launchApp(ip: String, appID: String) async throws {
        let request = try appRequest(ip: ip, appID: appID, method: "POST")
        let (_, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw TVError.appNotInstalled(appID) }
        guard (200..<300).contains(code) else { throw TVError.http(code) }
    }

    private func appRequest(ip: String, appID: String, method: String) throws -> URLRequest {
        guard NetworkAddress.ipv4Octets(ip) != nil,
              let encoded = appID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "http://\(ip):8001/api/v2/applications/\(encoded)")
        else { throw TVError.invalidAddress }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.httpMethod = method
        return request
    }
}
