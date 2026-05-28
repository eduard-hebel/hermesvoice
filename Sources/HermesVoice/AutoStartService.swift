import Foundation
import ServiceManagement
import OSLog

/// Registriert HermesVoice als Login-Item via SMAppService (macOS 13+).
/// Toggle in Settings. macOS zeigt beim ersten Register einen Bestätigungsdialog.
@MainActor
final class AutoStartService {
    static let shared = AutoStartService()
    private static let log = Logger(subsystem: "de.hermes.voice", category: "AutoStart")

    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Aktiviert oder deaktiviert den Login-Item-Eintrag.
    /// Wirft, wenn der OS-Call scheitert.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status == .enabled {
                Self.log.info("AutoStart already enabled — noop")
                return
            }
            try SMAppService.mainApp.register()
            Self.log.info("AutoStart registered — status: \(String(describing: SMAppService.mainApp.status))")
        } else {
            if SMAppService.mainApp.status == .notRegistered {
                Self.log.info("AutoStart already disabled — noop")
                return
            }
            try SMAppService.mainApp.unregister()
            Self.log.info("AutoStart unregistered — status: \(String(describing: SMAppService.mainApp.status))")
        }
    }
}
