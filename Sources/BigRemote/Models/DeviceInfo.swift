import Foundation

/// Decoded `GET http://<ip>:8001/api/v2/`.
/// All flags are strings ("true"/"false"); `isSupport` is JSON inside JSON.
struct DeviceInfo: Sendable, Hashable {
    var ip: String
    var name: String?
    var modelName: String?
    var model: String?
    var powerState: String?
    var isFrame: Bool
    var tokenAuthSupport: Bool
    var imeSyncedSupport: Bool
    var wifiMac: String?
    var networkType: String?
    var duid: String?
    var resolution: String?
    var language: String?
    var apiVersion: String?
    var isSamsungTV: Bool
    var support: [String: String]

    /// No PowerState field means an older TV that only answers when on.
    var isOn: Bool {
        guard let powerState else { return true }
        return powerState.lowercased() == "on"
    }

    var isWired: Bool { networkType?.lowercased() == "wired" }

    private struct Response: Decodable {
        var device: Device?
        var isSupport: String?
        var name: String?
        var version: String?
        var type: String?
    }

    private struct Device: Decodable {
        var FrameTVSupport: String?
        var ImeSyncedSupport: String?
        var Language: String?
        var PowerState: String?
        var TokenAuthSupport: String?
        var duid: String?
        var id: String?
        var ip: String?
        var model: String?
        var modelName: String?
        var name: String?
        var networkType: String?
        var resolution: String?
        var wifiMac: String?
        var type: String?
    }

    static func decode(_ data: Data, fallbackIP: String) throws -> DeviceInfo {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let device = response.device ?? Device()
        var support: [String: String] = [:]
        if let raw = response.isSupport, let inner = JSONValue.parse(raw)?.objectValue {
            for (key, value) in inner { support[key] = value.stringValue ?? value.jsonString() }
        }
        func flag(_ value: String?) -> Bool { value?.lowercased() == "true" }
        let frame = flag(device.FrameTVSupport) || flag(support["FrameTVSupport"])
        let type = device.type ?? response.type ?? ""
        return DeviceInfo(
            ip: device.ip ?? fallbackIP,
            name: device.name ?? response.name,
            modelName: device.modelName,
            model: device.model,
            powerState: device.PowerState,
            isFrame: frame,
            tokenAuthSupport: flag(device.TokenAuthSupport),
            imeSyncedSupport: flag(device.ImeSyncedSupport),
            wifiMac: device.wifiMac,
            networkType: device.networkType,
            duid: device.duid ?? device.id,
            resolution: device.resolution,
            language: device.Language,
            apiVersion: response.version,
            isSamsungTV: type.localizedCaseInsensitiveContains("samsung") || device.modelName != nil,
            support: support
        )
    }
}
