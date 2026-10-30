// story: e05s01
#if os(macOS)
import AppKit
#endif
import Foundation

/// Running and managing presets.
extension AppModel {
    func runPreset(_ preset: Preset) {
        guard runningPresetID == nil else { return show("Já existe um preset rodando.") }
        runningPresetID = preset.id
        Log.info(.command, "preset.run", ["name": preset.name, "steps": "\(preset.steps.count)"])
        Task {
            var problems: [String] = []
            for step in preset.steps {
                if let problem = step.validationProblem {
                    problems.append("\(step.summary): \(problem)")
                    continue
                }
                do {
                    try await self.runStep(step)
                } catch is CancellationError {
                    continue
                } catch {
                    problems.append("\(step.summary): \(error.localizedDescription)")
                }
            }
            self.runningPresetID = nil
            if problems.isEmpty {
                self.show("“\(preset.name)” concluído.")
            } else {
                self.show("“\(preset.name)”: \(problems.count) passo(s) com erro. \(problems[0])")
            }
        }
    }

    private func targets(for target: PresetTarget) -> [TVDevice] {
        switch target {
        case .selected: return selectedTV.map { [$0] } ?? []
        case .all: return tvs
        case .tv(let id): return tvs.filter { $0.id == id }
        }
    }

    private func runStep(_ step: PresetStep) async throws {
        if step.type == .delay {
            try await Task.sleep(for: .milliseconds(Int((step.seconds ?? 1) * 1000)))
            return
        }
        let list = targets(for: step.target)
        guard !list.isEmpty else { throw TVError.noTVSelected }
        if list.count == 1 { return try await runStep(step, on: list[0]) }
        // Each TV runs to the end on its own: one failure must not cancel
        // the others (e.g. one TV without MAC while the other is waking).
        let failures = await withTaskGroup(of: (String, Error)?.self) { group in
            for tv in list {
                group.addTask {
                    do {
                        try await self.runStep(step, on: tv)
                        return nil
                    } catch {
                        return (tv.name, error)
                    }
                }
            }
            var collected: [(String, Error)] = []
            for await result in group { if let result { collected.append(result) } }
            return collected
        }
        let real = failures.filter { !($0.1 is CancellationError) }
        if real.isEmpty {
            if !failures.isEmpty { throw CancellationError() }
            return
        }
        throw PresetStepError(failures: real.map { ($0.0, $0.1.localizedDescription) })
    }

    private func runStep(_ step: PresetStep, on tv: TVDevice) async throws {
        let client = try client(for: tv)
        switch step.type {
        case .delay:
            break
        case .key:
            let code = step.key ?? ""
            if let hold = step.holdSeconds, hold > 0 {
                try await client.holdKey(code, seconds: min(hold, 10))
            } else {
                try await client.sendKey(code)
            }
        case .launchApp:
            try await runLaunchStep(step, on: tv, client: client)
        case .artMode:
            if step.on ?? true {
                try await setPower(.art, on: tv)
            } else {
                try await samsungClient(for: tv).setArtMode(false)
            }
        case .power:
            try await setPower(step.power ?? .tv, on: tv)
        case .text:
            try await client.sendText(step.text ?? "", submit: true)
        case .smartThings:
            guard let st = smartThingsClient(), let deviceID = tv.smartThingsDeviceID else {
                throw TVError.smartThingsUnavailable
            }
            try await st.send(
                deviceID: deviceID,
                capability: step.capability ?? "",
                command: step.command ?? "",
                arguments: step.arguments ?? []
            )
        }
    }

    /// Catalogue apps resolve to the ID installed on this TV; raw IDs go as typed.
    private func runLaunchStep(_ step: PresetStep, on tv: TVDevice, client: any TVController) async throws {
        var appID = step.appID ?? ""
        let known = TVApp.find(appID, in: customApps)
        if let named = client as? any NamedAppLauncher {
            // Catalogue apps match by title; anything else is the TV's own id.
            if let known { try await named.launchApp(named: known.name) } else { try await named.launch(id: appID) }
            return
        }
        guard let client = client as? SamsungTVClient else { return }
        let type = step.launchType ?? known?.launchType ?? .deepLink
        if let known, known.appID == appID {
            appID = try await resolveAppID(known, on: tv)
        }
        try await client.launchApp(appID, type: type)
    }

    #if os(macOS)
    func revealPresetsFile() {
        presetStore.save(presets)
        NSWorkspace.shared.activateFileViewerSelecting([PresetStore.fileURL])
    }
    #endif

    func restoreExamplePresets() {
        let existing = Set(presets.map(\.name))
        presets.append(contentsOf: Preset.examples.filter { !existing.contains($0.name) })
    }
}

/// A preset step that failed on one or more TVs (names each TV).
struct PresetStepError: LocalizedError {
    var failures: [(tv: String, message: String)]

    var errorDescription: String? {
        failures.map { "\($0.tv): \($0.message)" }.joined(separator: "; ")
    }
}
