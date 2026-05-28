import SwiftUI

struct MenuBarContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            Text(statusLabel)
                .foregroundStyle(.secondary)

            Divider()

            Button("Aufnahme starten / stoppen") {
                Task { await state.toggle() }
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])

            if !state.lastTranscript.isEmpty {
                Divider()
                Text("Letztes Transcript:")
                    .foregroundStyle(.secondary)
                Text(state.lastTranscript.prefix(80) + (state.lastTranscript.count > 80 ? "…" : ""))
            }

            Divider()

            Toggle("Cleanup mit Claude Haiku", isOn: $state.cleanupEnabled)
                .onChange(of: state.cleanupEnabled) { _, new in
                    UserDefaults.standard.set(new, forKey: "cleanupEnabled")
                }

            SettingsLink {
                Text("Einstellungen…")
            }

            Divider()
            Button("HermesVoice beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var statusLabel: String {
        switch state.status {
        case .idle:         "Bereit · ⌘⇧Space"
        case .recording:    "● Aufnahme läuft"
        case .transcribing: "Transkribiere…"
        case .cleaning:     "Glätte Text…"
        case .error(let m): "Fehler: \(m)"
        }
    }
}
