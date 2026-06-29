import Foundation
import XCTest
@testable import HermesVoice

@MainActor
final class ImportCoreTests: XCTestCase {
    func testActionFeedbackCenterReplacesAndDismissesCurrentFeedback() {
        let center = ActionFeedbackCenter(automaticDismissal: false)

        center.show("Transkript kopiert", systemImage: "doc.on.doc", kind: .success)
        let firstID = center.current?.id
        center.show("Import gelöscht", systemImage: "trash", kind: .destructive)

        XCTAssertNotEqual(center.current?.id, firstID)
        XCTAssertEqual(center.current?.message, "Import gelöscht")
        XCTAssertEqual(center.current?.kind, .destructive)

        center.dismissCurrent()
        XCTAssertNil(center.current)
    }

    func testImportItemRoundTripsThroughJSON() throws {
        let item = ImportItem(
            id: UUID(uuidString: "E00E782E-765A-4B89-9E04-1B8D3E850A24")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .shareExtension,
            originalFilename: "voice-message.m4a",
            duration: 42,
            transcript: "Hallo aus HermesVoice.",
            summary: ImportSummary(
                text: "Eine kurze Begruessung.",
                keyPoints: ["HermesVoice wurde begruesst."],
                generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ImportItem.self, from: data)

        XCTAssertEqual(decoded, item)
    }

    func testImportStorePersistsEntriesSeparately() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("imports.json")
        let item = ImportItem(
            source: .file,
            originalFilename: "meeting.wav",
            duration: 90,
            transcript: "Besprechungstext"
        )

        let writer = ImportStore(fileURL: fileURL)
        try writer.add(item)
        let reader = ImportStore(fileURL: fileURL)

        XCTAssertEqual(reader.entries, [item])
    }

    func testImportStoreUpdatesSummaryAndDeletesEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("imports.json")
        let item = ImportItem(
            source: .file,
            originalFilename: "meeting.wav",
            duration: 90,
            transcript: "Besprechungstext"
        )
        let summary = ImportSummary(
            text: "Kurze Besprechung.",
            keyPoints: ["Ein Kernpunkt"],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let store = ImportStore(fileURL: fileURL)
        try store.add(item)
        try store.setSummary(summary, for: item.id)

        XCTAssertEqual(store.entries.first?.summary, summary)

        try store.remove(id: item.id)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(ImportStore(fileURL: fileURL).entries.isEmpty)
    }

    func testImportStoreReplacesAnExistingItemInsteadOfDuplicatingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("imports.json")
        let id = UUID()
        let first = ImportItem(
            id: id,
            source: .file,
            originalFilename: "meeting.wav",
            duration: 90,
            transcript: "Erste Fassung"
        )
        let replacement = ImportItem(
            id: id,
            source: .file,
            originalFilename: "meeting.wav",
            duration: 90,
            transcript: "Neue Fassung"
        )

        let store = ImportStore(fileURL: fileURL)
        try store.add(first)
        try store.add(replacement)

