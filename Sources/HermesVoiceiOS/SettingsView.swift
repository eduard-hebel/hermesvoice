import SwiftUI

/// Schlanke iOS-Einstellungen. Portiert vom Mac, was auf iOS sinnvoll ist:
/// Diktat-Sprache. Cleanup/Voice-Command/Hotkeys aus der Mac-App gibt es auf iOS
/// nicht (Claude-CLI-Subprozess gesperrt, keine globale Text-Selektion, keine
/// System-Hotkeys — dafür Action Button / Control Center).
struct SettingsView: View {
    // Gleicher UserDefaults-Key, den DictationController bei jeder Transkription liest.
    @AppStorage("languageHint") private var languageHint: String = "de"

    var body: some View {
        Form {
            Section("Sprache") {
                Picker("Diktat-Sprache", selection: $languageHint) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                    Text("Automatisch erkennen").tag("")
                }
            }

            Section("Modell") {
                LabeledContent("Whisper", value: "base · on-device")
                Text("Läuft komplett offline auf deinem iPhone — kein Upload, kein Internet nötig. Das Modell ist in die App eingebacken.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("So diktierst du überall") {
                Label("Hier aufnehmen → Text landet in der Zwischenablage → in jeder App einfügen.", systemImage: "doc.on.clipboard")
                    .font(.callout)
                Label("Action Button belegen: Einstellungen → Action Button → Kurzbefehl → „HermesVoice“ — dann startet das Diktat per Knopfdruck.", systemImage: "button.programmable")
                    .font(.callout)
            }

            Section {
                LabeledContent("Version", value: "0.1.0")
            }
        }
        .navigationTitle("Einstellungen")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
