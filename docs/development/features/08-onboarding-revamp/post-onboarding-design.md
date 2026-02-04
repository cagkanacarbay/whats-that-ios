# Post-Onboarding System Design

## Status: Decisions Made — Implementation Ready

---

## Key Decisions Summary

| Decision | Choice |
|----------|--------|
| Post-onboarding welcome copy | No credits mention. "You've been exploring. Now it's your turn." |
| Permissions approach | Primer screen before system prompts, bundled per path |
| Location permission | Camera path only (gallery gets EXIF) |
| Notification permission | Both paths, before first discovery |
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
        │   PERMISSIONS PRIMER MODAL                        │
        │   "A few quick permissions"                       │
        │   • Location — for richer stories                 │
        │   • Notifications — know when ready               │
        │   • Camera — to take photos                       │
        │   [Let's Go] [Skip]                               │
        │                                                   │
        │   ↓ (if Let's Go)                                 │
        │   Location system prompt                          │
        │   ↓                                               │
        │   Notification system prompt                      │
        │   ↓                                               │
        │   Camera system prompt (when picker opens)        │
        │                                                   │
        ├── GALLERY PATH ───────────────────────────────────┤
        │                                                   │
        │   PERMISSIONS PRIMER MODAL                        │
        │   "A few quick permissions"                       │
        │   • Notifications — know when ready               │
        │   • Photo Library — to select photos              │
        │   [Let's Go] [Skip]                               │
        │                                                   │
        │   ↓ (if Let's Go)                                 │
        │   Notification system prompt                      │
        │   ↓                                               │
        │   Photo Library prompt (when picker opens)        │
        │                                                   │
        ↓
CONFIRMATION SCREEN
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

## Phase 2: Permissions Primer

### Camera Path Primer

**Trigger:** User taps "Take a Photo" for the first time

```
┌─────────────────────────────────────┐
│                                     │
│   "A few quick permissions"         │
│                                     │
│   We need a couple things to give   │
│   you the best experience:          │
│                                     │
│   📍 Location                       │
│   Stories about exactly where       │
│   you're standing                   │
│                                     │
│   🔔 Notifications                  │
│   Know when your discovery          │
│   is ready                          │
│                                     │
│   📷 Camera                         │
│   Take photos of anything curious   │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    Let's Go                 │   │
│   └─────────────────────────────┘   │
│                                     │
│         Skip for now                │
│                                     │
└─────────────────────────────────────┘
```

**Flow after "Let's Go":**
1. `CLLocationManager.requestWhenInUseAuthorization()` → Location system prompt
2. `UNUserNotificationCenter.requestAuthorization()` → Notification system prompt
3. Camera UI opens → Camera system prompt appears

**If "Skip for now":**
- Skip location and notification prompts
- Camera UI still opens (camera prompt still appears — required for functionality)

### Gallery Path Primer

**Trigger:** User taps "Use Gallery" for the first time

```
┌─────────────────────────────────────┐
│                                     │
│   "A few quick permissions"         │
│                                     │
│   We need a couple things to give   │
│   you the best experience:          │
│                                     │
│   🔔 Notifications                  │
│   Know when your discovery          │
│   is ready                          │
│                                     │
│   🖼️ Photo Library                  │
│   Select photos to discover         │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    Let's Go                 │   │
│   └─────────────────────────────┘   │
│                                     │
│         Skip for now                │
│                                     │
└─────────────────────────────────────┘
```

**Flow after "Let's Go":**
1. `UNUserNotificationCenter.requestAuthorization()` → Notification system prompt
2. Photo picker opens → Photo library prompt appears (if needed)

**No location needed:** Gallery photos have EXIF location data

### Gallery First, Then Camera Later (Common Path)

**Scenario:** User goes Gallery path first, then later taps Camera tab. This is a common flow, not an edge case.

**Solution:** Track primer state per path:
- `hasSeenCameraPrimer: Bool` (UserDefaults)
- `hasSeenGalleryPrimer: Bool` (UserDefaults)

When they tap Camera after going Gallery first:
- Show simplified location-only primer (see "Final Decisions" section)
- Notifications already handled (or skipped) during Gallery flow

**Implementation note:** Check `UNUserNotificationCenter.current().notificationSettings()` to determine if notifications were already requested/granted.

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
│   • Ask follow-up questions         │
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

### 2. Permissions Primer — "Skip for now" Behavior

**Decision:** If they skip, we don't nag. No permissions are requested.

- Camera/gallery prompts still appear (required for functionality)
- Location and notifications are NOT requested during onboarding
- User can enable permissions later via Settings

**Settings Integration:**
- Add permission controls to Settings screen
- If permission not yet requested: Show toggle that triggers the system prompt
- If permission denied: Show option that opens System Settings so user can enable

### 3. Gallery-First Then Camera (Common Path)

**Decision:** Show simplified location-only primer.

This is NOT an edge case — many users will go Gallery first. When they later tap Camera:

```
┌─────────────────────────────────────┐
│                                     │
│   📍 "Enable location for           │
│       richer stories"               │
│                                     │
│   We can tell you about exactly     │
│   where you're standing — not       │
│   just what you're looking at.      │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    Enable Location          │   │
│   └─────────────────────────────┘   │
│                                     │
│         Not Now                     │
│                                     │
└─────────────────────────────────────┘
```

**Flow:**
- "Enable Location" → Location system prompt → Camera opens
- "Not Now" → Camera opens (no location prompt)

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

### New Components to Build

- [ ] `PermissionsPrimerView` — The modal explaining permissions (camera path vs gallery path variants)
- [ ] `LocationOnlyPrimerView` — Simplified primer for camera-after-gallery flow
- [ ] `PermissionsPrimerCoordinator` — Tracks which primers have been shown, checks permission states
- [ ] `AudioGeneratingModalView` — First-discovery audio wait guidance
- [ ] `CreditsExhaustedFullScreenView` — Replaces current alert
- [ ] `PostPurchaseConfigurationFlow` — Voice + IPOP after purchase
- [ ] `SettingsPermissionsSection` — New section in Settings for permission management

### Files to Modify

- [ ] `PostOnboardingCarousel.swift` — Update welcome copy
- [ ] `DiscoveryCreationFlowViewModel.swift` — Integrate primer flow
- [ ] `DiscoveryCreationFlowView.swift` — Add primer modal presentation
- [ ] `DiscoveryStreamingStageView.swift` — Add audio generating modal (after stream completes)
- [ ] `FreeCreditsAlertTracker.swift` — Track first-discovery modal state
- [ ] `SettingsView.swift` — Add permissions section
- [ ] `SettingsViewModel.swift` — Add permission state checking and actions

### State to Track (UserDefaults)

- `hasSeenCameraPrimer: Bool`
- `hasSeenGalleryPrimer: Bool`
- `hasSeenAudioGeneratingModal: Bool`
- `hasSeenCreditsExhaustedScreen: Bool`
- `hasCompletedPostPurchaseConfig: Bool`

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
