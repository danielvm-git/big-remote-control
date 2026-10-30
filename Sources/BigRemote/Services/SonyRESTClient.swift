// story: e09s02 e09s03
import Foundation

/// HTTP on port 80 for Sony BRAVIA: JSON-RPC `/sony/<service>` and IRCC.
/// Cookies are handled by hand (see `SonyPayloads.authCookie`).
struct SonyRESTClient: Sendable {
    private var session: URLSession { LANSession.shared }

    struct Reply: Sendable {
        var result: [JSONValue]
        var setCookie: String?
    }

    /// Throws `TVError.sonyAuthRequired` on 401/403, `TVError.sony` on a JSON-RPC error.
    func call(
        ip: String,
        service: String,
        body: Data,
        cookie: String? = nil,
        authorization: String? = nil,
        timeout: TimeInterval = 6
    ) async throws -> Reply {
        var request = try request(ip: ip, service: service, timeout: timeout, cookie: cookie)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        try check(http?.statusCode ?? 0)
        return Reply(result: try SonyPayloads.result(data), setCookie: http?.value(forHTTPHeaderField: "Set-Cookie"))
    }

    /// An empty code is a no-op request (wakes a dozing IRCC endpoint).
    func ircc(ip: String, code: String, cookie: String?) async throws {
        var request = try request(ip: ip, service: "ircc", timeout: 6, cookie: cookie)
        request.setValue("text/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(SonyPayloads.irccSOAPAction, forHTTPHeaderField: "SOAPACTION")
        request.httpBody = try SonyPayloads.irccEnvelope(code)
        let (_, response) = try await session.data(for: request)
        try check((response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Unauthenticated `getPowerStatus` + `getInterfaceInformation`. nil info = not a Sony TV or off.
    func fetchDeviceInfo(ip: String, timeout: TimeInterval = 2.5) async -> TVRESTClient.InfoResult {
        do {
            let power = try await call(ip: ip, service: "system", body: SonyPayloads.call("getPowerStatus"), timeout: timeout)
            let interface = try? await call(
                ip: ip, service: "system", body: SonyPayloads.call("getInterfaceInformation"), timeout: timeout
            )
            let status = power.result.first?["status"]?.stringValue
            return TVRESTClient.InfoResult(info: SonyPayloads.deviceInfo(ip: ip, power: status, interface: interface?.result.first))
        } catch let error as URLError {
            return TVRESTClient.InfoResult(error: error)
        } catch {
            return TVRESTClient.InfoResult()
        }
    }

    private func request(ip: String, service: String, timeout: TimeInterval, cookie: String?) throws -> URLRequest {
        guard let url = SonyPayloads.url(ip: ip, service: service) else { throw TVError.invalidAddress }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return request
    }

    private func check(_ code: Int) throws {
        if code == 401 || code == 403 { throw TVError.sonyAuthRequired }
        guard (200..<300).contains(code) else { throw TVError.http(code) }
    }
}
