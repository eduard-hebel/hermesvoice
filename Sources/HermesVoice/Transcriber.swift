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

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    enum TranscribeError: Error { case noPipeline }
}
