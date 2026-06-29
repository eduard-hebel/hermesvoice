import Foundation

enum SpeechOperation: Equatable {
    case dictation
    case mediaImport
    case modelLoading
    case voiceCommand
}

enum SpeechOperationError: Error, Equatable {
    case busy(SpeechOperation)
}

extension SpeechOperationError: LocalizedError {
    var errorDescription: String? {
        "Eine andere Sprachfunktion läuft bereits. Bitte kurz warten."
    }
}

@MainActor
final class SpeechOperationCoordinator {
    static let shared = SpeechOperationCoordinator()

    private var active: (token: UUID, operation: SpeechOperation)?

    var activeOperation: SpeechOperation? {
        active?.operation
    }

    func begin(_ operation: SpeechOperation) throws -> UUID {
        if let active {
            throw SpeechOperationError.busy(active.operation)
        }
        let token = UUID()
        active = (token, operation)
        return token
    }

    func acquire(_ operation: SpeechOperation) async throws -> UUID {
        while active != nil {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return try begin(operation)
    }

    func end(_ token: UUID) {
        guard active?.token == token else { return }
        active = nil
    }
}
