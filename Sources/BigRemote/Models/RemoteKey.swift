import Foundation

/// Common KEY_ codes (docs/PROTOCOL.md 2.4). Support varies by model.
enum RemoteKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case power = "KEY_POWER"
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case enter = "KEY_ENTER"
    case back = "KEY_RETURN"
    case exit = "KEY_EXIT"
    case home = "KEY_HOME"
    case menu = "KEY_MENU"
    case tools = "KEY_TOOLS"
    case info = "KEY_INFO"
    case guide = "KEY_GUIDE"
    case source = "KEY_SOURCE"
    case hdmi = "KEY_HDMI"
    case channelUp = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case previousChannel = "KEY_PRECH"
    case channelList = "KEY_CH_LIST"
    case play = "KEY_PLAY"
    case pause = "KEY_PAUSE"
    case stop = "KEY_STOP"
    case fastForward = "KEY_FF"
    case rewind = "KEY_REWIND"
    case red = "KEY_RED"
    case green = "KEY_GREEN"
    case yellow = "KEY_YELLOW"
    case blue = "KEY_BLUE"
    case digit0 = "KEY_0"
    case digit1 = "KEY_1"
    case digit2 = "KEY_2"
    case digit3 = "KEY_3"
    case digit4 = "KEY_4"
    case digit5 = "KEY_5"
    case digit6 = "KEY_6"
    case digit7 = "KEY_7"
    case digit8 = "KEY_8"
    case digit9 = "KEY_9"
    case pictureMode = "KEY_PMODE"
    case caption = "KEY_CAPTION"
    case ambient = "KEY_AMBIENT"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .power: return "Liga/desliga"
        case .volumeUp: return "Volume +"
        case .volumeDown: return "Volume −"
        case .mute: return "Mudo"
        case .up: return "Cima"
        case .down: return "Baixo"
        case .left: return "Esquerda"
        case .right: return "Direita"
        case .enter: return "OK"
        case .back: return "Voltar"
        case .exit: return "Sair (fecha menus)"
        case .home: return "Início (Smart Hub)"
        case .menu: return "Menu (Configurações)"
        case .tools: return "Ferramentas"
        case .info: return "Info"
        case .guide: return "Guia"
        case .source: return "Fonte"
        case .hdmi: return "HDMI (alterna)"
        case .channelUp: return "Canal +"
        case .channelDown: return "Canal −"
        case .previousChannel: return "Canal anterior"
        case .channelList: return "Lista de canais"
        case .play: return "Play"
        case .pause: return "Pausa"
        case .stop: return "Parar"
        case .fastForward: return "Avançar"
        case .rewind: return "Retroceder"
        case .red: return "Vermelho"
        case .green: return "Verde"
        case .yellow: return "Amarelo"
        case .blue: return "Azul"
        case .digit0, .digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9:
            return "Número \(rawValue.dropFirst(4))"
        case .pictureMode: return "Modo de imagem (não verificado)"
        case .caption: return "Legendas (não verificado)"
        case .ambient: return "Ambient/Arte (não verificado)"
        }
    }

    /// Keys the app must never send (service menu can misconfigure the TV).
    static let blockedCodes: Set<String> = ["KEY_FACTORY"]

    /// Accepts any `KEY_[A-Z0-9_]+` code except blocked ones.
    static func isAllowed(_ code: String) -> Bool {
        let upper = code.uppercased()
        guard upper == code, code.hasPrefix("KEY_"), code.count > 4 else { return false }
        guard !blockedCodes.contains(code), !code.contains("FACTORY") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return code.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func label(for code: String) -> String {
        RemoteKey(rawValue: code)?.label ?? code
    }

    /// Pause after the key before the next key (docs 2.3).
    static func pacing(after code: String) -> Duration {
        switch code {
        case "KEY_HOME", "KEY_MENU", "KEY_SOURCE", "KEY_EXIT": return .milliseconds(500)
        default: return .milliseconds(150)
        }
    }
}
