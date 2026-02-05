# Post-Onboarding System Design

## Status: Decisions Made — Implementation Ready

---

## Key Decisions Summary

| Decision | Choice |
|----------|--------|
| Post-onboarding welcome copy | No credits mention. "You've been exploring. Now it's your turn." |
| Permissions approach | **No primer.** Only request must-have permissions during intro (camera/gallery). Location and notifications deferred. |
| Camera permission | Asked first time user opens camera (required for functionality) |
| Photo Library permission | Asked first time user opens gallery (required for functionality) |
| Location permission | Asked on **second camera use**, on confirm page (after taking photo) — once only |
| Notification permission | Asked **after purchase**, on confirm page — once only |
| Audio generating modal | Show when first discovery completes |
| Celebration modal | Skip — focus on "Discover More" momentum |
| Credits exhausted | Full-screen conversion view (not alert) |
| IPOP & Voice selection | After first purchase (not during onboarding) |

---

## Existing System Analysis

### Free Credits: 5 Total

From `2025122702_grant_5_credits_on_signup.sql`:
```sql
-- Grant 5 starter credits: 3 for discoveries + 2 for intro voiceovers
```

**The math:**
- 1 credit = 1 discovery
- 1 credit = 1 audio guide
- 5 credits = 3 discoveries + 2 audio guides (for first 2 discoveries)

### "Intro Mode" System

`FreeCreditsAlertTracker.swift` manages "intro mode":

- **Intro mode active** = credits exhausted alert hasn't been shown yet
- During intro mode, **audio toggle is locked ON** (auto-generating audio)
- Intro mode ends when credits hit 0

**How it plays out:**
| Discovery | Credits Used | Credits After | Audio? |
|-----------|-------------|---------------|--------|
| 1st | 1 (discovery) + 1 (audio) = 2 | 3 remaining | Yes |
| 2nd | 1 (discovery) + 1 (audio) = 2 | 1 remaining | Yes |
| 3rd | 1 (discovery) | 0 remaining | No (not enough credits) |

### Existing Permission Services

| Permission | Service | Method |
|------------|---------|--------|
| Camera | `CameraCaptureService` | `AVCaptureDevice.requestAccess(for: .video)` |
| Photo Library | `PhotoLibrarySelectionService` | `PHPhotoLibrary.requestAuthorization(for: .readWrite)` |
| Location | `CoreLocationDiscoveryLocationService` | `CLLocationManager.requestWhenInUseAuthorization()` |
| Notifications | `OnboardingPermissionsCoordinator` | `UNUserNotificationCenter.requestAuthorization()` |

---

## Complete User Flow

```
SIGN UP COMPLETE
        ↓
WELCOME SCREEN
"You've been exploring. Now it's your turn."
[Take a Photo] [Use Gallery]
        ↓
        ├── CAMERA PATH ────────────────────────────────────┐
        │                                                   │
        │   Camera system prompt (required)                 │
        │   ↓                                               │
        │   User takes photo                                │
        │                                                   │
        ├── GALLERY PATH ───────────────────────────────────┤
        │                                                   │
        │   Photo Library prompt (required)                 │
        │   ↓                                               │
        │   User selects photo                              │
        │                                                   │
        ↓
CONFIRMATION SCREEN
(On 2nd+ camera use: Location permission prompt — once only)
[Confirm]
        ↓
FIRST DISCOVERY STREAMS (~8-10s)
        ↓
DISCOVERY COMPLETE
        ↓
AUDIO GENERATING MODAL (first discovery only)
"Your audio guide is generating..."
[Create Another] / [Read This Discovery]
        ↓
USER CREATES #2 OR READS #1
(Toast notifies when #1 audio ready)
        ↓
SECOND DISCOVERY
(Audio auto-generates)
        ↓
THIRD DISCOVERY
(No audio — not enough credits)
        ↓
CREDITS EXHAUSTED FULL-SCREEN
"3 stories you didn't know yesterday"
[Unlock 100 Discoveries]
        ↓
PURCHASE
        ↓
CONFIRMATION SCREEN (post-purchase)
(Notification permission prompt — once only)
        ↓
POST-PURCHASE CONFIGURATION
Voice selection + IPOP preferences
        ↓
CONTINUE EXPLORING
```

