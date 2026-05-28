import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "de.hermes.voice", category: "AppState")

enum DictationStatus {
    case loadingModel       // Erstmaliger ANE-Compile, kann 5–10 min dauern
    case idle
    case recording
    case transcribing
    case cleaning
    case error(String)

    var iconName: String {
        switch self {
        case .loadingModel: "arrow.down.circle"
        case .idle:         "mic.fill"
        case .recording:    "mic.circle.fill"
        case .transcribing: "waveform"
        case .cleaning:     "sparkles"
        case .error:        "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var status: DictationStatus = .loadingModel {
        didSet { RecordingHUDController.shared.update(status: status) }
    }
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
        log.info("toggle() called — current status: \(String(describing: self.status))")
        switch status {
        case .idle:    await startRecording()
        case .recording: await stopAndProcess()
        case .loadingModel:
            log.warning("toggle() ignored — model still loading")
        default:
            log.warning("toggle() ignored — busy: \(String(describing: self.status))")
        }
    }

    private func startRecording() async {
        log.info("startRecording() begin")
        do {
            try await recorder.start()
            status = .recording
            log.info("startRecording() success — engine running")
        } catch {
            log.error("startRecording() failed: \(error.localizedDescription)")
            status = .error("Mic-Start: \(error.localizedDescription)")
        }
    }

    private func stopAndProcess() async {
        log.info("stopAndProcess() begin")
        do {
            status = .transcribing
            let audioURL = try await recorder.stop()
            log.info("Recording stopped, file at \(audioURL.path)")
            var text = try await transcriber.transcribe(audioURL: audioURL, language: languageHint)
            log.info("Transcribed (\(text.count) chars): \(text.prefix(80), privacy: .public)")

            if cleanupEnabled, !text.isEmpty {
                status = .cleaning
                text = (try? await cleanup.polish(text)) ?? text
                log.info("Cleanup done")
            }

            lastTranscript = text
            let inserted = inserter.insert(text)
            log.info("Insert result — pasted: \(inserted, privacy: .public)")
            NotificationService.shared.showTranscript(text, insertedSuccessfully: inserted)
            status = .idle
        } catch {
            log.error("stopAndProcess() failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
        }
    }
}
