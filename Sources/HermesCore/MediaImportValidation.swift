import Foundation

struct MediaMetadata: Equatable {
    let duration: TimeInterval
    let hasAudio: Bool
}

struct MediaSegment: Equatable {
    let index: Int
    let start: TimeInterval
    let duration: TimeInterval
}

enum MediaSegmentPlan {
    static func segments(duration: TimeInterval, maximumDuration: TimeInterval = 600) -> [MediaSegment] {
        guard duration > 0, maximumDuration > 0 else { return [] }

        var result: [MediaSegment] = []
        var start: TimeInterval = 0
        var index = 0
        while start < duration {
            let remaining = duration - start
            result.append(
                MediaSegment(
                    index: index,
                    start: start,
                    duration: min(maximumDuration, remaining)
                )
            )
            start += maximumDuration
            index += 1
        }
        return result
    }
}

enum MediaImportError: Error, Equatable, LocalizedError {
    case unsupportedFormat(String)
    case unreadableMedia
    case missingAudioTrack
    case durationExceeded(maximum: TimeInterval)
    case insufficientStorage(required: Int64, available: Int64)
    case exportFailed
    case emptyTranscript
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(fileExtension):
            return "Das Format .\(fileExtension) wird nicht unterstützt."
        case .unreadableMedia:
            return "Die Mediendatei konnte nicht gelesen werden."
        case .missingAudioTrack:
            return "Die Datei enthält keine Tonspur."
        case let .durationExceeded(maximum):
            return "Die Datei ist länger als \(Int(maximum / 60)) Minuten."
        case let .insufficientStorage(required, available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "Zu wenig freier Speicher. Benötigt: \(formatter.string(fromByteCount: required)), frei: \(formatter.string(fromByteCount: available))."
        case .exportFailed:
            return "Die Tonspur konnte nicht vorbereitet werden."
        case .emptyTranscript:
            return "In der Datei wurde keine Sprache erkannt."
        case .cancelled:
            return "Der Import wurde abgebrochen."
        }
    }
}

struct MediaImportValidator {
    static let maximumDuration: TimeInterval = 3_600
    static let supportedExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "m4v", "mov", "mp3", "mp4", "mpeg", "mpg",
        "oga", "ogg", "opus", "wav",
    ]

    func validate(
        fileURL: URL,
        metadata: MediaMetadata,
        fileSize: Int64,
        availableBytes: Int64
    ) throws {
        let fileExtension = fileURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(fileExtension) else {
            throw MediaImportError.unsupportedFormat(fileExtension.isEmpty ? "unbekannt" : fileExtension)
        }
        guard metadata.duration.isFinite, metadata.duration > 0 else {
            throw MediaImportError.unreadableMedia
        }
        guard metadata.hasAudio else {
            throw MediaImportError.missingAudioTrack
        }
        guard metadata.duration <= Self.maximumDuration else {
            throw MediaImportError.durationExceeded(maximum: Self.maximumDuration)
        }

        let doubledSize = fileSize.multipliedReportingOverflow(by: 2)
        let requiredBytes = doubledSize.overflow
            ? Int64.max
            : max(200_000_000, doubledSize.partialValue)
        guard availableBytes >= requiredBytes else {
            throw MediaImportError.insufficientStorage(required: requiredBytes, available: availableBytes)
        }
    }
}
