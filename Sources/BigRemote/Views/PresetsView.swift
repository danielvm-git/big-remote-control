import SwiftUI

/// Grid of preset buttons.
struct PresetButtonsView: View {
    @Environment(AppModel.self) private var model
    var columns = 2

    var body: some View {
        if model.presets.isEmpty {
            Text("Nenhum preset. Crie um nas Configurações.").font(.caption).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(model.presets) { preset in
                    Button { model.runPreset(preset) } label: {
                        HStack(spacing: 6) {
                            if model.runningPresetID == preset.id {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: preset.symbol)
                            }
                            Text(preset.name).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(height: 26))
                    .disabled(model.runningPresetID != nil)
                    .help(preset.steps.map(\.summary).joined(separator: " → "))
                }
            }
        }
    }
}
