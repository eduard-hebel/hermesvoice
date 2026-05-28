# HermesVoice

Eigene macOS-Diktat-App. Überall Spracheingabe per Global-Shortcut. Lokal, keine Pro-Sekunde-Kosten, native macOS-App.

## Ziel

Wispr-Flow-Alternative für meinen eigenen Bedarf. Kein Abo, keine Cloud-Abhängigkeit (es sei denn opt-in Cleanup), native Mac-Polish.

## Architektur

| Schicht | Komponente | Begründung |
|---------|-----------|------------|
| UI | Swift + SwiftUI + MenuBarExtra | Native Polish, kleine Binary, App Store-fähig |
| Global Hotkey | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | macOS-Standard im Mac-OSS-Ökosystem |
| Audio | AVFoundation (`AVAudioEngine`) | Native Mic-Capture, niedrige Latenz |
| STT | [WhisperKit](https://github.com/argmaxinc/WhisperKit) mit `large-v3` | Lokal auf Apple Neural Engine, keine API-Kosten, hohe Qualität |
| Cleanup (optional) | Claude Haiku 4.5 via Anthropic API | Toggle, default off. Bei aktivem Toggle: Versprecher raus, Sätze gerade ziehen |
| Insertion | `NSPasteboard` + simulierter ⌘V | Funktioniert überall wo Text-Input geht |

## Permissions (einmalig)

- Microphone
- Accessibility (für ⌘V Simulation)
- Input Monitoring (für Global Hotkey)

## Hardware

- Target: Apple Silicon (M1+), macOS 14+ wegen WhisperKit
- RAM-Footprint im Idle: ~50 MB. Bei aktivem Modell: ~2–3 GB (Whisper Large V3)

## Aktueller Stand

- [x] Repo + README
- [x] WhisperKit-CLI lokal validiert (siehe Benchmarks unten)
- [x] SwiftUI-Skeleton (MenuBarExtra + Settings)
- [x] KeyboardShortcuts integriert (Code)
- [x] AVAudioEngine-Capture (Code)
- [x] WhisperKit-Integration (Code)
- [x] Cleanup-Stage (optional, Claude Haiku) (Code)
- [x] Clipboard-Insertion (Code)
- [ ] **Xcode 26.5 installiert** (Voraussetzung für Build)
- [ ] Xcode-Projekt generieren via `xcodegen`
- [ ] Erster Build + Run + Permission-Flow
- [ ] Notarized DMG-Build mit Apple-Developer-ID

## Benchmarks (M1 / 8 GB / macOS 26.5)

Whisper Large V3 lokal, deutscher TTS-Sample (17 s Audio):

| Lauf | Dauer | Anmerkung |
|------|-------|-----------|
| 1. Start | **~9 Min** | Einmalige Apple-Neural-Engine-Kompilierung des Modells |
| 2. Start | **~9 Sek** | Cache aktiv: Load <5 s, Transkription 3.6 s |
| Real-time-factor | **0.20** | 1 Sek Audio → 0.2 Sek Transkription (≈ 5× Realtime) |

Qualität: praktisch fehlerfrei, deutsche Fachbegriffe (Apple Silicon, WhisperKit) korrekt, kontextuelle Korrekturen (TTS sagte „Whisper Kit", Whisper schrieb „WhisperKit"). Einziger Schönheitsfehler: „Notarization" → „Notarisation".

## Lizenz

Privat (vorerst).
