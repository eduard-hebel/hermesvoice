import SwiftUI
import UIKit

struct ImportDetailView: View {
    let itemID: UUID
    @Bindable var controller: ImportController
    @State private var confirmsDeletion = false
    @State private var transcriptCopied = false

    private var item: ImportItem? {
        controller.store.entries.first(where: { $0.id == itemID })
    }

    private var job: ImportJob? {
        controller.workspace.jobs.first(where: { $0.id == itemID })
    }

    var body: some View {
        Group {
            if let item {
                completedImport(item)
            } else if let job {
                pendingImport(job)
            } else {
                ContentUnavailableView("Import nicht gefunden", systemImage: "doc.questionmark")
            }
        }
        .onChange(of: item?.summary) { oldSummary, newSummary in
            guard oldSummary != newSummary, newSummary != nil else { return }
            ActionFeedbackCenter.shared.show(
                "Kurzfassung fertig",
                systemImage: "sparkles",
                kind: .success
            )
        }
    }

    private func completedImport(_ item: ImportItem) -> some View {
        List {
            if let summary = item.summary {
                Section("Kurzfassung") {
                    Text(summary.text)
                    if !summary.keyPoints.isEmpty {
                        Text("Kernpunkte")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(summary.keyPoints, id: \.self) { point in
                            Label(point, systemImage: "checkmark.circle")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }

            Section {
                Text(item.transcript)
                    .textSelection(.enabled)
            } header: {
                HStack {
                    Text("Transkript")
                    Spacer()
                    Button(action: { copyTranscript(item.transcript) }) {
                        Label(
                            transcriptCopied ? "Kopiert" : "Kopieren",
                            systemImage: transcriptCopied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .font(.caption.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(transcriptCopied ? "Transkript kopiert" : "Transkript kopieren")
                }
            }

            Section {
                Button {
                    controller.summarize(item)
                    ActionFeedbackCenter.shared.show(
                        "Kurzfassung wird erstellt",
                        systemImage: "sparkles",
                        kind: .information
                    )
                } label: {
                    if controller.summarizingItemID == item.id {
                        ProgressView()
                    } else {
                        Label(
                            item.summary == nil ? "Kurzfassung erstellen" : "Kurzfassung neu erstellen",
                            systemImage: "sparkles"
                        )
                    }
                }
                .disabled(controller.summarizingItemID != nil || controller.isProcessing)

                ShareLink(item: shareText(item)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }

                Button("Löschen", systemImage: "trash", role: .destructive) {
                    confirmsDeletion = true
                }
            }
        }
        .navigationTitle(item.originalFilename)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Diesen Import dauerhaft löschen?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                controller.delete(item)
                ActionFeedbackCenter.shared.show(
                    "Import gelöscht",
                    systemImage: "trash.fill",
                    kind: .destructive
                )
            }
        }
    }

    private func pendingImport(_ job: ImportJob) -> some View {
        List {
            Section("Transkription") {
                VStack(alignment: .leading, spacing: 12) {
                    if let progress = progress(for: job) {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }

                    Text(statusText(for: job))
                        .font(.headline)

                    Text("Das Transkript erscheint hier automatisch, sobald es fertig ist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                if job.lastError != nil {
                    Button("Erneut versuchen", systemImage: "arrow.clockwise") {
                        controller.retry(job)
                        ActionFeedbackCenter.shared.show(
                            "Import wird erneut versucht",
                            systemImage: "arrow.clockwise",
                            kind: .information
                        )
                    }
                    .disabled(controller.isProcessing)
                } else if controller.activeJobID == job.id {
                    Button("Abbrechen", systemImage: "xmark", role: .destructive) {
                        controller.cancelImport()
                        ActionFeedbackCenter.shared.show(
                            "Import abgebrochen",
                            systemImage: "xmark.circle.fill",
                            kind: .warning
                        )
                    }
                }

                Button("Import löschen", systemImage: "trash", role: .destructive) {
                    controller.deletePendingImport(job)
                    ActionFeedbackCenter.shared.show(
                        "Import gelöscht",
                        systemImage: "trash.fill",
                        kind: .destructive
                    )
                }
            }
        }
        .navigationTitle(job.originalFilename)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusText(for job: ImportJob) -> String {
        if let error = job.lastError {
            return "Fehler: \(error)"
        }
        guard controller.activeJobID == job.id else {
            return "Wartet auf Verarbeitung …"
        }
        switch controller.phase {
        case .idle: return "Import wird gestartet …"
        case .waitingForSpeechEngine: return "Warte auf die laufende Sprachfunktion …"
        case .validating: return "Datei wird geprüft …"
        case let .preparing(current, total): return "Tonspur wird vorbereitet (\(current)/\(total)) …"
        case let .transcribing(current, total): return "Teil \(current) von \(total) wird transkribiert …"
        case .saving: return "Transkript wird gespeichert …"
        case .completed: return "Transkript ist fertig"
        case let .failed(message): return "Fehler: \(message)"
        }
    }

    private func progress(for job: ImportJob) -> Double? {
        guard controller.activeJobID == job.id else { return nil }
        switch controller.phase {
        case let .preparing(current, total):
            guard total > 0 else { return nil }
            return 0.2 * Double(current) / Double(total)
        case let .transcribing(current, total):
            guard total > 0 else { return nil }
            return 0.2 + 0.75 * Double(current) / Double(total)
        case .saving, .completed:
            return 1
        default:
            return nil
        }
    }

    private func shareText(_ item: ImportItem) -> String {
        guard let summary = item.summary else { return item.transcript }
        let points = summary.keyPoints.map { "- \($0)" }.joined(separator: "\n")
        return "\(summary.text)\n\n\(points)\n\nTranskript:\n\(item.transcript)"
    }

    private func copyTranscript(_ transcript: String) {
        UIPasteboard.general.string = transcript
        transcriptCopied = true
        ActionFeedbackCenter.shared.show(
            "Transkript kopiert",
            systemImage: "doc.on.doc.fill",
            kind: .success
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            transcriptCopied = false
        }
    }
}
