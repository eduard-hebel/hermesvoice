# HermesVoice

**Private, on-device voice dictation for macOS and iPhone.** A free, offline alternative to Wispr Flow / Superwhisper: speak, get text, paste anywhere — your audio never leaves the device.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20iOS%2018%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![Engine](https://img.shields.io/badge/engine-WhisperKit%20(on--device)-black)
![License](https://img.shields.io/badge/license-MIT-green)

Transcription runs **100% on-device** via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (OpenAI Whisper on the Apple Neural Engine). No cloud, no account, no API key, works in airplane mode.

---

## Why

Cloud dictation apps lose your transcript on a Wi-Fi blip, truncate long brain-dumps, charge a subscription, and send your voice to someone else's servers. HermesVoice does the same job locally: it can't lose your words to the network, it's free, and nothing leaves your phone or Mac.

The one honest trade-off vs. cloud apps: no server-side LLM "polish." Whisper's `large-v3-turbo` already punctuates naturally, and a built-in personal dictionary handles names, acronyms, and dialect.

## Features

**Both platforms**
- On-device Whisper transcription (no internet, no key, no account)
- Multilingual + code-switching (mixing e.g. English terms into German) — native to Whisper
- Local history of recent dictations

**macOS** (menu-bar app)
- Global hotkey to start/stop dictation
- Pastes into the focused app via the Accessibility API (system-wide)
- Optional text cleanup via the local Claude CLI (no API key — uses your Max plan subprocess)
- Vocabulary that learns from your corrections

**iPhone**
- **Action Button** trigger → record in any context
- **Custom keyboard** that auto-inserts the last dictation into any app (clipboard-based, aligned with iOS 26.4's "swipe back to your app" flow)
- **Live waveform** + level-reactive "listening" pulse while recording
- **Personal dictionary** — `heard → correct` post-correction for names, acronyms, dialect (e.g. *oida*)
- Light / Dark / System appearance, Liquid Glass UI (iOS 26)
- `large-v3-turbo` (632 MB, quantized) bundled for offline first-launch

## Tech stack

Swift · SwiftUI · WhisperKit · AVFoundation · AppIntents (Action Button) · UIInputViewController (keyboard) · [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the project definition.

## Project structure

```
Sources/
  HermesCore/        # shared, platform-agnostic core (Transcriber, AudioRecorder,
                     #   AudioMeter, History/Recording/Vocabulary/UserDictionary stores)
  HermesVoice/       # macOS menu-bar app
  HermesVoiceiOS/    # iOS app (RecordView, DictationController, DictionaryView, …)
  HermesKeyboard/    # iOS keyboard extension (clipboard auto-insert)
Models/              # WhisperKit model (gitignored — see Setup)
docs/POLISH.md       # design system / UI rules
project.yml          # XcodeGen project definition (.xcodeproj is generated, gitignored)
```

## Setup

Requires **macOS + Xcode 26** and an Apple developer team for device signing.

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Download the on-device Whisper model (gitignored — too large for git)
./scripts/download-model.sh        # ~646 MB into Models/

# 3. Generate the Xcode project
xcodegen generate

# 4. Open it
open HermesVoice.xcodeproj
```

In Xcode pick a scheme — **HermesVoice** (macOS) or **HermesVoiceiOS** (iPhone) — and Run.

**iOS signing:** set your team in `project.yml` (`DEVELOPMENT_TEAM`) or via Xcode's Signing & Capabilities, then `xcodegen generate` again. Build **Release** for a physical device (Debug dylibs don't launch standalone).

**iPhone keyboard (optional):** Settings → General → Keyboard → Keyboards → add *HermesVoice* and allow **Full Access** (needed to read the clipboard). Bind the Action Button to the *HermesVoice* shortcut to start dictation hands-free.

## How it works on iPhone (the iOS reality)

iOS keyboard extensions are capped at ~77 MB RAM and can't reliably use the mic, so Whisper can't run *inside* the keyboard. Instead: the **app** records + transcribes on-device (triggered by the Action Button), copies the result, and the **HermesVoice keyboard** inserts it into whatever app you're in. That's one app-hop per dictation — the same limitation every on-device iOS dictation tool has.

## Swapping the model

The bundled model folder name lives in `Sources/HermesVoiceiOS/DictationController.swift` (`bundledModelFolder`) and in `project.yml`. To use the full 1.6 GB `openai_whisper-large-v3-v20240930_turbo` (slightly better, more RAM), download that folder instead and update both references.

## Credits

Built on [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax. Models from the [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) Hugging Face repo.

## License

MIT — see [LICENSE](LICENSE).
