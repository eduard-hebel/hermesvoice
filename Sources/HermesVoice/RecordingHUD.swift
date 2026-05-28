import SwiftUI
import AppKit

/// Schwebendes Mini-HUD während Aufnahme & Transkription.
/// Borderless NSPanel, always-on-top, klickbar aber nicht fokussierend.
@MainActor
final class RecordingHUDController {
    static let shared = RecordingHUDController()

    private static let width: CGFloat = 240
    private static let height: CGFloat = 56

    /// Wird vom AppState gesetzt; der X-Button im HUD ruft das auf.
    var onCancel: (() -> Void)?

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

        let view = HUDView(status: status, onCancel: { [weak self] in self?.onCancel?() })
        hostingView?.rootView = view
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let view = HUDView(status: .recording, onCancel: { [weak self] in self?.onCancel?() })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
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
            let x = frame.midX - Self.width / 2
            let y = frame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        self.hostingView = host
    }
}

private struct HUDView: View {
    let status: DictationStatus
    @State private var meter = AudioMeter.shared
    @State private var cancelHover = false
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if status.isRecording {
                WaveformBars(level: meter.level)
                    .frame(width: 32, height: 28)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)

            // Abbrechen-Button
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(cancelHover ? .white : .white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help(cancelHint)
            .onHover { cancelHover = $0 }
        }
        .padding(.horizontal, 14)
        .frame(width: 240, height: 56)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var cancelHint: String {
        switch status {
        case .recording:    "Aufnahme verwerfen"
        case .cleaning:     "Glätten abbrechen (Rohtext einfügen)"
        default:            "Abbrechen"
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

/// 5 vertikale Bars, deren Höhe sich vom Audio-Level + Sinus-Versatz ableitet.
/// Ergibt die typische Diktat-App-Waveform-Look.
private struct WaveformBars: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: barHeight(index: i, time: t))
                }
            }
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let phase = time * 6.0 + Double(index) * 0.7
        let oscillation = (sin(phase) + 1) / 2 * 0.6 + 0.4   // [0.4, 1.0]
        let base = CGFloat(level) * 22.0 + 4.0
        return base * CGFloat(oscillation)
    }
}
