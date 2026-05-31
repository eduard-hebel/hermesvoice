import Foundation
import OSLog
import WhisperKit

actor Transcriber {
    /// Geteilte Instanz: Diktat (AppState) UND Voice-Command nutzen DIESELBE geladene
    /// Pipeline. Zwei separate Large-V3-Modelle (~2–3 GB each) würden auf 8 GB RAM den
    /// Speicher sprengen — und Voice-Command lud sein eigenes Modell früher nie, lief
    /// also immer in `noPipeline`.
    static let shared = Transcriber()

    private static let log = Logger(subsystem: "de.hermes.voice", category: "Transcriber")
    private var pipeline: WhisperKit?

    func preloadModel(name: String) async {
        // Alte Pipeline ZUERST freigeben (8 GB RAM — niemals zwei Modelle gleichzeitig
        // im Speicher). Bei Erststart ist das ein No-op, beim Modellwechsel essenziell.
        pipeline = nil
        do {
            // Default-Compute (Encoder/Decoder auf der ANE): auf M1 ~10× schneller als
            // CPU+GPU (RTF ~0.2 vs ~2.9). Der Preis ist ein einmaliger ANE-AOT-Kaltkompile
            // (~9 min beim Erststart bzw. nach OS-Update), der danach gecacht wird.
            // prewarm+load ist hier ESSENZIELL: ohne sie würde `WhisperKit(model:)`
            // (Convenience) nur setupModels (Dateien lokalisieren) machen — `load ??
            // (modelFolder != nil)` = false — und das eigentliche Laden + die ANE-Kompilierung
            // erst beim ersten transcribe() nachholen, das dort in den 180s-Timeout
            // (AppState.transcriptionTimeout) liefe → „hängt". Mit prewarm+load passiert die
            // Kompilierung im .loadingModel-Status OHNE Timeout.
            let config = WhisperKitConfig(model: name, prewarm: true, load: true)
            pipeline = try await WhisperKit(config)
            Self.log.notice("WhisperKit model loaded + prewarmed: \(name, privacy: .public)")
        } catch {
            Self.log.error("WhisperKit preload failed for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func transcribe(audioURL: URL, language: String) async throws -> String {
        // Kein stiller Fallback auf `WhisperKit()` ohne Modell-Argument: das würde das
        // DEFAULT-Modell laden und ggf. einen Download von HuggingFace antreten, der
        // ohne UI-Feedback ewig hängt (HUD bleibt auf „Transkribiere…"). Stattdessen
        // klar fehlschlagen → processAudio sichert das Audio und zeigt einen Hinweis.
        guard let pipe = pipeline else {
            Self.log.error("transcribe() called but no model loaded")
            throw TranscribeError.noPipeline
        }

        // WICHTIG: KEINE promptTokens. Bei langem Audio (mehrere 30s-Fenster) reicht
        // WhisperKit den Prompt an jedes Fenster weiter; das akkumuliert und sprengt
        // Whisper's 448-Token-Context → Decoding bricht ab → 0 chars Totalverlust.
        // Der Akronym-/Vokabel-Fix passiert stattdessen in der Claude-Cleanup-Stage,
        // die das robuster und kontextbewusster macht (siehe CleanupService).
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let texts: [String] = results.map { $0.text }
        return texts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    enum TranscribeError: Error { case noPipeline }
}
