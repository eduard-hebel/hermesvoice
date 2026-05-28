import KeyboardShortcuts
import OSLog

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyController {
    static let shared = HotkeyController()
    static let log = Logger(subsystem: "de.hermes.voice", category: "Hotkey")
    var onToggle: (() -> Void)?

    private init() {
        Self.log.info("HotkeyController init — registering ⌘⇧Space")
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            Self.log.info("Hotkey fired (⌘⇧Space)")
            self?.onToggle?()
        }
    }
}
