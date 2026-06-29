import SwiftUI
import AppKit

@main
struct HermesVoiceApp: App {
    @State private var appState = AppState()
    @State private var importController = ImportController()
    @State private var actionFeedback = ActionFeedbackCenter.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appState)
        } label: {
            MenubarIconLabel(status: appState.status)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 520, height: 460)
                .actionFeedbackOverlay(actionFeedback)
        }

        Window("Verlauf", id: "history") {
            HistoryWindow()
                .actionFeedbackOverlay(actionFeedback)
        }

        Window("Importe", id: "imports") {
            ImportWindow(controller: importController)
                .actionFeedbackOverlay(actionFeedback)
        }
        .defaultSize(width: 980, height: 680)
    }
}

/// Menubar-Icon mit Status-spezifischer SF-Symbol-Animation.
private struct MenubarIconLabel: View {
    let status: DictationStatus

    var body: some View {
        switch status {
        case .recording:
            Image(systemName: "mic.fill")
                .symbolEffect(.pulse, options: .repeating, value: status)
        case .transcribing:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating, value: status)
        case .cleaning:
            Image(systemName: "sparkles")
                .symbolEffect(.bounce, options: .repeating, value: status)
        case .loadingModel:
            Image(systemName: "arrow.down.circle")
                .symbolEffect(.pulse, options: .repeating, value: status)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
        case .idle:
            Image(systemName: "mic.fill")
        }
    }
}

/// Triggert das Onboarding beim ersten Start — via klassisches NSWindow,
/// weil MenuBarExtra-Apps kein Default-Fenster zeigen können.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let done = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !done {
            Task { @MainActor [weak self] in
                self?.presentOnboarding()
            }
        }
    }

    @MainActor
    private func presentOnboarding() {
        let view = OnboardingView()
            .actionFeedbackOverlay(ActionFeedbackCenter.shared)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Willkommen bei HermesVoice"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