---

## Phase 1: Welcome Screen

**Replaces:** Current `PostOnboardingCarousel`

**Design:**

```
┌─────────────────────────────────────┐
│                                     │
│   "You've been exploring.           │
│    Now it's your turn."             │
│                                     │
│   Your first discovery is           │
│   waiting. Point your camera        │
│   at anything that makes you        │
│   curious.                          │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    📷 Take a Photo          │   │
│   └─────────────────────────────┘   │
│                                     │
│         Use Gallery                 │
│                                     │
└─────────────────────────────────────┘
```

**Key points:**
- No mention of credits or limitations
- Acknowledges pre-onboarding ("You've been exploring")
- Skip all configuration
- Straight to action

---

## Phase 2: Permissions (Simplified — No Primer)

**Decision:** No permissions primer modal. We only request permissions when needed:

### During Intro Mode (First 3 Discoveries)

Only **must-have** permissions are requested:

| Permission | When Requested | Notes |
|------------|----------------|-------|
| Camera | First time user opens camera | Required for functionality |
| Photo Library | First time user opens gallery | Required for functionality |
| Location | **Not requested** | Deferred to second camera use |
| Notifications | **Not requested** | Deferred to after purchase |

### After Intro Mode (Post-Purchase)

| Permission | When Requested | Notes |
|------------|----------------|-------|
| Notifications | On confirm page, once | After user purchases, first time they land on confirm page |
| Location | On confirm page, second camera use, once | After user takes a photo on their 2nd camera use |

### Implementation

Tracked in `FreeCreditsAlertTracker`:
- `cameraUseCount: Int` — Incremented after each successful camera capture
- `hasRequestedLocationPermission: Bool` — True after location permission requested
- `hasRequestedNotificationPermission: Bool` — True after notification permission requested

**Location request logic:**
```swift
// In prepareConfirmation(), for camera flow only:
if cameraUseCount >= 2 && !hasRequestedLocationPermission {
    await locationService.startTrackingIfNeeded() // triggers permission prompt
    markLocationPermissionRequested()
}
```

**Notification request logic:**
```swift
// In prepareConfirmation():
if !isInIntroMode && !hasRequestedNotificationPermission {
    await pushService.requestPushAuthorizationIfNeeded()
    markNotificationPermissionRequested()
}
```

**Why this approach:**
- Reduces friction during intro (user only sees camera/gallery permission)
- Location permission asked after user has experienced value (2nd discovery)
- Notifications asked after user has purchased (invested in the app)
- Each optional permission asked exactly once

---

## Phase 3: First Discovery Experience

### During Streaming

Existing system works well. No changes needed. User sees:
- Their photo
- Title streaming in
- Short description streaming in
- Full narrative streaming in

### After Stream Completes (First Discovery Only)

**Trigger:** Stream completes on first discovery (detected via discovery count or `hasSeenAudioGeneratingModal`)

**Timing:** Modal appears after stream completes — user has seen the full title, short description, and narrative. The "wow" moment has landed.

**Show Audio Generating Modal:**

```
┌─────────────────────────────────────┐
│                                     │
│         🎧                          │
│                                     │
│   "Your audio guide is              │
│    generating..."                   │
│                                     │
│   You can create another discovery  │
│   while you wait, or read this one  │
│   first.                            │
│                                     │
│   (We're making this faster — soon  │
│   it'll be almost instant!)         │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    Create Another           │   │
│   └─────────────────────────────┘   │
│                                     │
│         Read This Discovery         │
│                                     │
└─────────────────────────────────────┘
```

**"Create Another"** → Triggers "Discover More" flow (existing behavior)
**"Read This Discovery"** → Dismisses modal, stays on current discovery

**Why this works:**
- Sets expectations (audio is coming)
- Gives them something to do
- When they return from creating #2, audio for #1 is ready
- No boring wait time

**Show only on first discovery:** Track via `hasSeenAudioGeneratingModal: Bool` in UserDefaults

---

## Phase 4: Credits Exhausted — Full-Screen Conversion

