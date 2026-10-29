import Foundation

enum NetworkAddress {
    static func ipv4Octets(_ text: String) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        return octets
    }

    /// RFC 1918 ranges only (10/8, 172.16/12, 192.168/16).
    static func isPrivateIPv4(_ text: String) -> Bool {
        guard let octets = ipv4Octets(text) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        default: return false
        }
    }

    static func subnetBroadcast24(_ ip: String) -> String? {
        guard let octets = ipv4Octets(ip) else { return nil }
        return "\(octets[0]).\(octets[1]).\(octets[2]).255"
    }

    /// All host addresses .1-.254 of the /24 that contains `ip`.
    static func hosts24(around ip: String) -> [String] {
        guard let octets = ipv4Octets(ip) else { return [] }
        return (1...254).map { "\(octets[0]).\(octets[1]).\(octets[2]).\($0)" }
    }
}
