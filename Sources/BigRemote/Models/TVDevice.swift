import Foundation

/// A TV the user controls. Persisted as JSON in UserDefaults.
struct TVDevice: Codable, Identifiable, Hashable, Sendable {
    /// Stable local id. Pairing tokens are stored per id.
    var id: String
    var name: String
    var ip: String
    /// MAC used for Wake-on-LAN (interface actually in use: Wi-Fi or wired).
    var mac: String?
    var modelName: String?
    var isFrame: Bool
    /// "wired" or "wireless", from `GET /api/v2/`.
    var networkType: String?
    var duid: String?
    /// Optional SmartThings device id mapped to this TV.
    var smartThingsDeviceID: String?

    init(
        id: String,
        name: String,
        ip: String,
        mac: String? = nil,
        modelName: String? = nil,
        isFrame: Bool = false,
        networkType: String? = nil,
        duid: String? = nil,
        smartThingsDeviceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.ip = ip
        self.mac = mac
        self.modelName = modelName
        self.isFrame = isFrame
        self.networkType = networkType
        self.duid = duid
        self.smartThingsDeviceID = smartThingsDeviceID
    }

    /// Builds a new TV entry from the REST device info.
    static func from(info: DeviceInfo) -> TVDevice {
        TVDevice(
            id: info.duid.map { "duid-\($0)" } ?? "ip-\(info.ip)",
            name: info.name ?? "TV \(info.ip)",
            ip: info.ip,
            mac: info.isWired ? nil : info.wifiMac?.uppercased(),
            modelName: info.modelName,
            isFrame: info.isFrame,
            networkType: info.networkType,
            duid: info.duid
        )
    }
}
