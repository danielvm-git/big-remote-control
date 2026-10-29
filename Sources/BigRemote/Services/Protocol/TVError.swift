import Foundation

enum TVError: LocalizedError, Sendable, Equatable {
    case invalidAddress
    case notConnected
    case timeout
    /// `ms.channel.unauthorized`: the user pressed Deny or the client is blocked.
    case unauthorized
    /// `ms.channel.timeOut`: token missing or stale; pair again.
    case channelTimeOut
    case blockedKey(String)
    case notFrame
    case artUnavailable
    case artError(String)
    case noMAC
    case wakeFailed
    case invalidMAC(String)
    case socket(String)
    case http(Int)
    case appNotInstalled(String)
    case smartThingsUnavailable
    case smartThings(String)
    case noTVSelected

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Endereço IP inválido."
        case .notConnected: return "Sem conexão com a TV."
        case .timeout: return "A TV não respondeu a tempo."
        case .unauthorized:
            return "A TV recusou a conexão. Libere o Big Remote em Configurações > Geral > "
                + "Gerenciador de dispositivos externos > Gerenciador de conexão do dispositivo > Lista de dispositivos."
        case .channelTimeOut: return "O pareamento expirou. Tente de novo e aceite na TV."
        case .blockedKey(let key): return "A tecla \(key) é bloqueada pelo app."
        case .notFrame: return "Esta TV não é uma The Frame."
        case .artUnavailable: return "O serviço do Modo Arte não está respondendo. Nova tentativa em instantes."
        case .artError(let code): return "O Modo Arte retornou erro \(code)."
        case .noMAC: return "Sem endereço MAC para Wake-on-LAN. Informe o MAC nas configurações."
        case .wakeFailed:
            return "A TV não acordou. Ative “Ligar com celular” nas configurações de rede da TV "
                + "(é só o nome da opção da Samsung; o Mac acorda a TV direto pela rede, sem celular)."
        case .invalidMAC(let mac): return "MAC inválido: \(mac)"
        case .socket(let message): return "Erro de rede: \(message)"
        case .http(let code): return "A TV respondeu HTTP \(code)."
        case .appNotInstalled(let id): return "App \(id) não está instalado."
        case .smartThingsUnavailable: return "SmartThings não configurado para esta TV."
        case .smartThings(let message): return "SmartThings: \(message)"
        case .noTVSelected: return "Nenhuma TV selecionada."
        }
    }
}
