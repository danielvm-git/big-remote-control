// story: e12s03
#if os(macOS)
import AppKit
#endif
import SwiftUI

/// Where the log lives and how to get it out: Share on iPhone, Finder on the Mac.
struct DiagnosticsSection: View {
    @State private var exportURL: URL?
    @State private var fileCount = 0

    var body: some View {
        Section("Diagnóstico") {
            Text("O app grava um log local (uma linha JSON por evento) com pareamento, conexões e comandos. "
                + "Tokens, PINs e cookies nunca entram: só uma impressão digital curta.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Arquivos de log", value: "\(fileCount)")
            #if os(macOS)
            Button("Mostrar pasta de logs") { NSWorkspace.shared.activateFileViewerSelecting([Log.directory]) }
            #endif
            if let exportURL {
                ShareLink("Compartilhar log", item: exportURL)
            }
            Button("Atualizar", action: refresh)
        }
        .task { refresh() }
    }

    private func refresh() {
        fileCount = Log.fileURLs().count
        exportURL = Log.exportURL()
    }
}

#if os(macOS)
struct DiagnosticsSettingsView: View {
    var body: some View {
        Form { DiagnosticsSection() }
            .formStyle(.grouped)
    }
}
#endif
