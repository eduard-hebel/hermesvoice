import SwiftUI

/// Schlanke iOS-Einstellungen. Portiert vom Mac, was auf iOS sinnvoll ist:
/// Diktat-Sprache. Cleanup/Voice-Command/Hotkeys aus der Mac-App gibt es auf iOS
/// nicht (Claude-CLI-Subprozess gesperrt, keine globale Text-Selektion, keine
/// System-Hotkeys — dafür Action Button / Control Center).
struct SettingsView: View {
    // Gleicher UserDefaults-Key, den DictationController bei jeder Transkription liest.
    @AppStorage("languageHint") private var languageHint: String = "de"
    // App-weites Erscheinungsbild (gleicher Key wie in HermesVoiceiOSApp).
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Sprache") {
                Picker(selection: $languageHint) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                    Text("Automatisch erkennen").tag("")
                } label: {
                    Label("Diktat-Sprache", systemImage: "character.bubble")
                }
            }

            Section("Modell") {
                LabeledContent {
                    Text("large-v3-turbo · on-device")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Whisper", systemImage: "cpu")
                }
                Label {
                    Text("Läuft komplett offline auf deinem iPhone — kein Upload, kein Internet nötig. Das Modell ist in die App eingebacken.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Wörterbuch") {
                NavigationLink {
                    DictionaryView()
                } label: {
                    Label("Eigenes Wörterbuch", systemImage: "character.book.closed")
                }
                Text("Eigene Begriffe, Namen oder Dialektwörter (z. B. „oida“) nach dem Diktat automatisch korrigieren.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("So diktierst du überall") {
                Label("Hier aufnehmen → Text landet in der Zwischenablage → in jeder App einfügen.", systemImage: "doc.on.clipboard")
                Label("Action Button belegen: Einstellungen → Action Button → Kurzbefehl → „HermesVoice“ — dann startet das Diktat per Knopfdruck.", systemImage: "button.programmable")
            }
            .font(.callout)

            Section {
                LabeledContent {
                    Text("0.1.0").foregroundStyle(.secondary)
                } label: {
                    Label("Version", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Einstellungen")
        .tint(Brand.accent)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
