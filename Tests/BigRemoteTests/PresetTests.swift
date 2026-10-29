// story: e05s01
import Foundation
import Testing

@Suite("Presets")
struct PresetTests {
    @Test func roundTrip() throws {
        let preset = Preset(name: "Teste", symbol: "star", steps: [
            PresetStep(type: .key, key: "KEY_HOME"),
            PresetStep(type: .key, key: "KEY_POWER", holdSeconds: 3),
            PresetStep(type: .delay, seconds: 0.5),
            PresetStep(type: .launchApp, target: .tv("tv-samsung-32"), appID: "111299001912", launchType: .deepLink),
            PresetStep(type: .artMode, target: .all, on: false),
            PresetStep(type: .power, power: .off),
            PresetStep(type: .text, text: "café"),
            PresetStep(type: .smartThings, capability: "audioVolume", command: "setVolume", arguments: [15, "x", true]),
        ])
        let data = try JSONEncoder().encode([preset])
        let decoded = try JSONDecoder().decode([Preset].self, from: data)
        #expect(decoded == [preset])
        #expect(decoded[0].steps[3].target == .tv("tv-samsung-32"))
        #expect(decoded[0].steps[7].arguments == [.int(15), .string("x"), .bool(true)])
    }

    @Test func examplesRoundTrip() throws {
        let data = try JSONEncoder().encode(Preset.examples)
        #expect(try JSONDecoder().decode([Preset].self, from: data) == Preset.examples)
        #expect(Preset.examples.contains { $0.name == "Cinema" })
        let off = try #require(Preset.examples.first { $0.name == "Desligar tudo" })
        #expect(off.steps.first?.target == .all)
        #expect(off.steps.first?.power == .off)
    }

    @Test func decodesHandWrittenJSON() throws {
        let json = #"""
        [{"name":"Noite","steps":[
          {"type":"power","target":"all","power":"art"},
          {"type":"delay","seconds":2},
          {"type":"key","key":"KEY_EXIT"},
          {"type":"smartThings","capability":"custom.picturemode","command":"setPictureMode","arguments":["Filme"]}
        ]}]
        """#
        let presets = try JSONDecoder().decode([Preset].self, from: Data(json.utf8))
        #expect(presets.count == 1)
        #expect(presets[0].symbol == "sparkles")
        #expect(presets[0].steps.count == 4)
        #expect(presets[0].steps[0].target == .all)
        #expect(presets[0].steps[2].target == .selected)
        #expect(presets[0].steps.allSatisfy { $0.validationProblem == nil })
    }

    @Test func validation() {
        #expect(PresetStep(type: .key, key: "KEY_FACTORY").validationProblem != nil)
        #expect(PresetStep(type: .delay, seconds: 500).validationProblem != nil)
        #expect(PresetStep(type: .smartThings).validationProblem != nil)
    }

    @Test func userTokens() {
        #expect(JSONValue.fromUserToken("15") == .int(15))
        #expect(JSONValue.fromUserToken(" \"7\" ") == .string("7"))
        #expect(JSONValue.fromUserToken("true") == .bool(true))
        #expect(JSONValue.fromUserToken("Filme") == .string("Filme"))
        #expect(JSONValue.string("7").userToken == "\"7\"")
    }
}
