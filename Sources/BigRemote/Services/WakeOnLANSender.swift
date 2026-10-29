import Darwin
import Foundation

/// Sends the magic packet from a BSD UDP socket with SO_BROADCAST.
enum WakeOnLANSender {
    static func send(mac: String, ip: String?) async throws {
        let packet = try WakeOnLANPacket.magicPacket(macString: mac)
        let destinations = WakeOnLANPacket.destinations(for: ip)
        var lastError: TVError?
        var anySent = false
        for round in 0..<WakeOnLANPacket.rounds {
            if round > 0 { try await Task.sleep(for: WakeOnLANPacket.roundInterval) }
            for destination in destinations {
                for port in WakeOnLANPacket.ports {
                    do {
                        try sendOnce(packet, to: destination, port: port)
                        anySent = true
                    } catch let error as TVError {
                        lastError = error
                    }
                }
            }
        }
        if !anySent, let lastError { throw lastError }
    }

    private static func sendOnce(_ packet: [UInt8], to host: String, port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw TVError.socket(String(cString: strerror(errno))) }
        defer { close(fd) }
        var yes: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw TVError.socket(String(cString: strerror(errno)))
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { throw TVError.invalidAddress }
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, bytes.baseAddress, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw TVError.socket(String(cString: strerror(errno))) }
    }
}
