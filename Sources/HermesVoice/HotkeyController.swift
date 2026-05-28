import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyController {
    static let shared = HotkeyController()
    var onToggle: (() -> Void)?

    private init() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.onToggle?()
        }
    }
}
