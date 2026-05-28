import SwiftUI
import AppKit

/// Schwebendes Mini-HUD während Aufnahme & Transkription.
/// Borderless NSPanel, always-on-top, klickbar aber nicht fokussierend.
@MainActor
final class RecordingHUDController {
    static let shared = RecordingHUDController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<HUDView>?
    private var currentStatus: DictationStatus = .idle

    func update(status: DictationStatus) {
        currentStatus = status
        switch status {
        case .recording, .transcribing, .cleaning:
            show(status: status)
        case .idle, .loadingModel, .error:
            hide()
        }
    }

    private func show(status: DictationStatus) {
        if panel == nil { build() }
        guard let panel else { return }

        let view = HUDView(status: status)
        hostingView?.rootView = view
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let view = HUDView(status: .recording)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 180, height: 56)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        // Oben mittig im Hauptbildschirm
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 90
            let y = frame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        self.hostingView = host
    }
}

private struct HUDView: View {
    let status: DictationStatus
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .scaleEffect(pulse && status.isRecording ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                           value: pulse)
                .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 180, height: 56)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var iconName: String {
        switch status {
        case .recording:    "mic.fill"
        case .transcribing: "waveform"
        case .cleaning:     "sparkles"
        default:            "mic"
        }
    }

    private var label: String {
        switch status {
        case .recording:    "Aufnahme"
        case .transcribing: "Transkribiere…"
        case .cleaning:     "Glätte Text…"
        default:            ""
        }
    }

    private var hint: String {
        switch status {
        case .recording: "⌘⇧Space zum Stoppen"
        default:         "einen Moment"
        }
    }
}

private extension DictationStatus {
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}
