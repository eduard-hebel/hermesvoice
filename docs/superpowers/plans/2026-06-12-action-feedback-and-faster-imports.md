# Action Feedback and Faster Imports Plan

1. Add failing tests for the shared feedback state and ordered batch transcription API.
2. Implement a shared feedback center plus platform-specific banner and haptic presentation.
3. Move transcript copy controls into transcript headers and label summary bullets as key points.
4. Wire meaningful copy, delete, retry, cancel, import, and summary actions to feedback.
5. Replace per-part sequential transcription calls with WhisperKit's ordered multi-file batch API while keeping all decode settings unchanged.
6. Run unit tests, macOS build, iOS build, install, and launch on the connected iPhone.
