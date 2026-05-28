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

    func polish(_ raw: String) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: claudePath) else {
            throw CleanupError.cliNotFound(claudePath)
        }

        let prompt = """
        Räume folgenden diktierten Text auf: Versprecher und Füllwörter (äh, ähm, halt, also) raus, \
        Satzbau gerade ziehen, fehlende Interpunktion ergänzen. \
        Inhalt nicht verändern, Sprache beibehalten. \
        Gib NUR den bereinigten Text zurück — keine Anführungszeichen, kein Kommentar, kein Vor- oder Nachwort.

        Text:
        \(raw)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // Timeout-Wächter (5 Min — sollte fast nie greifen, Cleanup ist sub-Sekunde)
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            if process.isRunning {
                process.terminate()
                Self.log.warning("claude CLI timed out, terminated")
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

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
