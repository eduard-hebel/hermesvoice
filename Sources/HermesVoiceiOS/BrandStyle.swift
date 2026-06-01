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

/// Pegelreaktive Pulsringe hinter dem Mic-Button während der Aufnahme.
/// Lauter = stärkere Ringe. Stille fällt unter `reduceMotion` weg.
struct PulseRings: View {
    let level: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Brand.recordA.opacity(0.35), lineWidth: 2)
                    .frame(width: 168, height: 168)
                    .scaleEffect(animate ? 2.0 : 1.0)
                    .opacity(animate ? 0 : 0.55)
                    .animation(
                        reduceMotion ? nil :
                            .easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(Double(i) * 0.85),
                        value: animate)
            }
        }
        .opacity(0.4 + min(level, 1) * 0.6)
        .onAppear { animate = true }
    }
}

/// Großer Diktat-Auslöser. Idle = Brand-Gradient mit sanftem „Atmen", Aufnahme =
/// warmer Gradient mit Pulsringen, beides mit Tiefe (getönter Schatten + Highlight).
struct MicButton: View {
    let isRecording: Bool
    let busy: Bool
    let level: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var scale: CGFloat {
        if isRecording { return 1.0 + min(level, 1) * 0.10 }
        return (breathe && !reduceMotion) ? 1.035 : 1.0
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording { PulseRings(level: level) }

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
                    .scaleEffect(scale)
                    .animation(reduceMotion ? nil :
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
                    .animation(.easeOut(duration: 0.12), value: level)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(scale)
            }
        }
        .buttonStyle(MicButtonStyle())
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
        .onAppear { breathe = true }
        .accessibilityLabel(isRecording ? "Aufnahme stoppen" : "Diktat starten")
    }
}
