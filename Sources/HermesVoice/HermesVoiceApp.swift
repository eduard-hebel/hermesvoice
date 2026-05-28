import SwiftUI

@main
struct HermesVoiceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appState)
        } label: {
            Image(systemName: appState.status.iconName)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 480, height: 360)
        }
    }
}
