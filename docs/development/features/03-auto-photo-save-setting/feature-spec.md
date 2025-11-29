# Auto Photo Save Setting – Feature Specification

## Goal
- Give users control over whether newly captured photos are automatically saved to the iPhone Photos library.
  Default is **enabled** for parity with the current experience; disabling skips all photo library writes while
  keeping the capture/analysis flow unchanged.

## Current Behavior (Swift Port)
- Captured photos are saved to the Photos library whenever permission is available; there is no user-facing toggle.
  Gallery imports are already user-initiated and should not be re-saved.
- The setting state is not persisted anywhere; permission prompts occur implicitly when saving.

## UX Placement & Copy
- Location: Settings screen (`native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Settings`). Add a new toggle
  row under the camera/permissions section.
- Copy:
  - Title: “Save captures to Photos”
  - Subtitle: “Keep a copy of shots in your iPhone library. Off keeps them only inside the app.”
- Default: On for new installs and for users without an existing stored value.
- Toggle state is local-only (UserDefaults), not synced across devices/accounts.

## Behavioral Rules
- Applies **only** to photos taken with the in-app camera; does **not** attempt to re-save gallery imports or
  downloaded/generated assets.
- When enabled and permission is authorized:
  - Save a copy of the captured image to Photos after a successful capture (post-processing, pre-upload). Use
  add-only access to avoid reads.
- When enabled and permission not determined:
  - Defer the prompt until the first eligible capture; request `PHAccessLevel.addOnly` to minimize scope.
  - If the user denies, continue the capture/analysis flow without saving; show a non-blocking toast/banner suggesting
    enabling Photos access from Settings to save copies.
- When enabled and permission is limited/denied/restricted:
  - Skip saving and surface the same non-blocking notice; never block capture.
- When the toggle is flipped on while permission is `denied`/`restricted` (or `limited` with no writable album):
  - Immediately show a modal alert explaining that Photos permission is needed to save captures, with actions:
    - “Open Settings” → deep link to app settings (`UIApplication.openSettingsURLString`).
    - “Not Now” → dismiss and leave capture behavior unchanged (no saves).
- When disabled:
  - Never write to Photos and never prompt for Photo Library permission. Existing permission status remains unchanged.
- Do not retry saving the same capture multiple times within a session; log failures but do not block the flow.

## Data & State
- Storage: `UserDefaults` key `settings.autoPhotoSaveEnabled` (Bool). Default to `true` when the key is absent.
- Migration: If a legacy key exists (none today), migrate once; otherwise seed to true.
- Exposure: Provide a read-only derived state for UI and a setter that also emits analytics/OSLog.

## Permissions Handling
- Request `PHPhotoLibrary.requestAuthorization(for: .addOnly)` on demand only when the toggle is enabled and the
  first save is attempted.
- Respect existing `limited` status; attempt save and handle the Photos error if the selected asset set is empty.
- If permission is `denied`/`restricted`, do not re-request; show the Settings deep link alert the first time the toggle
  is enabled (and again on subsequent enables if the status remains denied).
- Do not request `.readWrite`; the feature is write-only.
- Ensure `NSPhotoLibraryAddUsageDescription` string remains accurate; update copy if needed to mention optional
  saving.

## Telemetry & Logging
- Analytics events:
  - `settings.photo_save.toggle` with `enabled: Bool`.
  - `photo_save.attempt` with `result: success|denied|error`, `error_code` when applicable, and `permission_status`.
- OSLog category `PhotoSave` for failures and permission outcomes.

## QA / Test Plan
- Toggle defaults to on for a clean install; off after user flips it.
- Enabled + permission authorized: capture saves to Photos; no prompts after first grant.
- Enabled + permission not determined: first capture prompts add-only; after deny, capture still succeeds without
  saving.
- Enabled + permission limited: save succeeds to allowed album set or reports error gracefully.
- Enabled while permission denied/restricted: alert appears with Settings link; choosing Settings deep links to app
  settings; choosing Not Now continues without saving.
- Disabled: no permission prompt, no Photos writes, capture flow unchanged.
- Gallery import path never attempts to save to Photos regardless of toggle.
- Killing/relaunching the app preserves the toggle state (UserDefaults persisted).

## Out of Scope
- Cloud backup settings, per-session overrides, or per-photo prompts.
- Retroactive cleanup/removal of previously saved photos.
- Cross-device sync of the toggle.
