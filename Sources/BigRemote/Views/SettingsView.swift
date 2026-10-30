import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TVSettingsView().tabItem { Label("TVs", systemImage: "tv") }
            AppsSettingsView().tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            PresetEditorView().tabItem { Label("Presets", systemImage: "sparkles") }
            SmartThingsSettingsView().tabItem { Label("SmartThings", systemImage: "cloud") }
            DiagnosticsSettingsView().tabItem { Label("Diagnóstico", systemImage: "stethoscope") }
        }
    }
}

// MARK: - TVs

struct TVSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newIP = ""
    @State private var selection: String?

    var body: some View {
        @Bindable var model = model
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.tvs) { tv in
                        HStack {
                            StatusDot(power: model.status(of: tv).power)
                            Text(tv.name)
                        }
                        .tag(tv.id)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("IP, ex. 192.168.1.44", text: $newIP)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addIP)
                        Button("Adicionar", action: addIP).disabled(newIP.isEmpty)
                    }
                    HStack {
                        Button {
                            model.discover()
                        } label: {
                            Label("Procurar na rede", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .disabled(model.isScanning)
                        if model.isScanning { ProgressView().controlSize(.small) }
                    }
                    ForEach(model.discovered, id: \.ip) { info in
                        let known = model.tvs.contains { $0.ip == info.ip }
                        HStack {
                            VStack(alignment: .leading) {
                                Text(info.name ?? info.ip).font(.caption)
                                Text("\(info.ip) · \(info.modelName ?? "?")").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(known ? "Na lista" : "Adicionar") { model.add(info: info) }
                                .disabled(known)
                                .controlSize(.small)
                        }
                    }
                }
                .padding(8)
            }
            .frame(minWidth: 230, idealWidth: 260)

            Group {
                if let tv = model.tvs.first(where: { $0.id == selection }) {
                    TVDetailView(tv: binding(for: tv)) {
                        // End editing first so a focus-loss commit cannot write
                        // into a TV that is gone, then drop the selection.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        selection = nil
                        model.remove(tv)
                    }
                    .id(tv.id)
                } else {
                    ContentUnavailableView("Escolha uma TV", systemImage: "tv")
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selection = selection ?? model.selectedTVID }
    }

    /// Binds by id, not by index: the binding stays safe after a removal.
    private func binding(for tv: TVDevice) -> Binding<TVDevice> {
        let id = tv.id
        return Binding(
            get: { model.tvs.first { $0.id == id } ?? tv },
            set: { new in
                if let index = model.tvs.firstIndex(where: { $0.id == id }) { model.tvs[index] = new }
            }
        )
    }

    private func addIP() {
        let ip = newIP
        newIP = ""
        Task { await model.addTV(ip: ip) }
    }
}

