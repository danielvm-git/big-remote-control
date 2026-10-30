// story: e09s02
import SwiftUI

/// Sony pairing: the TV shows a 4-digit PIN, the user types it here once.
struct SonyPairingSection: View {
    @Environment(AppModel.self) private var model
    let tv: TVDevice
    @State private var pin = ""

    var body: some View {
        Section("Pareamento (Sony)") {
            Text(model.hasToken(tv)
                ? "PIN salvo. O Mac renova o acesso sozinho."
                : "Toque em “Pedir PIN”: a TV mostra 4 dígitos. Digite aqui e confirme.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Pedir PIN") { model.requestSonyPIN(tv) }
                TextField("PIN", text: $pin)
                    .frame(width: 70)
                    .onSubmit(confirm)
                Button("Confirmar", action: confirm)
                    .disabled(SonyPayloads.normalizedPIN(pin) == nil)
            }
            Button("Esquecer pareamento") { model.forgetPairing(tv) }
                .disabled(!model.hasToken(tv))
        }
    }

    private func confirm() {
        guard SonyPayloads.normalizedPIN(pin) != nil else { return }
        model.confirmSonyPIN(pin, for: tv)
        pin = ""
    }
}
