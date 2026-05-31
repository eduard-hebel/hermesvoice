import AppIntents
import Observation

/// Signal-Objekt, das die App beim Foreground prüft: hat der Action Button /
/// Control / URL-Scheme ein Sofort-Diktat angefordert?
@MainActor
@Observable
final class AutoRecordSignal {
    static let shared = AutoRecordSignal()
    var pending = false
    private init() {}
}

/// App Intent für den Action Button (iPhone 16 Pro) und Kurzbefehle.
/// `openAppWhenRun` bringt die App in den Vordergrund; beim Aktivwerden startet
/// sie automatisch die Aufnahme (siehe HermesVoiceiOSApp.handleAutoRecord).
struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Diktat starten"
    static let description = IntentDescription("Öffnet HermesVoice und startet sofort eine Aufnahme.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AutoRecordSignal.shared.pending = true
        return .result()
    }
}

struct HermesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: ["Diktat mit \(.applicationName)", "\(.applicationName) Diktat"],
            shortTitle: "Diktat",
            systemImageName: "mic.fill"
        )
    }
}