struct TVDetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var tv: TVDevice
    var onRemove: () -> Void
    @State private var confirmRemove = false

    var body: some View {
        let status = model.status(of: tv)
        Form {
            Section("TV") {
                TextField("Nome", text: $tv.name)
                TextField("IP", text: $tv.ip)
                TextField("MAC (Wake-on-LAN)", text: Binding(get: { tv.mac ?? "" }, set: { tv.mac = $0.isEmpty ? nil : $0 }))
                if let mac = tv.mac, WakeOnLANPacket.parseMAC(mac) == nil {
                    Text("MAC inválido").font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Marca", value: tv.vendor.label)
                if tv.vendor == .samsung {
                    Toggle("The Frame (Modo Arte)", isOn: $tv.isFrame)
                }
            }
            Section("Estado") {
                LabeledContent("Energia", value: status.power.label)
                LabeledContent("Conexão", value: status.link.label)
                if let info = status.info {
                    LabeledContent("Modelo", value: "\(info.modelName ?? "?") (\(info.model ?? "?"))")
                    LabeledContent("Rede", value: info.networkType ?? "?")
                    if let res = info.resolution { LabeledContent("Resolução", value: res) }
                    if let api = info.apiVersion { LabeledContent("API", value: api) }
                }
                if let art = status.artAPIVersion { LabeledContent("API Modo Arte", value: art) }
            }
            if tv.vendor == .sony {
                SonyPairingSection(tv: tv)
            } else {
                Section("Pareamento") {
                    Text(model.hasToken(tv)
                        ? "Token salvo. Os comandos não pedem confirmação na TV."
                        : "Ainda não pareada. Na primeira conexão a TV mostra um aviso: aceite com o controle físico.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Parear agora") { model.pair(tv) }
                        Button("Esquecer pareamento") { model.forgetPairing(tv) }
                            .disabled(!model.hasToken(tv))
                    }
                }
            }
            Section {
                Button("Remover TV", role: .destructive) { confirmRemove = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remover “\(tv.name)”?", isPresented: $confirmRemove) {
            Button("Remover", role: .destructive) { onRemove() }
        }
    }
}

// MARK: - Apps

struct AppsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var probeResults: [String: String] = [:]
    @State private var newName = ""
    @State private var newID = ""

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            Text("Marque os favoritos da barra de apps. “Verificar” consulta a TV selecionada (somente leitura) para saber se o app está instalado.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(model.allApps) { app in
                    HStack {
                        Toggle(isOn: Binding(get: { model.isFavorite(app) }, set: { _ in model.toggleFavorite(app) })) {
                            Label(app.name, systemImage: app.symbol)
                        }
                        if app.uncertain {
                            Text("ID não confirmado").font(.caption2).foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(app.appID).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let result = probeResults[app.appID] {
                            Text(result).font(.caption2)
                        }
                        Button("Verificar") {
                            Task { probeResults[app.appID] = await model.probe(app) }
                        }
                        .controlSize(.small)
                        Button("Abrir") { model.launch(app) }.controlSize(.small)
                        if model.customApps.contains(app) {
                            Button {
                                model.customApps.removeAll { $0 == app }
                                model.favoriteAppIDs.removeAll { $0 == app.appID }
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            HStack {
                TextField("Nome", text: $newName).textFieldStyle(.roundedBorder).frame(width: 160)
                TextField("ID do app", text: $newID).textFieldStyle(.roundedBorder)
                Button("Adicionar app") {
                    let app = TVApp(name: newName, appID: newID.trimmingCharacters(in: .whitespaces), symbol: "app")
                    model.customApps.append(app)
                    model.favoriteAppIDs.append(app.appID)
                    newName = ""
                    newID = ""
                }
                .disabled(newName.isEmpty || newID.isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - SmartThings

struct SmartThingsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                Text("Opcional. Com SmartThings o app define modo de imagem, modo de som e entrada pelo nome. Sem token, tudo o mais funciona pela rede local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.smartThingsConfigured {
                    LabeledContent("Token", value: "salvo no Keychain")
                    HStack {
                        Button("Recarregar aparelhos") { model.loadSmartThingsDevices() }
                        Button("Apagar token", role: .destructive) { model.clearSmartThingsToken() }
                    }
                } else {
                    SecureField("Token (Bearer)", text: $token)
                    Button("Salvar no Keychain") {
                        model.saveSmartThingsToken(token)
                        token = ""
                    }
                    .disabled(token.isEmpty)
                    Text("Tokens pessoais criados em account.smartthings.com/tokens valem só 24 h. Para uso contínuo, crie um app OAuth (veja o README).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if model.stLoading { ProgressView().controlSize(.small) }
                if let error = model.stError { Text(error).font(.caption).foregroundStyle(.red) }
            } header: { Text("Token") }

            if model.smartThingsConfigured {
                Section("Associação") {
                    ForEach(model.tvs) { tv in
                        Picker(tv.name, selection: Binding(
                            get: { tv.smartThingsDeviceID },
                            set: { model.mapSmartThings(tvID: tv.id, deviceID: $0) }
                        )) {
                            Text("Nenhum").tag(String?.none)
                            ForEach(model.stDevices) { device in
                                Text("\(device.displayName) (\(device.ocf?.mnmo ?? device.deviceTypeName ?? "?"))").tag(Optional(device.deviceId))
                            }
                            if let id = tv.smartThingsDeviceID, !model.stDevices.contains(where: { $0.deviceId == id }) {
                                Text(id).tag(Optional(id))
                            }
                        }
                    }
                }
                Section("TV selecionada") {
                    SmartThingsPanelView()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if model.smartThingsConfigured && model.stDevices.isEmpty { model.loadSmartThingsDevices() } }
    }
}
