import AppKit
import SwiftUI

@main
struct BigRemoteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRemoteView()
                .environment(model)
        } label: {
            Image(systemName: "appletvremote.gen4.fill")
        }
        .menuBarExtraStyle(.window)

        Window("Big Remote", id: "main") {
            MainWindowView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 600)
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 720, height: 560)
        }
    }
}

extension NSApplication {
    /// The app is LSUIElement, so bring windows to the front explicitly.
    @MainActor static func bringToFront() {
        NSApp.activate()
    }
}
