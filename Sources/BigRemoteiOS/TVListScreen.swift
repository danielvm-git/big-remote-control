// story: e11s01
import SwiftUI

/// Add, discover, pair and remove TVs.
struct TVListScreen: View {
    @Environment(AppModel.self) private var model
    @State private var newIP = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Minhas TVs") {
                    ForEach($model.tvs) { $tv in
                        NavigationLink {
                            TVDetailScreen(tv: $tv)
                        } label: {
                            HStack {
                                StatusDot(power: model.status(of: tv).power)
                                VStack(alignment: .leading) {
                                    Text(tv.name)
                                    Text("\(tv.vendor.label) · \(tv.ip)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Adicionar") {
                    HStack {
                        // Not .decimalPad: in pt-BR it shows a comma and no dot.
                        TextField("IP da TV", text: $newIP)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                        Button("Adicionar") {
                            let ip = newIP
                            newIP = ""
                            Task { await model.addTV(ip: ip) }
                        }
                        .disabled(newIP.isEmpty)
                    }
                    Button {
                        model.discover()
                    } label: {
                        HStack {
                            Label("Procurar na rede", systemImage: "magnifyingglass")
                            if model.isScanning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isScanning)
                    // TVs already in the list are not offered again.
                    ForEach(model.discovered.filter { info in !model.tvs.contains { $0.ip == info.ip } }, id: \.ip) { info in
                        Button { model.add(info: info) } label: {
                            Label("\(info.name ?? info.ip) · \(info.brand.label)", systemImage: "plus.circle")
                        }
                    }
                }
                if let banner = model.banner {
                    Section { Text(banner).font(.caption) }
                }
                DiagnosticsSection()
            }
            .navigationTitle("TVs")
        }
    }
}

struct TVDetailScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var tv: TVDevice

    var body: some View {
        let status = model.status(of: tv)
        Form {
            Section("TV") {
                TextField("Nome", text: $tv.name)
                TextField("IP", text: $tv.ip)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                TextField("MAC (Wake-on-LAN)", text: Binding(get: { tv.mac ?? "" }, set: { tv.mac = $0.isEmpty ? nil : $0 }))
                    .textInputAutocapitalization(.characters)
                LabeledContent("Marca", value: tv.vendor.label)
                if tv.vendor == .samsung { Toggle("The Frame (Modo Arte)", isOn: $tv.isFrame) }
            }
            Section("Estado") {
                LabeledContent("Energia", value: status.power.label)
                LabeledContent("Conexão", value: status.link.label)
                if let model = status.info?.modelName { LabeledContent("Modelo", value: model) }
            }
            if tv.vendor == .sony {
                SonyPairingSection(tv: tv)
            } else {
                Section("Pareamento") {
                    Text(model.hasToken(tv)
                        ? "Pareada. Os comandos não pedem confirmação na TV."
                        : "Na primeira conexão a TV mostra um aviso: aceite com o controle físico.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Parear agora") { model.pair(tv) }
                    Button("Esquecer pareamento") { model.forgetPairing(tv) }
                        .disabled(!model.hasToken(tv))
                }
            }
            Section {
                Button("Remover TV", role: .destructive) {
                    // Pop first: the row binding must not outlive its TV.
                    let removed = tv
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        model.remove(removed)
                    }
                }
            }
        }
        .navigationTitle(tv.name)
    }
}
