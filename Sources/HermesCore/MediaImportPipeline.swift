import AVFoundation
import Foundation

struct MediaInspection: Equatable {
    let metadata: MediaMetadata
    let fileSize: Int64
    let availableBytes: Int64
}

protocol MediaInspecting {
    func inspect(_ fileURL: URL) async throws -> MediaInspection
}

protocol MediaSegmenting {
    func segment(
        fileURL: URL,
        segments: [MediaSegment],
        outputDirectory: URL,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [URL]
}

protocol MediaTranscribing {
    func transcribeMedia(
        audioURLs: [URL],
        language: String,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [String]
}

@MainActor
final class MediaImportPipeline {
    private let inspector: any MediaInspecting
    private let segmenter: any MediaSegmenting
    private let transcriber: any MediaTranscribing
    private let validator: MediaImportValidator
    private let temporaryRootURL: URL

    init(
        inspector: any MediaInspecting = AVMediaInspector(),
        segmenter: any MediaSegmenting = AVMediaSegmenter(),
        transcriber: any MediaTranscribing = Transcriber.shared,
        validator: MediaImportValidator = MediaImportValidator(),
        temporaryRootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesVoiceImports", isDirectory: true)
    ) {
        self.inspector = inspector
        self.segmenter = segmenter
        self.transcriber = transcriber
        self.validator = validator
        self.temporaryRootURL = temporaryRootURL
    }

    func process(
        fileURL: URL,
        source: ImportSource,
        originalFilename: String,
        language: String,
        onPhase: @escaping @MainActor (ImportPhase) -> Void
    ) async throws -> ImportItem {
        let processDirectory = temporaryRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRootURL) }

        do {
            try Task.checkCancellation()
            onPhase(.validating)
            let inspection = try await inspector.inspect(fileURL)
            try validator.validate(
                fileURL: fileURL,
                metadata: inspection.metadata,
                fileSize: inspection.fileSize,
                availableBytes: inspection.availableBytes
            )

            let plan = MediaSegmentPlan.segments(duration: inspection.metadata.duration)
            onPhase(.preparing(current: 0, total: plan.count))
            let audioURLs = try await segmenter.segment(
                fileURL: fileURL,
                segments: plan,
                outputDirectory: processDirectory
            ) { current, total in
                onPhase(.preparing(current: current, total: total))
            }

            try Task.checkCancellation()
            onPhase(.transcribing(current: 0, total: audioURLs.count))
            let transcribedParts = try await transcriber.transcribeMedia(
                audioURLs: audioURLs,
                language: language
            ) { current, total in
                onPhase(.transcribing(current: current, total: total))
            }
            try Task.checkCancellation()
            let transcriptParts = transcribedParts.compactMap { part -> String? in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            try Task.checkCancellation()
            let transcript = transcriptParts.joined(separator: "\n\n")
            guard !transcript.isEmpty else {
                throw MediaImportError.emptyTranscript
            }

            return ImportItem(
                source: source,
                originalFilename: originalFilename,
                duration: inspection.metadata.duration,
                transcript: transcript
            )
        } catch is CancellationError {
            throw MediaImportError.cancelled
        }
    }
}

struct AVMediaInspector: MediaInspecting {
    func inspect(_ fileURL: URL) async throws -> MediaInspection {
        let asset = AVURLAsset(url: fileURL)
        do {
            let duration = try await asset.load(.duration)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let fileValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let capacityValues = try FileManager.default.temporaryDirectory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            return MediaInspection(
                metadata: MediaMetadata(duration: duration.seconds, hasAudio: !audioTracks.isEmpty),
                fileSize: Int64(fileValues.fileSize ?? 0),
                availableBytes: capacityValues.volumeAvailableCapacityForImportantUsage ?? Int64.max
            )
        } catch let error as MediaImportError {
            throw error
        } catch {
            throw MediaImportError.unreadableMedia
        }
    }
}

struct AVMediaSegmenter: MediaSegmenting {
    func segment(
        fileURL: URL,
        segments: [MediaSegment],
        outputDirectory: URL,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: fileURL)
        var outputURLs: [URL] = []

        for segment in segments {
            try Task.checkCancellation()
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw MediaImportError.exportFailed
            }
            let outputURL = outputDirectory.appendingPathComponent(
                String(format: "part-%03d.m4a", segment.index)
            )
            exporter.timeRange = CMTimeRange(
                start: CMTime(seconds: segment.start, preferredTimescale: 600),
                duration: CMTime(seconds: segment.duration, preferredTimescale: 600)
            )

            try await export(exporter, to: outputURL)
            outputURLs.append(outputURL)
            await progress(segment.index + 1, segments.count)
        }

        return outputURLs
    }

    private func export(_ exporter: AVAssetExportSession, to outputURL: URL) async throws {
        let box = ExportSessionBox(exporter)

#if os(iOS)
        try await withTaskCancellationHandler {
            try await exporter.export(to: outputURL, as: .m4a)
        } onCancel: {
            box.session.cancelExport()
        }
#elseif os(macOS)
        if #available(macOS 15.0, *) {
            try await withTaskCancellationHandler {
                try await exporter.export(to: outputURL, as: .m4a)
            } onCancel: {
                box.session.cancelExport()
            }
        } else {
            exporter.outputURL = outputURL
            exporter.outputFileType = .m4a
            try await legacyExport(box)
        }
#endif
    }

#if os(macOS)
    private func legacyExport(_ box: ExportSessionBox) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.session.exportAsynchronously {
                    switch box.session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: box.session.error ?? MediaImportError.exportFailed)
                    }
                }
            }
        } onCancel: {
            box.session.cancelExport()
        }
    }
#endif
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

extension Transcriber: MediaTranscribing {
    func transcribeMedia(
        audioURLs: [URL],
        language: String,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [String] {
        try await transcribe(audioURLs: audioURLs, language: language, progress: progress)
    }
}
