// story: e06s01
import Foundation
import Testing

@Suite("SmartThings")
struct SmartThingsTests {
    @Test func commandBody() throws {
        let body = SmartThingsPayloads.commandBody(capability: "custom.picturemode", command: "setPictureMode", arguments: ["Filme"])
        #expect(body == #"{"commands":[{"arguments":["Filme"],"capability":"custom.picturemode","command":"setPictureMode","component":"main"}]}"#)
        let volume = try #require(JSONValue.parse(SmartThingsPayloads.commandBody(capability: "audioVolume", command: "setVolume", arguments: [15])))
        #expect(volume["commands"]?.arrayValue?.first?["arguments"]?.arrayValue == [.int(15)])
    }

    @Test func parsesStatus() throws {
        let json = #"""
        {"components":{"main":{
          "switch":{"switch":{"value":"on"}},
          "audioVolume":{"volume":{"value":12}},
          "audioMute":{"mute":{"value":"unmuted"}},
          "custom.picturemode":{"pictureMode":{"value":"Padrão"},
            "supportedPictureModesMap":{"value":[{"id":"modeStandard","name":"Padrão"},{"id":"modeMovie","name":"Filme"}]}},
          "custom.soundmode":{"soundMode":{"value":"Standard"},"supportedSoundModes":{"value":["Standard","Amplify"]}},
          "samsungvd.mediaInputSource":{"inputSource":{"value":"HDMI1"},
            "supportedInputSourcesMap":{"value":[{"id":"dtv","name":"TV"},{"id":"HDMI1","name":"PlayStation 5"}]}},
          "custom.disabledCapabilities":{"disabledCapabilities":{"value":["custom.soundmode"]}}
        }}}
        """#
        let status = STDeviceStatus(raw: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        #expect(status.switchOn == true)
        #expect(status.volume == 12)
        #expect(status.muted == false)
        #expect(status.pictureModes.map(\.name) == ["Padrão", "Filme"])
        #expect(status.pictureMode == "Padrão")
        #expect(status.soundModes.isEmpty) // disabled
        #expect(status.inputSourceCapability == "samsungvd.mediaInputSource")
        #expect(status.inputSources.map(\.id) == ["dtv", "HDMI1"])
        #expect(status.inputSource == "HDMI1")
    }
}

@Suite("JSONValue")
struct JSONValueTests {
    @Test func keepsIntsBoolsAndStringsApart() throws {
        let value = try #require(JSONValue.parse(#"[1, true, "x", 1.5, null, {"a": false}]"#))
        #expect(value == .array([.int(1), .bool(true), .string("x"), .double(1.5), .null, .object(["a": .bool(false)])]))
        #expect(value.jsonString() == #"[1,true,"x",1.5,null,{"a":false}]"#)
    }
}
