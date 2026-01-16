# UI Requirements: Version Control & Compliance

## Screens Overview

| Screen | Trigger | Blocking? |
|--------|---------|-----------|
| Maintenance Mode | `app_config.maintenance_mode = TRUE` | **Yes** (blocks all app usage) |
| Legal Acceptance Modal | ToS or Privacy version newer than user's latest acceptance | **Yes** (must accept) |
| App Update Prompt (Soft) | New app version, reminder at 1/3/7 days | No (dismissible) |
| App Update Prompt (Force, grace) | Force update within 7-day grace | No (prominent but dismissible) |
| App Update Prompt (Force, expired) | Force update, grace period expired | **Yes (blocking)** |
| App Update Prompt (Force, immediate) | Force update, version < min_supported_version | **Yes (blocking immediately)** |

---

## 1. Legal Acceptance Modal

**Purpose:** Require explicit checkbox acceptance before user can continue.

### Layout

```
┌─────────────────────────────────────────┐
│                                         │
│      📜 Terms Update Required           │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Terms of Service v1.1           │    │
│  │                                 │    │
│  │ [message from version_log]      │    │
│  │ e.g., "Added section on audio   │    │
│  │ guides and data processing."    │    │
│  │                                 │    │
│  │ [View Full Terms →]             │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Privacy Policy v1.1             │    │
│  │                                 │    │
│  │ [message from version_log]      │    │
│  │                                 │    │
│  │ [View Full Policy →]            │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ☐ I have read and agree to the         │
│    updated Terms of Service and         │
│    Privacy Policy                       │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │    Accept and Continue          │    │  ← Disabled until checked
│  └─────────────────────────────────┘    │
│                                         │
│          [Sign Out]                     │
│                                         │
└─────────────────────────────────────────┘
```

### Behavior

- **Checkbox** → Enables "Accept and Continue" button when checked
- **Accept and Continue** → Calls `accept-terms` endpoint → Records acceptance → Dismisses modal (silently retries if API fails)
- **View Full Terms/Policy** → Opens in-app browser or Safari
- **Delete Account** → **Sign Out**: Logs user out immediately. "Delete Account" is accessible from Settings if desired, but declining terms simply means stopping usage.

### Styling Notes
- Modal cannot be dismissed by tapping outside or swiping
- Use existing app styling (dark mode, accent colors)
- Cards for each updated document (show only those that need acceptance)
- **iPad**: Present as centered card (not full-screen), consistent with other iPad modals

---

## 2. App Update Prompt (Soft)

**Purpose:** Inform user a new app version is available. Shown at 1, 3, and 7 days.

### Layout

```
┌─────────────────────────────────────────┐
│                                         │
│    🎉 New Version Available!            │
│                                         │
│    Version 1.2.0                        │
│                                         │
│    [message from version_log]           │
│    e.g., "New iPad support, improved    │
│    audio playback, bug fixes."          │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │       Update Now                │    │
│  └─────────────────────────────────┘    │
│                                         │
│           [Maybe Later]                 │
│                                         │
└─────────────────────────────────────────┘
```

### Behavior

- **Update Now** → Opens App Store page
- **Maybe Later** → Dismisses, updates local reminder state
- Reminder schedule: Day 1, Day 3, Day 7 from first detection
- After Day 7: Stop showing for this version
- New version released: Reset schedule

---

## 3. App Update Prompt (Force, within grace)

**Purpose:** Required update is coming. User has limited time.

### Layout

```
┌─────────────────────────────────────────┐
│                                         │
│    ⚠️ Required Update                   │
│                                         │
│    Version 1.3.0 is required            │
│                                         │
│    You have 5 days to update before     │
│    this becomes mandatory.              │
│                                         │
│    [message from version_log]           │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │       Update Now                │    │
│  └─────────────────────────────────┘    │
│                                         │
│       [Remind Me Later]                 │
│                                         │
└─────────────────────────────────────────┘
```

### Behavior

- **Update Now** → Opens App Store
- **Remind Me Later** → Dismisses, continues to app
- Shows countdown of days remaining

---

## 4. Force Update Required (grace expired)

**Purpose:** Block app usage until update.

### Layout

```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│              🔒                         │
│                                         │
│    Update Required                      │
│                                         │
│    A required update must be installed  │
│    to continue using What's That?       │
│                                         │
│    Version 1.3.0                        │
│                                         │
│    [message from version_log]           │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │       Update Now                │    │
│  └─────────────────────────────────┘    │
│                                         │
│                                         │
└─────────────────────────────────────────┘
```

### Behavior

- **Full-screen, no dismiss option**
- **Update Now** → Opens App Store
- No navigation allowed

---

## 5. Maintenance Mode Screen

**Purpose:** Block all app usage during maintenance.

### Layout

```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│              🔧                          │
│                                         │
│    Under Maintenance                    │
│                                         │
│    We are currently undergoing          │
│    maintenance. Please check back       │
│    later.                               │
│                                         │
│    ┌─────────────────────────────────┐  │
│    │ [Custom message if set]        │   │
│    │ e.g., "We're upgrading our     │   │
│    │ servers to improve performance.│   │
│    │ Expected downtime: 30 minutes."│   │
│    └─────────────────────────────────┘  │
│                                         │
│                                         │
└─────────────────────────────────────────┘
```

### Behavior

- **Full-screen, no dismiss option**
- **No navigation allowed**
- If `maintenance_message` is NULL, show only default text
- If `maintenance_message` is set, show default text + custom message in a card below
- No buttons (user can only close and reopen app to check)

### Styling Notes
- Use a muted/neutral color scheme (not alarming like red)
- App should re-check config on next launch or app foreground
- **iPad**: Present as full-screen (not modal card)

---

## Sign Out Flow

When user taps "Sign Out":

1.  Standard alert: "Are you sure you want to sign out?"
2.  On Confirm: Clear session -> Navigate to Login Screen.

> [!NOTE]
> We previously considered "Delete Account" here. That was too aggressive. If a user declines terms, they simply stop using the service (Sign Out). They can come back later and accept if they choose. Deleting data should be a separate, deliberate action in Settings.

<!-- Steps removed -->

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Offline on launch | Skip all version checks, proceed normally |
| Network restored while in app | Do NOT interrupt — only check on next launch |
| Both ToS and Privacy updated | Single modal with both cards + one checkbox |
| Only ToS updated | Modal shows only ToS card |
| Only Privacy updated | Modal shows only Privacy card |
| ToS + App update needed | Show legal modal first, app update after |
| User in onboarding | Defer version checks until after onboarding complete |
| No message in version_log | Don't show message section in UI |

---

## Timing: When Checks Happen

```
App Launch
    ↓
Start loading main app content (non-blocking)
    ↓
Parallel: Fetch config + user agreements in background
    ↓
App content loads and displays normally
    ↓
Background check completes
    ↓
If updates needed:
    → Present modal over current content
    → User interacts with modal
    → Continue
```

**Key principle:** User sees their content loading/loaded. The check happens in the background. Only once we know there's an update do we interrupt with the modal.

### Safe-to-Present Logic

We must **NOT** interrupt the user during critical flows.

**Safe Screens:**
- Discoveries Home (Grid)
- Audio Guides List
- Settings

**Unsafe Screens (Queue the modal):**
- Discovery Creation (Camera, Streaming, Loading)
- Audio Guide Detail / Playback (User listening)
- Paywall / Purchase Flow

**Mechanism:**
- If update required `AppFlowState` sets `needsPresentation = true`
- View modifiers on Safe Screens listen for this changes and present `.sheet`
- Unsafe screens simply ignore it. When user navigates back to Home, the sheet appears.
