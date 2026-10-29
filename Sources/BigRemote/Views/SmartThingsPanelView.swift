import SwiftUI

/// Picture mode / sound mode / input pickers. Hidden without a token.
struct SmartThingsPanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let tv = model.selectedTV {
            if !model.smartThingsConfigured {
                Text("Opcional: adicione um token SmartThings nas Configurações para modo de imagem, som e entrada.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if tv.smartThingsDeviceID == nil {
                Text("Associe esta TV a um aparelho SmartThings nas Configurações.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                content(tv)
            }
        }
    }

    @ViewBuilder
    private func content(_ tv: TVDevice) -> some View {
        let status = model.stStatus[tv.id]
        VStack(alignment: .leading, spacing: 6) {
            if let status {
                picker("Imagem", options: status.pictureModes, current: status.pictureMode, useName: true) {
                    model.sendSmartThings("custom.picturemode", "setPictureMode", [.string($0)])
                }
                picker("Som", options: status.soundModes, current: status.soundMode, useName: true) {
                    model.sendSmartThings("custom.soundmode", "setSoundMode", [.string($0)])
                }
                if let cap = status.inputSourceCapability {
                    picker("Entrada", options: status.inputSources, current: status.inputSource, useName: false) {
                        model.sendSmartThings(cap, "setInputSource", [.string($0)])
                    }
                }
                if let volume = status.volume {
                    Text("Volume \(volume)\(status.muted == true ? " (mudo)" : "")").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Carregando estado…").font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.stError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            Button("Atualizar") { model.refreshSmartThingsStatus(for: tv) }
                .controlSize(.small)
        }
        .task(id: tv.id) { model.refreshSmartThingsStatus(for: tv) }
    }

    @ViewBuilder
    private func picker(_ title: String, options: [STOption], current: String?, useName: Bool, send: @escaping (String) -> Void) -> some View {
        if !options.isEmpty {
            HStack {
                Text(title).font(.caption).frame(width: 52, alignment: .leading)
                Menu(currentLabel(options, current, useName)) {
                    ForEach(options) { option in
                        Button(option.name) { send(useName ? option.name : option.id) }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func currentLabel(_ options: [STOption], _ current: String?, _ useName: Bool) -> String {
        guard let current else { return "—" }
        return options.first { $0.id == current || $0.name == current }?.name ?? current
    }
}
