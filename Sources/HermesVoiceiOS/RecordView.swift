import SwiftUI

/// Haupt-Diktat-Screen. Held ist der Mic-Button (Tap = Start/Stop) mit Tiefe,
/// Pulsringen und Live-Timer. Status, „Kopiert"-Pille und Transcript-Karte in
/// Liquid Glass. Hintergrund-Glow folgt dem Zustand. Alle Bewegungen springen weich.
struct RecordView: View {
    @Bindable var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { controller.status == .recording }
    private var busy: Bool { controller.status == .transcribing || controller.status == .loadingModel }

    var body: some View {
        ZStack {
            backgroundGlow
            VStack(spacing: 24) {
                Spacer(minLength: 4)
                statusLine
                timer
                if isRecording {
                    WaveformView()
                        .frame(height: 88)
                        .padding(.horizontal, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                MicButton(isRecording: isRecording, busy: busy) {
                    Task { await controller.toggle() }
                }
                if controller.showCopied { copiedPill }
                if !controller.lastText.isEmpty && !isRecording { transcriptCard }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .navigationTitle("HermesVoice")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: controller.showCopied)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: controller.lastText)
        .animation(.easeInOut(duration: 0.35), value: controller.status)
        // Differenzierte Haptik je Zustandswechsel: Start / Stop / Fertig / Fehler.
        .sensoryFeedback(trigger: controller.status) { old, new in
            switch new {
            case .recording:                       return .impact(weight: .medium)
            case .transcribing:                    return .impact(weight: .light)
            case .idle where old == .transcribing: return .success
            case .error:                           return .warning
            default:                               return nil
            }
        }
    }

    // MARK: Hintergrund

    private var backgroundGlow: some View {
        let glow = isRecording ? Brand.recordA : Brand.violet
        return RadialGradient(colors: [glow.opacity(isRecording ? 0.26 : 0.16), .clear],
                              center: .init(x: 0.5, y: 0.42), startRadius: 8, endRadius: 360)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: isRecording)
    }

    // MARK: Status

    private var statusLine: some View {
        Group {
            switch controller.status {
            case .loadingModel:
                Label("Modell wird vorbereitet … (einmalig)", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            case .idle:
                Text("Tippen zum Diktieren")
                    .foregroundStyle(.secondary)
            case .recording:
                Label("Aufnahme läuft", systemImage: "waveform")
                    .foregroundStyle(Brand.recordA)
                    .symbolEffect(.variableColor.iterative, options: reduceMotion ? .nonRepeating : .repeating)
            case .transcribing:
                Label("Transkribiere …", systemImage: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.secondary)
            case .error(let m):
                Label(m, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout.weight(.medium))
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var timer: some View {
        if isRecording, let start = controller.recordingStartedAt {
            Text(timerInterval: start...Date(timeInterval: 3600, since: start),
                 countsDown: false, showsHours: false)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Brand.recordA)
                .transition(.opacity)
        } else {
            Color.clear.frame(height: 28)   // hält das Layout stabil
        }
    }

    // MARK: Kopiert-Pille

    private var copiedPill: some View {
        Label("Kopiert · zurückwischen & einfügen", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassSurface(Brand.R.pill)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: Transcript

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Letztes Diktat")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = controller.lastText
                    controller.showCopied = true
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                        .font(.footnote.weight(.medium))
                }
                .tint(Brand.accent)
            }
            ScrollView {
                Text(controller.lastText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 170)
        }
        .padding(18)
        .contentCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
