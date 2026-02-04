# Onboarding Revamp

This feature revamps the pre-onboarding experience with an interactive discovery gallery that showcases what the app can do before users sign up.

## Documentation

| Document | Purpose |
|----------|---------|
| [Design Spec](./design-spec.md) | UX design, copy, and interaction requirements |
| [Implementation Plan](./implementation-plan.md) | Technical implementation details and code |

## Status

| Component | Status |
|-----------|--------|
| Design spec | ✅ Complete |
| Implementation plan | ✅ Complete |
| Analytics platform decision | ⏳ Pending |
| `sample_discoveries` table | ❌ Not created |
| Sample voiceovers | ❌ Not generated |
| Storage upload (images/audio) | ❌ Not done |
| iOS implementation | ❌ Not started |
| Analytics integration | ❌ Not started |
| End-to-end testing | ❌ Not started |

---

## Overview

### Current State
- `PreOnboardingDiscoveriesView` (499 lines) - separate implementation
- Queries main `discoveries` table with hardcoded IDs
- Dev/prod ID mismatch problem
- RLS bypass needed via `SECURITY DEFINER`

### Target State
- `PreOnboardingDiscoveriesContainer` (~150 lines) - reuses shared components
- Dedicated `sample_discoveries` table (like `voice_inventory` pattern)
- Same data in dev/prod via migration
- Public read RLS - no bypass needed

---

## Key Architecture Decisions

### 1. Separate `sample_discoveries` Table

Following the `voice_inventory` pattern for sample voiceovers:

```sql
CREATE TABLE sample_discoveries (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    short_description TEXT,
    description TEXT,
    image_path TEXT,        -- samples/1.jpg
    voiceover_path TEXT,    -- samples/1.mp3
    country TEXT,
    locality TEXT,
    display_order INT
);

-- Public read - no auth required
CREATE POLICY "Anyone can read" ON sample_discoveries
    FOR SELECT USING (true);
```

**Why this approach:**
- Solves dev/prod ID mismatch (seeded via migration)
- Simple public read RLS (no `SECURITY DEFINER` needed)
- Isolated from user data (no accidental deletion risk)
- Small, static table - fast queries

### 2. Storage Structure

```
discovery_images/samples/     <- Sample images
voiceovers/samples/           <- Sample audio guides
```

### 3. Bottom Sheet Design

- **Expanded** (~35% of screen): Welcome copy + "Get Started" button
- **Collapsed** (~80pt): Just the button
- Draggable, cannot be fully dismissed
- Hides when detail overlay is open

---

## Selected Sample Discoveries

| Sample ID | Title | Original Source |
|-----------|-------|-----------------|
| 1 | Klimt's Golden Muse | Dev (126) |
| 2 | Venice's Winged Brand | Prod (1565) |
| 3 | A Nation's Golden Anchor | Prod (1570) |
| 4 | Feast in the House of Levi | Prod (1618) |
| 5 | Venice's Golden Ascent | Prod (1640) |
| 6 | The General of Vítkov | Prod (1681) |
| 7 | Sobieski at Vienna | Prod (1771) |

Discovery content exported to `selected_discoveries/` folder.

---

## Copy

**Expanded bottom sheet:**
> **Welcome to What's That?**
>
> These are real discoveries from real places. Tap any to read the story and listen to the audio guide.
>
> When you're ready, create your own.
>
> **[Create Your Own]**
> Account · Sign in

**Collapsed bottom sheet:**
> **[Create Your Own]**
> Account · Sign in

**Offline/Error state:**
> Connect to the internet for the full experience
> **[Refresh]**

---

## Analytics

**Decision needed:** Which analytics platform to use?

| Option | Pros | Cons |
|--------|------|------|
| Firebase Analytics (→ GA4) | Feeds into Google Analytics, familiar | Requires Firebase SDK |
| Mixpanel | Standalone, powerful funnel analysis | Another vendor |
| Amplitude | Standalone, good free tier | Another vendor |

**Events to track:**
- `pre_onboarding_opened`
- `sample_discovery_tapped` (which discovery)
- `sample_audio_played` / `sample_audio_completed`
- `create_your_own_tapped` (conversion)
- `sign_in_tapped` (returning user)

See [design-spec.md](./design-spec.md#analytics) for full event list.

---

## Implementation Order

1. **Decide analytics platform** - Firebase/Mixpanel/Amplitude
2. **Generate voiceovers** - Script + Fish Audio API for 7 discoveries
3. **Database migration** - Create `sample_discoveries` table, seed data
4. **Storage upload** - Upload images and audio to `samples/` folders (manual)
5. **iOS implementation** - New container, bottom sheet, repository
6. **Analytics integration** - Add event tracking
7. **Testing** - Verify full flow

---

## Quick Reference

### New Files to Create
- `sample_discoveries` table + RPC (migration)
- `SampleDiscovery.swift` - Domain model
- `SampleDiscoveryService.swift` - Protocol
- `SampleDiscoveryRepository.swift` - Data layer
- `SampleDiscoveryStoreObserver.swift` - State management
- `PreOnboardingBottomSheetView.swift` - Bottom sheet UI
- `PreOnboardingDiscoveriesContainer.swift` - Main container

### Files to Modify
- `RootContentView.swift` - Route to new container
- `AppDependencyContainer.swift` - Create repository

### Files to Delete
- `PreOnboardingDiscoveriesView.swift`
- `OnboardingDiscoveryRepository.swift`
- `OnboardingDiscoveryStoreObserver.swift`
- `OnboardingDiscoveryService.swift`
