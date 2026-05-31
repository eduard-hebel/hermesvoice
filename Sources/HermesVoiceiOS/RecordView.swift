import SwiftUI

/// Haupt-Diktat-Screen: großer Mic-Button (Tap = Start/Stop), Live-Pegel,
/// Status, „Kopiert"-Bestätigung und das letzte Transkript zum Nachlesen.
struct RecordView: View {
    @Bindable var controller: DictationController

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)
            statusLine
            micButton
            if controller.showCopied {
                Label("Kopiert ✓ — zur App zurückwischen & einfügen", systemImage: "doc.on.clipboard")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            if !controller.lastText.isEmpty {
                ScrollView {
                    Text(controller.lastText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxHeight: 220)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("HermesVoice")
        .animation(.easeInOut(duration: 0.2), value: controller.showCopied)
    }

    private var statusLine: some View {
        Group {
            switch controller.status {
            case .loadingModel: Label("Modell lädt … (einmalig)", systemImage: "arrow.down.circle")
            case .idle:         Text("Tippen zum Diktieren").foregroundStyle(.secondary)
            case .recording:    Label("Aufnahme läuft – nochmal tippen zum Stoppen", systemImage: "waveform").foregroundStyle(.red)
            case .transcribing: Label("Transkribiere …", systemImage: "waveform.badge.magnifyingglass")
            case .error(let m): Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
    }

    private var micButton: some View {
        let isRecording = controller.status == .recording
        let level = AudioMeter.shared.level   // @Observable → Pegel treibt die Animation
        let scale = isRecording ? 1.0 + CGFloat(level) * 0.4 : 1.0
        let busy = controller.status == .transcribing || controller.status == .loadingModel
        return Button {
            Task { await controller.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.25) : Color.accentColor.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .scaleEffect(scale)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(isRecording ? .red : Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}

// MARK: - Xcode-Canvas-Vorschau (zeigt die Screens live, ohne iPhone)

#Preview("1 · Bereit") {
    NavigationStack { RecordView(controller: DictationController(previewStatus: .idle)) }
}

#Preview("2 · Aufnahme läuft") {
    NavigationStack { RecordView(controller: DictationController(previewStatus: .recording)) }
}

#Preview("3 · Fertig – kopiert") {
    let controller = DictationController(previewStatus: .idle)
    controller.lastText = "Hey, kannst du mir bitte die Unterlagen für das Meeting morgen früh schicken? Am besten gleich heute Abend noch."
    controller.showCopied = true
    return NavigationStack { RecordView(controller: controller) }
}
