import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "de.hermes.voice", category: "AppState")

enum DictationStatus: Equatable {
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
    var formatMode: FormatMode = {
        guard let raw = UserDefaults.standard.string(forKey: "formatMode"),
              let mode = FormatMode(rawValue: raw) else { return .free }
        return mode
    }() {
        didSet { UserDefaults.standard.set(formatMode.rawValue, forKey: "formatMode") }
    }
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
        let hk = HotkeyController.shared
        hk.onToggle = { [weak self] in
            Task { @MainActor in await self?.toggle() }
        }
        hk.onPushToTalkDown = { [weak self] in
            Task { @MainActor in await self?.pushToTalkDown() }
        }
        hk.onPushToTalkUp = { [weak self] in
            Task { @MainActor in await self?.pushToTalkUp() }
        }
        hk.onVoiceCommandToggle = { [weak self] in
            Task { @MainActor in await self?.voiceCommandToggle() }
        }
    }

    /// Push-to-Talk DOWN: starte Aufnahme, falls idle.
    func pushToTalkDown() async {
        if case .idle = status { await toggle() }
    }

    /// Push-to-Talk UP: stoppe Aufnahme, falls recording.
    func pushToTalkUp() async {
        if case .recording = status { await toggle() }
    }

    /// Voice-Command (Selection wird mit Sprachbefehl modifiziert).
    /// Toggle wie Diktat — erst aufnehmen, dann Befehl an Claude.
    func voiceCommandToggle() async {
        // Implementiert in VoiceCommandController, hier nur Delegation
        await VoiceCommandController.shared.toggle()
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
        MediaController.pauseIfPlaying()
        do {
            try await recorder.start()
            status = .recording
            SoundService.play(.start)
            log.info("startRecording() success — engine running")
        } catch {
            log.error("startRecording() failed: \(error.localizedDescription)")
            SoundService.play(.error)
            status = .error("Mic-Start: \(error.localizedDescription)")
        }
    }

    private func stopAndProcess() async {
        log.info("stopAndProcess() begin")
        SoundService.play(.stop)
        do {
            status = .transcribing
            let audioURL = try await recorder.stop()
            log.info("Recording stopped, file at \(audioURL.path)")
            var text = try await transcriber.transcribe(audioURL: audioURL, language: languageHint)
            log.info("Transcribed (\(text.count) chars): \(text.prefix(80), privacy: .public)")

            // Stiller-Fehler-Schutz: bei leerem Ergebnis hörbar/sichtbar Bescheid geben
            // statt stumm durchzulaufen (kein Insert, kein History-Eintrag, kein
            // Clipboard-Overwrite). Verhindert den "App ist kaputt"-Eindruck.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                log.warning("Empty transcription — signalling user")
                SoundService.play(.error)
                status = .error("Nichts erkannt — nochmal?")
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                status = .idle
                return
            }

            if cleanupEnabled, !text.isEmpty {
                status = .cleaning
                let currentMode = formatMode
                let rawTranscript = text
                text = (try? await cleanup.polish(text, mode: currentMode)) ?? text
                // Auto-Learning: Diff zwischen Roh-Whisper-Output und Claude-Cleanup
                // wird als Vocab-Wissen gespeichert.
                VocabularyStore.shared.learn(raw: rawTranscript, cleaned: text)
                log.info("Cleanup done (mode: \(currentMode.rawValue, privacy: .public))")
            }

            lastTranscript = text
            HistoryStore.shared.add(text: text, mode: formatMode)
            let inserted = inserter.insert(text)
            log.info("Insert result — pasted: \(inserted, privacy: .public)")
            NotificationService.shared.showTranscript(text, insertedSuccessfully: inserted)
            status = .idle
        } catch {
            log.error("stopAndProcess() failed: \(error.localizedDescription)")
            SoundService.play(.error)
            status = .error(error.localizedDescription)
        }
    }
}
