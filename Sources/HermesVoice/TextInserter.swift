import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// Schreibt Text in den Clipboard und simuliert ⌘V im aktiven Fenster.
/// Gibt zurück ob die ⌘V-Simulation wahrscheinlich erfolgreich war
/// (= App hat Accessibility-Permission).
struct TextInserter {
    @discardableResult
    func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let canSimulate = AXIsProcessTrusted()
        if canSimulate {
            simulatePasteShortcut()
        }

        // Vorigen Inhalt wiederherstellen mit kurzer Verzögerung
        // (auch wenn nicht eingefügt — der neue Text bleibt aber im Clipboard,
        // damit der User selber ⌘V drücken kann)
        if let previous, canSimulate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        return canSimulate
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