**Trigger:** Credits reach 0 (replaces current alert)

**Design:**

```
┌─────────────────────────────────────┐
│                                     │
│   ┌───┐ ┌───┐ ┌───┐                 │
│   │ 1 │ │ 2 │ │ 3 │  (their images) │
│   └───┘ └───┘ └───┘                 │
│                                     │
│   "3 discoveries.                   │
│    3 stories you didn't know        │
│    yesterday."                      │
│                                     │
│   Ready for more?                   │
│                                     │
│   ┌─────────────────────────────┐   │
│   │  🔓 Unlock 100 Discoveries  │   │
│   │        $X.XX                │   │
│   └─────────────────────────────┘   │
│                                     │
│   That's just $0.0X per discovery   │
│                                     │
│   ─────────────────────────────     │
│                                     │
│   What you get:                     │
│   • 100 discoveries                 │
│   • Generate audio guides           │
│   • Credits never expire            │
│                                     │
│         See all packs               │
│                                     │
│   ┌─────────────────────────────┐   │
│   │       Not now               │   │
│   └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Copy notes:**
- Shows their actual discoveries (visual proof of value)
- "3 stories you didn't know yesterday" — personal accomplishment
- "Unlock" is positive vs "Buy"
- Price anchoring ("That's just $0.0X per discovery")
- "See all packs" → Secondary option for 1000-credit pack
- "Never expire" → Removes time pressure objection

**Replaces:** Current `freeCreditsExhaustedAtAudioGeneration` and `freeCreditsExhaustedAtConfirm` alerts

---

## Phase 5: Post-Purchase Configuration

**Trigger:** After first credit purchase completes

### Voice Selection Slide

```
┌─────────────────────────────────────┐
│                                     │
│   "Choose your narrator"            │
│                                     │
│   Pick a voice for your audio       │
│   guides. You can change this       │
│   anytime in Settings.              │
│                                     │
│   [Voice options with samples]      │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    Continue                 │   │
│   └─────────────────────────────┘   │
│                                     │
│         Skip for now                │
│                                     │
└─────────────────────────────────────┘
```

### IPOP Preferences Slide

```
┌─────────────────────────────────────┐
│                                     │
│   "What matters most to you?"       │
│                                     │
│   We'll shape your stories around   │
│   what you care about.              │
│                                     │
│   [IPOP sliders]                    │
│   • Ideas & Concepts                │
│   • People & Stories                │
│   • Objects & Details               │
│   • Physical Sensations             │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    Start Exploring          │   │
│   └─────────────────────────────┘   │
│                                     │
│         Skip for now                │
│                                     │
└─────────────────────────────────────┘
```

**Each slide individually skippable.**

---

## Final Decisions

### 1. Audio Generating Modal Timing

**Decision:** Show after stream completes.

User sees the full streaming experience (title, short description, narrative appearing). After stream completes, modal appears. This lets the "wow" moment land before we guide them to create another.

### 2. Permissions — Simplified Approach (No Primer)

**Decision:** No permissions primer modal. Only request must-have permissions during intro.

- Camera/gallery prompts appear when needed (required for functionality)
- Location: Requested on **second camera use**, on confirm page (once only)
- Notifications: Requested **after purchase**, on confirm page (once only)
- User can manage all permissions in Settings

**Why no primer:**
- Reduces friction during first 3 discoveries
- User experiences value before being asked for optional permissions
- Simpler UX — no intermediate modal before system prompts

### 3. Settings Integration

- Permissions section in Settings (already implemented)
- If permission not yet requested: Tap triggers system prompt
- If permission denied: Tap opens System Settings

---

## Settings: Permission Management

### New Settings Section: "Permissions"

```
┌─────────────────────────────────────┐
│ Permissions                         │
├─────────────────────────────────────┤
│                                     │
│ Location                    [>]     │
│ For richer, location-aware stories  │
│                                     │
│ Notifications               [>]     │
│ Know when discoveries are ready     │
│                                     │
│ Camera                      [>]     │
│ Take photos to discover             │
│                                     │
│ Photo Library               [>]     │
│ Select photos to discover           │
│                                     │
└─────────────────────────────────────┘
```

**Behavior per permission:**

| State | Tap Action |
|-------|------------|
| Not yet requested | Trigger system prompt |
| Denied | Open System Settings app |
| Granted | Show "Enabled" (no action needed) |

**Implementation:** Check current authorization status:
- Location: `CLLocationManager().authorizationStatus`
- Notifications: `UNUserNotificationCenter.current().notificationSettings()`
- Camera: `AVCaptureDevice.authorizationStatus(for: .video)`
- Photos: `PHPhotoLibrary.authorizationStatus(for: .readWrite)`

---

## Implementation Checklist

### New Components Built

- [x] `AudioGeneratingModalView` — First-discovery audio wait guidance
- [x] `CreditsExhaustedFullScreenView` — Replaces current alert
- [x] `PostPurchaseConfigurationFlow` — Voice + IPOP after purchase
- [x] `VoiceSelectionSlideView` — Voice selection slide
- [x] `IPOPPreferencesSlideView` — IPOP preferences slide
- [x] Settings permissions section — All 4 permissions manageable in Settings

### Files Modified

- [x] `PostOnboardingCarousel.swift` — Updated welcome copy ("You've been exploring. Now it's your turn.")
- [x] `DiscoveryCreationFlowViewModel.swift` — Conditional permission requests (location on 2nd camera, notifications post-purchase)
- [x] `DiscoveryCreationFlowView.swift` — Audio generating modal and credits exhausted fullscreen
- [x] `FreeCreditsAlertTracker.swift` — Track camera use count, permission request flags, intro state
- [x] `SettingsView.swift` — Permissions section added

### State Tracked (UserDefaults via FreeCreditsAlertTracker)

- `cameraUseCount: Int` — Number of camera captures
- `hasRequestedLocationPermission: Bool` — Location permission requested (on 2nd camera use)
- `hasRequestedNotificationPermission: Bool` — Notification permission requested (post-purchase)
- `hasSeenAudioGeneratingModal: Bool` — First discovery modal shown
- `hasShownCreditsExhausted: Bool` — Credits exhausted screen shown (ends intro mode)
- `hasCompletedPostPurchaseConfig: Bool` — Post-purchase config completed

### Permission State Checking

For Settings and primer logic, check current authorization:
```swift
// Location
CLLocationManager().authorizationStatus
// → .notDetermined, .denied, .authorizedWhenInUse, .authorizedAlways

