import AppKit
import SwiftUI

struct MenuBarRemoteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showSmartThings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TVHeaderView()
            PowerControlsView(height: 24)

            RemotePadView(scale: 0.9)
                .frame(maxWidth: .infinity)

            SectionCard(title: "Apps", symbol: "square.grid.2x2") {
                AppLaunchRowView(height: 24)
            }

            if model.selectedTV?.isFrame ?? false {
                SectionCard(title: "The Frame", symbol: "photo.artframe") {
                    FrameSectionView()
                }
            }

            SectionCard(title: "Presets", symbol: "sparkles") {
                PresetButtonsView(columns: 2)
            }

            if model.smartThingsConfigured {
                DisclosureGroup(isExpanded: $showSmartThings) {
                    SmartThingsPanelView().padding(.top, 4)
                } label: {
                    Label("SmartThings", systemImage: "cloud").font(.caption.weight(.semibold))
                }
            }

            if let banner = model.banner {
                BannerView(text: banner)
            }

            Divider()
            HStack {
                Button {
                    openWindow(id: "main")
                    NSApplication.bringToFront()
                } label: { Label("Abrir janela", systemImage: "macwindow") }
                Button {
                    openSettings()
                    NSApplication.bringToFront()
                } label: { Label("Configurações", systemImage: "gearshape") }
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Sair do Big Remote")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(12)
        .frame(width: 320)
        .animation(.default, value: model.banner)
    }
}
