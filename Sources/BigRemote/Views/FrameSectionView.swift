import SwiftUI

/// Art Mode toggle with status (and a few art settings in the big window).
struct FrameSectionView: View {
    @Environment(AppModel.self) private var model
    var showSettings = false
    @State private var brightness: Double = 5

    var body: some View {
        let status = model.selectedStatus
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { status.artMode == true },
                    set: { model.setArtMode($0) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Modo Arte")
                        Text(artText(status)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(model.selectedTV == nil)
                Spacer()
                Button { model.refreshArtMode() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Consultar o estado do Modo Arte")
                    .disabled(!status.power.isAwake)
            }

            if showSettings {
                HStack {
                    Text("Brilho na arte")
                    Slider(value: $brightness, in: 1...10, step: 1) { editing in
                        if !editing { model.setArtBrightness(Int(brightness)) }
                    }
                    Text("\(Int(brightness))").monospacedDigit().frame(width: 22)
                }
                .font(.caption)
                HStack {
                    Text("Desligar sem movimento após").font(.caption)
                    Menu("Escolher") {
                        ForEach(["off", "5", "15", "30", "60", "120", "240"], id: \.self) { value in
                            Button(value == "off" ? "Nunca" : "\(value) min") { model.setMotionTimer(value) }
                        }
                    }
                    .fixedSize()
                }
                if let version = status.artAPIVersion {
                    Text("API do Modo Arte \(version)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func artText(_ status: TVStatus) -> String {
        switch status.power {
        case .art: return "Mostrando arte"
        case .tv: return "TV em uso"
        case .on: return "Estado desconhecido"
        case .standby, .off: return "TV desligada; ligar acorda via Wake-on-LAN"
        case .unknown: return "Verificando…"
        }
    }
}
