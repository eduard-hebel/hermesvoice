import Foundation
import Observation
import UIKit

/// Schlanker iOS-Diktat-Controller. Nutzt die geteilten HermesCore-Bausteine
/// (AudioRecorder, Transcriber, HistoryStore, AudioMeter), bewusst ohne die
/// Mac-UX-Maschinerie aus AppState (HUD-Abbruch, Hotkeys, Voice-Commands,
/// Cleanup). Pipeline: aufnehmen → on-device transkribieren → Zwischenablage + Verlauf.
@MainActor
@Observable
final class DictationController {
    enum Status: Equatable {
        case loadingModel   // einmaliger Modell-Load/ANE-Kompile beim ersten Start
        case idle
        case recording
        case transcribing
        case error(String)
    }

    var status: Status = .loadingModel
    var lastText: String = ""
    var showCopied = false

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber.shared
    // Auf dem iPhone (8 GB RAM) ist large-v3-turbo zu schwer — der erste ANE-Kompile
    // erdrückt den Speicher und friert die App ein (gleiche Lektion wie auf dem Mac).
    // Small lädt in Sekunden, läuft flott und reicht fürs Diktat. Über UserDefaults
    // ("modelName") jederzeit übersteuerbar (z.B. auf "medium" für bessere Erkennung).
    private let modelName = UserDefaults.standard.string(forKey: "modelName") ?? "small"
    private let languageHint = UserDefaults.standard.string(forKey: "languageHint") ?? "de"

    init() {
        Task { @MainActor in
            await transcriber.preloadModel(name: modelName)
            status = .idle
        }
    }

    /// Nur für SwiftUI-Previews: setzt direkt einen Status, OHNE das Whisper-Modell
    /// zu laden (sonst würde der Xcode-Canvas am Modell-Load hängen).
    init(previewStatus: Status) {
        status = previewStatus
    }

    /// Start/Stop wie auf dem Mac: idle → aufnehmen, recording → verarbeiten.
    func toggle() async {
        switch status {
        case .idle:      await startRecording()
        case .recording: await stopAndProcess()
        default:         break   // während loadingModel/transcribing ignorieren
        }
    }

    private func startRecording() async {
        guard await AudioSessionConfig.ensurePermission() else {
            status = .error("Mikrofon-Zugriff fehlt — in Einstellungen erlauben")
            resetErrorSoon()
            return
        }
        AudioMeter.shared.reset()
        AudioSessionConfig.activate()
        do {
            try await recorder.start()
            showCopied = false
            status = .recording
        } catch {
            AudioSessionConfig.deactivate()
            status = .error("Mikro-Start: \(error.localizedDescription)")
            resetErrorSoon()
        }
    }

    private func stopAndProcess() async {
        status = .transcribing
        do {
            let url = try await recorder.stop()
            AudioSessionConfig.deactivate()
            let text = try await transcriber.transcribe(audioURL: url, language: languageHint)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                status = .error("Nichts erkannt — nochmal versuchen")
                resetErrorSoon()
                return
            }
            lastText = text
            HistoryStore.shared.add(text: text, mode: .free)
            UIPasteboard.general.string = text
            showCopied = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            status = .idle
        } catch {
            AudioSessionConfig.deactivate()
            status = .error(error.localizedDescription)
            resetErrorSoon()
        }
    }

    private func resetErrorSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if case .error = status { status = .idle }
        }
    }
}
