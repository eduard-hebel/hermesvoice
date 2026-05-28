import Foundation
import OSLog

/// Optionaler zweiter Schritt: räumt das Roh-Transcript via Claude CLI auf.
/// Default off (Toggle in Settings). Nutzt Edwards eingeloggten Max Plan
/// über die Claude-CLI (siehe `ClaudeCLI`) — kein API-Key nötig.
actor CleanupService {
    func polish(_ raw: String, mode: FormatMode = .free, vocabHint: String = "", model: ClaudeModel = .haiku) async throws -> String {
        // Gelernte Schreibweisen (Auto-Learning) als zusätzlichen Hinweis — hier statt
        // in Whisper, weil Claude robust damit umgeht (kein Context-Limit-Problem).
        let vocabLine = vocabHint.isEmpty ? "" : "\n   - Bevorzugte Schreibweisen:\(vocabHint)"

        let prompt = """
        Du bekommst einen diktierten Text aus einer Speech-to-Text-Erkennung. \
        Räume ihn auf:

        1. Versprecher und Füllwörter (äh, ähm, halt, also, ne, weißt-du) raus.
        2. Offensichtliche Transkriptions-Fehler korrigieren:
           - Buchstabierte Akronyme wieder zusammenziehen (z.B. "H-U-D" → "HUD", "A-P-I" → "API").
           - Falsche Umlaute oder fehlende Buchstaben in häufigen deutschen Wörtern fixen (z.B. "Fühwörter" → "Füllwörter").
           - Isolierte Laute wie "S-" oder "M-" die offensichtlich für Wörter wie "Ähs", "Mhm" stehen, kontextgerecht setzen.\(vocabLine)
        3. Satzbau gerade ziehen, fehlende Interpunktion ergänzen.

        Modus-spezifisch:
        \(mode.cleanupInstruction)

        Inhalt NICHT erfinden, Sprache beibehalten.
        Gib NUR den bereinigten Text zurück — keine Anführungszeichen, kein Kommentar, kein Vor- oder Nachwort.

        Text:
        \(raw)
        """

        // Modell ist in den Einstellungen pro Funktion umschaltbar (Default: Haiku,
        // schnellste Latenz). Reicht für Füllwörter + Akronym-/Umlaut-Korrektur.
        let cleaned = try await ClaudeCLI.shared.run(prompt: prompt, model: model)
        return cleaned.isEmpty ? raw : cleaned
    }
}
