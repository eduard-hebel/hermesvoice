import SwiftUI

@main
struct HermesVoiceiOSApp: App {
    @State private var controller = DictationController()
    @State private var importController = ImportController()
    @State private var actionFeedback = ActionFeedbackCenter.shared
    @State private var selectedTab: AppTab = .dictation
    @State private var importPath: [UUID] = []
    @Environment(\.scenePhase) private var scenePhase
    private let autoRecord = AutoRecordSignal.shared
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                NavigationStack { RecordView(controller: controller) }
                    .tabItem { Label("Diktat", systemImage: "mic.fill") }
                    .tag(AppTab.dictation)
                NavigationStack { HistoryView() }
                    .tabItem { Label("Verlauf", systemImage: "clock") }
                    .tag(AppTab.history)
                NavigationStack(path: $importPath) {
                    ImportsView(controller: importController)
                }
                    .tabItem { Label("Importe", systemImage: "square.and.arrow.down") }
                    .tag(AppTab.imports)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .tint(Brand.accent)
            .preferredColorScheme(appearance.colorScheme)
            .actionFeedbackOverlay(actionFeedback, bottomInset: 72)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    handleAutoRecord()
                    importController.ingestSharedInbox()
                }
            }
            .onAppear { importController.ingestSharedInbox() }
            .onChange(of: importController.presentationRequestID, initial: true) { _, importID in
                guard let importID else { return }
                selectedTab = .imports
                importPath = [importID]
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

private enum AppTab: Hashable {
    case dictation
    case history
    case imports
    case settings
}
