import Foundation
import Observation

@MainActor
@Observable
final class ImportController {
    let store: ImportStore
    let workspace: ImportWorkspace

    private(set) var phase: ImportPhase = .idle
    private(set) var activeJobID: UUID?
    private(set) var summarizingItemID: UUID?
    private(set) var presentationRequestID: UUID?
    var message: String?

    private let pipeline: MediaImportPipeline
    private let coordinator: SpeechOperationCoordinator
    private let summarizer: any TranscriptSummarizing
    private let sharedInbox: SharedImportInbox?
    private var importTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var inboxTask: Task<Void, Never>?

    var isProcessing: Bool { importTask != nil }

    init(
        store: ImportStore? = nil,
        workspace: ImportWorkspace? = nil,
        pipeline: MediaImportPipeline? = nil,
        coordinator: SpeechOperationCoordinator? = nil,
        summarizer: (any TranscriptSummarizing)? = nil,
        sharedInbox: SharedImportInbox? = SharedImportInbox.appGroupInbox()
    ) {
        let resolvedWorkspace = workspace ?? .shared
        self.store = store ?? .shared
        self.workspace = resolvedWorkspace
        self.pipeline = pipeline ?? MediaImportPipeline()
        self.coordinator = coordinator ?? .shared
        self.summarizer = summarizer ?? DefaultTranscriptSummarizer()
        self.sharedInbox = sharedInbox
        presentationRequestID = resolvedWorkspace.jobs
            .last(where: { $0.source == .shareExtension })?
            .id
    }

    func importFile(
        _ fileURL: URL,
        source: ImportSource,
        removeSourceAfterStaging: Bool = false
    ) {
        guard importTask == nil else {
            message = "Es läuft bereits ein Import."
            return
        }
        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                importTask = nil
                processNextPendingImport()
            }
            do {
                let job = try await workspace.stage(fileURL: fileURL, source: source)
                if removeSourceAfterStaging {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                await process(job)
            } catch {
                phase = .failed(error.localizedDescription)
                message = error.localizedDescription
            }
        }
    }

    func retry(_ job: ImportJob) {
        guard importTask == nil else { return }
        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                importTask = nil
                processNextPendingImport()
            }
            await process(job)
        }
    }

    func processNextPendingImport() {
        guard importTask == nil,
              let job = workspace.jobs.first(where: { $0.lastError == nil })
        else { return }
        retry(job)
    }

    func ingestSharedInbox() {
        guard inboxTask == nil,
              let inbox = sharedInbox
        else { return }
        inboxTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { inboxTask = nil }
            do {
                for envelope in try inbox.pending() {
                    let job = try await workspace.stage(
                        fileURL: envelope.fileURL,
                        source: .shareExtension,
                        originalFilename: envelope.originalFilename,
                        sharedInboxID: envelope.id
                    )
                    presentationRequestID = job.id
                    try inbox.remove(envelope)
                }
                processNextPendingImport()
            } catch {
                message = "Geteilte Datei konnte nicht übernommen werden: \(error.localizedDescription)"
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func deletePendingImport(_ job: ImportJob) {
        do {
            try workspace.cancel(job.id)
            if activeJobID == job.id {
                importTask?.cancel()
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func summarize(_ item: ImportItem) {
        guard summaryTask == nil, !isProcessing else { return }
        summarizingItemID = item.id
        summaryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                summarizingItemID = nil
                summaryTask = nil
            }
            do {
                let summary = try await summarizer.summarize(item.transcript)
                try store.setSummary(summary, for: item.id)
            } catch is CancellationError {
                return
            } catch {
                message = "Kurzfassung fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func delete(_ item: ImportItem) {
        do {
            try store.remove(id: item.id)
        } catch {
            message = error.localizedDescription
        }
    }

    private func process(_ job: ImportJob) async {
        activeJobID = job.id

        if store.entries.contains(where: { $0.id == job.id }) {
            do {
                try workspace.complete(job.id)
                phase = .completed(job.id)
            } catch {
                let text = error.localizedDescription
                try? workspace.markFailed(job.id, message: text)
                phase = .failed(text)
                message = text
            }
            activeJobID = nil
            return
        }

        phase = .waitingForSpeechEngine
        let operationToken: UUID
        do {
            operationToken = try await coordinator.acquire(.mediaImport)
        } catch is CancellationError {
            try? workspace.cancel(job.id)
            phase = .idle
            activeJobID = nil
            return
        } catch {
            let text = error.localizedDescription
            try? workspace.markFailed(job.id, message: text)
            phase = .failed(text)
            message = text
            activeJobID = nil
            return
        }
        defer {
            coordinator.end(operationToken)
            activeJobID = nil
        }

        do {
            let rawItem = try await pipeline.process(
                fileURL: job.fileURL,
                source: job.source,
                originalFilename: job.originalFilename,
                language: UserDefaults.standard.string(forKey: "languageHint") ?? "de"
            ) { [weak self] phase in
                self?.phase = phase
            }
            let item = ImportItem(
                id: job.id,
                createdAt: rawItem.createdAt,
                source: rawItem.source,
                originalFilename: rawItem.originalFilename,
                duration: rawItem.duration,
                transcript: UserDictionaryStore.shared.apply(to: rawItem.transcript)
            )
            phase = .saving
            try store.add(item)
            try workspace.complete(job.id)
            phase = .completed(item.id)
        } catch let error as MediaImportError where error == .cancelled {
            try? workspace.cancel(job.id)
            phase = .idle
        } catch is CancellationError {
            try? workspace.cancel(job.id)
            phase = .idle
        } catch {
            let text = error.localizedDescription
            try? workspace.markFailed(job.id, message: text)
            phase = .failed(text)
            message = text
        }
    }
}
