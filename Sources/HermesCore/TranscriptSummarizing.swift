import Foundation
import NaturalLanguage

protocol TranscriptSummarizing {
    func summarize(_ transcript: String) async throws -> ImportSummary
}

enum TranscriptChunker {
    static func chunks(_ transcript: String, maximumCharacters: Int = 6_000) -> [String] {
        guard maximumCharacters > 0 else { return [] }
        let words = transcript.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""
        for word in words {
            if word.count > maximumCharacters {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                var remaining = word[...]
                while remaining.count > maximumCharacters {
                    let end = remaining.index(remaining.startIndex, offsetBy: maximumCharacters)
                    chunks.append(String(remaining[..<end]))
                    remaining = remaining[end...]
                }
                current = String(remaining)
                continue
            }

            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count <= maximumCharacters {
                current = candidate
            } else {
                chunks.append(current)
                current = word
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

struct ResilientTranscriptSummarizer: TranscriptSummarizing {
    let primary: any TranscriptSummarizing
    let fallback: any TranscriptSummarizing

    func summarize(_ transcript: String) async throws -> ImportSummary {
        do {
            return try await primary.summarize(transcript)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.summarize(transcript)
        }
    }
}

struct DefaultTranscriptSummarizer: TranscriptSummarizing {
    private let fallback = ExtractiveTranscriptSummarizer()

    func summarize(_ transcript: String) async throws -> ImportSummary {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await ResilientTranscriptSummarizer(
                primary: FoundationModelsTranscriptSummarizer(),
                fallback: fallback
            ).summarize(transcript)
        }
        #endif
        return try await fallback.summarize(transcript)
    }
}

struct ExtractiveTranscriptSummarizer: TranscriptSummarizing {
    private let maximumKeyPoints: Int

    init(maximumKeyPoints: Int = 5) {
        self.maximumKeyPoints = maximumKeyPoints
    }

    func summarize(_ transcript: String) async throws -> ImportSummary {
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranscript.isEmpty else {
            throw MediaImportError.emptyTranscript
        }

        let sentences = sentenceRanges(in: cleanTranscript).map {
            String(cleanTranscript[$0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        guard sentences.count > 1 else {
            let parts = TranscriptChunker.chunks(cleanTranscript, maximumCharacters: 240)
            let keyPoints = Array(parts.prefix(maximumKeyPoints))
            return ImportSummary(
                text: parts.first ?? cleanTranscript,
                keyPoints: keyPoints,
                generatedAt: .now
            )
        }

        let frequencies = wordFrequencies(in: cleanTranscript)
        let ranked = sentences.enumerated().map { index, sentence in
            let words = normalizedWords(in: sentence)
            let score = words.reduce(0.0) { $0 + Double(frequencies[$1, default: 0]) }
                / Double(max(words.count, 1))
                + (index == 0 ? 0.25 : 0)
            return (index: index, sentence: sentence, score: score)
        }
        .sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }

        let selected = ranked.prefix(min(maximumKeyPoints, sentences.count))
            .sorted { $0.index < $1.index }
            .map { shortened($0.sentence, maximumCharacters: 240) }
        let paragraph = selected.prefix(2).joined(separator: " ")

        return ImportSummary(text: paragraph, keyPoints: selected, generatedAt: .now)
    }

    private func sentenceRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.setLanguage(.german)
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
    }

    private func wordFrequencies(in text: String) -> [String: Int] {
        var frequencies: [String: Int] = [:]
        for word in normalizedWords(in: text) {
            frequencies[word, default: 0] += 1
        }
        return frequencies
    }

    private func normalizedWords(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.german)
        let stopWords: Set<String> = [
            "aber", "auch", "das", "der", "die", "ein", "eine", "einer", "eines", "fuer", "fur", "ist", "mit", "oder", "und", "von", "werden", "wird", "zu",
        ]

        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
            let word = text[range]
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            guard word.count > 2, !stopWords.contains(word) else { return nil }
            return word
        }
    }

    private func shortened(_ text: String, maximumCharacters: Int) -> String {
        TranscriptChunker.chunks(text, maximumCharacters: maximumCharacters).first ?? text
    }
}
