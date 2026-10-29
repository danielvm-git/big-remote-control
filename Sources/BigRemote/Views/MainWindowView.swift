import SwiftUI

/// Larger remote + presets editor + text input. Arrow keys, Return, Escape
/// and Delete control the TV while the remote panel has focus.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.presets
    @State private var text = ""
    @State private var liveTyping = false
    @FocusState private var remoteFocused: Bool

    enum Tab: Hashable { case presets, apps, smartThings }

    var body: some View {
        HSplitView {
            remotePanel
                .frame(minWidth: 340, idealWidth: 360, maxWidth: 420)
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Presets").tag(Tab.presets)
                    Text("Apps").tag(Tab.apps)
                    Text("SmartThings").tag(Tab.smartThings)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                Divider()
                switch tab {
                case .presets: PresetEditorView()
                case .apps: AppsSettingsView()
                case .smartThings: SmartThingsSettingsView()
                }
            }
            .frame(minWidth: 440)
        }
    }

    private var remotePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TVHeaderView()
                PowerControlsView(height: 30)
                RemotePadView(scale: 1.25)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .focusable()
                    .focused($remoteFocused)
                    .focusEffectDisabled()
                    .onKeyPress(phases: .down) { press in handle(press) }
                    .onTapGesture { remoteFocused = true }
                    .overlay(alignment: .bottomTrailing) {
                        if remoteFocused {
                            Image(systemName: "keyboard").font(.caption2).foregroundStyle(.secondary)
                                .help("Setas, Return, Esc (voltar), Delete (início) controlam a TV")
                        }
                    }

                SectionCard(title: "Teclas extras", symbol: "ellipsis.circle") {
                    HStack(spacing: 6) {
                        extra(.menu, "gearshape")
                        extra(.exit, "xmark.circle")
                        extra(.info, "info.circle")
                        extra(.tools, "wrench.and.screwdriver")
                        extra(.previousChannel, "arrow.left.arrow.right")
                    }
                    HStack(spacing: 6) {
                        extra(.rewind, "backward.fill")
                        extra(.play, "play.fill")
                        extra(.pause, "pause.fill")
                        extra(.stop, "stop.fill")
                        extra(.fastForward, "forward.fill")
                    }
                }

                SectionCard(title: "Apps", symbol: "square.grid.2x2") { AppLaunchRowView(height: 28) }

                if model.selectedTV?.isFrame ?? false {
                    SectionCard(title: "The Frame", symbol: "photo.artframe") { FrameSectionView(showSettings: true) }
                }

                SectionCard(title: "Texto na TV", symbol: "character.cursor.ibeam") {
                    TextField("Digite e pressione Return", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.submitText(text) }
                        .onChange(of: text) { _, value in if liveTyping { model.typeLive(value) } }
                    HStack {
                        Toggle("Enviar enquanto digita", isOn: $liveTyping).controlSize(.small)
                        Spacer()
                        if model.selectedStatus.imeActive {
                            Label("Teclado aberto na TV", systemImage: "keyboard").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                }

                SectionCard(title: "Presets", symbol: "sparkles") { PresetButtonsView(columns: 2) }

                if model.smartThingsConfigured {
                    SectionCard(title: "SmartThings", symbol: "cloud") { SmartThingsPanelView() }
                }

                if let banner = model.banner { BannerView(text: banner) }
            }
            .padding(16)
        }
        .background(.regularMaterial)
        .animation(.default, value: model.banner)
    }

    private func extra(_ key: RemoteKey, _ symbol: String) -> some View {
        KeyButton(key: key, symbol: symbol, size: 32)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let key: RemoteKey?
        switch press.key {
        case .upArrow: key = .up
        case .downArrow: key = .down
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .return: key = .enter
        case .escape: key = .back
        case .delete: key = .home
        default: key = nil
        }
        guard let key else { return .ignored }
        model.press(key)
        return .handled
    }
}
