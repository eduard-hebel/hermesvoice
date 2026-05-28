import SwiftUI

@main
struct HermesVoiceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("HermesVoice", systemImage: appState.status.iconName) {
            MenuBarContent()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 480, height: 360)
        }
    }
}
