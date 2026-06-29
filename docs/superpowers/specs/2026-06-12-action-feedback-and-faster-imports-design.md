# HermesVoice Action Feedback and Faster Imports

## Goal

HermesVoice confirms meaningful completed actions consistently on iPhone and Mac, places transcript copying beside the transcript, clarifies summary key points, and speeds up long media imports without changing the Whisper model or decoding quality settings.

## Interaction design

- Native button press states remain the immediate acknowledgement for navigation and simple controls.
- Completed actions show a short, unobtrusive banner such as `Transkript kopiert` or `Import gelöscht`.
- iPhone adds success, warning, or destructive haptics only for meaningful outcomes.
- Mac uses the same visual banner and supported trackpad feedback for meaningful outcomes.
- Copy lives in the transcript header and changes briefly to a confirmed state.
- Summary bullets are explicitly introduced as `Kernpunkte`.

## Transcription performance

- Keep the existing `large-v3-v20240930_turbo_632MB` model.
- Keep the current language, temperature, prompt, token, and timestamp options.
- Keep the existing ten-minute media boundaries and final transcript order.
- Submit prepared parts to WhisperKit as one ordered batch so its supported worker pool can process independent parts concurrently.
- Preserve cancellation, progress reporting, error propagation, and temporary-file cleanup.

This optimization changes scheduling only. It does not switch to a smaller model or lower decoding settings.

## Verification

- Unit tests cover feedback replacement/dismissal and ordered batch transcript assembly.
- Existing import, cancellation, persistence, summary, and coordinator tests remain green.
- Build both macOS and iOS schemes.
- Install and launch the iOS app on the connected iPhone.
