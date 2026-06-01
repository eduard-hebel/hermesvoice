import Foundation
import Observation
import OSLog

/// Ein vom Nutzer gepflegter Korrektur-Eintrag: „heard" (wie Whisper es hört) →
/// „correct" (wie es geschrieben werden soll). Deterministische On-Device-Nachkorrektur.
struct DictionaryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var heard: String
    var correct: String
    init(id: UUID = UUID(), heard: String, correct: String) {
        self.id = id; self.heard = heard; self.correct = correct
    }
}

/// Persistentes Nutzer-Wörterbuch. Ersetzt nach jeder Transkription bekannte
/// Fehl-Hörungen, Namen, Akronyme und Dialektwörter (z. B. „oida") — ganzwortig,
/// Groß-/Kleinschreibung egal. On-device, deterministisch, kein Modell-Risiko
/// (im Gegensatz zu WhisperKit-promptTokens, die den 448-Token-Context sprengen).
@MainActor
@Observable
final class UserDictionaryStore {
    static let shared = UserDictionaryStore()
    private static let log = Logger(subsystem: "de.hermes.voice", category: "UserDict")

    private(set) var entries: [DictionaryEntry] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("HermesVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("user_dictionary.json")
        load()
    }

    func add(heard: String, correct: String) {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !c.isEmpty else { return }
        entries.removeAll { $0.heard.lowercased() == h.lowercased() }   // Duplikat ersetzen
        entries.insert(DictionaryEntry(heard: h, correct: c), at: 0)
        save()
    }

    func remove(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    /// Wendet alle Korrekturen auf einen Transkript-Text an. Ganzwortig (Unicode-Wort-
    /// grenzen), case-insensitive; längstes „heard" zuerst, damit Mehrwort-Einträge
    /// vor ihren Teilstücken greifen.
    func apply(to text: String) -> String {
        guard !entries.isEmpty else { return text }
        var result = text
        for entry in entries.sorted(by: { $0.heard.count > $1.heard.count }) {
            let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: entry.heard) + "(?![\\p{L}])"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: entry.correct)
            result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        do {
            try JSONEncoder().encode(entries).write(to: fileURL, options: [.atomic])
        } catch {
            Self.log.error("UserDict save failed: \(error.localizedDescription)")
        }
    }
}
