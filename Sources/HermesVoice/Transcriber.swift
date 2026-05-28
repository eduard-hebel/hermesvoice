import Foundation
import OSLog
import WhisperKit

actor Transcriber {
    private static let log = Logger(subsystem: "de.hermes.voice", category: "Transcriber")
    private var pipeline: WhisperKit?

    func preloadModel(name: String) async {
        do {
            pipeline = try await WhisperKit(model: name)
            Self.log.notice("WhisperKit model loaded: \(name, privacy: .public)")
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
