import Foundation

/// A named sequence of steps ("tweak"). Stored as JSON in Application Support.
struct Preset: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
    var steps: [PresetStep]

    init(id: UUID = UUID(), name: String, symbol: String = "sparkles", steps: [PresetStep]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey { case id, name, symbol, steps }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "sparkles"
        steps = try container.decodeIfPresent([PresetStep].self, forKey: .steps) ?? []
    }
}

/// Which TVs a step runs on.
enum PresetTarget: Codable, Hashable, Sendable {
    case selected
    case all
    case tv(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: raw)
    }

    init(rawValue raw: String) {
        switch raw {
        case "selected", "": self = .selected
        case "all": self = .all
        default: self = .tv(raw)
        }
    }

    var rawValue: String {
        switch self {
        case .selected: return "selected"
        case .all: return "all"
        case .tv(let id): return id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum PowerAction: String, Codable, CaseIterable, Sendable {
    /// Wake if needed, then TV mode (Art Mode off).
    case tv
    /// Wake if needed, then Art Mode.
    case art
    /// Real off: SmartThings `switch off`; a Frame without it goes to Art Mode
    /// (see specs/adr/0002-frame-power-off.md).
    case off
    /// Wake-on-LAN only.
    case wake

    var label: String {
        switch self {
        case .tv: return "Ligar em modo TV"
        case .art: return "Modo Arte"
        case .off: return "Desligar"
        case .wake: return "Acordar (Wake-on-LAN)"
        }
    }
}

struct PresetStep: Codable, Identifiable, Hashable, Sendable {
    enum StepType: String, Codable, CaseIterable, Sendable {
        case key
        case delay
        case launchApp
        case artMode
        case power
        case text
        case smartThings

        var label: String {
            switch self {
            case .key: return "Tecla"
            case .delay: return "Esperar"
            case .launchApp: return "Abrir app"
            case .artMode: return "Modo Arte"
            case .power: return "Energia"
            case .text: return "Texto"
            case .smartThings: return "SmartThings"
            }
        }

        var symbol: String {
            switch self {
            case .key: return "keyboard"
            case .delay: return "timer"
            case .launchApp: return "square.grid.2x2"
            case .artMode: return "photo.artframe"
            case .power: return "power"
            case .text: return "character.cursor.ibeam"
            case .smartThings: return "cloud"
            }
        }
    }

    var id: UUID
    var type: StepType
    var target: PresetTarget
    /// key: KEY_ code. Optional `holdSeconds` makes it Press/wait/Release.
    var key: String?
    var holdSeconds: Double?
    /// delay: seconds to wait.
    var seconds: Double?
    /// launchApp
    var appID: String?
    var launchType: TVApp.LaunchType?
    /// artMode: true = on, false = off.
    var on: Bool?
    /// power
    var power: PowerAction?
    /// text: whole string sent to the focused field.
    var text: String?
    /// smartThings
    var capability: String?
    var command: String?
    var arguments: [JSONValue]?

    init(
        id: UUID = UUID(),
        type: StepType,
        target: PresetTarget = .selected,
        key: String? = nil,
        holdSeconds: Double? = nil,
        seconds: Double? = nil,
        appID: String? = nil,
        launchType: TVApp.LaunchType? = nil,
        on: Bool? = nil,
        power: PowerAction? = nil,
        text: String? = nil,
        capability: String? = nil,
        command: String? = nil,
        arguments: [JSONValue]? = nil
    ) {
        self.id = id
        self.type = type
        self.target = target
        self.key = key
        self.holdSeconds = holdSeconds
        self.seconds = seconds
        self.appID = appID
        self.launchType = launchType
        self.on = on
        self.power = power
        self.text = text
        self.capability = capability
        self.command = command
        self.arguments = arguments
    }

    enum CodingKeys: String, CodingKey {
        case id, type, target, key, holdSeconds, seconds, appID, launchType, on, power, text, capability, command, arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(StepType.self, forKey: .type)
        target = try container.decodeIfPresent(PresetTarget.self, forKey: .target) ?? .selected
        key = try container.decodeIfPresent(String.self, forKey: .key)
        holdSeconds = try container.decodeIfPresent(Double.self, forKey: .holdSeconds)
        seconds = try container.decodeIfPresent(Double.self, forKey: .seconds)
        appID = try container.decodeIfPresent(String.self, forKey: .appID)
        launchType = try container.decodeIfPresent(TVApp.LaunchType.self, forKey: .launchType)
        on = try container.decodeIfPresent(Bool.self, forKey: .on)
        power = try container.decodeIfPresent(PowerAction.self, forKey: .power)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        capability = try container.decodeIfPresent(String.self, forKey: .capability)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        arguments = try container.decodeIfPresent([JSONValue].self, forKey: .arguments)
    }

    /// Short human text for lists and error messages.
    var summary: String {
        switch type {
        case .key:
            let name = RemoteKey.label(for: key ?? "?")
            if let hold = holdSeconds, hold > 0 { return "Segurar \(name) por \(hold.formatted()) s" }
            return "Tecla \(name)"
        case .delay: return "Esperar \((seconds ?? 1).formatted()) s"
        case .launchApp: return "Abrir \(TVApp.find(appID ?? "")?.name ?? appID ?? "?")"
        case .artMode: return (on ?? true) ? "Modo Arte ligado" : "Modo Arte desligado"
        case .power: return (power ?? .tv).label
        case .text: return "Texto “\(text ?? "")”"
        case .smartThings:
            let args = (arguments ?? []).map(\.userToken).joined(separator: ", ")
            return "SmartThings \(capability ?? "?").\(command ?? "?")(\(args))"
        }
    }

    /// Returns a problem description, or nil when the step can run.
    var validationProblem: String? {
        switch type {
        case .key:
            guard let key, RemoteKey.isAllowed(key) else { return "Tecla inválida ou bloqueada" }
        case .delay:
            guard let wait = seconds, wait >= 0, wait <= 120 else { return "Espera deve ficar entre 0 e 120 wait" }
        case .launchApp:
            guard let appID, !appID.isEmpty else { return "Falta o ID do app" }
        case .smartThings:
            guard let capability, !capability.isEmpty, let command, !command.isEmpty else { return "Falta capability ou comando" }
        case .text:
            guard let text, !text.isEmpty else { return "Texto vazio" }
        case .artMode, .power:
            break
        }
        return nil
    }
}

extension Preset {
    static let examples: [Preset] = [
        Preset(
            name: "Cinema",
            symbol: "popcorn",
            steps: [
                PresetStep(type: .power, power: .tv),
                PresetStep(type: .delay, seconds: 1.5),
                PresetStep(type: .smartThings, capability: "custom.picturemode", command: "setPictureMode", arguments: ["Filme"]),
                PresetStep(type: .launchApp, appID: "3201907018807"),
            ]
        ),
        Preset(
            name: "Desligar tudo",
            symbol: "power",
            steps: [
                PresetStep(type: .power, target: .all, power: .off),
            ]
        ),
        Preset(
            name: "Arte em todas",
            symbol: "photo.artframe",
            steps: [
                PresetStep(type: .artMode, target: .all, on: true),
            ]
        ),
        Preset(
            name: "Fechar menus",
            symbol: "xmark.circle",
            steps: [
                PresetStep(type: .key, key: "KEY_EXIT"),
            ]
        ),
        Preset(
            name: "Abrir configurações",
            symbol: "gearshape",
            steps: [
                PresetStep(type: .key, key: "KEY_MENU"),
            ]
        ),
    ]
}
