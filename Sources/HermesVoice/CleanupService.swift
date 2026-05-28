import Foundation
import OSLog

/// Optionaler zweiter Schritt: räumt das Roh-Transcript via Claude CLI auf.
/// Default off (Toggle in Settings). Nutzt Edwards eingeloggten Max Plan
/// über `/Users/edward/.local/bin/claude` — kein API-Key nötig.
actor CleanupService {
    private static let log = Logger(subsystem: "de.hermes.voice", category: "Cleanup")
    private let claudePath: String

    init(claudePath: String = "/Users/edward/.local/bin/claude") {
        self.claudePath = claudePath
    }

    func polish(_ raw: String, mode: FormatMode = .free, vocabHint: String = "") async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: claudePath) else {
            throw CleanupError.cliNotFound(claudePath)
        }

        // Gelernte Schreibweisen (Auto-Learning) als zusätzlichen Hinweis — hier statt
        // in Whisper, weil Claude robust damit umgeht (kein Context-Limit-Problem).
        let vocabLine = vocabHint.isEmpty ? "" : "\n   - Bevorzugte Schreibweisen:\(vocabHint)"

        let prompt = """
        Du bekommst einen diktierten Text aus einer Speech-to-Text-Erkennung. \
        Räume ihn auf:

        1. Versprecher und Füllwörter (äh, ähm, halt, also, ne, weißt-du) raus.
        2. Offensichtliche Transkriptions-Fehler korrigieren:
           - Buchstabierte Akronyme wieder zusammenziehen (z.B. "H-U-D" → "HUD", "A-P-I" → "API").
           - Falsche Umlaute oder fehlende Buchstaben in häufigen deutschen Wörtern fixen (z.B. "Fühwörter" → "Füllwörter").
           - Isolierte Laute wie "S-" oder "M-" die offensichtlich für Wörter wie "Ähs", "Mhm" stehen, kontextgerecht setzen.\(vocabLine)
        3. Satzbau gerade ziehen, fehlende Interpunktion ergänzen.

        Modus-spezifisch:
        \(mode.cleanupInstruction)

        Inhalt NICHT erfinden, Sprache beibehalten.
        Gib NUR den bereinigten Text zurück — keine Anführungszeichen, kein Kommentar, kein Vor- oder Nachwort.

        Text:
        \(raw)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        // Sonnet ist die richtige Mischung aus Quality und Latenz für Cleanup —
        // versteht Kontext (Akronyme, Umlaute) deutlich besser als Haiku,
        // bleibt aber unter 2 Sek pro Diktat.
        process.arguments = ["-p", prompt, "--model", "sonnet"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Timeout-Wächter (5 Min — sollte fast nie greifen, Cleanup ist sub-Sekunde)
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            if process.isRunning {
                process.terminate()
                Self.log.warning("claude CLI timed out, terminated")
            }
        }

        // Prozess starten und auf Ende warten — abbrechbar. Bei Task-Cancellation
        // (User drückt X im HUD) wird der claude-Prozess sofort getötet und
        // CancellationError geworfen. terminationHandler wird VOR run() gesetzt,
        // damit kein Race (kein doppeltes resume, kein verpasstes Ende).
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in cont.resume() }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
            Self.log.info("claude CLI cancelled by user")
        }
        timeoutTask.cancel()

        try Task.checkCancellation()

        let data = try stdout.fileHandleForReading.readToEnd() ?? Data()
        let errData = try stderr.fileHandleForReading.readToEnd() ?? Data()

        if process.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown"
            Self.log.error("claude CLI failed (\(process.terminationStatus)): \(errMsg, privacy: .public)")
            throw CleanupError.cliFailed(status: Int(process.terminationStatus), stderr: errMsg)
        }

        let cleaned = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
        return cleaned.isEmpty ? raw : cleaned
    }

    enum CleanupError: Error, LocalizedError {
        case cliNotFound(String)
        case cliFailed(status: Int, stderr: String)

        var errorDescription: String? {
            switch self {
            case .cliNotFound(let p): "Claude CLI nicht gefunden unter \(p)"
            case .cliFailed(let s, _): "Claude CLI Exit-Code \(s)"
            }
        }
    }
}
