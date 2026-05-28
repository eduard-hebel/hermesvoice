import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import OSLog

/// Voice-Command: User markiert Text, drückt ⌘⇧⌃V, sagt einen Befehl
/// ("mach kürzer", "übersetze ins Englische"), drückt nochmal — der
/// markierte Text wird via Claude transformiert und ersetzt.
@MainActor
final class VoiceCommandController {
    static let shared = VoiceCommandController()
    private static let log = Logger(subsystem: "de.hermes.voice", category: "VoiceCommand")

    private let recorder = AudioRecorder()
    // Geteilte Pipeline mit dem Diktat-Pfad — eigenes Modell wäre nie geladen worden
    // (→ noPipeline) und würde auf 8 GB RAM den Speicher sprengen.
    private let transcriber = Transcriber.shared
    private let inserter = TextInserter()

    private var capturedSelection: String = ""
    private var isRecording = false
    private var isProcessing = false

    private init() {}

    func toggle() async {
        if isProcessing {
            Self.log.info("Already processing — ignore")
            return
        }
        if isRecording {
            await stop()
        } else {
            await start()
        }
    }

    private func start() async {
        Self.log.info("Voice-Command start — reading selection")
        capturedSelection = readSelectedText() ?? ""
        if capturedSelection.isEmpty {
            Self.log.info("No selection — falling back to clipboard")
            capturedSelection = NSPasteboard.general.string(forType: .string) ?? ""
        }
        guard !capturedSelection.isEmpty else {
            Self.log.warning("No selection and no clipboard — abort")
            postSimpleNotification(title: "Voice-Command", body: "Erst Text markieren, dann ⌘⇧⌃V.")
            return
        }
        Self.log.info("Captured selection (\(self.capturedSelection.count) chars)")

        do {
            AudioMeter.shared.reset()
            try await recorder.start()
            isRecording = true
            SoundService.play(.start)
            RecordingHUDController.shared.update(status: .recording)
        } catch {
            Self.log.error("recorder.start failed: \(error.localizedDescription)")
            SoundService.play(.error)
        }
    }

    private func stop() async {
        Self.log.info("Voice-Command stop — transcribing command")
        isRecording = false
        isProcessing = true
        SoundService.play(.stop)
        RecordingHUDController.shared.update(status: .transcribing)

        do {
            let audioURL = try await recorder.stop()
            let command = try await transcriber.transcribe(audioURL: audioURL, language: "de")
            Self.log.info("Command: \(command, privacy: .public)")

            guard !command.isEmpty else {
                Self.log.warning("Empty command — abort")
                isProcessing = false
                RecordingHUDController.shared.update(status: .idle)
                return
            }

            RecordingHUDController.shared.update(status: .cleaning)
            let result = try await runClaudeCommand(text: capturedSelection, command: command)
            Self.log.info("Result (\(result.count) chars)")

            // Ergebnis ins Clipboard + ⌘V simulieren → ersetzt die Selection
            inserter.insert(result)
            NotificationService.shared.showTranscript(result, insertedSuccessfully: true)
        } catch {
            Self.log.error("Voice-Command failed: \(error.localizedDescription)")
            SoundService.play(.error)
            postSimpleNotification(title: "Voice-Command Fehler", body: error.localizedDescription)
        }

        isProcessing = false
        RecordingHUDController.shared.update(status: .idle)
    }

    private func runClaudeCommand(text: String, command: String) async throws -> String {
        let prompt = """
        Du bekommst einen Text und einen Befehl. Wende den Befehl auf den Text an. \
        Gib NUR den modifizierten Text zurück — keine Anführungszeichen, kein Kommentar, kein Vor- oder Nachwort.

        Befehl: \(command)

        Text:
        \(text)
        """

        // Modell in den Einstellungen umschaltbar (Default: Sonnet — besseres
        // Kontextverständnis für Transformationen wie „mach kürzer", „übersetze").
        // Läuft über den gemeinsamen Runner: off-main + kein Pipe-Deadlock bei
        // großen Selektionen (Output > 64 KB).
        return try await ClaudeCLI.shared.run(prompt: prompt, model: ClaudeModel.voiceCommand())
    }

    /// Liest die aktuelle Text-Selection des fokussierten UI-Elements via AX-API.
    /// Funktioniert in den meisten Native-/Electron-Apps; manche (z.B. Web-Browser)
    /// blockieren das. Fallback: Clipboard.
    private func readSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let r1 = AXUIElementCopyAttributeValue(systemWide,
                                               kAXFocusedUIElementAttribute as CFString,
                                               &focused)
        guard r1 == .success, focused != nil else { return nil }
        let focusedEl = focused as! AXUIElement

        var selected: AnyObject?
        let r2 = AXUIElementCopyAttributeValue(focusedEl,
                                               kAXSelectedTextAttribute as CFString,
                                               &selected)
        guard r2 == .success, let text = selected as? String, !text.isEmpty else { return nil }
        return text
    }

    private func postSimpleNotification(title: String, body: String) {
        Task { @MainActor in
            NotificationService.shared.showTranscript("\(title)\n\(body)", insertedSuccessfully: false)
        }
    }
}
