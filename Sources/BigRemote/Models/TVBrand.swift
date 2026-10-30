// story: e09s03 e10s01
import Foundation

/// Which LAN protocol drives a TV.
enum TVBrand: String, Codable, Sendable, CaseIterable {
    /// Tizen: REST on 8001 and WebSockets on 8002 (docs/PROTOCOL.md 1-4).
    case samsung
    /// BRAVIA: JSON-RPC and IRCC on port 80 (docs/PROTOCOL.md 11).
    case sony
    /// webOS: SSAP over wss on 3001 (docs/PROTOCOL.md 12).
    case lg

    var label: String {
        switch self {
        case .samsung: return "Samsung"
        case .sony: return "Sony"
        case .lg: return "LG"
        }
    }
}
