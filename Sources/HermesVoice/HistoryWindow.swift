import SwiftUI
import AppKit

/// Verlaufs-Fenster: links die Diktate, rechts der volle Text zum Lesen + Kopieren.
/// Löst das "man sieht den vollen Text nicht"-Problem des Menubar-Submenus.
struct HistoryWindow: View {
    @State private var store = HistoryStore.shared
    @State private var selection: HistoryEntry.ID?
    @State private var copied = false

    private var selectedEntry: HistoryEntry? {
        store.entries.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(store.entries, selection: $selection) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.preview)
                        .lineLimit(2)
                        .font(.callout)
                    HStack(spacing: 6) {
                        Image(systemName: entry.mode.iconName)
                        Text(entry.mode.label)
                        Text("·")
                        Text(entry.timestamp, format: .dateTime.day().month().hour().minute())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .tag(entry.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let entry = selectedEntry {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        Text(entry.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    Divider()
                    HStack {
                        Text("\(entry.text.count) Zeichen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Clipboard.copy(entry.text, feedbackMessage: "Diktat kopiert")
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: {
                            Label(copied ? "Kopiert ✓" : "In Zwischenablage", systemImage: "doc.on.doc")
                        }
                    }
                    .padding(12)
                }
            } else {
                ContentUnavailableView("Kein Diktat ausgewählt",
                                       systemImage: "text.bubble",
                                       description: Text("Wähle links ein Diktat, um den vollen Text zu lesen."))
            }
        }
        .navigationTitle("Verlauf")
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            if selection == nil { selection = store.entries.first?.id }
        }
    }
}
