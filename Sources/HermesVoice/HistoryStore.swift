import Foundation
import AppKit
import Observation
import OSLog

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let text: String
    let mode: FormatMode

    init(id: UUID = UUID(), timestamp: Date = .now, text: String, mode: FormatMode) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.mode = mode
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
    }
}

/// Persistente History der letzten Diktate, max 50 Einträge.
/// Liegt in ~/Library/Application Support/HermesVoice/history.json.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    private static let log = Logger(subsystem: "de.hermes.voice", category: "History")
    private static let maxEntries = 50

    private(set) var entries: [HistoryEntry] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("HermesVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, mode: FormatMode) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = HistoryEntry(text: text, mode: mode)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Kopiert einen Eintrag zurück ins Clipboard (für Re-Insert per ⌘V).
    func copyToClipboard(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Self.log.error("History save failed: \(error.localizedDescription)")
        }
    }
}
