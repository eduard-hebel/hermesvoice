import SwiftUI
import AVFoundation
import AppKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Willkommen bei HermesVoice")
                    .font(.title2.bold())
                Spacer()
                Text("\(step + 1) / 5")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(24)

            Divider()

            // Step content
            Group {
                switch step {
                case 0: welcome
                case 1: microphone
                case 2: inputMonitoring
                case 3: accessibility
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)

            Divider()

            // Footer
            HStack {
                if step > 0 {
                    Button("Zurück") { step -= 1 }
                }
                Spacer()
                if step < 4 {
                    Button("Weiter") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Loslegen") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        dismiss()
                        NSApp.windows.first(where: { $0.title.contains("Willkommen") })?.close()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 460)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 16)

            Text("Sprich, statt zu tippen — überall auf deinem Mac.")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                Label("Drück ⌘⇧Space, sprich, drück nochmal — Text landet wo dein Cursor steht.", systemImage: "1.circle.fill")
                Label("Läuft 100% lokal auf der Neural Engine — keine Cloud, keine Kosten.", systemImage: "2.circle.fill")
                Label("Optional: Claude räumt Versprecher und Akronyme auf.", systemImage: "3.circle.fill")
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: micGranted ? "checkmark.circle.fill" : "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(micGranted ? Color.green : Color.accentColor)
                .padding(.top, 16)

            Text("Mikrofon-Zugriff")
                .font(.title3.bold())

            Text(micGranted
                 ? "Schon erlaubt — keine Aktion nötig."
                 : "Klick unten auf den Button, dann erlaubt macOS HermesVoice den Mikrofon-Zugriff. Audio wird ausschließlich lokal verarbeitet.")
                .foregroundStyle(.secondary)

            if !micGranted {
                Button("Mikrofon-Zugriff anfragen") {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        Task { @MainActor in micGranted = granted }
                    }
                }
                .controlSize(.large)
            }

            Spacer()
        }
    }

    private var inputMonitoring: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .padding(.top, 16)

            Text("Eingabeüberwachung")
                .font(.title3.bold())

            Text("Damit der Global-Hotkey ⌘⇧Space überall funktioniert, braucht HermesVoice die Berechtigung Eingabeüberwachung.")
                .foregroundStyle(.secondary)

            Button("Systemeinstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
            .controlSize(.large)

            Text("In der Liste HermesVoice anhaken. Falls nicht da → Plus-Button → HermesVoice.app aus /Programme.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .padding(.top, 16)

            Text("Bedienungshilfen")
                .font(.title3.bold())

            Text("Damit der transkribierte Text per ⌘V automatisch eingefügt wird, braucht HermesVoice die Bedienungshilfen-Berechtigung.")
                .foregroundStyle(.secondary)

            Button("Systemeinstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .controlSize(.large)

            Text("Auch ohne diese Berechtigung kommt dein Text ins Clipboard — du musst ihn dann selbst mit ⌘V einfügen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .padding(.top, 16)

            Text("Du bist startklar!")
                .font(.title3.bold())

            Text("Drück jetzt ⌘⇧Space, sag was, und drück nochmal ⌘⇧Space. Beim ersten Diktat kompiliert das Modell einmalig für die Neural Engine (ein paar Minuten) — danach ist es blitzschnell.")
                .foregroundStyle(.secondary)

            Text("Einstellungen findest du oben rechts im Menubar-Mikrofon-Icon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()
        }
    }
}
