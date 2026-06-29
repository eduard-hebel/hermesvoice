import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportWindow: View {
    @Bindable var controller: ImportController
    @State private var selection: UUID?
    @State private var showsFileImporter = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !controller.workspace.jobs.isEmpty {
                    Section("Nicht abgeschlossen") {
                        ForEach(controller.workspace.jobs) { job in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.originalFilename)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let error = job.lastError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                HStack {
                                    Button("Erneut versuchen") {
                                        controller.retry(job)
                                        ActionFeedbackCenter.shared.show(
                                            "Import wird erneut versucht",
                                            systemImage: "arrow.clockwise",
                                            kind: .information
                                        )
                                    }
                                        .disabled(controller.isProcessing)
                                    Button("Löschen", role: .destructive) {
                                        controller.deletePendingImport(job)
                                        ActionFeedbackCenter.shared.show(
                                            "Import gelöscht",
                                            systemImage: "trash.fill",
                                            kind: .destructive
                                        )
                                    }
                                    .disabled(controller.activeJobID == job.id)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Transkripte") {
                    ForEach(controller.store.entries) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.originalFilename)
                                .font(.headline)
                                .lineLimit(1)
                            Text(item.transcript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .tag(item.id)
                    }
                }
            }
            .navigationTitle("Importe")
            .toolbar {
                ToolbarItem {
                    Button {
                        showsFileImporter = true
                    } label: {
                        Label("Datei importieren", systemImage: "plus")
                    }
                    .disabled(controller.isProcessing)
                }
            }
        } detail: {
            if let selection,
               let item = controller.store.entries.first(where: { $0.id == selection }) {
                MacImportDetailView(itemID: item.id, controller: controller)
            } else {
                ContentUnavailableView(
                    "Audio oder Video importieren",
                    systemImage: "waveform.badge.plus",
                    description: Text("Datei hierher ziehen oder über + auswählen. Maximal 60 Minuten, vollständig lokal.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if controller.isProcessing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(phaseText)
                    Spacer()
                    Button("Abbrechen", role: .destructive) {
                        controller.cancelImport()
                        ActionFeedbackCenter.shared.show(
                            "Import abgebrochen",
                            systemImage: "xmark.circle.fill",
                            kind: .warning
                        )
                    }
                }
                .padding(12)
                .background(.bar)
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.audio, .movie, .audiovisualContent],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                controller.importFile(url, source: .file)
                ActionFeedbackCenter.shared.show(
                    "Import gestartet",
                    systemImage: "waveform.badge.plus",
                    kind: .information
                )
            } catch {
                controller.message = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !controller.isProcessing else { return false }
            controller.importFile(url, source: .file)
            ActionFeedbackCenter.shared.show(
                "Import gestartet",
                systemImage: "waveform.badge.plus",
                kind: .information
            )
            return true
        }
        .alert("HermesVoice", isPresented: messageIsPresented) {
            Button("OK", role: .cancel) { controller.message = nil }
        } message: {
            Text(controller.message ?? "Unbekannter Fehler")
        }
        .onAppear {
            controller.processNextPendingImport()
        }
        .onChange(of: controller.phase) { _, phase in
            if case .completed = phase {
                ActionFeedbackCenter.shared.show(
                    "Transkript fertig",
                    systemImage: "checkmark.circle.fill",
                    kind: .success
                )
            }
        }
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(
            get: { controller.message != nil },
            set: { if !$0 { controller.message = nil } }
        )
    }

    private var phaseText: String {
        switch controller.phase {
        case .idle: "Bereit"
        case .waitingForSpeechEngine: "Warte auf die laufende Sprachfunktion …"
        case .validating: "Datei wird geprüft …"
        case let .preparing(current, total): "Tonspur \(current)/\(total) wird vorbereitet ..."
        case let .transcribing(current, total): "Transkription \(current)/\(total) ..."
        case .saving: "Wird gespeichert ..."
        case .completed: "Abgeschlossen"
        case let .failed(message): "Fehler: \(message)"
        }
    }
}

private struct MacImportDetailView: View {
    let itemID: UUID
    @Bindable var controller: ImportController
    @State private var confirmsDeletion = false
    @State private var transcriptCopied = false

    private var item: ImportItem? {
        controller.store.entries.first(where: { $0.id == itemID })
    }

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.originalFilename)
                                .font(.title2.bold())
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
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
                                    item.summary == nil ? "Kurzfassung" : "Neu zusammenfassen",
                                    systemImage: "sparkles"
                                )
                            }
                        }
                        .disabled(controller.summarizingItemID != nil || controller.isProcessing)
                    }

                    if let summary = item.summary {
                        GroupBox("Kurzfassung") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(summary.text)
                                if !summary.keyPoints.isEmpty {
                                    Text("Kernpunkte")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                    ForEach(summary.keyPoints, id: \.self) { point in
                                        Label(point, systemImage: "checkmark.circle")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox {
                        Text(item.transcript)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack {
                            Label("Transkript", systemImage: "text.alignleft")
                            Spacer()
                            Button(action: { copyTranscript(item.transcript) }) {
                                Label(
                                    transcriptCopied ? "Kopiert" : "Kopieren",
                                    systemImage: transcriptCopied ? "checkmark.circle.fill" : "doc.on.doc"
                                )
                                .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack {
                        ShareLink(item: shareText(item)) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button("Löschen", systemImage: "trash", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
                .padding(24)
            }
            .confirmationDialog(
                "Diesen Import dauerhaft löschen?",
                isPresented: $confirmsDeletion
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
            .onChange(of: item.summary) { oldSummary, newSummary in
                guard oldSummary != newSummary, newSummary != nil else { return }
                ActionFeedbackCenter.shared.show(
                    "Kurzfassung fertig",
                    systemImage: "sparkles",
                    kind: .success
                )
            }
        } else {
            ContentUnavailableView("Import nicht gefunden", systemImage: "doc.questionmark")
        }
    }

    private func shareText(_ item: ImportItem) -> String {
        guard let summary = item.summary else { return item.transcript }
        let points = summary.keyPoints.map { "- \($0)" }.joined(separator: "\n")
        return "\(summary.text)\n\n\(points)\n\nTranskript:\n\(item.transcript)"
    }

    private func copyTranscript(_ transcript: String) {
        Clipboard.copy(transcript, feedbackMessage: "Transkript kopiert")
        transcriptCopied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            transcriptCopied = false
        }
    }
}
