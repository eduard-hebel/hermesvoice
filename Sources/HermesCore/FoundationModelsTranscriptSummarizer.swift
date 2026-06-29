#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct GeneratedTranscriptSummary {
    @Guide(description: "Ein kurzer deutscher Absatz mit der wichtigsten Aussage")
    var paragraph: String

    @Guide(description: "Höchstens fünf kurze Kernpunkte auf Deutsch")
    var keyPoints: [String]
}

@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelsTranscriptSummarizer: TranscriptSummarizing {
    func summarize(_ transcript: String) async throws -> ImportSummary {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw CocoaError(.featureUnsupported)
        }

        let chunks = TranscriptChunker.chunks(transcript)
        guard !chunks.isEmpty else {
            throw MediaImportError.emptyTranscript
        }

        var partials: [GeneratedTranscriptSummary] = []
        for chunk in chunks {
            try Task.checkCancellation()
            partials.append(try await generateSummary(for: chunk, model: model))
        }

        let finalSummary: GeneratedTranscriptSummary
        if partials.count == 1 {
            finalSummary = partials[0]
        } else {
            let condensedInput = partials.map { partial in
                ([partial.paragraph] + partial.keyPoints).joined(separator: "\n")
            }.joined(separator: "\n\n")
            finalSummary = try await generateSummary(for: condensedInput, model: model)
        }

        let paragraph = finalSummary.paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyPoints = finalSummary.keyPoints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(5)
        guard !paragraph.isEmpty else {
            throw MediaImportError.emptyTranscript
        }
        return ImportSummary(text: paragraph, keyPoints: Array(keyPoints), generatedAt: .now)
    }

    private func generateSummary(
        for text: String,
        model: SystemLanguageModel
    ) async throws -> GeneratedTranscriptSummary {
        let session = LanguageModelSession(
            model: model,
            instructions: """
            Fasse Transkripte sachlich auf Deutsch zusammen. Erfinde keine Fakten. \
            Gib einen kurzen Absatz und höchstens fünf knappe Kernpunkte aus.
            """
        )
        let response = try await session.respond(
            to: "Fasse dieses Transkript zusammen:\n\n\(text)",
            generating: GeneratedTranscriptSummary.self
        )
        return response.content
    }
}
#endif
