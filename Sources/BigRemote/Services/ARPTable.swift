import Darwin
import Foundation

/// Reads the kernel ARP cache (like `arp -n`) to find the MAC of a wired TV.
/// `GET /api/v2/` only reports the Wi-Fi MAC, which is wrong for a TV on
/// Ethernet. Best effort: returns nil if the entry is missing.
enum ARPTable {
    static func mac(for ip: String) -> String? {
        #if os(macOS)
        return macFromRoutingTable(ip)
        #else
        // The routing sysctl is not available to iOS apps: the user types the MAC.
        return nil
        #endif
    }

    #if os(macOS)
    private static func macFromRoutingTable(_ ip: String) -> String? {
        guard let target = NetworkAddress.ipv4Octets(ip) else { return nil }
        // CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS (2), RTF_LLINFO (0x400)
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, 2, 0x400]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        let headerSize = MemoryLayout<rt_msghdr>.size
        var offset = 0
        while offset + headerSize <= length {
            let messageLength = Int(UInt16(buffer[offset]) | (UInt16(buffer[offset + 1]) << 8))
            guard messageLength > 0 else { break }
            defer { offset += messageLength }
            let sinOffset = offset + headerSize
            guard sinOffset + 8 <= length else { break }
            // sockaddr_in: len, family, port(2), addr(4)
            let sinLength = Int(buffer[sinOffset])
            let address = Array(buffer[(sinOffset + 4)..<(sinOffset + 8)])
            guard address == target else { continue }
            let rounded = sinLength > 0 ? (1 + ((sinLength - 1) | 3)) : 4
            let sdlOffset = sinOffset + rounded
            // sockaddr_dl: len, family, index(2), type, nlen, alen, slen, data...
            guard sdlOffset + 8 <= length else { continue }
            let nameLength = Int(buffer[sdlOffset + 5])
            let addressLength = Int(buffer[sdlOffset + 6])
            let macOffset = sdlOffset + 8 + nameLength
            guard addressLength == 6, macOffset + 6 <= length else { continue }
            let mac = buffer[macOffset..<(macOffset + 6)]
            guard mac.contains(where: { $0 != 0 }) else { continue }
            return mac.map { String(format: "%02X", $0) }.joined(separator: ":")
        }
        return nil
    }
    #endif
}
