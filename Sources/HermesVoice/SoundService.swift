import AppKit

/// Dezente System-Sounds für Diktat-Events.
/// Nutzt macOS-Bord-Sounds aus /System/Library/Sounds/.
/// Wird über UserDefaults-Toggle "soundsEnabled" gesteuert.
@MainActor
enum SoundService {
    enum Cue: String {
        case start  = "Tink"     // kurz, hoch, dezent
        case stop   = "Pop"      // rund, abschließend
        case error  = "Basso"    // dumpf, warnend
    }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true
    }

    static func play(_ cue: Cue) {
        guard enabled else { return }
        // System-Sound aus /System/Library/Sounds/, NSSound(named:) liest die automatisch
        if let sound = NSSound(named: cue.rawValue) {
            sound.volume = 0.4   // dezent, nicht aufdringlich
            sound.play()
        }
    }
}