        XCTAssertEqual(store.entries, [replacement])
    }

    func testCoordinatorRejectsASecondSpeechOperation() throws {
        let coordinator = SpeechOperationCoordinator()
        let firstToken = try coordinator.begin(.dictation)

        XCTAssertThrowsError(try coordinator.begin(.mediaImport)) { error in
            XCTAssertEqual(error as? SpeechOperationError, .busy(.dictation))
        }

        coordinator.end(firstToken)
        XCTAssertNoThrow(try coordinator.begin(.mediaImport))
    }

    func testCoordinatorKeepsOperationUntilMatchingTokenEnds() throws {
        let coordinator = SpeechOperationCoordinator()
        let token = try coordinator.begin(.modelLoading)

        coordinator.end(UUID())
        XCTAssertEqual(coordinator.activeOperation, .modelLoading)

        coordinator.end(token)
        XCTAssertNil(coordinator.activeOperation)
    }

    func testCoordinatorWaitsUntilTheSpeechEngineIsAvailable() async throws {
        let coordinator = SpeechOperationCoordinator()
        let firstToken = try coordinator.begin(.modelLoading)
        let waiter = Task { try await coordinator.acquire(.mediaImport) }

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(coordinator.activeOperation, .modelLoading)

        coordinator.end(firstToken)
        let importToken = try await waiter.value
        XCTAssertEqual(coordinator.activeOperation, .mediaImport)
        coordinator.end(importToken)
    }

    func testSegmentPlanUsesOrderedTenMinuteParts() {
        let segments = MediaSegmentPlan.segments(duration: 1_201)

        XCTAssertEqual(
            segments,
            [
                MediaSegment(index: 0, start: 0, duration: 600),
                MediaSegment(index: 1, start: 600, duration: 600),
                MediaSegment(index: 2, start: 1_200, duration: 1),
            ]
        )
    }

    func testMediaValidatorRejectsUnsupportedMissingAudioAndLongFiles() throws {
        let validator = MediaImportValidator()

        XCTAssertThrowsError(
            try validator.validate(
                fileURL: URL(fileURLWithPath: "/tmp/recording.xyz"),
                metadata: MediaMetadata(duration: 10, hasAudio: true),
                fileSize: 1_000,
                availableBytes: 1_000_000_000
            )
        ) { error in
            XCTAssertEqual(error as? MediaImportError, .unsupportedFormat("xyz"))
        }

        XCTAssertThrowsError(
            try validator.validate(
                fileURL: URL(fileURLWithPath: "/tmp/movie.mov"),
                metadata: MediaMetadata(duration: 10, hasAudio: false),
                fileSize: 1_000,
                availableBytes: 1_000_000_000
            )
        ) { error in
            XCTAssertEqual(error as? MediaImportError, .missingAudioTrack)
        }

        XCTAssertThrowsError(
            try validator.validate(
                fileURL: URL(fileURLWithPath: "/tmp/meeting.m4a"),
                metadata: MediaMetadata(duration: 3_601, hasAudio: true),
                fileSize: 1_000,
                availableBytes: 1_000_000_000
            )
        ) { error in
            XCTAssertEqual(error as? MediaImportError, .durationExceeded(maximum: 3_600))
        }
    }

    func testMediaValidatorRejectsInsufficientFreeSpace() throws {
        let validator = MediaImportValidator()

        XCTAssertThrowsError(
            try validator.validate(
                fileURL: URL(fileURLWithPath: "/tmp/meeting.m4a"),
                metadata: MediaMetadata(duration: 120, hasAudio: true),
                fileSize: 50_000_000,
                availableBytes: 1
            )
        ) { error in
            guard case let MediaImportError.insufficientStorage(required, available) = error else {
                return XCTFail("Expected insufficient storage error")
            }
            XCTAssertGreaterThan(required, available)
        }
    }

    func testMediaValidatorRejectsUnreadableDuration() throws {
        let validator = MediaImportValidator()

        XCTAssertThrowsError(
            try validator.validate(
                fileURL: URL(fileURLWithPath: "/tmp/broken.m4a"),
                metadata: MediaMetadata(duration: 0, hasAudio: true),
                fileSize: 1_000,
                availableBytes: 1_000_000_000
            )
        ) { error in
            XCTAssertEqual(error as? MediaImportError, .unreadableMedia)
        }
    }

    func testMediaValidatorAcceptsTelegramVoiceMessageExtensions() throws {
        let validator = MediaImportValidator()

        for fileExtension in ["ogg", "oga", "opus"] {
            XCTAssertNoThrow(
                try validator.validate(
                    fileURL: URL(fileURLWithPath: "/tmp/telegram-voice.\(fileExtension)"),
                    metadata: MediaMetadata(duration: 30, hasAudio: true),
                    fileSize: 1_000,
                    availableBytes: 1_000_000_000
                ),
                "Expected .\(fileExtension) to pass extension validation"
            )
        }
    }

    func testFallbackSummaryCreatesShortParagraphAndAtMostFivePoints() async throws {
        let transcript = """
        Das HermesVoice Projekt bekommt einen neuen Importbereich. Audio und Video werden lokal verarbeitet. \
        Dateien duerfen maximal sechzig Minuten lang sein. Die Transkription bleibt vollstaendig offline. \
        Eine Kurzfassung wird nur auf Knopfdruck erstellt. Bei fehlender Apple Intelligence greift ein lokaler Ersatz. \
        Die Originaldatei wird nach erfolgreicher Verarbeitung geloescht.
        """

        let result = try await ExtractiveTranscriptSummarizer().summarize(transcript)

        XCTAssertFalse(result.text.isEmpty)
        XCTAssertFalse(result.keyPoints.isEmpty)
        XCTAssertLessThanOrEqual(result.keyPoints.count, 5)
        XCTAssertTrue(result.text.count < transcript.count)
    }

    func testFallbackSummaryKeepsUnpunctuatedTranscriptShort() async throws {
        let transcript = Array(repeating: "dies ist ein langer transkribierter abschnitt", count: 100)
            .joined(separator: " ")

        let result = try await ExtractiveTranscriptSummarizer().summarize(transcript)

        XCTAssertLessThanOrEqual(result.text.count, 240)
        XCTAssertLessThanOrEqual(result.keyPoints.count, 5)
        XCTAssertTrue(result.keyPoints.allSatisfy { $0.count <= 240 })
    }

    func testMediaPipelineTranscribesSegmentsInOrderAndRemovesTemporaryParts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("meeting.mov")
        try Data("media".utf8).write(to: sourceURL)
        let transcriber = RecordingMediaTranscriber(results: ["Teil eins", "Teil zwei", "Teil drei"])
        let pipeline = MediaImportPipeline(
            inspector: StaticMediaInspector(
                inspection: MediaInspection(
                    metadata: MediaMetadata(duration: 1_201, hasAudio: true),
                    fileSize: 5,
                    availableBytes: 1_000_000_000
                )
            ),
            segmenter: FileCreatingSegmenter(),
            transcriber: transcriber,
            temporaryRootURL: directory.appendingPathComponent("parts", isDirectory: true)
        )
        var phases: [ImportPhase] = []

        let item = try await pipeline.process(
            fileURL: sourceURL,
            source: .file,
            originalFilename: "meeting.mov",
            language: "de"
        ) { phases.append($0) }

        XCTAssertEqual(item.transcript, "Teil eins\n\nTeil zwei\n\nTeil drei")
        XCTAssertEqual(transcriber.filenames, ["part-000.m4a", "part-001.m4a", "part-002.m4a"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("parts").path))
        XCTAssertTrue(phases.contains(.preparing(current: 3, total: 3)))
        XCTAssertTrue(phases.contains(.transcribing(current: 3, total: 3)))
    }

    func testMediaPipelineUsesOrderedBatchTranscription() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("meeting.mov")
        try Data("media".utf8).write(to: sourceURL)
        let transcriber = BatchRecordingMediaTranscriber(
            results: ["Teil eins", "Teil zwei", "Teil drei"]
        )
        let pipeline = MediaImportPipeline(
            inspector: StaticMediaInspector(
                inspection: MediaInspection(
                    metadata: MediaMetadata(duration: 1_201, hasAudio: true),
                    fileSize: 5,
                    availableBytes: 1_000_000_000
                )
            ),
            segmenter: FileCreatingSegmenter(),
            transcriber: transcriber,
            temporaryRootURL: directory.appendingPathComponent("parts", isDirectory: true)
        )

        let item = try await pipeline.process(
            fileURL: sourceURL,
            source: .file,
            originalFilename: "meeting.mov",
            language: "de"
        ) { _ in }

        XCTAssertEqual(item.transcript, "Teil eins\n\nTeil zwei\n\nTeil drei")
        XCTAssertEqual(
            transcriber.batchFilenames,
            ["part-000.m4a", "part-001.m4a", "part-002.m4a"]
        )
        XCTAssertEqual(transcriber.languages, ["de"])
    }

    func testMediaPipelineCancellationRemovesTemporaryParts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("meeting.m4a")
        try Data("media".utf8).write(to: sourceURL)
        let partsURL = directory.appendingPathComponent("parts", isDirectory: true)
        let pipeline = MediaImportPipeline(
            inspector: StaticMediaInspector(
                inspection: MediaInspection(
                    metadata: MediaMetadata(duration: 10, hasAudio: true),
                    fileSize: 5,
                    availableBytes: 1_000_000_000
                )
            ),
            segmenter: FileCreatingSegmenter(),
            transcriber: CancellingMediaTranscriber(),
            temporaryRootURL: partsURL
        )

        do {
            _ = try await pipeline.process(
                fileURL: sourceURL,
                source: .file,
                originalFilename: "meeting.m4a",
                language: "de"
            ) { _ in }
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? MediaImportError, .cancelled)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partsURL.path))
    }

    func testWorkspaceRetainsFailedImportAndDeletesSuccessfulOrCancelledImport() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSource = directory.appendingPathComponent("first.m4a")
        let secondSource = directory.appendingPathComponent("second.m4a")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let workspace = ImportWorkspace(rootURL: directory.appendingPathComponent("workspace", isDirectory: true))
        let failedJob = try await workspace.stage(fileURL: firstSource, source: .file)
        let completedJob = try await workspace.stage(fileURL: secondSource, source: .file)

        try workspace.markFailed(failedJob.id, message: "Testfehler")
        try workspace.complete(completedJob.id)

        XCTAssertEqual(workspace.jobs.map(\.id), [failedJob.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedJob.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedJob.fileURL.path))

        try workspace.cancel(failedJob.id)
        XCTAssertTrue(workspace.jobs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedJob.fileURL.path))
    }

    func testLongTranscriptChunkingPreservesOrderAndLimitsChunkSize() {
        let transcript = (1...80).map { "Satz \($0) mit etwas Inhalt." }.joined(separator: " ")

        let chunks = TranscriptChunker.chunks(transcript, maximumCharacters: 180)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 180 })
        XCTAssertEqual(chunks.joined(separator: " "), transcript)
    }

    func testResilientSummarizerUsesFallbackWhenPrimaryFails() async throws {
        let expected = ImportSummary(
            text: "Lokale Kurzfassung",
            keyPoints: ["Punkt"],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let summarizer = ResilientTranscriptSummarizer(
            primary: ThrowingSummaryProvider(),
            fallback: FixedSummaryProvider(summary: expected)
        )

        let result = try await summarizer.summarize("Ein Transkript")

        XCTAssertEqual(result, expected)
    }

    func testSharedInboxPublishesOnlyCompleteAtomicImports() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("voice.m4a")
        try Data("audio".utf8).write(to: sourceURL)
        let inbox = SharedImportInbox(rootURL: directory.appendingPathComponent("inbox", isDirectory: true))

        let envelope = try inbox.enqueue(fileURL: sourceURL)
        try Data("partial".utf8).write(
            to: directory
                .appendingPathComponent("inbox/Ready/interrupted.json.partial")
        )

        XCTAssertEqual(try inbox.pending(), [envelope])

        try inbox.remove(envelope)
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: envelope.fileURL.path))
    }

    func testSharedInboxPreservesTelegramFilenameWhenTemporaryFileHasNoExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("ItemProviderFile")
        try Data("audio".utf8).write(to: sourceURL)
        let inbox = SharedImportInbox(rootURL: directory.appendingPathComponent("inbox", isDirectory: true))

        let envelope = try inbox.enqueue(fileURL: sourceURL, originalFilename: "telegram-voice.ogg")

        XCTAssertEqual(envelope.originalFilename, "telegram-voice.ogg")
        XCTAssertEqual(envelope.fileURL.pathExtension, "ogg")
    }

    func testSharedInboxUsesTheConfiguredAppGroup() {
        XCTAssertEqual(SharedImportInbox.appGroupIdentifier, "group.de.hermes.voice.shared")
    }

    func testSharedInboxIngestionRequestsDirectPresentationOfTheStagedImport() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("voice-message.m4a")
        try Data("audio".utf8).write(to: sourceURL)
        let inbox = SharedImportInbox(rootURL: directory.appendingPathComponent("inbox", isDirectory: true))
        let envelope = try inbox.enqueue(fileURL: sourceURL)
        let workspace = ImportWorkspace(rootURL: directory.appendingPathComponent("workspace", isDirectory: true))
        let store = ImportStore(fileURL: directory.appendingPathComponent("imports.json"))
        let coordinator = SpeechOperationCoordinator()
        let blockingToken = try coordinator.begin(.modelLoading)
        let controller = ImportController(
            store: store,
            workspace: workspace,
            coordinator: coordinator,
            sharedInbox: inbox
        )

        controller.ingestSharedInbox()

        for _ in 0..<100 where controller.presentationRequestID == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let stagedJob = try XCTUnwrap(workspace.jobs.first)
        XCTAssertEqual(stagedJob.sharedInboxID, envelope.id)
        XCTAssertEqual(controller.presentationRequestID, stagedJob.id)

        controller.cancelImport()
        coordinator.end(blockingToken)
    }
}

