import SwiftUI

/// Zentrales Design-System der iOS-App. EIN Accent (aus dem App-Icon gesampelt),
/// EINE Radius-Skala, EINE Motion-Sprache — app-weit gelockt. Liquid Glass (iOS 26)
/// mit `.ultraThinMaterial`-Fallback. Alle Bewegungen respektieren `reduceMotion`.
enum Brand {
    // Exakt aus AppIcon (icon-1024.png) gesampelt: Verlauf oben-links → unten-rechts.
    static let violet  = Color(red: 117/255, green: 109/255, blue: 248/255) // #756DF8
    static let blue    = Color(red:  76/255, green: 150/255, blue: 251/255) // #4C96FB
    static let accent  = Color(red:  97/255, green: 130/255, blue: 249/255) // #6182F9 (Tab-Tint)
    static let recordA = Color(red: 255/255, green:  86/255, blue:  92/255) // warmes Rot
    static let recordB = Color(red: 255/255, green: 132/255, blue:  74/255) // Bernstein

    static let gradient = LinearGradient(
        colors: [violet, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let recordingGradient = LinearGradient(
        colors: [recordA, recordB], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Eine Radius-Skala fürs ganze Projekt.
    enum R {
        static let card: CGFloat = 22
        static let pill: CGFloat = 999
    }
}

// MARK: - Erscheinungsbild (Hell / Dunkel / System)

/// In den Einstellungen wählbar, app-weit via `.preferredColorScheme` angewandt.
/// RawRepresentable<String> → direkt in `@AppStorage` speicherbar.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Auto"
        case .light:  "Hell"
        case .dark:   "Dunkel"
        }
    }

    /// nil = dem System folgen.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max"
        case .dark:   "moon"
        }
    }
}

// MARK: - Glass-Oberfläche (iOS 26 Liquid Glass, sonst Material)

extension View {
    /// Liquid Glass auf iOS 26, sauberer Material-Fallback darunter.
    @ViewBuilder
    func glassSurface(_ radius: CGFloat = Brand.R.card) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    /// Content-Layer-Karte: bewusst Material (NICHT Glass). Liquid Glass gehört laut
    /// Apple/Community nur auf Chrome/Overlays — Content-Karten bleiben Material.
    func contentCard(_ radius: CGFloat = Brand.R.card) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}

// MARK: - Mic-Button (Held des Diktat-Screens)

/// Press-Feedback: weicher Spring-Druck statt hartem Tap.
struct MicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Live-Waveform während der Aufnahme: gespiegelte Balken aus dem AudioMeter-Ringpuffer.
/// Bewusst die EINZIGE Hero-Bewegung im Aufnahme-Zustand (kein zusätzliches Pulsieren/
/// Glass — GPU/Thermik-schonend auf 8 GB). Liest AudioMeter direkt im body → nur diese
/// View rendert bei jedem Pegel-Update neu, nicht der ganze Screen.
struct WaveformView: View {
    private let meter = AudioMeter.shared

    var body: some View {
        let levels = meter.levels   // Lesen im body = Observation-Abhängigkeit
        return Canvas { ctx, size in
            let n = levels.count
            guard n > 0 else { return }
            let barWidth: CGFloat = 4
            let gap = n > 1 ? (size.width - CGFloat(n) * barWidth) / CGFloat(n - 1) : 0
            let midY = size.height / 2
            let grad = Gradient(colors: [Brand.recordA, Brand.recordB])
            for (i, lvl) in levels.enumerated() {
                let h = max(3, CGFloat(lvl) * size.height)
                let x = CGFloat(i) * (barWidth + gap)
                let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                         with: .linearGradient(grad,
                                               startPoint: CGPoint(x: 0, y: midY - size.height / 2),
                                               endPoint: CGPoint(x: 0, y: midY + size.height / 2)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Großer Diktat-Auslöser. Idle = Brand-Gradient mit dezentem, snappy „Atmen", Aufnahme =
/// warmer Gradient (die Bewegung übernimmt die Waveform), beides mit Tiefe (getönter
/// Schatten + Highlight). Kein Pegel-Scale mehr → nur die Waveform bewegt sich.
struct MicButton: View {
    let isRecording: Bool
    let busy: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var scale: CGFloat {
        guard !isRecording, !busy else { return 1.0 }
        return (breathe && !reduceMotion) ? 1.03 : 1.0
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Brand.recordingGradient : Brand.gradient)
                    .frame(width: 168, height: 168)
                    .overlay(
                        // Oberes Glanzlicht für plastische Tiefe.
                        Circle().stroke(
                            LinearGradient(colors: [.white.opacity(0.55), .clear],
                                           startPoint: .top, endPoint: .center),
                            lineWidth: 1.5)
                    )
                    .shadow(color: (isRecording ? Brand.recordA : Brand.violet).opacity(0.45),
                            radius: 30, x: 0, y: 14)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .scaleEffect(scale)
            .animation(reduceMotion ? nil :
                .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: breathe)
        }
        .buttonStyle(MicButtonStyle())
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
        .onAppear { breathe = true }
        .accessibilityLabel(isRecording ? "Aufnahme stoppen" : "Diktat starten")
    }
}
