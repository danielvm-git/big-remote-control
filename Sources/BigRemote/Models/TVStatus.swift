import Foundation

/// What the REST poll says about the TV.
enum Reachability: Sendable, Equatable {
    case unknown
    case unreachable
    case standby
    case on
}

/// Combined power state shown in the UI.
enum PowerState: Sendable, Equatable {
    case unknown
    case off
    case standby
    case on
    case tv
    case art

    var label: String {
        switch self {
        case .unknown: return "Verificando…"
        case .off: return "Desligada / sem resposta"
        case .standby: return "Em espera"
        case .on: return "Ligada"
        case .tv: return "Ligada (TV)"
        case .art: return "Modo Arte"
        }
    }

    var symbol: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .off: return "power.circle"
        case .standby: return "moon.zzz"
        case .on, .tv: return "tv"
        case .art: return "photo.artframe"
        }
    }

    var isAwake: Bool { self == .on || self == .tv || self == .art }
}

/// WebSocket link / pairing state.
enum LinkState: Sendable, Equatable {
    case idle
    case connecting
    case awaitingApproval
    case connected
    case denied
    case needsPairing
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Não conectado"
        case .connecting: return "Conectando…"
        case .awaitingApproval: return "Aceite na TV"
        case .connected: return "Conectado"
        case .denied: return "Recusado na TV"
        case .needsPairing: return "Pareie de novo"
        case .failed(let message): return "Erro: \(message)"
        }
    }
}

struct TVStatus: Sendable, Equatable {
    var reachability: Reachability = .unknown
    /// From the art channel: true = Art Mode, false = TV, nil = unknown.
    var artMode: Bool?
    var link: LinkState = .idle
    var imeActive = false
    var info: DeviceInfo?
    var lastSeen: Date?
    var artAPIVersion: String?

    var power: PowerState {
        switch reachability {
        case .unknown: return .unknown
        case .unreachable: return .off
        case .standby: return .standby
        case .on:
            switch artMode {
            case .some(true): return .art
            case .some(false): return .tv
            case .none: return .on
            }
        }
    }
}