private struct StaticMediaInspector: MediaInspecting {
    let inspection: MediaInspection

    func inspect(_ fileURL: URL) async throws -> MediaInspection {
        inspection
    }
}

private struct FileCreatingSegmenter: MediaSegmenting {
    func segment(
        fileURL: URL,
        segments: [MediaSegment],
        outputDirectory: URL,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for segment in segments {
            let url = outputDirectory.appendingPathComponent(String(format: "part-%03d.m4a", segment.index))
            try Data("part".utf8).write(to: url)
            urls.append(url)
            await progress(segment.index + 1, segments.count)
        }
        return urls
    }
}

@MainActor
private final class RecordingMediaTranscriber: MediaTranscribing {
    private var results: [String]
    private(set) var filenames: [String] = []

    init(results: [String]) {
        self.results = results
    }

    func transcribeMedia(
        audioURLs: [URL],
        language: String,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [String] {
        filenames = audioURLs.map(\.lastPathComponent)
        for index in audioURLs.indices {
            progress(index + 1, audioURLs.count)
        }
        return results
    }
}

@MainActor
private final class BatchRecordingMediaTranscriber: MediaTranscribing {
    let results: [String]
    private(set) var batchFilenames: [String] = []
    private(set) var languages: [String] = []

    init(results: [String]) {
        self.results = results
    }

    func transcribeMedia(
        audioURLs: [URL],
        language: String,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [String] {
        batchFilenames = audioURLs.map(\.lastPathComponent)
        languages.append(language)
        for index in audioURLs.indices {
            progress(index + 1, audioURLs.count)
        }
        return results
    }
}

@MainActor
private final class CancellingMediaTranscriber: MediaTranscribing {
    func transcribeMedia(
        audioURLs: [URL],
        language: String,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [String] {
        throw CancellationError()
    }
}

private struct ThrowingSummaryProvider: TranscriptSummarizing {
    func summarize(_ transcript: String) async throws -> ImportSummary {
        throw CocoaError(.featureUnsupported)
    }
}

private struct FixedSummaryProvider: TranscriptSummarizing {
    let summary: ImportSummary

    func summarize(_ transcript: String) async throws -> ImportSummary {
        summary
    }
}
