import AppKit
import SwiftUI

/// List + editor for presets. Changes are saved to presets.json right away.
struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?

    var body: some View {
        @Bindable var model = model
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.presets) { preset in
                        Label(preset.name, systemImage: preset.symbol).tag(preset.id)
                    }
                    .onMove { model.presets.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 4) {
                    Button {
                        let preset = Preset(name: "Novo preset", steps: [PresetStep(type: .key, key: RemoteKey.home.rawValue)])
                        model.presets.append(preset)
                        selection = preset.id
                    } label: { Image(systemName: "plus") }
                    .help("Novo preset")
                    Button {
                        // Commit any focused TextField while the preset still exists.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        let removed = selection
                        selection = nil
                        model.presets.removeAll { $0.id == removed }
                        selection = model.presets.first?.id
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help("Apagar preset")
                    Spacer()
                    Menu {
                        Button("Mostrar presets.json no Finder") { model.revealPresetsFile() }
                        Button("Restaurar exemplos") { model.restoreExamplePresets() }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 170, idealWidth: 200, maxWidth: 260)

            Group {
                if let preset = model.presets.first(where: { $0.id == selection }) {
                    PresetDetailView(preset: binding(for: preset))
                        .id(preset.id)
                } else {
                    ContentUnavailableView(
                        "Escolha um preset",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Presets são sequências de passos: teclas, esperas, apps, Modo Arte, energia e comandos SmartThings.")
                    )
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = model.presets.first?.id } }
    }

    /// Binds by id, not by index: the binding stays safe after a deletion.
    private func binding(for preset: Preset) -> Binding<Preset> {
        let id = preset.id
        return Binding(
            get: { model.presets.first { $0.id == id } ?? preset },
            set: { new in
                if let index = model.presets.firstIndex(where: { $0.id == id }) { model.presets[index] = new }
            }
        )
    }
}

struct PresetDetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var preset: Preset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Nome", text: $preset.name).textFieldStyle(.roundedBorder)
                TextField("Símbolo SF", text: $preset.symbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Image(systemName: preset.symbol).frame(width: 20)
                Button("Executar") { model.runPreset(preset) }
                    .disabled(model.runningPresetID != nil)
            }

            List {
                ForEach($preset.steps) { $step in
                    StepEditorRow(step: $step)
                }
                .onMove { preset.steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { preset.steps.remove(atOffsets: $0) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Menu {
                    ForEach(PresetStep.StepType.allCases, id: \.self) { type in
                        Button { preset.steps.append(Self.newStep(type)) } label: { Label(type.label, systemImage: type.symbol) }
                    }
                } label: { Label("Adicionar passo", systemImage: "plus") }
                .fixedSize()
                Spacer()
                Text("Arraste para reordenar. Apague com ⌫ ou o botão da linha.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    static func newStep(_ type: PresetStep.StepType) -> PresetStep {
        switch type {
        case .key: return PresetStep(type: .key, key: RemoteKey.home.rawValue)
        case .delay: return PresetStep(type: .delay, seconds: 1)
        case .launchApp: return PresetStep(type: .launchApp, appID: TVApp.catalog[0].appID)
        case .artMode: return PresetStep(type: .artMode, on: true)
        case .power: return PresetStep(type: .power, power: .tv)
        case .text: return PresetStep(type: .text, text: "")
        case .smartThings: return PresetStep(type: .smartThings, capability: "custom.picturemode", command: "setPictureMode", arguments: [])
        }
    }
}

struct StepEditorRow: View {
    @Environment(AppModel.self) private var model
    @Binding var step: PresetStep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: step.type.symbol).frame(width: 18)
                Picker("Tipo", selection: $step.type) {
                    ForEach(PresetStep.StepType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                if step.type != .delay {
                    Picker("TV", selection: targetBinding) {
                        Text("TV selecionada").tag("selected")
                        Text("Todas as TVs").tag("all")
                        ForEach(model.tvs) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Spacer()
                if let problem = step.validationProblem {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(problem)
                }
            }
            fields
        }
        .padding(.vertical, 4)
    }

    private var targetBinding: Binding<String> {
        Binding(get: { step.target.rawValue }, set: { step.target = PresetTarget(rawValue: $0) })
    }

    private func text(_ keyPath: WritableKeyPath<PresetStep, String?>) -> Binding<String> {
        Binding(get: { step[keyPath: keyPath] ?? "" }, set: { step[keyPath: keyPath] = $0 })
    }

    private func number(_ keyPath: WritableKeyPath<PresetStep, Double?>, default value: Double) -> Binding<Double> {
        Binding(get: { step[keyPath: keyPath] ?? value }, set: { step[keyPath: keyPath] = $0 })
    }

    @ViewBuilder
    private var fields: some View {
        switch step.type {
        case .key:
            HStack {
                Picker("Tecla", selection: text(\.key)) {
                    ForEach(RemoteKey.allCases) { Text("\($0.label) (\($0.rawValue))").tag($0.rawValue) }
                    if let key = step.key, RemoteKey(rawValue: key) == nil { Text(key).tag(key) }
                }
                .frame(maxWidth: 300)
                TextField("KEY_…", text: text(\.key)).textFieldStyle(.roundedBorder).frame(width: 120)
                Stepper("Segurar \((step.holdSeconds ?? 0).formatted()) s", value: number(\.holdSeconds, default: 0), in: 0...10, step: 0.5)
            }
        case .delay:
            Stepper("Esperar \((step.seconds ?? 1).formatted()) s", value: number(\.seconds, default: 1), in: 0...120, step: 0.5)
        case .launchApp:
            HStack {
                Picker("App", selection: text(\.appID)) {
                    ForEach(model.allApps) { Text($0.name).tag($0.appID) }
                    if let id = step.appID, !model.allApps.contains(where: { $0.appID == id }) { Text(id).tag(id) }
                }
                .frame(maxWidth: 220)
                TextField("ID do app", text: text(\.appID)).textFieldStyle(.roundedBorder).frame(width: 150)
            }
        case .artMode:
            Picker("Modo Arte", selection: Binding(get: { step.on ?? true }, set: { step.on = $0 })) {
                Text("Ligar").tag(true)
                Text("Desligar").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        case .power:
            Picker("Ação", selection: Binding(get: { step.power ?? .tv }, set: { step.power = $0 })) {
                ForEach(PowerAction.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .frame(maxWidth: 260)
        case .text:
            TextField("Texto enviado ao campo da TV", text: text(\.text)).textFieldStyle(.roundedBorder)
        case .smartThings:
            HStack {
                TextField("capability", text: text(\.capability)).textFieldStyle(.roundedBorder)
                TextField("comando", text: text(\.command)).textFieldStyle(.roundedBorder).frame(width: 130)
                ArgumentsField(arguments: $step.arguments)
            }
            if !model.smartThingsConfigured {
                Text("Sem token SmartThings: este passo será pulado com aviso.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Comma-separated arguments. `15` is a number, `"7"` a string, `true` a bool.
struct ArgumentsField: View {
    @Binding var arguments: [JSONValue]?
    @State private var text = ""

    var body: some View {
        TextField("argumentos, separados por vírgula", text: $text)
            .textFieldStyle(.roundedBorder)
            .onAppear { text = (arguments ?? []).map(\.userToken).joined(separator: ", ") }
            .onChange(of: text) { _, newValue in
                let tokens = newValue.split(separator: ",").map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                arguments = tokens.map(JSONValue.fromUserToken)
            }
    }
}
