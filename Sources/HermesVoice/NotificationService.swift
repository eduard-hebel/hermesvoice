import UserNotifications
import OSLog

/// Zeigt eine macOS-Notification mit dem Transcript an.
/// Sichert das Ergebnis visuell ab — der Text ist auch immer im Clipboard,
/// falls ⌘V-Simulation am Zielfenster scheitert.
private nonisolated let notifLog = Logger(subsystem: "de.hermes.voice", category: "Notifications")

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private var authorized = false

    private init() {
        Task { await requestAuthorizationIfNeeded() }
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            do {
                authorized = try await center.requestAuthorization(options: [.alert, .sound])
                notifLog.info("Notification authorization granted: \(self.authorized)")
            } catch {
                notifLog.error("Notification authorization failed: \(error.localizedDescription)")
            }
        case .denied:
            authorized = false
        @unknown default:
            authorized = false
        }
    }

    /// Zeigt das Transcript als Notification. Wird nicht-blockierend gezeigt.
    /// Body wird gekürzt damit die Notification kompakt bleibt.
    func showTranscript(_ text: String, insertedSuccessfully: Bool) {
        guard authorized else {
            notifLog.info("Skipping notification — not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = insertedSuccessfully ? "Eingefügt" : "Im Clipboard"
        content.body = text.count > 240 ? String(text.prefix(237)) + "…" : text
        content.sound = nil   // Diktat-App sollte nicht piepen
        content.interruptionLevel = .passive

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // sofort zeigen
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                notifLog.error("Notification deliver failed: \(error.localizedDescription)")
            }
        }
    }
}
