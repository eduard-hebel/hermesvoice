import KeyboardShortcuts
import OSLog

extension KeyboardShortcuts.Name {
    /// Toggle-Hotkey: einmal drücken = aufnehmen, nochmal = stoppen.
    static let toggleDictation = Self("toggleDictation",
        default: .init(.space, modifiers: [.command, .shift]))

    /// Push-to-Talk: gedrückt halten = aufnehmen, loslassen = stoppen.
    static let pushToTalk = Self("pushToTalk",
        default: .init(.space, modifiers: [.control]))

    /// Voice-Command: aktive Selection wird mit gesprochenem Befehl modifiziert.
    static let voiceCommand = Self("voiceCommand",
        default: .init(.v, modifiers: [.command, .shift, .control]))
}

@MainActor
final class HotkeyController {
    static let shared = HotkeyController()
    static let log = Logger(subsystem: "de.hermes.voice", category: "Hotkey")
    var onToggle: (() -> Void)?
    var onPushToTalkDown: (() -> Void)?
    var onPushToTalkUp: (() -> Void)?
    var onVoiceCommandToggle: (() -> Void)?

    private init() {
        Self.log.info("HotkeyController init — registering hotkeys")

        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            Self.log.info("Toggle hotkey fired")
            self?.onToggle?()
        }

        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            Self.log.info("Push-to-talk DOWN")
            self?.onPushToTalkDown?()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            Self.log.info("Push-to-talk UP")
            self?.onPushToTalkUp?()
        }

        KeyboardShortcuts.onKeyDown(for: .voiceCommand) { [weak self] in
            Self.log.info("Voice-command hotkey fired")
            self?.onVoiceCommandToggle?()
        }
    }
}
