import Foundation

/// Welches Claude-Modell die CLI-Stufen (Cleanup, Voice-Command) nutzen.
/// Pro Funktion in den Einstellungen umschaltbar — kein Recompile nötig.
enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case haiku
    case sonnet
    case opus

    var id: String { rawValue }

    /// Argument für `claude --model <cliName>`. Die CLI kennt diese Aliase.
    var cliName: String { rawValue }

    var label: String {
        switch self {
        case .haiku:  "Haiku — am schnellsten"
        case .sonnet: "Sonnet — ausgewogen"
        case .opus:   "Opus — höchste Qualität"
        }
    }

    // MARK: - Persistente Wahl pro Funktion

    /// UserDefaults-Keys, geteilt zwischen Settings-Picker und CLI-Stufen.
    static let cleanupKey = "cleanupModel"
    static let voiceCommandKey = "voiceCommandModel"

    /// Cleanup-Default: Haiku (schnellste Latenz, reicht für Füllwörter/Akronyme).
    static func cleanup() -> ClaudeModel {
        resolve(key: cleanupKey, fallback: .haiku)
    }

    /// Voice-Command-Default: Sonnet (besseres Kontextverständnis für
    /// Transformationen wie „mach kürzer", „übersetze").
    static func voiceCommand() -> ClaudeModel {
        resolve(key: voiceCommandKey, fallback: .sonnet)
    }

    private static func resolve(key: String, fallback: ClaudeModel) -> ClaudeModel {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let model = ClaudeModel(rawValue: raw) else { return fallback }
        return model
    }
}
