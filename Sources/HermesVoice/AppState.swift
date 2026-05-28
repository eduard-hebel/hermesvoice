import Foundation
import Observation

enum DictationStatus {
    case loadingModel       // Erstmaliger ANE-Compile, kann 5–10 min dauern
    case idle
    case recording
    case transcribing
    case cleaning
    case error(String)

    var iconName: String {
        switch self {
        case .loadingModel: "arrow.down.circle.dotted"
        case .idle:         "mic.fill"
        case .recording:    "mic.circle.fill"
        case .transcribing: "waveform.circle.fill"
        case .cleaning:     "sparkles"
        case .error:        "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var status: DictationStatus = .loadingModel
    var lastTranscript: String = ""
    var cleanupEnabled: Bool = UserDefaults.standard.bool(forKey: "cleanupEnabled")
    var modelName: String = UserDefaults.standard.string(forKey: "modelName") ?? "large-v3-v20240930_626MB"
    var languageHint: String = UserDefaults.standard.string(forKey: "languageHint") ?? "de"
    /// Zeigt an, ob das Modell schon mal erfolgreich geladen wurde (ANE-Cache vorhanden).
    var hasLoadedBefore: Bool = UserDefaults.standard.bool(forKey: "hasLoadedBefore")

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let inserter = TextInserter()
    private let cleanup = CleanupService()

    init() {
        Task { @MainActor in
            await transcriber.preloadModel(name: modelName)
            status = .idle
            if !hasLoadedBefore {
                hasLoadedBefore = true
                UserDefaults.standard.set(true, forKey: "hasLoadedBefore")
            }
        }
        registerHotkey()
    }

    func registerHotkey() {
        // Wird in HotkeyController umgesetzt
        HotkeyController.shared.onToggle = { [weak self] in
            Task { @MainActor in await self?.toggle() }
        }
    }

    func toggle() async {
        switch status {
        case .idle:    await startRecording()
        case .recording: await stopAndProcess()
        default: break // während Verarbeitung kein Toggle
        }
    }

    private func startRecording() async {
        do {
            try await recorder.start()
            status = .recording
        } catch {
            status = .error("Mic-Start: \(error.localizedDescription)")
        }
    }

    private func stopAndProcess() async {
        do {
            status = .transcribing
            let audioURL = try await recorder.stop()
            var text = try await transcriber.transcribe(audioURL: audioURL, language: languageHint)

            if cleanupEnabled, !text.isEmpty {
                status = .cleaning
                text = (try? await cleanup.polish(text)) ?? text
            }

            lastTranscript = text
            inserter.insert(text)
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}
