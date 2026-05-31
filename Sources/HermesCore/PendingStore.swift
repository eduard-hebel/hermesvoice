import Foundation

/// Geteilter „Briefkasten" zwischen Haupt-App und Tastatur-Erweiterung über eine
/// App Group. Die App schreibt nach jedem Diktat den Text hinein; die Hermes-Tastatur
/// liest ihn und fügt ihn mit EINEM Tipp in die gerade aktive App ein.
/// `consumed` verhindert versehentliches Doppel-Einfügen.
enum PendingStore {
    /// Muss identisch in den Entitlements von App UND Tastatur stehen.
    static let appGroup = "group.de.hermes.voice"
    private static let key = "pendingTranscription"

    struct Pending: Codable {
        let text: String
        let createdAt: Date
        var consumed: Bool
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Von der App nach erfolgreichem Diktat aufgerufen.
    static func write(_ text: String) {
        guard let d = defaults,
              let data = try? JSONEncoder().encode(Pending(text: text, createdAt: Date(), consumed: false))
        else { return }
        d.set(data, forKey: key)
    }

    /// Letztes Diktat (egal wie alt) — für den „Einfügen"-Button der Tastatur.
    static func latest() -> Pending? {
        guard let d = defaults, let data = d.data(forKey: key),
              let p = try? JSONDecoder().decode(Pending.self, from: data) else { return nil }
        return p
    }

    /// Frisches (≤ maxAge), noch nicht eingefügtes Diktat — für Auto-Insert nach
    /// dem Zurückwischen aus der App.
    static func unconsumedFresh(maxAge: TimeInterval = 300) -> String? {
        guard let p = latest(), !p.consumed,
              Date().timeIntervalSince(p.createdAt) <= maxAge else { return nil }
        return p.text
    }

    static func markConsumed() {
        guard let d = defaults, var p = latest() else { return }
        p.consumed = true
        if let data = try? JSONEncoder().encode(p) { d.set(data, forKey: key) }
    }
}
