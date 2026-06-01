# HermesVoice iOS — Polish-Regeln (verbindlich)

Destillat aus Recherche (Reddit r/SwiftUI + r/iOSProgramming, X/Grok zu jmtrivedi/
Dimillian/mecid/christianselig, Apple WWDC25, Donny Wals, Paul Hudson) für eine
on-device Diktat-Utility auf iOS 26 / 8 GB-Hardware. Diese Regeln gelten für alle
weiteren UI-Änderungen.

## Layer-Trennung (wichtigste Regel)
- **Liquid Glass NUR auf Chrome/Overlays**: Tab-Bar, Toolbar, schwebende Controls,
  Sheets, transiente Chips (z. B. „Kopiert"-Pille). → `glassSurface()`.
- **Content bleibt Material**: Karten, Listen-Zeilen, Transcript-Text. → `contentCard()`
  (`.regularMaterial`). NIE Glass auf Content, kein Glass-auf-Glass.
- System-Komponenten bekommen Glass auf iOS 26 automatisch (mit Xcode 26 kompiliert).

## Motion
- **Springs statt linearer Eases**: `.snappy` (UI-Reaktion), `.bouncy` (nur Hero-Toggle),
  `.smooth` (ruhig). Kein `.easeInOut(duration:)` als Default.
- **Nur `transform`/`opacity` animieren**, nie Layout-Properties (Layout-Thrashing).
- **Instant > „slow razzle dazzle"** (Selig): kurze, dezente Bewegung. Idle-Atmen snappy.
- **Eine Hero-Bewegung pro Zustand.** Aufnahme = Waveform; KEINE Pulsringe/Glass
  zusätzlich (GPU/Thermik auf 8 GB; Glass und Motion konkurrieren ums Frame-Budget).
- Alles `> reduceMotion` muss `accessibilityReduceMotion` respektieren.

## Haptik (differenziert, nicht spammen)
- Start = `.impact(.medium)`, Stop = `.impact(.light)`, Fertig = `.success`,
  Fehler = `.warning`, Copy/Auswahl = `.selection`.
- `.sensoryFeedback` reicht (iOS 17+); Core Haptics nur für custom Patterns.
- Feedback beim Auslösen, nicht erst nach der Animation.

## Symbole & Typo
- `.symbolEffect` für SF-Symbols: `.variableColor` (aktiv), `.bounce` (Tap),
  `.contentTransition(.symbolEffect(.replace))` (mic↔stop).
- `.contentTransition(.numericText())` für mitlaufende Zahlen/Timer.
- Native `List`/`Form`/`TabView` als Basis; custom nur für Hero-Momente.

## Brand
- EIN Accent, aus dem App-Icon gesampelt (Violett `#756DF8` → Blau `#4C96FB`,
  Tint `#6182F9`). App-weit gelockt. Aufnahme = warm (`recordA/recordB`).
- EINE Radius-Skala (`Brand.R`). Off-Black/Off-White statt reinem Schwarz/Weiß.

## Whisper / Erkennung
- KEIN `de-AT`-Sprachtoken in Whisper — Qualität kommt über Modellgröße, nicht Sprache.
- KEINE `promptTokens`/Vokabel-Bias auf WhisperKit (sprengt 448-Token-Context bei
  langem Audio → 0 chars; + Empty-Result-Bug Issue #372). Vokabel-Fix lief am Mac über
  Claude-Cleanup, die es on-device/iOS nicht gibt.
- Modell gebundelt (`download: false`), kein HF-Download beim Erststart.

## Libraries (Stand Juni 2026)
- **Pow** (EmergeTools) — optionale Micro-Effects, aber Maintenance-Mode (04/2024).
- **DSWaveformImage** — Alternative zur eigenen Canvas-Waveform.
- Inferno/Wave/Lottie = für diese Utility Overkill. Native APIs sind das Rückgrat.

## Quellen
- WWDC25 „Build a SwiftUI app with the new design": https://developer.apple.com/videos/play/wwdc2025/323/
- GlassEffectContainer: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- LiquidGlassReference: https://github.com/conorluddy/LiquidGlassReference
- Donny Wals (Liquid Glass): https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/
- Janum Trivedi (fluid interfaces): https://x.com/jmtrivedi/status/1848471238584504443
- Christian Selig (instant > slow): https://x.com/christianselig/status/1995895179631296541
- Paul Hudson SwiftUI Agent Skill: https://www.hackingwithswift.com/articles/282/swiftui-agent-skill-claude-codex-ai
- WhisperKit promptTokens-Bug: https://github.com/argmaxinc/WhisperKit/issues/372
