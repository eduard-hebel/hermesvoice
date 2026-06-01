import SwiftUI

@main
struct HermesVoiceiOSApp: App {
    @State private var controller = DictationController()
    @Environment(\.scenePhase) private var scenePhase
    private let autoRecord = AutoRecordSignal.shared
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { RecordView(controller: controller) }
                    .tabItem { Label("Diktat", systemImage: "mic.fill") }
                NavigationStack { HistoryView() }
                    .tabItem { Label("Verlauf", systemImage: "clock") }
                NavigationStack { SettingsView() }
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
            }
            .tint(Brand.accent)
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { handleAutoRecord() }
            }
            .onOpenURL { url in
                // hermes://record — vom Action Button / Keyboard (Stage 2)
                if url.scheme == "hermes", url.host == "record" {
                    autoRecord.pending = true
                    handleAutoRecord()
                }
            }
        }
    }

    /// Wenn ein Sofort-Diktat angefordert wurde und das Modell bereit ist, starte
    /// die Aufnahme automatisch. (Während .loadingModel passiert nichts — dann
    /// tippt der User den Button selbst.)
    private func handleAutoRecord() {
        guard autoRecord.pending else { return }
        autoRecord.pending = false
        Task { @MainActor in
            if case .idle = controller.status { await controller.toggle() }
        }
    }
}
