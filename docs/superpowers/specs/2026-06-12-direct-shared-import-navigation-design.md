# Direct Shared Import Navigation Design

## Goal

When HermesVoice becomes active after a media file was shared to it, the user is taken directly to that import. The same screen shows processing progress and automatically changes to the transcript when processing finishes.

## Flow

1. The share extension atomically places the media file in the shared inbox.
2. `ImportController` stages the inbox envelope and publishes the resulting import job ID as a presentation request.
3. The iOS app selects the Imports tab and replaces its navigation path with that import ID.
4. `ImportDetailView` shows progress while the job exists and the transcript as soon as the matching `ImportItem` is saved.
5. A pending shared job restored after relaunch publishes the same presentation request.

## Constraints

- The share extension does not force-open the containing app.
- Manual file and Photos imports keep their existing navigation behavior.
- The import ID remains stable from inbox staging through the saved transcript.
- Errors remain visible in the same detail screen and can be retried there.

## Verification

- Unit test that ingesting a shared inbox item publishes the staged import ID.
- Existing import tests remain green.
- iPhone device build succeeds with the App Group entitlements.
- Updated app installs and launches on the connected iPhone.
