import Foundation
import OSLog

/// Verwaltet aufbewahrte Audio-Aufnahmen als Sicherheitsnetz.
/// Jedes Diktat-WAV bleibt erhalten, damit es bei fehlgeschlagener/leerer/
/// schlechter Transkription neu transkribiert werden kann — kein Totalverlust
/// bei langen Diktaten. Auto-Cleanup behält nur die jüngsten N Aufnahmen.
enum RecordingStore {
    private static let log = Logger(subsystem: "de.hermes.voice", category: "Recordings")
    private static let maxRecordings = 30

    /// Persistenter Ordner für Aufnahmen (nicht temp, übersteht Neustart/Cleanup).
    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("HermesVoice/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Neue, eindeutige WAV-URL mit sortierbarem Timestamp-Namen.
    static func newRecordingURL() -> URL {
        let stamp = ISO8601DateFormatter.filenameFormatter.string(from: .now)
        return directory.appendingPathComponent("rec-\(stamp).wav")
    }

    /// Alle vorhandenen Aufnahmen, neueste zuerst.
    static func allRecordings() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension == "wav" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return l > r
            }
    }

    static var latestRecording: URL? { allRecordings().first }

    /// Löscht alte Aufnahmen über das Limit hinaus.
    static func pruneOld() {
        let all = allRecordings()
        guard all.count > maxRecordings else { return }
        for url in all[maxRecordings...] {
            try? FileManager.default.removeItem(at: url)
        }
        log.info("Pruned \(all.count - maxRecordings) old recording(s)")
    }
}

private extension ISO8601DateFormatter {
    /// Dateisystem-sicherer Timestamp: 2026-05-28T04-30-12
    static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
