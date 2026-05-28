import Foundation
import OSLog

/// Pausiert Spotify/Music beim Aufnahme-Start.
/// Kein Auto-Resume — der User soll bewusst weiterhören.
enum MediaController {
    private static let log = Logger(subsystem: "de.hermes.voice", category: "Media")

    static var pauseEnabled: Bool {
        UserDefaults.standard.object(forKey: "mediaPauseEnabled") as? Bool ?? true
    }

    static func pauseIfPlaying() {
        guard pauseEnabled else { return }
        Task.detached {
            for app in ["Spotify", "Music"] {
                let script = """
                tell application "System Events"
                    if exists (processes where name is "\(app)") then
                        tell application "\(app)"
                            if player state is playing then pause
                        end tell
                    end if
                end tell
                """
                runOsascript(script)
            }
        }
    }

    private static func runOsascript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        // stderr abgreifen, sonst spammt es ins Log wenn Spotify nicht läuft
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("osascript failed: \(error.localizedDescription)")
        }
    }
}
