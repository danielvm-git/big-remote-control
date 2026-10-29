// story: e07s01
import Darwin
import Foundation

/// Finds TVs by probing `GET :8001/api/v2/` on every host of the local /24s.
enum TVDiscovery {
    /// Private IPv4 addresses of the Mac's active interfaces.
    static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ok = getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard ok == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if NetworkAddress.isPrivateIPv4(ip), !result.contains(ip) { result.append(ip) }
        }
        return result
    }

    /// Probes all /24 hosts concurrently (short timeouts, bounded width).
    static func scan(rest: TVRESTClient = TVRESTClient(), timeout: TimeInterval = 0.8, width: Int = 48) async -> [DeviceInfo] {
        var hosts: [String] = []
        for local in localIPv4Addresses() {
            for host in NetworkAddress.hosts24(around: local) where host != local && !hosts.contains(host) {
                hosts.append(host)
            }
        }
        var found: [DeviceInfo] = []
        await withTaskGroup(of: DeviceInfo?.self) { group in
            var iterator = hosts.makeIterator()
            for _ in 0..<width {
                guard let host = iterator.next() else { break }
                group.addTask { await rest.deviceInfo(ip: host, timeout: timeout) }
            }
            while let result = await group.next() {
                if let info = result, info.isSamsungTV { found.append(info) }
                if let host = iterator.next() {
                    group.addTask { await rest.deviceInfo(ip: host, timeout: timeout) }
                }
            }
        }
        return found.sorted { $0.ip.compare($1.ip, options: .numeric) == .orderedAscending }
    }
}
