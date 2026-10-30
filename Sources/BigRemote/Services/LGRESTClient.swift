// story: e10s03
import Foundation

/// The only unauthenticated LG call: `GET https://<ip>:3001/` ("Hello world"
/// while the TV is on). The TV certificate is self-signed (`LANTrustDelegate`).
struct LGRESTClient: Sendable {
    func fetchDeviceInfo(ip: String, timeout: TimeInterval = 2.5) async -> TVRESTClient.InfoResult {
        guard NetworkAddress.ipv4Octets(ip) != nil, let url = URL(string: "https://\(ip):3001/") else {
            return TVRESTClient.InfoResult()
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        do {
            let (data, response) = try await LANSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return TVRESTClient.InfoResult() }
            return TVRESTClient.InfoResult(info: WebOSPayloads.deviceInfo(ip: ip, body: String(decoding: data, as: UTF8.self)))
        } catch let error as URLError {
            return TVRESTClient.InfoResult(error: error)
        } catch {
            return TVRESTClient.InfoResult()
        }
    }
}
