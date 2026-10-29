import SwiftUI

struct AppLaunchRowView: View {
    @Environment(AppModel.self) private var model
    var height: CGFloat = 26

    var body: some View {
        let apps = model.favoriteApps
        if apps.isEmpty {
            Text("Escolha apps favoritos nas Configurações.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(apps) { app in
                        Button { model.launch(app) } label: {
                            Label(app.name, systemImage: app.symbol)
                        }
                        .buttonStyle(PillButtonStyle(height: height))
                        .help("Abrir \(app.name) (\(app.appID))")
                    }
                }
            }
        }
    }
}
