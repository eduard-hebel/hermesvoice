import SwiftUI
import UIKit

/// Nutzer-Wörterbuch (Wispr-„personalized dictionary"-Pendant, on-device): eigene
/// Begriffe/Namen/Dialektwörter eintragen, die nach jedem Diktat automatisch korrigiert
/// werden. „Gehört als" → „Korrekt".
struct DictionaryView: View {
    private let store = UserDictionaryStore.shared
    @State private var heard = ""
    @State private var correct = ""
    @FocusState private var focus: Field?

    private enum Field { case heard, correct }

    private var canAdd: Bool {
        !heard.trimmingCharacters(in: .whitespaces).isEmpty &&
        !correct.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Gehört als (z. B. Alter)", text: $heard)
                    .focused($focus, equals: .heard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .correct }
                TextField("Korrekt (z. B. Oida)", text: $correct)
                    .focused($focus, equals: .correct)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addEntry)
                Button(action: addEntry) {
                    Label("Hinzufügen", systemImage: "plus.circle.fill")
                }
                .disabled(!canAdd)
            } header: {
                Text("Neue Korrektur")
            } footer: {
                Text("Nach jedem Diktat wird „Gehört als“ automatisch durch „Korrekt“ ersetzt — ganzes Wort, Groß-/Kleinschreibung egal. Gut für Namen, Akronyme und Dialekt (z. B. „oida“).")
            }

            if !store.entries.isEmpty {
                Section("Meine Korrekturen (\(store.entries.count))") {
                    ForEach(store.entries) { e in
                        HStack(spacing: 10) {
                            Text(e.heard)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(e.correct)
                                .fontWeight(.medium)
                        }
                    }
                    .onDelete { store.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("Wörterbuch")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.accent)
    }

    private func addEntry() {
        guard canAdd else { return }
        store.add(heard: heard, correct: correct)
        heard = ""; correct = ""
        focus = .heard
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

#Preview {
    NavigationStack { DictionaryView() }
}
