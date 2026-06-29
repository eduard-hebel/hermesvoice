import Foundation
import Observation

@MainActor
@Observable
final class ImportStore {
    static let shared = ImportStore(fileURL: defaultFileURL())

    private(set) var entries: [ImportItem] = []
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func add(_ item: ImportItem) throws {
        var updated = entries
        updated.removeAll { $0.id == item.id }
        updated.insert(item, at: 0)
        try save(updated)
        entries = updated
    }

    func setSummary(_ summary: ImportSummary, for id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = entries
        updated[index].summary = summary
        try save(updated)
        entries = updated
    }

    func remove(id: UUID) throws {
        let updated = entries.filter { $0.id != id }
        guard updated.count != entries.count else { return }
        try save(updated)
        entries = updated
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ImportItem].self, from: data)
        else { return }
        entries = decoded
    }

    private func save(_ entries: [ImportItem]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("HermesVoice", isDirectory: true)
            .appendingPathComponent("imports.json")
    }
}
