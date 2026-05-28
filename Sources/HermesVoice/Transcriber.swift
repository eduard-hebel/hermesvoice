import Foundation
import OSLog
import CoreML
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
            // computeOptions: CPU+GPU statt der WhisperKit-Defaults (Encoder/Decoder = ANE).
            // Die ANE braucht einen einmaligen AOT-Kaltkompile (5–15 min), der fragil ist und
            // bei jedem OS-Update neu anfällt — genau das hat die App reproduzierbar zum
            // Hängen gebracht. Der GPU-Pfad (Metal) kompiliert in Sekunden und cacht sauber;
            // bei Diktat-Längen ist der Speed-Unterschied vernachlässigbar.
            // prewarm+load: ohne sie würde `WhisperKit(model:)` (Convenience) nur setupModels
            // (Dateien lokalisieren) machen — `load ?? (modelFolder != nil)` = false — und das
            // eigentliche Laden erst beim ersten transcribe() nachholen, das dort in den
            // 180s-Timeout (AppState.transcriptionTimeout) liefe. Mit prewarm+load ist das
            // Modell schon im .loadingModel-Status fertig.
            let config = WhisperKitConfig(
                model: name,
                computeOptions: ModelComputeOptions(
                    melCompute: .cpuAndGPU,
                    audioEncoderCompute: .cpuAndGPU,
                    textDecoderCompute: .cpuAndGPU
                ),
                prewarm: true,
                load: true
            )
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
