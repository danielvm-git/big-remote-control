// story: e10s01
import Foundation
import Testing

@Suite("LG webOS payloads")
struct WebOSPayloadTests {
    @Test func mainSocketIsWSSOn3001() throws {
        let url = try #require(WebOSPayloads.mainURL(ip: "192.168.1.22"))
        #expect(url.absoluteString == "wss://192.168.1.22:3001/")
        #expect(WebOSPayloads.mainURL(ip: "nope") == nil)
    }

    @Test func registerWithoutKeyPromptsAndWithKeyReuses() throws {
        let fresh = try #require(JSONValue.parse(try WebOSPayloads.register(clientKey: nil)))
        #expect(fresh["type"] == "register")
        #expect(fresh["payload"]?["pairingType"] == "PROMPT")
        #expect(fresh["payload"]?["client-key"] == nil)
        let permissions = fresh["payload"]?["manifest"]?["permissions"]?.arrayValue ?? []
        #expect(permissions.contains("CONTROL_POWER"))
        #expect(permissions.contains("CONTROL_INPUT_TEXT"))
        let known = try #require(JSONValue.parse(try WebOSPayloads.register(clientKey: "abc")))
        #expect(known["payload"]?["client-key"] == "abc")
    }

    @Test func requestEnvelope() throws {
        let json = try #require(JSONValue.parse(try WebOSPayloads.request(id: "7", uri: "system.launcher/launch", payload: ["id": "netflix"])))
        #expect(json["id"] == "7")
        #expect(json["type"] == "request")
        #expect(json["uri"] == "ssap://system.launcher/launch")
        #expect(json["payload"]?["id"] == "netflix")
    }

    @Test func buttonMessageIsLineProtocol() {
        #expect(WebOSPayloads.button("VOLUMEUP") == "type:button\nname:VOLUMEUP\n\n")
    }

    @Test func samsungKeysMapToWebOSButtons() {
        #expect(WebOSPayloads.buttonName(for: "KEY_VOLUP") == "VOLUMEUP")
        #expect(WebOSPayloads.buttonName(for: "KEY_RETURN") == "BACK")
        #expect(WebOSPayloads.buttonName(for: "KEY_FF") == "FASTFORWARD")
        #expect(WebOSPayloads.buttonName(for: "KEY_3") == "3")
        #expect(WebOSPayloads.buttonName(for: "KEY_FACTORY") == nil)
        let missing = RemoteKey.allCases.filter { WebOSPayloads.buttonName(for: $0.rawValue) == nil }
        #expect(missing == [.previousChannel, .pictureMode, .ambient])
    }

    @Test func parsesPromptRegisteredAndError() throws {
        let prompt = try WebOSPayloads.parse(#"{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT","returnValue":true}}"#)
        #expect(prompt.type == "response")
        #expect(prompt.id == "register_0")
        let registered = try WebOSPayloads.parse(#"{"type":"registered","id":"register_0","payload":{"client-key":"k1"}}"#)
        #expect(registered.payload["client-key"] == "k1")
        let error = try WebOSPayloads.parse(#"{"type":"error","id":"3","error":"403 cancelled","payload":{}}"#)
        #expect(error.error == "403 cancelled")
    }

    @Test func numericIDsBecomeStrings() throws {
        #expect(try WebOSPayloads.parse(#"{"type":"response","id":12,"payload":{}}"#).id == "12")
    }

    @Test func appsFromLaunchPoints() throws {
        let points = #"[{"title":"Netflix","id":"netflix"},{"title":"YouTube","id":"youtube.leanback.v4"}]"#
        let message = try WebOSPayloads.parse(#"{"type":"response","id":"1","payload":{"returnValue":true,"launchPoints":\#(points)}}"#)
        #expect(WebOSPayloads.apps(from: message.payload) == [
            TVAppEntry(title: "Netflix", id: "netflix"),
            TVAppEntry(title: "YouTube", id: "youtube.leanback.v4"),
        ])
    }

    @Test func helloWorldMeansOn() {
        let info = WebOSPayloads.deviceInfo(ip: "192.168.1.22", body: "Hello world")
        #expect(info?.isOn == true)
        #expect(info?.brand == .lg)
        #expect(info?.name == "LG 192.168.1.22")
        #expect(WebOSPayloads.deviceInfo(ip: "192.168.1.22", body: "<html>router</html>") == nil)
    }
}
