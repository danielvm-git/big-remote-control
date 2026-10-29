// story: e01s01 e01s02 e01s03 e02s01
import Foundation
import Testing

@Suite("Remote channel payloads")
struct RemotePayloadTests {
    @Test func keyClickPayloadMatchesSpec() throws {
        let json = try RemotePayloads.key("KEY_VOLUP")
        #expect(json == #"{"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"KEY_VOLUP","Option":"false","TypeOfRemote":"SendRemoteKey"}}"#)
    }

    @Test func keyPressAndRelease() throws {
        let press = try #require(JSONValue.parse(try RemotePayloads.key("KEY_POWER", command: .press)))
        let release = try #require(JSONValue.parse(try RemotePayloads.key("KEY_POWER", command: .release)))
        #expect(press["params"]?["Cmd"] == "Press")
        #expect(release["params"]?["Cmd"] == "Release")
        #expect(press["params"]?["Option"] == "false")
    }

    @Test func factoryKeyIsBlocked() {
        #expect(throws: TVError.blockedKey("KEY_FACTORY")) { try RemotePayloads.key("KEY_FACTORY") }
        #expect(!RemoteKey.isAllowed("KEY_FACTORY"))
        #expect(!RemoteKey.isAllowed("key_home"))
        #expect(!RemoteKey.isAllowed("KEY_HOME\"}"))
        #expect(RemoteKey.isAllowed("KEY_HDMI1"))
        #expect(!RemoteKey.allCases.map(\.rawValue).contains("KEY_FACTORY"))
    }

    @Test func channelURLEncodesNameAndToken() throws {
        let url = try #require(RemotePayloads.channelURL(ip: "192.168.1.20", channel: .remote, token: "12345678"))
        #expect(url.absoluteString == "wss://192.168.1.20:8002/api/v2/channels/samsung.remote.control?name=QmlnIFJlbW90ZQ%3D%3D&token=12345678")
        let art = try #require(RemotePayloads.channelURL(ip: "192.168.1.21", channel: .art, token: nil))
        #expect(art.absoluteString == "wss://192.168.1.21:8002/api/v2/channels/com.samsung.art-app?name=QmlnIFJlbW90ZQ%3D%3D")
        #expect(RemotePayloads.channelURL(ip: "not-an-ip", channel: .remote, token: nil) == nil)
    }

    @Test func percentEncodesPlusAndSlash() {
        #expect(RemotePayloads.percentEncode("a+b/c=") == "a%2Bb%2Fc%3D")
    }

    @Test func launchAppPayload() throws {
        let root = try #require(JSONValue.parse(try RemotePayloads.launchApp("3201907018807", type: .deepLink)))
        #expect(root["method"] == "ms.channel.emit")
        #expect(root["params"]?["event"] == "ed.apps.launch")
        #expect(root["params"]?["to"] == "host")
        #expect(root["params"]?["data"]?["appId"] == "3201907018807")
        #expect(root["params"]?["data"]?["action_type"] == "DEEP_LINK")
        #expect(root["params"]?["data"]?["metaTag"] == "")
    }

    @Test func textInputPayloads() throws {
        let broadcast = try RemotePayloads.textReceivedBroadcast()
        #expect(broadcast == #"{"method":"ms.channel.emit","params":{"event":"custom.remote.textReceived","to":"broadcast"}}"#)

        let input = try #require(JSONValue.parse(try RemotePayloads.inputString("ação")))
        #expect(input["params"]?["TypeOfRemote"] == "SendInputString")
        #expect(input["params"]?["DataOfCmd"] == "base64")
        let b64 = try #require(input["params"]?["Cmd"]?.stringValue)
        #expect(String(data: try #require(Data(base64Encoded: b64)), encoding: .utf8) == "ação")
        #expect(input["params"]?["Option"] == nil)

        #expect(try RemotePayloads.inputEnd() == #"{"method":"ms.remote.control","params":{"TypeOfRemote":"SendInputEnd"}}"#)
    }
}

@Suite("Channel events")
struct ChannelEventTests {
    @Test func tokenAsString() throws {
        let event = try #require(ChannelEvent.parse(#"{"event":"ms.channel.connect","data":{"id":"x","clients":[],"token":"12345678"}}"#))
        #expect(event.name == "ms.channel.connect")
        #expect(event.token == "12345678")
    }

    @Test func tokenAsNumber() throws {
        let event = try #require(ChannelEvent.parse(#"{"data":{"token":123456789},"event":"ms.channel.connect","from":"host"}"#))
        #expect(event.token == "123456789")
    }

    @Test func noTokenAndUnauthorized() throws {
        let ready = try #require(ChannelEvent.parse(#"{"data":{},"event":"ms.channel.ready"}"#))
        #expect(ready.token == nil)
        let denied = try #require(ChannelEvent.parse(#"{"event":"ms.channel.unauthorized"}"#))
        #expect(denied.name == "ms.channel.unauthorized")
        #expect(ChannelEvent.parse("not json") == nil)
        #expect(ChannelEvent.ignored.contains("ed.edenTV.update"))
    }
}
