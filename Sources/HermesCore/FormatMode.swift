import Foundation

/// Bestimmt wie Cleanup-Stage den Text bearbeitet.
enum FormatMode: String, CaseIterable, Identifiable, Codable {
    case free
    case mail
    case prompt
    case note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free:   "Frei"
        case .mail:   "E-Mail"
        case .prompt: "AI-Prompt"
        case .note:   "Notiz"
        }
    }

    var iconName: String {
        switch self {
        case .free:   "text.alignleft"
        case .mail:   "envelope"
        case .prompt: "sparkles"
        case .note:   "list.bullet"
        }
    }

    /// Mode-spezifische Instruktion für die Cleanup-Stage.
    /// Wird in den Prompt eingebettet zusätzlich zu den Basis-Regeln.
    var cleanupInstruction: String {
        switch self {
        case .free:
            return """
            Stil: Behalte den Original-Stil bei. Nicht umformulieren, nicht förmlicher oder lockerer machen.
            """
        case .mail:
            return """
            Stil: Formuliere es als professionelle E-Mail. \
            Wenn keine Anrede erkennbar ist, ergänze keine. Wenn ein Empfänger erwähnt wurde, eleganter formulieren. \
            Kein Abschluss / Signatur ergänzen. Sätze etwas formeller als gesprochener Text, aber natürlich.
            """
        case .prompt:
            return """
            Stil: Behandle das als AI-Prompt-Eingabe. \
            Halte technische Begriffe und Namen exakt bei (auch unkonventionelle Schreibweise). \
            Formuliere präzise, behalte Anweisungs-Charakter. \
            Keine Höflichkeitsfloskeln, keine Anrede. Direkt zur Sache.
            """
        case .note:
            return """
            Stil: Komprimiere auf das Wesentliche. \
            Wenn der Text mehrere Punkte enthält → als Stichpunkt-Liste mit "- " formatieren. \
            Wenn ein Fließtext-Gedanke → kurze prägnante Sätze, kein Ausschmücken. \
            Telegram-Stil ist ok.
            """
        }
    }
}
