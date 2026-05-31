import Foundation
import Observation
import OSLog

struct VocabPair: Codable, Identifiable, Hashable {
    var id: String { "\(wrong)→\(right)" }
    let wrong: String
    let right: String
    var weight: Int
    var lastSeen: Date
}

/// Lernt aus Diffs zwischen Whisper-Rohtext und Claude-Cleanup-Output.
/// Häufige Korrekturen werden bei künftigen Transkriptionen als Context
/// an Whisper mitgegeben → Whisper kennt die Schreibweise direkt.
@MainActor
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore()
    private static let log = Logger(subsystem: "de.hermes.voice", category: "Vocabulary")
    private static let maxPairs = 60

    private(set) var pairs: [VocabPair] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("HermesVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("vocabulary.json")
        load()
    }

    /// Vergleicht Roh- und Cleanup-Output token-weise. Token-Paare an gleicher Position,
    /// die sich unterscheiden und nahe (Levenshtein ≤ 3) sind, werden als Korrektur
    /// registriert. Bei Lücken-Mismatch ignorieren (sicherer Pfad).
    func learn(raw: String, cleaned: String) {
        let rawTokens = Self.tokenize(raw)
        let cleanedTokens = Self.tokenize(cleaned)
        guard rawTokens.count == cleanedTokens.count else {
            // Strukturelle Cleanup-Änderungen (gelöschte Wörter etc.) — nicht token-aligned
            return
        }

        for (r, c) in zip(rawTokens, cleanedTokens) {
            guard r != c, r.count > 2, c.count > 2 else { continue }
            let dist = Self.levenshtein(r.lowercased(), c.lowercased())
            guard dist > 0 && dist <= 3 else { continue }
            recordPair(wrong: r, right: c)
        }
        save()
    }

    /// Top-N häufigste rechte Schreibweisen als Kontext-Hint für Whisper / Cleanup.
    var contextHint: String {
        let topRights = pairs.sorted { $0.weight > $1.weight }
            .prefix(20)
            .map(\.right)
        guard !topRights.isEmpty else { return "" }
        return " Häufige Schreibweisen: " + topRights.joined(separator: ", ") + "."
    }

    func clear() {
        pairs.removeAll()
        save()
    }

    // MARK: - Private

    private func recordPair(wrong: String, right: String) {
        if let idx = pairs.firstIndex(where: {
            $0.wrong.lowercased() == wrong.lowercased() &&
            $0.right.lowercased() == right.lowercased()
        }) {
            pairs[idx].weight += 1
            pairs[idx].lastSeen = .now
        } else {
            pairs.append(VocabPair(wrong: wrong, right: right, weight: 1, lastSeen: .now))
        }
        // Trim: nach Weight + Recency
        if pairs.count > Self.maxPairs {
            pairs.sort { lhs, rhs in
                lhs.weight != rhs.weight ? lhs.weight > rhs.weight : lhs.lastSeen > rhs.lastSeen
            }
            pairs = Array(pairs.prefix(Self.maxPairs))
        }
        Self.log.info("Vocab pair: \(wrong, privacy: .public) → \(right, privacy: .public)")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VocabPair].self, from: data) else { return }
        pairs = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(pairs)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Self.log.error("Vocab save failed: \(error.localizedDescription)")
        }
    }

    private static func tokenize(_ s: String) -> [String] {
        // Wörter inkl. Umlauten / Apostrophen, Interpunktion separat behandeln
        s.split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "'" }
            .map { String($0) }
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = [Int](0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
