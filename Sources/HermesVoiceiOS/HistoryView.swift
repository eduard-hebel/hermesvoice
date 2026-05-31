import SwiftUI
import UIKit

/// Verlauf der letzten Diktate (geteilter HistoryStore). Tap kopiert den Eintrag
/// erneut in die Zwischenablage.
struct HistoryView: View {
    private let store = HistoryStore.shared
    @State private var copiedID: UUID?

    var body: some View {
        List {
            if store.entries.isEmpty {
                ContentUnavailableView("Noch keine Diktate", systemImage: "clock",
                                       description: Text("Aufgenommene Diktate erscheinen hier."))
            }
            ForEach(store.entries) { entry in
                Button {
                    UIPasteboard.general.string = entry.text
                    copiedID = entry.id
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text).lineLimit(3).foregroundStyle(.primary)
                        Text(entry.timestamp, style: .relative)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .trailing) {
                    if copiedID == entry.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle("Verlauf")
    }
}