// Notifications
await UNUserNotificationCenter.current().notificationSettings()
// → .notDetermined, .denied, .authorized, .provisional

// Camera
AVCaptureDevice.authorizationStatus(for: .video)
// → .notDetermined, .denied, .authorized, .restricted

// Photos
PHPhotoLibrary.authorizationStatus(for: .readWrite)
// → .notDetermined, .denied, .authorized, .limited, .restricted
```

---

## Analytics Events

| Event | When |
|-------|------|
| `post_onboarding_shown` | Welcome screen appears |
| `permissions_primer_shown` | Primer modal appears |
| `permissions_primer_accepted` | User taps "Let's Go" |
| `permissions_primer_skipped` | User taps "Skip" |
| `location_permission_granted` | System prompt → allowed |
| `location_permission_denied` | System prompt → denied |
| `notification_permission_granted` | System prompt → allowed |
| `notification_permission_denied` | System prompt → denied |
| `first_discovery_completed` | First discovery done |
| `audio_modal_shown` | Audio generating modal appears |
| `audio_modal_create_another` | User taps "Create Another" |
| `audio_modal_read_discovery` | User taps "Read This Discovery" |
| `credits_exhausted_shown` | Full-screen conversion appears |
| `credits_exhausted_purchase_tapped` | User taps Unlock |
| `credits_exhausted_see_packs` | User taps See all packs |
| `credits_exhausted_declined` | User taps Not now |
| `purchase_completed` | StoreKit success |
| `post_purchase_voice_selected` | Voice chosen |
| `post_purchase_voice_skipped` | Voice slide skipped |
| `post_purchase_ipop_set` | IPOP configured |
| `post_purchase_ipop_skipped` | IPOP slide skipped |
