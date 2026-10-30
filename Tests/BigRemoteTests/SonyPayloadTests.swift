// story: e09s01
import Foundation
import Testing

@Suite("Sony BRAVIA payloads")
struct SonyPayloadTests {
    @Test func callBodyIsJSONRPC() throws {
        let body = try SonyPayloads.call("getPowerStatus")
        let json = try #require(JSONValue.parse(String(decoding: body, as: UTF8.self)))
        #expect(json["method"] == "getPowerStatus")
        #expect(json["version"] == "1.0")
        #expect(json["id"] == 1)
        #expect(json["params"]?.arrayValue?.isEmpty == true)
    }

    @Test func registerSendsClientAndWOLFunction() throws {
        let json = try #require(JSONValue.parse(String(decoding: try SonyPayloads.register(), as: UTF8.self)))
        let params = try #require(json["params"]?.arrayValue)
        #expect(json["method"] == "actRegister")
        #expect(params[0]["clientid"] == .string(SonyPayloads.clientID))
        #expect(params[0]["level"] == "private")
        #expect(params[1].arrayValue?.first?["function"] == "WOL")
    }

    @Test func basicAuthUsesEmptyUserAndPIN() {
        #expect(SonyPayloads.basicAuth(pin: "1234") == "Basic OjEyMzQ=")
    }

    @Test func pinMustBeFourDigits() {
        #expect(SonyPayloads.normalizedPIN(" 1234 ") == "1234")
        #expect(SonyPayloads.normalizedPIN("12a4") == nil)
        #expect(SonyPayloads.normalizedPIN("123") == nil)
    }

    @Test func authCookieIgnoresNonRFCExpires() {
        let header = "auth=abc123def; Path=/sony/; Max-Age=1209600; Expires=Thu, 12 Nov 2026 10:00:00 GMT+00:00"
        #expect(SonyPayloads.authCookie(fromSetCookie: header) == "auth=abc123def")
        #expect(SonyPayloads.authCookie(fromSetCookie: "other=1") == nil)
        #expect(SonyPayloads.authCookie(fromSetCookie: nil) == nil)
    }

    @Test func resultAndErrorParsing() throws {
        let ok = Data(#"{"result":[{"status":"active"}],"id":1}"#.utf8)
        #expect(try SonyPayloads.result(ok).first?["status"] == "active")
        let failed = Data(#"{"error":[40005,"Display Is Turned off"],"id":1}"#.utf8)
        #expect(throws: TVError.sony(40005, "Display Is Turned off")) { try SonyPayloads.result(failed) }
    }

    @Test func irccEnvelopeCarriesCode() throws {
        let body = String(decoding: try SonyPayloads.irccEnvelope("AAAAAQAAAAEAAAASAw=="), as: UTF8.self)
        #expect(body.contains("<IRCCCode>AAAAAQAAAAEAAAASAw==</IRCCCode>"))
        #expect(body.contains("urn:schemas-sony-com:service:IRCC:1"))
        #expect(throws: TVError.blockedKey("<x>")) { try SonyPayloads.irccEnvelope("<x>") }
    }

    @Test func samsungKeysMapToSonyCommands() {
        #expect(SonyPayloads.commandName(for: "KEY_VOLUP") == "VolumeUp")
        #expect(SonyPayloads.commandName(for: "KEY_ENTER") == "Confirm")
        #expect(SonyPayloads.commandName(for: "KEY_RETURN") == "Return")
        #expect(SonyPayloads.commandName(for: "KEY_SOURCE") == "Input")
        #expect(SonyPayloads.commandName(for: "KEY_7") == "Num7")
        #expect(SonyPayloads.commandName(for: "KEY_AMBIENT") == nil)
        #expect(SonyPayloads.commandName(for: "KEY_FACTORY") == nil)
    }

    @Test func onlyChannelListAndAmbientHaveNoSonyCommand() {
        let missing = RemoteKey.allCases.filter { SonyPayloads.commandName(for: $0.rawValue) == nil }
        #expect(missing == [.channelList, .ambient])
    }

    @Test func commandListFromRemoteControllerInfo() throws {
        let list = #"[{"name":"Num1","value":"AAAAAQAAAAEAAAAAAw=="},{"name":"Mute","value":"AAAAAQAAAAEAAAAUAw=="}]"#
        let data = Data(#"{"result":[{"bundled":true},\#(list)],"id":1}"#.utf8)
        let commands = SonyPayloads.commands(from: try SonyPayloads.result(data))
        #expect(commands == ["Num1": "AAAAAQAAAAEAAAAAAw==", "Mute": "AAAAAQAAAAEAAAAUAw=="])
    }

    @Test func deviceInfoFromPowerAndInterface() {
        let interface: JSONValue = .object(["modelName": "KD-49X755F", "productName": "BRAVIA", "interfaceVersion": "5.4.0"])
        let on = SonyPayloads.deviceInfo(ip: "192.168.1.30", power: "active", interface: interface)
        #expect(on.isOn)
        #expect(on.brand == .sony)
        #expect(on.modelName == "KD-49X755F")
        #expect(on.name == "Sony KD-49X755F")
        #expect(on.apiVersion == "5.4.0")
        #expect(!on.isFrame)
        #expect(!SonyPayloads.deviceInfo(ip: "192.168.1.30", power: "standby", interface: nil).isOn)
    }

    @Test func appMatchingByTitle() {
        let apps = [
            TVAppEntry(title: "YouTube", id: "com.sony.dtv.com.google.android.youtube.tv"),
            TVAppEntry(title: "Max", id: "com.sony.dtv.com.wbd.stream"),
            TVAppEntry(title: "Prime Video", id: "com.sony.dtv.com.amazon.amazonvideo.livingroom"),
            TVAppEntry(title: "Netflix", id: "com.sony.dtv.com.netflix.ninja"),
        ]
        #expect(TVAppEntry.match("YouTube", in: apps)?.title == "YouTube")
        #expect(TVAppEntry.match("prime video", in: apps)?.title == "Prime Video")
        #expect(TVAppEntry.match("HBO Max", in: apps)?.title == "Max")
        #expect(TVAppEntry.match("Spotify", in: apps) == nil)
    }

    @Test func appsFromApplicationList() throws {
        let data = Data(#"{"result":[[{"title":"Netflix","uri":"com.sony.dtv.com.netflix.ninja","icon":""}]],"id":1}"#.utf8)
        #expect(SonyPayloads.apps(from: try SonyPayloads.result(data)) == [TVAppEntry(title: "Netflix", id: "com.sony.dtv.com.netflix.ninja")])
    }

    @Test func legacyTVDeviceDecodesWithoutBrand() throws {
        let json = Data(#"{"id":"duid-x","name":"Sala","ip":"192.168.1.20","isFrame":true}"#.utf8)
        let tv = try JSONDecoder().decode(TVDevice.self, from: json)
        #expect(tv.brand == nil)
        #expect(tv.vendor == .samsung)
    }
}
