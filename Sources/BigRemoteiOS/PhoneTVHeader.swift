// story: e11s01
import SwiftUI

/// iPhone header: TV menu on one line, status on the next. The Mac's
/// `TVHeaderView` puts both on one row with a 170 pt picker; with larger
/// Dynamic Type the name wrapped and spilled over the power buttons.
struct PhoneTVHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Picker("TV", selection: $model.selectedTVID) {
                    ForEach(model.tvs) { tv in
                        Label(tv.name, systemImage: tv.isFrame ? "photo.artframe" : "tv").tag(Optional(tv.id))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.selectedTV?.isFrame == true ? "photo.artframe" : "tv")
                    Text(model.selectedTV?.name ?? "Escolha uma TV")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote)
                }
                .font(.title3.weight(.semibold))
            }
            if let tv = model.selectedTV {
                let status = model.status(of: tv)
                HStack(spacing: 6) {
                    StatusDot(power: status.power)
                    Text(status.power.label)
                    Spacer(minLength: 8)
                    Text(status.link.label)
                        .foregroundStyle(linkColor(status.link))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.subheadline)
            }
            if model.localNetworkBlocked {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TVHeaderView.localNetworkHint).font(.caption)
                    Button("Abrir Ajustes") { model.openLocalNetworkSettings() }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkColor(_ link: LinkState) -> Color {
        switch link {
        case .awaitingApproval: return .orange
        case .denied, .needsPairing, .failed: return .red
        default: return .secondary
        }
    }
}
