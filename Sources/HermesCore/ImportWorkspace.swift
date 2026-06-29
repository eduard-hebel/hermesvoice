import Foundation
import Observation

struct ImportJob: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let source: ImportSource
    let originalFilename: String
    let fileURL: URL
    let sharedInboxID: UUID?
    var lastError: String?
}

@MainActor
@Observable
final class ImportWorkspace {
    static let shared = ImportWorkspace(rootURL: defaultRootURL())

    private(set) var jobs: [ImportJob] = []
    private let rootURL: URL
    private let filesURL: URL
    private let manifestURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        filesURL = rootURL.appendingPathComponent("Files", isDirectory: true)
        manifestURL = rootURL.appendingPathComponent("jobs.json")
        load()
    }

    func stage(
        fileURL: URL,
        source: ImportSource,
        originalFilename: String? = nil,
        sharedInboxID: UUID? = nil
    ) async throws -> ImportJob {
        if let sharedInboxID,
           let existing = jobs.first(where: { $0.sharedInboxID == sharedInboxID }) {
            return existing
        }
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        let id = UUID()
        let filename = originalFilename
            ?? (fileURL.lastPathComponent.isEmpty ? "Import" : fileURL.lastPathComponent)
        let destination = filesURL.appendingPathComponent("\(id.uuidString)-\(filename)")
        let partial = destination.appendingPathExtension("partial")
        do {
            try await Task.detached(priority: .userInitiated) {
                let hasSecurityAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if hasSecurityAccess { fileURL.stopAccessingSecurityScopedResource() }
                }
                try FileManager.default.copyItem(at: fileURL, to: partial)
                try FileManager.default.moveItem(at: partial, to: destination)
            }.value
            let job = ImportJob(
                id: id,
                createdAt: .now,
                source: source,
                originalFilename: filename,
                fileURL: destination,
                sharedInboxID: sharedInboxID,
                lastError: nil
            )
            var updated = jobs
            updated.append(job)
            try save(updated)
            jobs = updated
            return job
        } catch {
            try? FileManager.default.removeItem(at: partial)
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func markFailed(_ id: UUID, message: String) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        var updated = jobs
        updated[index].lastError = message
        try save(updated)
        jobs = updated
    }

    func complete(_ id: UUID) throws {
        try removeJob(id)
    }

    func cancel(_ id: UUID) throws {
        try removeJob(id)
    }

    private func removeJob(_ id: UUID) throws {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let updated = jobs.filter { $0.id != id }
        try save(updated)
        jobs = updated
        try? FileManager.default.removeItem(at: job.fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([ImportJob].self, from: data)
        else { return }
        jobs = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private func save(_ jobs: [ImportJob]) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(jobs)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func defaultRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HermesVoice", isDirectory: true)
            .appendingPathComponent("ImportWorkspace", isDirectory: true)
    }
}
