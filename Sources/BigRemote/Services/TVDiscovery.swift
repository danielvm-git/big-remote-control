// story: e07s01
import Darwin
import Foundation

/// Finds TVs by probing every host of the local /24s: Samsung `GET :8001/api/v2/`,
/// then Sony `POST :80/sony/system getPowerStatus`, then LG `GET https://:3001/`.
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
    static func scan(
        rest: TVRESTClient = TVRESTClient(),
        sony: SonyRESTClient = SonyRESTClient(),
        lg: LGRESTClient = LGRESTClient(),
        timeout: TimeInterval = 1.5,
        width: Int = 32
    ) async -> [DeviceInfo] {
        // The three brands are probed at once, so a host costs one timeout, not three.
        // 0.8 s was too short under load on the iOS simulator (every probe timed out).
        @Sendable func probe(_ host: String) async -> DeviceInfo? {
            async let samsung = rest.deviceInfo(ip: host, timeout: timeout)
            async let bravia = sony.fetchDeviceInfo(ip: host, timeout: timeout).info
            async let webOS = lg.fetchDeviceInfo(ip: host, timeout: timeout).info
            if let info = await samsung, info.isSamsungTV { return info }
            if let info = await bravia { return info }
            return await webOS
        }
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
                group.addTask { await probe(host) }
            }
            while let result = await group.next() {
                if let info = result { found.append(info) }
                if let host = iterator.next() {
                    group.addTask { await probe(host) }
                }
            }
        }
        return found.sorted { $0.ip.compare($1.ip, options: .numeric) == .orderedAscending }
    }
}
