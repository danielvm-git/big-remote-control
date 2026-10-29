import Foundation

enum WakeOnLANPacket {
    /// Accepts `AA:BB:CC:DD:EE:FF`, `AA-BB-...` or `AABBCCDDEEFF`.
    static func parseMAC(_ text: String) -> [UInt8]? {
        let hex = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// 6 x 0xFF + MAC x 16 = 102 bytes.
    static func magicPacket(mac: [UInt8]) -> [UInt8] {
        precondition(mac.count == 6, "MAC must be 6 bytes")
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }
        return packet
    }

    static func magicPacket(macString: String) throws -> [UInt8] {
        guard let mac = parseMAC(macString) else { throw TVError.invalidMAC(macString) }
        return magicPacket(mac: mac)
    }

    /// Destinations: limited broadcast, /24 broadcast and unicast (docs 5).
    static func destinations(for ip: String?) -> [String] {
        var result = ["255.255.255.255"]
        if let ip, let broadcast = NetworkAddress.subnetBroadcast24(ip) {
            result.append(broadcast)
            result.append(ip)
        }
        return result
    }

    static let ports: [UInt16] = [9, 7]
    static let rounds = 3
    static let roundInterval: Duration = .milliseconds(300)
}
