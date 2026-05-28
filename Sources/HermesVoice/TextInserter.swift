import AppKit
import Carbon.HIToolbox

/// Schreibt Text in den Clipboard und simuliert ⌘V im aktiven Fenster.
struct TextInserter {
    func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePasteShortcut()

        // Vorigen Inhalt wiederherstellen mit kurzer Verzögerung
        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private func simulatePasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
