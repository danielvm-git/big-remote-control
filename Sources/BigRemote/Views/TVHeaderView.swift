import SwiftUI

/// TV picker + power/link status.
struct TVHeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            header
            if model.localNetworkBlocked {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sem acesso à rede local. Permita Rede Local em Ajustes do Sistema > Privacidade e Segurança > Rede Local.")
                        .font(.caption)
                    Button("Abrir Ajustes de Rede Local") { model.openLocalNetworkSettings() }
                        .controlSize(.small)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Picker("TV", selection: $model.selectedTVID) {
                ForEach(model.tvs) { tv in
                    HStack {
                        Image(systemName: tv.isFrame ? "photo.artframe" : "tv")
                        Text(tv.name)
                    }
                    .tag(Optional(tv.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 170)

            Spacer(minLength: 0)

            if let tv = model.selectedTV {
                let status = model.status(of: tv)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        StatusDot(power: status.power)
                        Text(status.power.label).font(.caption)
                    }
                    linkLabel(status.link)
                }
            }
        }
    }

    @ViewBuilder
    private func linkLabel(_ link: LinkState) -> some View {
        switch link {
        case .awaitingApproval:
            Label("Aceite na TV", systemImage: "hand.tap")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        case .denied, .needsPairing, .failed:
            Text(link.label)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150, alignment: .trailing)
        case .connected:
            Text("Conectado").font(.caption2).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}
