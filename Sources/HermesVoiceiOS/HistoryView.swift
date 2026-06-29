import SwiftUI
import UIKit

/// Verlauf der letzten Diktate (geteilter HistoryStore). Tap kopiert erneut in die
/// Zwischenablage, Swipe löscht, Toolbar leert. Karten in Liquid Glass / Material.
struct HistoryView: View {
    private let store = HistoryStore.shared
    @State private var copiedID: UUID?
    @State private var showClearConfirm = false

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Diktate", systemImage: "waveform")
                } description: {
                    Text("Aufgenommene Diktate erscheinen hier.")
                }
            } else {
                List {
                    ForEach(store.entries) { entry in
                        row(entry)
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.35)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { store.remove(entry) }
                                    ActionFeedbackCenter.shared.show(
                                        "Diktat gelöscht",
                                        systemImage: "trash.fill",
                                        kind: .destructive
                                    )
                                } label: { Label("Löschen", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Verlauf")
        .toolbar {
            if !store.entries.isEmpty {
                Button("Leeren", role: .destructive) { showClearConfirm = true }
                    .tint(Brand.accent)
            }
        }
        .confirmationDialog("Ganzen Verlauf löschen?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                withAnimation { store.clear() }
                ActionFeedbackCenter.shared.show(
                    "Verlauf gelöscht",
                    systemImage: "trash.fill",
                    kind: .destructive
                )
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        Button {
            UIPasteboard.general.string = entry.text
            copiedID = entry.id
            ActionFeedbackCenter.shared.show(
                "Diktat kopiert",
                systemImage: "doc.on.doc.fill",
                kind: .success
            )
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if copiedID == entry.id { copiedID = nil }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(entry.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: copiedID == entry.id ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.body)
                    .foregroundStyle(copiedID == entry.id ? .green : Brand.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { HistoryView() }
}
