import SwiftUI
import AppKit

@main
struct HermesVoiceApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("HermesVoice", systemImage: appState.status.iconName) {
            MenuBarContent()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 520, height: 440)
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
            DispatchQueue.main.async { [weak self] in
                self?.presentOnboarding()
            }
        }
    }

    private func presentOnboarding() {
        let view = OnboardingView()
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
