# Direct Shared Import Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open the latest shared import directly and replace its progress UI with the transcript when processing completes.

**Architecture:** `ImportController` publishes the stable job ID created while ingesting the shared inbox. The app shell owns tab selection and the Imports navigation path; `ImportDetailView` renders pending, failed, and completed states for the same ID.

**Tech Stack:** Swift 5.10, SwiftUI, Observation, XCTest, XcodeGen

---

### Task 1: Publish The Shared Import Destination

**Files:**
- Modify: `Sources/HermesCore/ImportController.swift`
- Test: `Tests/HermesVoiceTests/ImportCoreTests.swift`

- [ ] Add a test that creates a temporary `SharedImportInbox`, ingests one envelope, and expects `presentationRequestID` to equal the staged workspace job ID.
- [ ] Run `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'platform=macOS' -derivedDataPath .derived-mac CODE_SIGNING_ALLOWED=NO test` and confirm the test fails because the presentation request API does not exist.
- [ ] Inject the inbox into `ImportController`, expose a read-only `presentationRequestID`, publish staged shared jobs, and restore the newest pending shared job on initialization.
- [ ] Re-run the test suite and confirm it passes.

### Task 2: Route Directly To The Import

**Files:**
- Modify: `Sources/HermesVoiceiOS/HermesVoiceiOSApp.swift`
- Modify: `Sources/HermesVoiceiOS/ImportsView.swift`
- Modify: `Sources/HermesVoiceiOS/ImportDetailView.swift`

- [ ] Add selected-tab and Imports navigation-path state to the app shell.
- [ ] Observe `presentationRequestID`, select the Imports tab, and set the path to that ID.
- [ ] Make the UUID navigation destination unconditional so pending jobs can open before a transcript exists.
- [ ] Render progress, cancellation, failure, retry, and deletion for a pending job; keep the existing transcript UI for a completed item.

### Task 3: Verify On The Connected iPhone

**Files:**
- Verify: `HermesVoice.xcodeproj`

- [ ] Regenerate the project with `xcodegen generate`.
- [ ] Run all macOS unit tests and require zero failures.
- [ ] Build `HermesVoiceiOS` for device `00008140-000929510240801C` with team `PX8L6667HC` and require `BUILD SUCCEEDED`.
- [ ] Install with `xcrun devicectl device install app` and launch bundle `de.hermes.voice.ios`.
