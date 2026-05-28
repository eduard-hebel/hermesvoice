import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var autoStartEnabled: Bool = AutoStartService.shared.isEnabled
    @State private var autoStartError: String?

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Toggle-Diktat:", name: .toggleDictation)
                KeyboardShortcuts.Recorder("Push-to-Talk (gedrückt halten):", name: .pushToTalk)
                KeyboardShortcuts.Recorder("Voice-Command auf Selection:", name: .voiceCommand)
                Text("Toggle: 1× drücken / 1× drücken. Push-to-Talk: gedrückt halten. Voice-Command: Text markieren, drücken, Befehl sagen, nochmal drücken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Toggle("Versprecher & Füllwörter rausräumen", isOn: $state.cleanupEnabled)
                    .onChange(of: state.cleanupEnabled) { _, new in
                        UserDefaults.standard.set(new, forKey: "cleanupEnabled")
                    }
                if state.cleanupEnabled {
                    Picker("Cleanup-Modell", selection: $state.cleanupModel) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.label).tag(model)
                        }
                    }
                }
                Text("Nutzt deinen lokalen Claude-CLI (Max Plan). Kein API-Key nötig. Haiku ist am schnellsten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice-Command (Selection)") {
                Picker("Voice-Command-Modell", selection: $state.voiceCommandModel) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                Text("Modell für Transformationen auf markiertem Text (⌘⇧⌃V). Sonnet versteht komplexe Befehle besser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Allgemein") {
                Toggle("Beim Login automatisch starten", isOn: $autoStartEnabled)
                    .onChange(of: autoStartEnabled) { _, new in
                        do {
                            try AutoStartService.shared.setEnabled(new)
                            autoStartError = nil
                        } catch {
                            autoStartError = error.localizedDescription
                            // Rollback, da OS-Call fehlgeschlagen ist
                            autoStartEnabled = AutoStartService.shared.isEnabled
                        }
                    }
                if let autoStartError {
                    Text("Fehler: \(autoStartError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
