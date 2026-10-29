// story: e03s01 e03s02
import Foundation
import Testing

@Suite("Art channel payloads")
struct ArtPayloadTests {
    @Test func requestIsDoubleEncoded() throws {
        let json = try ArtPayloads.request("set_artmode_status", params: ["value": "on"], id: "abc-123")
        let root = try #require(JSONValue.parse(json))
        #expect(root["method"] == "ms.channel.emit")
        #expect(root["params"]?["event"] == "art_app_request")
        #expect(root["params"]?["to"] == "host")
        let dataText = try #require(root["params"]?["data"]?.stringValue)
        let inner = try #require(JSONValue.parse(dataText))
        #expect(inner["request"] == "set_artmode_status")
        #expect(inner["value"] == "on")
        #expect(inner["id"] == "abc-123")
        #expect(inner["request_id"] == "abc-123")
        #expect(dataText == #"{"id":"abc-123","request":"set_artmode_status","request_id":"abc-123","value":"on"}"#)
    }

    @Test func parsesStatusReply() throws {
        // Verbatim wire frame; wrapping would change the payload under test.
        // swiftlint:disable:next line_length
        let frame = #"{"event":"d2d_service_message","from":"c","data":"{\"id\":\"u1\",\"request_id\":\"u1\",\"event\":\"artmode_status\",\"value\":\"on\",\"target_client_id\":\"t\"}"}"#
        let event = try #require(ChannelEvent.parse(frame))
        let message = try #require(ArtPayloads.innerMessage(event))
        #expect(ArtPayloads.requestID(of: message) == "u1")
        #expect(ArtPayloads.artModeValue(of: message) == true)
    }

    @Test func parsesPushAndError() throws {
        let push = try #require(ChannelEvent.parse(#"{"event":"d2d_service_message","data":"{\"event\":\"art_mode_changed\",\"status\":\"off\"}"}"#))
        let pushMessage = try #require(ArtPayloads.innerMessage(push))
        #expect(ArtPayloads.artModeValue(of: pushMessage) == false)
        #expect(ArtPayloads.requestID(of: pushMessage) == nil)

        let error = try #require(ChannelEvent.parse(#"{"event":"d2d_service_message","data":"{\"event\":\"error\",\"error_code\":\"-1\",\"id\":\"e1\"}"}"#))
        let errorMessage = try #require(ArtPayloads.innerMessage(error))
        #expect(errorMessage["event"] == "error")
        #expect(errorMessage["error_code"] == "-1")
        #expect(ArtPayloads.requestID(of: errorMessage) == "e1")
    }

    @Test func decodesNestedContentList() throws {
        // Verbatim wire frame; wrapping would change the payload under test.
        // swiftlint:disable:next line_length
        let frame = #"{"event":"d2d_service_message","data":"{\"id\":\"x\",\"event\":\"content_list\",\"content_list\":\"[{\\\"content_id\\\":\\\"MY_F0011\\\",\\\"width\\\":3840}]\\n\"}"}"#
        let event = try #require(ChannelEvent.parse(frame))
        let message = try #require(ArtPayloads.innerMessage(event))
        let list = try #require(ArtPayloads.nested(message, "content_list")?.arrayValue)
        #expect(list.count == 1)
        #expect(list[0]["content_id"] == "MY_F0011")
        #expect(list[0]["width"] == 3840)
    }
}
