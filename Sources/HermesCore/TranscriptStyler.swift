import Foundation

enum TranscriptStyler {
    static func style(_ text: String, as mode: FormatMode) -> String {
        switch mode {
        case .free:
            return text
        case .shortMessage:
            return compact(text)
        case .mail:
            return email(text)
        case .note:
            return note(text)
        case .prompt:
            return aiPrompt(text)
        }
    }

    private static func compact(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func email(_ text: String) -> String {
        let body = compact(text)
        guard !body.isEmpty else { return body }
        return body
    }

    private static func note(_ text: String) -> String {
        let body = compact(text)
        guard !body.isEmpty else { return body }
        let separators = CharacterSet(charactersIn: ".!?")
        let parts = body
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return body }
        return parts.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func aiPrompt(_ text: String) -> String {
        let body = compact(text)
        guard !body.isEmpty else { return body }
        return body.hasSuffix(".") || body.hasSuffix("?") || body.hasSuffix("!") ? body : "\(body)."
    }
}
