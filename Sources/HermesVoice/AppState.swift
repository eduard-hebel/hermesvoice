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
    /// Whisper-Modell. Wechsel in den Einstellungen wird persistiert UND die Pipeline
    /// neu geladen — sonst bliebe die Auswahl wirkungslos (altes Modell weiter aktiv).
    var modelName: String = UserDefaults.standard.string(forKey: "modelName") ?? "large-v3-v20240930_turbo_632MB" {
        didSet {
            guard modelName != oldValue else { return }
            UserDefaults.standard.set(modelName, forKey: "modelName")
            reloadModel()
        }
    }
    /// Sprach-Hinweis. Greift pro Transkription, muss aber persistiert werden, sonst
    /// fällt er bei jedem Neustart auf "de" zurück.
    var languageHint: String = UserDefaults.standard.string(forKey: "languageHint") ?? "de" {
        didSet {
            guard languageHint != oldValue else { return }
            UserDefaults.standard.set(languageHint, forKey: "languageHint")
        }
    }
    var formatMode: FormatMode = {
        guard let raw = UserDefaults.standard.string(forKey: "formatMode"),
              let mode = FormatMode(rawValue: raw) else { return .free }
        return mode
    }() {
        didSet { UserDefaults.standard.set(formatMode.rawValue, forKey: "formatMode") }
    }
    /// Claude-Modell für die Cleanup-Stage — in den Einstellungen umschaltbar.
    var cleanupModel: ClaudeModel = ClaudeModel.cleanup() {
        didSet { UserDefaults.standard.set(cleanupModel.rawValue, forKey: ClaudeModel.cleanupKey) }
    }
    /// Claude-Modell für Voice-Command-Transformationen — in den Einstellungen umschaltbar.
    var voiceCommandModel: ClaudeModel = ClaudeModel.voiceCommand() {
        didSet { UserDefaults.standard.set(voiceCommandModel.rawValue, forKey: ClaudeModel.voiceCommandKey) }
    }
    /// Zeigt an, ob das Modell schon mal erfolgreich geladen wurde (ANE-Cache vorhanden).
    var hasLoadedBefore: Bool = UserDefaults.standard.bool(forKey: "hasLoadedBefore")

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber.shared
    private let inserter = TextInserter()
    private let cleanup = CleanupService()
    private let operationCoordinator = SpeechOperationCoordinator.shared
    private var operationToken: UUID?

    /// Laufender Verarbeitungs-Task (Transcribe → Cleanup → Insert), abbrechbar via X im HUD.
    private var processingTask: Task<Void, Never>?

    /// User hat X während Transkription gedrückt. WhisperKit honoriert Task-Cancellation
    /// NICHT (läuft im Hintergrund weiter), daher dieses Flag: das HUD wird sofort
    /// freigegeben und das (verspätete) Transkriptions-Ergebnis verworfen.
    private var aborted = false

    /// Maximaldauer einer Transkription, bevor sie als „hängt" gilt (Speicher-Druck o.ä.).
    /// Danach: HUD freigeben, Audio bleibt erhalten, Hinweis auf Neu-Transkribieren.
    private static let transcriptionTimeout: UInt64 = 180  // Sekunden

    private enum ProcessingError: Error { case transcriptionTimeout }

    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            status = .idle
            return
        }
        let token: UUID
        do {
            token = try operationCoordinator.begin(.modelLoading)
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        Task { @MainActor in
            defer { operationCoordinator.end(token) }
            log.notice("Preloading Whisper model: \(self.modelName, privacy: .public)")
            await transcriber.preloadModel(name: modelName)
            status = .idle
            log.notice("Ready — status idle")
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

        // X im HUD → laufende Operation abbrechen
        RecordingHUDController.shared.onCancel = { [weak self] in
            self?.cancelCurrent()
        }
    }

    /// Lädt das Whisper-Modell nach einem Modellwechsel in den Einstellungen neu.
    /// Während einer laufenden Operation wird verschoben (greift beim nächsten Start —
    /// der neue Name ist bereits persistiert). Die alte Pipeline wird in preloadModel
    /// zuerst freigegeben, damit auf 8 GB RAM nie zwei Modelle gleichzeitig leben.
    private func reloadModel() {
        switch status {
        case .recording, .transcribing, .cleaning:
            log.notice("Model change deferred — busy, applies on next launch")
            return
        default:
            break
        }
        let name = modelName
        Task { @MainActor in
            let token: UUID
            do {
                token = try await operationCoordinator.acquire(.modelLoading)
            } catch {
                log.notice("Model change cancelled while waiting for another speech operation")
                return
            }
            defer { operationCoordinator.end(token) }
            log.notice("Reloading Whisper model: \(name, privacy: .public)")
            status = .loadingModel
            await transcriber.preloadModel(name: name)
            status = .idle
            log.notice("Model reloaded — status idle")
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
        do {
            operationToken = try operationCoordinator.begin(.dictation)
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        MediaController.pauseIfPlaying()
        AudioMeter.shared.reset()   // frischer Pegel — kein kurzes Aufblitzen des alten Werts
        do {
            try await recorder.start()
            status = .recording
            SoundService.play(.start)
            log.info("startRecording() success — engine running")
        } catch {
            releaseOperation()
            log.error("startRecording() failed: \(error.localizedDescription)")
            SoundService.play(.error)
            status = .error("Mic-Start: \(error.localizedDescription)")
        }
    }

    /// Bricht die aktuelle Operation ab (X im HUD). Verhält sich kontextabhängig:
    /// - während Aufnahme: Aufnahme verwerfen
    /// - während Transkribieren/Glätten: Verarbeitung abbrechen (bei Cleanup wird der
    ///   bereits erkannte Rohtext eingefügt, damit nichts verloren geht)
    func cancelCurrent() {
        log.notice("cancelCurrent() — status: \(String(describing: self.status))")
        switch status {
        case .recording:
            Task { await discardRecording() }
        case .transcribing:
            // WhisperKit lässt sich nicht mitten im Lauf abbrechen → HUD trotzdem
            // sofort freigeben, Ergebnis später per Flag verwerfen. Audio bleibt erhalten.
            aborted = true
            processingTask?.cancel()
            SoundService.play(.stop)
            status = .idle
        case .cleaning:
            // Cleanup-Subprozess IST abbrechbar → Rohtext wird eingefügt (siehe processAudio).
            processingTask?.cancel()
        default:
            break
        }
    }

    /// Transkription mit Timeout-Wächter: läuft sie länger als `transcriptionTimeout`,
    /// wird `transcriptionTimeout` geworfen, statt das HUD ewig hängen zu lassen.
    /// (WhisperKit selbst läuft im Hintergrund aus; das Ergebnis wird verworfen.)
    private func transcribeWithTimeout(_ audioURL: URL) async throws -> String {
        let t = transcriber
        let lang = languageHint
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await t.transcribe(audioURL: audioURL, language: lang) }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.transcriptionTimeout * 1_000_000_000)
                throw ProcessingError.transcriptionTimeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func discardRecording() async {
        _ = try? await recorder.stop()   // Engine stoppen, Audio verwerfen
        releaseOperation()
        SoundService.play(.stop)
        status = .idle
    }

    private func stopAndProcess() async {
        defer { releaseOperation() }
        log.notice("stopAndProcess() begin")
        SoundService.play(.stop)
        do {
            status = .transcribing
            let audioURL = try await recorder.stop()
            log.notice("Recording stopped, file at \(audioURL.path, privacy: .public)")
            RecordingStore.pruneOld()   // Aufnahme bleibt erhalten, nur alte aufräumen
            let task = Task { await processAudio(at: audioURL) }
            processingTask = task
            await task.value
            processingTask = nil
        } catch {
            log.error("stopAndProcess() failed: \(error.localizedDescription)")
            SoundService.play(.error)
            status = .error(error.localizedDescription)
        }
    }

    /// Transkribiert eine bereits vorhandene Aufnahme erneut — Sicherheitsnetz,
    /// falls die letzte Transkription leer/schlecht war oder die App vorher abstürzte.
    func retranscribeLatest() async {
        guard case .idle = status else {
            log.warning("retranscribeLatest ignored — busy")
            return
        }
        guard let url = RecordingStore.latestRecording else {
            status = .error("Keine Aufnahme vorhanden")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            status = .idle
            return
        }
        do {
            operationToken = try operationCoordinator.begin(.dictation)
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        defer { releaseOperation() }
        log.info("Re-transcribing latest recording: \(url.lastPathComponent)")
        status = .transcribing
        let task = Task { await processAudio(at: url) }
        processingTask = task
        await task.value
        processingTask = nil
    }

    /// Gemeinsame Pipeline: Transcribe → (optional) Cleanup → Insert.
    /// Wird von Live-Stop und Re-Transcribe geteilt.
    private func processAudio(at audioURL: URL) async {
        aborted = false
        do {
            var text = try await transcribeWithTimeout(audioURL)
            log.notice("Transcribed (\(text.count) chars): \(text.prefix(80), privacy: .public)")

            // X während Transkription gedrückt: HUD ist schon frei (status=.idle),
            // Ergebnis verwerfen. Audio bleibt erhalten.
            if aborted {
                log.notice("Aborted by user during transcription — result discarded, audio preserved")
                return
            }

            // Abbruch während/nach Transkription: nichts einfügen, Audio ist gesichert.
            if Task.isCancelled {
                log.notice("Cancelled after transcription — audio preserved, no insert")
                status = .idle
                return
            }

            // Stiller-Fehler-Schutz: bei leerem Ergebnis hörbar/sichtbar Bescheid geben.
            // Die Aufnahme bleibt erhalten — Hinweis nennt die Neu-Transkribieren-Option.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                log.warning("Empty transcription — recording preserved at \(audioURL.lastPathComponent)")
                SoundService.play(.error)
                status = .error("Nichts erkannt — Audio gesichert, ⌘⇧Space-Menü → neu transkribieren")
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                status = .idle
                return
            }

            if cleanupEnabled, !text.isEmpty {
                status = .cleaning
                let currentMode = formatMode
                let rawTranscript = text
                let vocabHint = VocabularyStore.shared.contextHint
                let model = cleanupModel
                do {
                    text = try await cleanup.polish(text, mode: currentMode, vocabHint: vocabHint, model: model)
                    VocabularyStore.shared.learn(raw: rawTranscript, cleaned: text)
                    log.info("Cleanup done (mode: \(currentMode.rawValue, privacy: .public))")
                } catch is CancellationError {
                    // Abbruch während Glätten → Rohtext einfügen, nicht verlieren.
                    log.info("Cleanup cancelled — inserting raw transcript")
                    text = rawTranscript
                } catch {
                    // Anderer Cleanup-Fehler → Fallback auf Rohtext.
                    log.error("Cleanup failed: \(error.localizedDescription) — using raw")
                    text = rawTranscript
                }
            }

            // X während Glätten gedrückt nachdem das HUD frei gemacht wurde: nicht einfügen.
            if aborted {
                log.notice("Aborted by user during cleaning — result discarded")
                return
            }

            lastTranscript = text
            HistoryStore.shared.add(text: text, mode: formatMode)
            let inserted = inserter.insert(text)
            log.notice("Insert result — pasted: \(inserted, privacy: .public)")
            NotificationService.shared.showTranscript(text, insertedSuccessfully: inserted)
            status = .idle
        } catch is ProcessingError {
            // Transkription hängt (Timeout) — HUD freigeben, Audio bleibt erhalten.
            log.error("Transcription timed out after \(Self.transcriptionTimeout)s — audio preserved at \(audioURL.lastPathComponent, privacy: .public)")
            if aborted { return }
            SoundService.play(.error)
            status = .error("Transkription hängt (Speicher knapp?) — Audio gesichert, ⌘⇧Space-Menü → neu transkribieren")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if case .error = status { status = .idle }
        } catch is CancellationError {
            log.notice("Processing cancelled during transcription — audio preserved")
            if !aborted { status = .idle }
        } catch {
            log.error("processAudio() failed: \(error.localizedDescription)")
            SoundService.play(.error)
            status = .error(error.localizedDescription)
        }
    }

    private func releaseOperation() {
        guard let operationToken else { return }
        operationCoordinator.end(operationToken)
        self.operationToken = nil
    }
}
