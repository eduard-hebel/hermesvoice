import AppKit

/// macOS-Clipboard-Helfer. Auf dem Mac wandert ein History-Eintrag zurück ins
/// Pasteboard, damit der User ihn per ⌘V erneut einfügen kann. (Die iOS-App nutzt
/// stattdessen UIPasteboard direkt in ihrem eigenen Controller.)
enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
