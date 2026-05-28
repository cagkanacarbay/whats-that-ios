# Demo Mode: Bottom Sheet Design

## Overview

When a user opens the app for the first time (before sign-up), they land directly on the Discoveries grid populated with pre-selected sample discoveries. A persistent bottom sheet provides context and the path to sign-up.

---

## Screen State: Demo Mode

**What's visible:**
- Full Discoveries grid (same layout as authenticated users)
- Pre-filled with 4-6 curated sample discoveries
- Bottom sheet overlay (always present, collapsible)

**What's NOT visible:**
- Top navigation bar (no "My Discoveries" header)
- Bottom tab bar (no Camera/Discoveries/Audio Guides/Gallery tabs)

The bottom sheet replaces the navigation—it's the only UI element guiding the user.

---

## Bottom Sheet: Two States

### State 1: Expanded (Default on first open)

Sheet covers approximately 30-40% of screen. Grid is visible above.

```
┌─────────────────────────────────────┐
│                                     │
│   [Discovery Grid - visible]        │
│                                     │
│   ┌─────────────────────────────┐   │
│   │ ─── (drag handle) ───       │   │
│   │                             │   │
│   │  Welcome to What's That?    │   │
│   │                             │   │
│   │  These are real discoveries │   │
│   │  from real places. Tap any  │   │
│   │  to read the story and      │   │
│   │  listen to the audio guide. │   │
│   │                             │   │
│   │  When you're ready, create  │   │
│   │  your own.                  │   │
│   │                             │   │
│   │  [Create Your Own]          │   │
│   │                             │   │
│   └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**Copy (Expanded):**

> **Welcome to What's That?**
>
> These are real discoveries from real places. Tap any to read the story and listen to the audio guide.
>
> When you're ready, create your own.
>
> **[Create Your Own]**
> Account · Sign in

---

### State 2: Collapsed (After user drags down)

Sheet minimizes to a slim bar at bottom. Almost full grid visible.

```
┌─────────────────────────────────────┐
│                                     │
│   [Discovery Grid - full view]      │
│                                     │
│                                     │
│                                     │
│   ┌─────────────────────────────┐   │
│   │ ─── (drag handle) ───       │   │
│   │  [Create Your Own]          │   │
│   └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**Copy (Collapsed):**

> **[Create Your Own]**
> Account · Sign in

Button with sign-in link below. User can drag up to see full copy again.

---

## Interaction Behavior

| Action | Result |
|--------|--------|
| User drags sheet down | Sheet collapses to button-only state |
| User drags sheet up | Sheet expands to show full welcome copy |
| User taps discovery | Opens discovery detail view (full experience) |
| User taps "Create Your Own" | Navigates to sign-up flow |
| User presses back from discovery | Returns to demo grid with sheet |

**The sheet is always present.** It cannot be fully dismissed—it's the navigation element.

---

## Discovery Detail View (Demo Mode)

When user taps a discovery from the grid:

- Full discovery detail view opens (same as authenticated experience)
- User can read the full story
- User can tap Play to listen to audio
- User can scroll through all sections
- Back button returns to demo grid

**No restrictions.** They get the complete experience.

---

## Sign-Up Trigger

When user taps **"Create Your Own"**:

- Navigates to sign-up/authentication screen
- After sign-up completes:
  - Demo discoveries are cleared
  - User sees empty "My Discoveries" grid
  - Normal navigation appears (top header, bottom tabs)
  - Post-sign-up flow begins (first discovery prompt)

---

## Sample Discoveries (Pre-Selected)

Curate 4-6 discoveries that showcase variety and quality:

| Discovery | Why Include |
|-----------|-------------|
| Sobieski at Vienna | Art/painting, dramatic story, strong visual |
| Shield of the Legions | Artifact/museum piece, tactile detail |
| Old Town Bridge Tower | Architecture/landmark, travel context |
| Leopard and Steel (Hussar armor) | Unusual subject, rich sensory details |
| The Warning Tower | Architecture, interesting title |
| [One food/local culture option] | Shows breadth beyond landmarks |

**Selection criteria:**
- Visually striking thumbnail
- Compelling title (creates curiosity)
- Strong audio guide (they might listen)
- Variety of subject types

---

## Copy Variations (Test Options)

### Option A (Current)
> These are real discoveries from real places. Tap any to read the story and listen to the audio guide.

### Option B (More direct)
> Real photos. Real stories. Tap any to explore.

### Option C (Benefit-focused)
> See what others discovered. Tap any to hear the story behind it.

### Button Copy Options
- **"Create Your Own"** ← Selected
- ~~"Start Discovering"~~
- ~~"Make Your First Discovery"~~
- ~~"Sign Up to Create Yours"~~

**Final button design:**
```
┌─────────────────────────┐
│    [Create Your Own]    │  <- Primary button
│     Account · Sign in   │  <- Secondary text link
└─────────────────────────┘
```

The "Account · Sign in" link below accommodates returning users who already have an account.

---

## Technical Notes

- Demo discoveries are fetched from `sample_discoveries` table via RPC
- No user account required to view demo content
- Audio files for demo discoveries should be pre-cached or fast-loading
- Sheet state (expanded/collapsed) can reset on each app open
- Analytics: Track which demo discoveries users tap, how long they explore before sign-up

---

## Offline Handling

This app requires internet to function. If the user has no connectivity when opening for the first time:

**Display message:**
> Connect to the internet for the full experience

With a **Refresh** button to retry.

No fallback content needed - users cannot sign up or create discoveries without internet anyway.

---

## Analytics

### Events to Track

| Event | Parameters | Purpose |
|-------|------------|---------|
| `pre_onboarding_opened` | - | User opened app for first time |
| `sample_discovery_tapped` | `discovery_id`, `discovery_title` | Which samples interest users |
| `sample_audio_played` | `discovery_id` | Audio engagement |
| `sample_audio_completed` | `discovery_id`, `duration_seconds` | Full audio engagement |
| `bottom_sheet_collapsed` | - | User explored grid more |
| `bottom_sheet_expanded` | - | User read welcome copy |
| `create_your_own_tapped` | `discoveries_viewed_count`, `time_spent_seconds` | Conversion point |
| `sign_in_tapped` | - | Returning user |

### Implementation

**Platform:** TBD - Options:
- Firebase Analytics (feeds into GA4) - requires Firebase SDK
- Mixpanel - standalone, no Firebase needed
- Amplitude - standalone, no Firebase needed

*Decision pending on analytics provider.*

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Demo → Sign-up conversion | > 60% (up from current ~55%) |
| Avg. discoveries viewed before sign-up | 2+ |
| Avg. time in demo mode | 60-90 seconds |
| % who listen to audio in demo | > 30% |

---

## Edge Cases

**User force-closes app during demo:**
- Returns to demo mode on next open (not signed in)

**User already has account:**
- If returning user (logged out), show "Sign In" option alongside "Create Your Own"

**User tries to access Camera/Gallery (if visible):**
- These tabs are NOT visible in demo mode
- The bottom sheet is the only navigation

---

## Implementation Checklist

- [ ] Create demo mode state (pre-authentication)
- [ ] Build collapsible bottom sheet component
- [ ] Select and prepare sample discoveries
- [ ] Pre-cache audio for sample discoveries
- [ ] Remove top/bottom navigation in demo mode
- [ ] Connect "Create Your Own" to sign-up flow
- [ ] Add analytics tracking for demo interactions
- [ ] Test discovery detail view in demo mode
- [ ] Test sign-up transition (demo → authenticated)
