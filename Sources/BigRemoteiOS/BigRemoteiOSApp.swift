// story: e11s01
import SwiftUI

/// iPhone app: the same TV clients and AppModel as the Mac app, with touch screens.
@main
struct BigRemoteiOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                RemoteScreen()
                    .tabItem { Label("Controle", systemImage: "appletvremote.gen4") }
                PresetsScreen()
                    .tabItem { Label("Presets", systemImage: "sparkles") }
                TVListScreen()
                    .tabItem { Label("TVs", systemImage: "tv") }
            }
            .environment(model)
        }
    }
}
