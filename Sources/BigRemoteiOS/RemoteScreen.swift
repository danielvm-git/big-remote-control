// story: e11s01
import SwiftUI

/// The main remote: TV picker, power, pad, favourite apps and text.
struct RemoteScreen: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if model.tvs.isEmpty {
                        ContentUnavailableView(
                            "Nenhuma TV",
                            systemImage: "tv",
                            description: Text("Adicione uma TV na aba TVs.")
                        )
                    } else {
                        PhoneTVHeader()
                        if let banner = model.banner { BannerView(text: banner) }
                        PowerControlsView(height: 36)
                        RemotePadView(scale: 1.5)
                        if model.selectedTV?.isFrame ?? false { FrameSectionView() }
                        AppLaunchRowView(height: 36)
                        textField
                    }
                }
                .padding()
            }
            .navigationTitle("Big Remote")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var textField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Texto para a TV", text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onChange(of: text) { _, value in model.typeLive(value) }
                .onSubmit {
                    model.submitText(text)
                    text = ""
                }
            // Samsung drops text unless a TV text field (search, login) has its keyboard open.
            if model.selectedStatus.imeActive {
                Label("Teclado aberto na TV", systemImage: "keyboard").foregroundStyle(.green)
                    .font(.caption)
            } else {
                Text("Abra um campo de texto na TV (ex.: busca do YouTube) para o texto aparecer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
