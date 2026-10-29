import Foundation

/// SmartThings cloud REST (optional; docs 7).
struct SmartThingsClient: Sendable {
    let token: String
    static let base = URL(string: "https://api.smartthings.com/v1")!

    private func request(_ url: URL, method: String = "GET", body: String? = nil) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: return data
        case 401: throw TVError.smartThings("token inválido ou expirado (tokens pessoais novos valem 24 h)")
        case 403: throw TVError.smartThings("sem permissão (escopos r/w/x:devices:*)")
        case 429: throw TVError.smartThings("limite de requisições atingido")
        default:
            let text = String(decoding: data.prefix(200), as: UTF8.self)
            throw TVError.smartThings("HTTP \(code) \(text)")
        }
    }

    func devices() async throws -> [STDevice] {
        var result: [STDevice] = []
        var next: URL? = Self.base.appending(path: "devices")
        var pages = 0
        while let url = next, pages < 20 {
            let data = try await request(url)
            let page = try JSONDecoder().decode(STDeviceList.self, from: data)
            result.append(contentsOf: page.items)
            next = page._links?.next?.href.flatMap(URL.init(string:))
            pages += 1
        }
        return result
    }

    func status(deviceID: String) async throws -> STDeviceStatus {
        let data = try await request(Self.base.appending(path: "devices/\(deviceID)/status"))
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        return STDeviceStatus(raw: raw)
    }

    func send(deviceID: String, capability: String, command: String, arguments: [JSONValue] = []) async throws {
        let body = SmartThingsPayloads.commandBody(capability: capability, command: command, arguments: arguments)
        _ = try await request(Self.base.appending(path: "devices/\(deviceID)/commands"), method: "POST", body: body)
    }
}
