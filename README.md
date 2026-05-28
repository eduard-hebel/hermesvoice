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

- [ ] Xcode 16+ installiert (Voraussetzung)
- [x] Repo + README
- [ ] WhisperKit-CLI lokal validiert (läuft Build im Hintergrund)
- [ ] SwiftUI-Skeleton (MenuBarExtra + Settings)
- [ ] KeyboardShortcuts integriert
- [ ] AVAudioEngine-Capture
- [ ] WhisperKit-Integration
- [ ] Cleanup-Stage (optional, Claude Haiku)
- [ ] Clipboard-Insertion
- [ ] Notarized DMG-Build

## Lizenz

Privat (vorerst).
