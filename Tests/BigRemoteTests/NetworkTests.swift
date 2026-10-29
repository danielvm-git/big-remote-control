// story: e04s01 e07s01
import Foundation
import Testing

@Suite("Wake-on-LAN")
struct WakeOnLANTests {
    @Test func magicPacketBytes() throws {
        let packet = try WakeOnLANPacket.magicPacket(macString: "02:00:00:00:00:21")
        #expect(packet.count == 102)
        #expect(Array(packet[0..<6]) == [UInt8](repeating: 0xFF, count: 6))
        let mac: [UInt8] = [0x02, 0x00, 0x00, 0x00, 0x00, 0x21]
        for index in 0..<16 {
            let start = 6 + index * 6
            #expect(Array(packet[start..<(start + 6)]) == mac)
        }
    }

    @Test func parsesMACFormats() {
        // Documentation MAC (locally administered); the real TV MACs are not committed.
        let expected: [UInt8] = [0x02, 0xAB, 0xCD, 0xEF, 0x00, 0x20]
        #expect(WakeOnLANPacket.parseMAC("02:AB:CD:EF:00:20") == expected)
        #expect(WakeOnLANPacket.parseMAC("02-ab-cd-ef-00-20") == expected)
        #expect(WakeOnLANPacket.parseMAC("02ABCDEF0020") == expected)
        #expect(WakeOnLANPacket.parseMAC("02:AB:CD:EF:00") == nil)
        #expect(WakeOnLANPacket.parseMAC("ZZ:AB:CD:EF:00:20") == nil)
        #expect(throws: TVError.self) { try WakeOnLANPacket.magicPacket(macString: "bad") }
    }

    @Test func destinations() {
        #expect(WakeOnLANPacket.destinations(for: "192.168.1.21") == ["255.255.255.255", "192.168.1.255", "192.168.1.21"])
        #expect(WakeOnLANPacket.destinations(for: nil) == ["255.255.255.255"])
        #expect(WakeOnLANPacket.ports == [9, 7])
    }
}

@Suite("Network addresses")
struct NetworkAddressTests {
    @Test func privateRanges() {
        #expect(NetworkAddress.isPrivateIPv4("192.168.1.20"))
        #expect(NetworkAddress.isPrivateIPv4("10.1.2.3"))
        #expect(NetworkAddress.isPrivateIPv4("172.20.0.1"))
        #expect(!NetworkAddress.isPrivateIPv4("172.32.0.1"))
        #expect(!NetworkAddress.isPrivateIPv4("8.8.8.8"))
        #expect(!NetworkAddress.isPrivateIPv4("api.smartthings.com"))
        #expect(!NetworkAddress.isPrivateIPv4("192.168.1.256"))
    }

    @Test func subnetHosts() {
        let hosts = NetworkAddress.hosts24(around: "192.168.1.10")
        #expect(hosts.count == 254)
        #expect(hosts.first == "192.168.1.1")
        #expect(hosts.last == "192.168.1.254")
    }
}

@Suite("Device info")
struct DeviceInfoTests {
    @Test func decodesStringFlagsAndNestedIsSupport() throws {
        let json = #"""
        {"device":{"FrameTVSupport":"true","ImeSyncedSupport":"true","Language":"pt_BR","OS":"Tizen","PowerState":"on",
        "TokenAuthSupport":"true","duid":"uuid:00000000-0000-0000-0000-000000000020",
        "id":"uuid:00000000-0000-0000-0000-000000000020","ip":"192.168.1.20","model":"23_KSUE_FTV_T09",
        "modelName":"QN32LS03CBGXZD","name":"tv-samsung-32","networkType":"wireless","resolution":"1920x1080",
        "wifiMac":"02:00:00:00:00:20","type":"Samsung SmartTV"},
        "isSupport":"{\"FrameTVSupport\":\"true\",\"remote_available\":\"true\"}\n",
        "name":"tv-samsung-32","remote":"1.0","uri":"http://192.168.1.20:8001/api/v2/","version":"2.0.25"}
        """#
        let info = try DeviceInfo.decode(Data(json.utf8), fallbackIP: "0.0.0.0")
        #expect(info.ip == "192.168.1.20")
        #expect(info.isFrame)
        #expect(info.tokenAuthSupport)
        #expect(info.isOn)
        #expect(!info.isWired)
        #expect(info.support["remote_available"] == "true")
        #expect(info.apiVersion == "2.0.25")
        #expect(info.isSamsungTV)

        let tv = TVDevice.from(info: info)
        #expect(tv.mac == "02:00:00:00:00:20")
        #expect(tv.isFrame)
    }

    @Test func standbyAndWiredMAC() throws {
        let json = #"{"device":{"PowerState":"standby","networkType":"wired","wifiMac":"AA:BB:CC:DD:EE:FF","type":"Samsung SmartTV"}}"#
        let info = try DeviceInfo.decode(Data(json.utf8), fallbackIP: "192.168.1.21")
        #expect(!info.isOn)
        #expect(info.ip == "192.168.1.21")
        // Wi-Fi MAC is wrong for a wired TV: do not use it for WoL.
        #expect(TVDevice.from(info: info).mac == nil)
    }

    @Test func powerStateMapping() {
        var status = TVStatus()
        #expect(status.power == .unknown)
        status.reachability = .unreachable
        #expect(status.power == .off)
        status.reachability = .on
        #expect(status.power == .on)
        status.artMode = true
        #expect(status.power == .art)
        status.artMode = false
        #expect(status.power == .tv)
    }
}
