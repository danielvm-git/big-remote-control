// story: e11s01
import SwiftUI

/// Runs presets. Editing stays on the Mac (shared JSON file per device).
struct PresetsScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                PresetButtonsView(columns: 2).padding()
            }
            .navigationTitle("Presets")
        }
    }
}
