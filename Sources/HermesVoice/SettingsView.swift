import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var apiKeyInput: String = ""
    @State private var apiKeySaved: Bool = false

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Diktat starten / stoppen:", name: .toggleDictation)
            }

            Section("Sprache & Modell") {
                Picker("Sprache", selection: $state.languageHint) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                    Text("Auto").tag("")
                }
                Picker("Whisper-Modell", selection: $state.modelName) {
                    Text("Large V3 (beste Qualität, ~626 MB)").tag("large-v3-v20240930_626MB")
                    Text("Medium (schneller, ~325 MB)").tag("medium")
                    Text("Small (am schnellsten, ~150 MB)").tag("small")
                }
            }

            Section("Cleanup (optional)") {
                Toggle("Aktiv (Claude Haiku 4.5)", isOn: $state.cleanupEnabled)
                SecureField("Anthropic API-Key", text: $apiKeyInput)
                Button(apiKeySaved ? "Gespeichert ✓" : "Speichern") {
                    KeychainHelper.shared.save(key: "anthropic_api_key", value: apiKeyInput)
                    apiKeySaved = true
                    apiKeyInput = ""
                }
                .disabled(apiKeyInput.isEmpty)
                Text("Der Key bleibt lokal im Keychain. Kosten ~$0.0001 pro Diktat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
