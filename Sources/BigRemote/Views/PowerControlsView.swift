import SwiftUI

/// Three explicit actions on a Frame (TV / Arte / Desligar), not a toggle.
struct PowerControlsView: View {
    @Environment(AppModel.self) private var model
    var height: CGFloat = 28

    var body: some View {
        let tv = model.selectedTV
        let busy = tv.map { model.busyTVIDs.contains($0.id) } ?? false
        let power = model.selectedStatus.power
        HStack(spacing: 6) {
            Button { model.power(.tv) } label: { Label("TV", systemImage: "tv") }
                .help("Liga (Wake-on-LAN se preciso) e sai do Modo Arte")
            if tv?.isFrame ?? false {
                Button { model.power(.art) } label: { Label("Arte", systemImage: "photo.artframe") }
                    .help("Modo Arte")
            }
            Button { model.power(.off) } label: { Label("Desligar", systemImage: "power") }
                .help(tv?.isFrame == true ? "Desliga de verdade (segura Power por 3 s)" : "Desliga")
            if !power.isAwake {
                Button { model.power(.wake) } label: { Label("Acordar", systemImage: "wake") }
                    .help("Envia Wake-on-LAN")
            }
            if busy { ProgressView().controlSize(.small) }
        }
        .buttonStyle(PillButtonStyle(height: height))
        .labelStyle(.titleAndIcon)
        .disabled(tv == nil)
    }
}
