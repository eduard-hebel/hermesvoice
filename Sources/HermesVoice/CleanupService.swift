import Foundation

/// Optionaler zweiter Schritt: Claude Haiku räumt das Roh-Transcript.
/// Default off, Toggle in Settings. Nur dann pro-Aufruf-Kosten (~$0.0001/Diktat).
actor CleanupService {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func polish(_ raw: String) async throws -> String {
        guard let apiKey = KeychainHelper.shared.read(key: "anthropic_api_key"),
              !apiKey.isEmpty else {
            throw CleanupError.missingApiKey
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let prompt = """
        Räume folgenden diktierten Text auf: Versprecher und Füllwörter (äh, ähm, halt) raus, Satzbau gerade ziehen, Interpunktion ergänzen. \
        Inhalt nicht verändern, Sprache beibehalten. Nur den bereinigten Text zurückgeben, ohne Kommentar.

        Text:
        \(raw)
        """

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = (json?["content"] as? [[String: Any]])?.first?["text"] as? String
        return content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
    }

    enum CleanupError: Error { case missingApiKey }
}
