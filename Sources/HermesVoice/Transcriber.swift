import Foundation
import WhisperKit

actor Transcriber {
    private var pipeline: WhisperKit?

    func preloadModel(name: String) async {
        do {
            pipeline = try await WhisperKit(model: name)
        } catch {
            print("WhisperKit preload failed: \(error)")
        }
    }

    func transcribe(audioURL: URL, language: String) async throws -> String {
        if pipeline == nil { pipeline = try await WhisperKit() }
        guard let pipe = pipeline else { throw TranscribeError.noPipeline }

        // Context-Prompt: konditioniert Whisper auf häufige Begriffe.
        // Akronyme/Fachwörter werden dadurch seltener als Buchstaben-Folgen interpretiert.
        let baseHint = language == "de"
            ? "Diktat auf Deutsch. Technische Begriffe wie HUD, App, API, macOS, GPU, CPU, WiFi, GitHub, ChatGPT, Claude erscheinen als Akronyme."
            : "Dictation in English. Technical terms like HUD, API, macOS, GPU, CPU, WiFi, GitHub, ChatGPT, Claude appear as acronyms."

        // Gelernte Schreibweisen (Auto-Learning aus Cleanup-Diffs) anhängen
        let learnedHint = await MainActor.run { VocabularyStore.shared.contextHint }
        let contextPrompt = baseHint + learnedHint

        var promptTokens: [Int]? = nil
        if let tokenizer = pipe.tokenizer {
            promptTokens = tokenizer.encode(text: contextPrompt)
        }

        // Whisper-Defaults für die Decoding-Schwellwerte verwenden. Strengere Werte
        // (compressionRatio/logProb) hatten legitime, v.a. repetitive Diktate komplett
        // verworfen (0 chars). promptTokens (Context + Auto-Learning) bleiben — die sind
        // unschädlich und hilfreich.
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens
        )
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let texts: [String] = results.map { $0.text }
        return texts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    enum TranscribeError: Error { case noPipeline }
}
