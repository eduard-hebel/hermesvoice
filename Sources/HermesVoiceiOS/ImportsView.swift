import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ImportsView: View {
    @Bindable var controller: ImportController
    @State private var showsFileImporter = false
    @State private var selectedVideo: PhotosPickerItem?
    @State private var photoImportError: String?

    var body: some View {
        List {
            importActions

            if controller.isProcessing {
                processingSection
            }

            if !controller.workspace.jobs.isEmpty {
                failedImportsSection
            }

            Section("Transkripte") {
                if controller.store.entries.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Importe",
                        systemImage: "waveform.badge.plus",
                        description: Text("Wähle eine Audio- oder Videodatei bis 60 Minuten.")
                    )
                } else {
                    ForEach(controller.store.entries) { item in
                        NavigationLink(value: item.id) {
                            ImportRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Importe")
        .navigationDestination(for: UUID.self) { id in
            ImportDetailView(itemID: id, controller: controller)
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
        .onChange(of: selectedVideo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else { return }
                    await MainActor.run {
                        controller.importFile(
                            movie.url,
                            source: .photoLibrary,
                            removeSourceAfterStaging: true
                        )
                        ActionFeedbackCenter.shared.show(
                            "Videoimport gestartet",
                            systemImage: "waveform.badge.plus",
                            kind: .information
                        )
                        selectedVideo = nil
                    }
                } catch {
                    await MainActor.run {
                        photoImportError = error.localizedDescription
                        selectedVideo = nil
                    }
                }
            }
        }
        .onChange(of: controller.isProcessing, initial: true) { _, processing in
            UIApplication.shared.isIdleTimerDisabled = processing
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
        .onDisappear {
            if !controller.isProcessing {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        .alert("HermesVoice", isPresented: messageIsPresented) {
            Button("OK", role: .cancel) {
                controller.message = nil
                photoImportError = nil
            }
        } message: {
            Text(photoImportError ?? controller.message ?? "Unbekannter Fehler")
        }
    }

    private var importActions: some View {
        Section {
            Button {
                showsFileImporter = true
            } label: {
                Label("Audio oder Video aus Dateien", systemImage: "folder")
            }
            .disabled(controller.isProcessing)

            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                Label("Video aus Fotos", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(controller.isProcessing)
        } footer: {
            Text("Alles bleibt auf diesem Gerät. Für lange Importe muss HermesVoice geöffnet bleiben.")
        }
    }

    private var processingSection: some View {
        Section("Verarbeitung") {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: phaseProgress)
                Text(phaseText)
                    .font(.subheadline.weight(.semibold))
                Text("Bitte HermesVoice im Vordergrund lassen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Abbrechen", role: .destructive) {
                    controller.cancelImport()
                    ActionFeedbackCenter.shared.show(
                        "Import abgebrochen",
                        systemImage: "xmark.circle.fill",
                        kind: .warning
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var failedImportsSection: some View {
        Section("Nicht abgeschlossen") {
            ForEach(controller.workspace.jobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.originalFilename)
                        .font(.headline)
                    if let error = job.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            .buttonStyle(.borderedProminent)
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
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(
            get: { controller.message != nil || photoImportError != nil },
            set: { if !$0 { controller.message = nil; photoImportError = nil } }
        )
    }

    private var phaseText: String {
        switch controller.phase {
        case .idle: "Bereit"
        case .waitingForSpeechEngine: "Warte auf die laufende Sprachfunktion …"
        case .validating: "Datei wird geprüft …"
        case let .preparing(current, total): "Tonspur wird vorbereitet (\(current)/\(total)) ..."
        case let .transcribing(current, total): "Teil \(current) von \(total) wird transkribiert ..."
        case .saving: "Transkript wird gespeichert ..."
        case .completed: "Import abgeschlossen"
        case let .failed(message): "Fehler: \(message)"
        }
    }

    private var phaseProgress: Double? {
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
}

private struct ImportRow: View {
    let item: ImportItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.originalFilename)
                .font(.headline)
                .lineLimit(1)
            Text(item.transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(formattedDuration)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var formattedDuration: String {
        let totalSeconds = max(0, Int(item.duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedMovie(url: destination)
        }
    }
}
