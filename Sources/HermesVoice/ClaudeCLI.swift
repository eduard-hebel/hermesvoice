import Foundation
import OSLog

/// Zentraler, robuster Aufruf der Claude-CLI (`claude -p … --model …`).
/// Genutzt von Cleanup und Voice-Command. Als Actor → läuft off-main, blockiert
/// also nie den UI-Thread während Claude antwortet.
///
/// WICHTIG: stdout/stderr werden NEBENLÄUFIG geleert, WÄHREND der Prozess läuft.
/// Würde man (wie früher) erst nach Prozess-Ende lesen, könnte ein Output größer
/// als der ~64-KB-Pipe-Buffer den claude-Prozess beim Schreiben blockieren → er
/// endet nie → Deadlock (Hänger bis zum Timeout). Tritt v.a. bei Voice-Command auf
/// langen Selektionen auf.
actor ClaudeCLI {
    static let shared = ClaudeCLI()

    private static let log = Logger(subsystem: "de.hermes.voice", category: "ClaudeCLI")
    private static let timeoutNanos: UInt64 = 5 * 60 * 1_000_000_000  // 5 min

    private let claudePath: String

    init(claudePath: String = "/Users/edward/.local/bin/claude") {
        self.claudePath = claudePath
    }

    func run(prompt: String, model: ClaudeModel) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: claudePath) else {
            throw CLIError.notFound(claudePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt, "--model", model.cliName]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Pipes ab sofort nebenläufig leeren — verhindert den 64-KB-Deadlock.
        // readToEnd() blockiert bis EOF (= Prozess hat geschrieben und beendet sich).
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        let outReader = Task.detached { (try? outHandle.readToEnd()) ?? Data() }
        let errReader = Task.detached { (try? errHandle.readToEnd()) ?? Data() }

        // Timeout-Wächter — sollte fast nie greifen (Cleanup ist sub-Sekunde).
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: Self.timeoutNanos)
            if process.isRunning {
                process.terminate()
                Self.log.warning("claude CLI timed out, terminated")
            }
        }

        // Start + auf Ende warten, abbrechbar (User drückt X → terminate()).
        // terminationHandler wird VOR run() gesetzt, damit kein Race entsteht
        // (kein doppeltes resume, kein verpasstes Ende).
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

        let outData = await outReader.value
        let errData = await errReader.value

        guard process.terminationStatus == 0 else {
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown"
            Self.log.error("claude CLI failed (\(process.terminationStatus)): \(errMsg, privacy: .public)")
            throw CLIError.failed(status: Int(process.terminationStatus), stderr: errMsg)
        }

        return String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    enum CLIError: Error, LocalizedError {
        case notFound(String)
        case failed(status: Int, stderr: String)

        var errorDescription: String? {
            switch self {
            case .notFound(let p): "Claude CLI nicht gefunden unter \(p)"
            case .failed(let s, _): "Claude CLI Exit-Code \(s)"
            }
        }
    }
}
