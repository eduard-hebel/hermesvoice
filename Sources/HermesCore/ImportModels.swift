import Foundation

enum ImportSource: String, Codable, Equatable {
    case file
    case photoLibrary
    case shareExtension
}

enum ImportPhase: Equatable {
    case idle
    case waitingForSpeechEngine
    case validating
    case preparing(current: Int, total: Int)
    case transcribing(current: Int, total: Int)
    case saving
    case completed(UUID)
    case failed(String)
}

struct ImportSummary: Codable, Equatable {
    let text: String
    let keyPoints: [String]
    let generatedAt: Date
}

struct ImportItem: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let source: ImportSource
    let originalFilename: String
    let duration: TimeInterval
    let transcript: String
    var summary: ImportSummary?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: ImportSource,
        originalFilename: String,
        duration: TimeInterval,
        transcript: String,
        summary: ImportSummary? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.originalFilename = originalFilename
        self.duration = duration
        self.transcript = transcript
        self.summary = summary
    }
}
