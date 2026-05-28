import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

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

            let history = HistoryStore.shared.entries
            if !history.isEmpty {
                Divider()
                Menu("Letzte Diktate") {
                    ForEach(history.prefix(20)) { entry in
                        Button(entry.preview) {
                            HistoryStore.shared.copyToClipboard(entry)
                        }
                    }
                    Divider()
                    Button("History leeren") {
                        HistoryStore.shared.clear()
                    }
                }
            }

            Divider()

            Toggle("Cleanup aktiv", isOn: $state.cleanupEnabled)
                .onChange(of: state.cleanupEnabled) { _, new in
                    UserDefaults.standard.set(new, forKey: "cleanupEnabled")
                }

            if state.cleanupEnabled {
                Picker("Format", selection: $state.formatMode) {
                    ForEach(FormatMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.iconName).tag(mode)
                    }
                }
            }

            Divider()

            Button("Einstellungen…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",")

            Divider()
            Button("HermesVoice beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var statusLabel: String {
        switch state.status {
        case .loadingModel: state.hasLoadedBefore
                            ? "Modell lädt…"
                            : "Erster Start: optimiere für Neural Engine (~5–10 min, einmalig)"
        case .idle:         "Bereit · ⌘⇧Space toggle · ⌃Space halten · ⌘⇧⌃V Command"
        case .recording:    "● Aufnahme läuft"
        case .transcribing: "Transkribiere…"
        case .cleaning:     "Glätte Text…"
        case .error(let m): "Fehler: \(m)"
        }
    }
}
