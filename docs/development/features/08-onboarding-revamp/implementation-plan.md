# Implementation Plan: Pre-Onboarding Bottom Sheet

## Summary

Create a thin `PreOnboardingDiscoveriesContainer` that reuses existing components and adds a collapsible bottom sheet. Sample discoveries are stored in a dedicated `sample_discoveries` table, seeded via migration.

---

## Part 1: Database & Storage Setup

### 1.1 Sample Discoveries Table

Create a new table for sample discoveries (following `voice_inventory` pattern):

```sql
-- Migration: YYYYMMDD_create_sample_discoveries.sql

CREATE TABLE public.sample_discoveries (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    short_description TEXT,
    description TEXT,
    image_path TEXT NOT NULL,           -- Path in storage: samples/1.jpg
    voiceover_path TEXT,                -- Path in storage: samples/1.mp3
    country TEXT,
    locality TEXT,
    street_name TEXT,
    closest_place TEXT,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Public read access (no auth required)
ALTER TABLE public.sample_discoveries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read sample discoveries"
    ON public.sample_discoveries
    FOR SELECT
    USING (true);

-- Index for ordering
CREATE INDEX idx_sample_discoveries_display_order ON public.sample_discoveries(display_order);
```

### 1.2 Seed Sample Discoveries

Same migration file seeds the 7 curated discoveries:

```sql
-- Seed sample discoveries
INSERT INTO public.sample_discoveries
    (id, title, short_description, description, image_path, voiceover_path, country, locality, display_order)
VALUES
    (1, 'Klimt''s Golden Muse',
     'Short description here...',
     'Full description here...',
     'samples/1.jpg',
     'samples/1.mp3',
     'Austria', 'Vienna', 1),

    (2, 'Venice''s Winged Brand',
     'Short description...',
     'Full description...',
     'samples/2.jpg',
     'samples/2.mp3',
     'Italy', 'Venice', 2),

    -- ... (5 more discoveries)

ON CONFLICT (id) DO NOTHING;

-- Reset sequence
SELECT setval('sample_discoveries_id_seq', (SELECT MAX(id) FROM sample_discoveries));
```

### 1.3 Storage Structure

```
discovery_images/
└── samples/
    ├── 1.jpg    (Klimt's Golden Muse)
    ├── 2.jpg    (Venice's Winged Brand)
    ├── 3.jpg    (A Nation's Golden Anchor)
    ├── 4.jpg    (Feast in the House of Levi)
    ├── 5.jpg    (Venice's Golden Ascent)
    ├── 6.jpg    (The General of Vítkov)
    └── 7.jpg    (Sobieski at Vienna)

voiceovers/
└── samples/
    ├── 1.mp3
    ├── 2.mp3
    ├── 3.mp3
    ├── 4.mp3
    ├── 5.mp3
    ├── 6.mp3
    └── 7.mp3
```

### 1.4 RPC Function for Fetching Samples

```sql
-- Migration: YYYYMMDD_sample_discoveries_rpc.sql

CREATE OR REPLACE FUNCTION get_sample_discoveries()
RETURNS TABLE (
    id INT,
    title TEXT,
    short_description TEXT,
    description TEXT,
    image_path TEXT,
    voiceover_path TEXT,
    country TEXT,
    locality TEXT,
    street_name TEXT,
    closest_place TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        id,
        title,
        short_description,
        description,
        image_path,
        voiceover_path,
        country,
        locality,
        street_name,
        closest_place,
        created_at
    FROM sample_discoveries
    ORDER BY display_order ASC;
$$;
```

---

## Part 2: Generate Sample Voiceovers

### 2.1 Current Audio Status

| Sample ID | Discovery | Audio Status |
|-----------|-----------|--------------|
| 1 | Klimt's Golden Muse | ❌ Not generated |
| 2 | Venice's Winged Brand | ❌ Not generated |
| 3 | A Nation's Golden Anchor | ❌ Not generated |
| 4 | Feast in the House of Levi | ❌ Not generated |
| 5 | Venice's Golden Ascent | ❌ Not generated |
| 6 | The General of Vítkov | ❌ Not generated |
| 7 | Sobieski at Vienna | ❌ Not generated |

### 2.2 Voiceover Generation Approach

**Method:** Script-based generation using Fish Audio API

We'll create a one-time script that:
1. Reads discovery content from `selected_discoveries/` JSON files
2. Calls Fish Audio API to generate voiceovers
3. Saves MP3 files locally
4. Files are then manually uploaded to `voiceovers/samples/`

### 2.3 Generation Script

Create `scripts/generate-sample-voiceovers.ts` (or Python equivalent):

```typescript
// Pseudocode for voiceover generation
import fs from 'fs';

const FISH_AUDIO_API_KEY = process.env.FISH_AUDIO_API_KEY;
const VOICE_ID = 'your-voice-id'; // Same voice used in production

const discoveries = [
  { sampleId: 1, folder: '126-klimts-golden-muse' },
  { sampleId: 2, folder: '1565-venices-winged-brand' },
  { sampleId: 3, folder: '1570-a-nations-golden-anchor' },
  { sampleId: 4, folder: '1618-feast-in-the-house-of-levi' },
  { sampleId: 5, folder: '1640-venices-golden-ascent' },
  { sampleId: 6, folder: '1681-the-general-of-vitkov' },
  { sampleId: 7, folder: '1771-sobieski-at-vienna' },
];

async function generateVoiceover(text: string, outputPath: string) {
  const response = await fetch('https://api.fish.audio/v1/tts', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${FISH_AUDIO_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      text,
      voice_id: VOICE_ID,
      format: 'mp3',
    }),
  });

  const audioBuffer = await response.arrayBuffer();
  fs.writeFileSync(outputPath, Buffer.from(audioBuffer));
}

async function main() {
  for (const { sampleId, folder } of discoveries) {
    const jsonPath = `docs/development/features/08-onboarding-revamp/selected_discoveries/${folder}/discovery.json`;
    const discovery = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));

    // Use description as voiceover text
    const text = discovery.description;
    const outputPath = `output/samples/${sampleId}.mp3`;

    console.log(`Generating voiceover for sample ${sampleId}...`);
    await generateVoiceover(text, outputPath);
  }
}

main();
```

### 2.4 Manual Steps

1. **Run generation script:**
   ```bash
   FISH_AUDIO_API_KEY=xxx npx ts-node scripts/generate-sample-voiceovers.ts
   ```

2. **Upload to Supabase Storage:**
   - Go to Supabase Dashboard → Storage → voiceovers
   - Create `samples/` folder if needed
   - Upload `1.mp3` through `7.mp3`

3. **Verify public read access** on the `voiceovers` bucket

---

## Part 3: iOS Implementation

### 3.1 Architecture

```
RootContentView (flowState == .preOnboarding)
        ↓
PreOnboardingDiscoveriesContainer (~150 lines)
├── SampleDiscoveryStoreObserver (NEW - fetches from sample_discoveries)
├── DiscoveryDetailTransitionCoordinator (existing)
├── Inline LazyVGrid using DiscoveryCardView (existing)
├── DiscoveryDetailOverlayView (existing - read-only mode)
└── PreOnboardingBottomSheetView (NEW - collapsible welcome sheet)
```

### 3.2 Files to Create

#### 3.2.1 SampleDiscoveryRepository.swift

**Location:** `WhatsThatData/Repositories/Onboarding/SampleDiscoveryRepository.swift`

```swift
import Foundation
import WhatsThatDomain
import Supabase

public struct SampleDiscoveryRepository: SampleDiscoveryService {
    private let client: SupabaseClient
    private let signedURLTTL: TimeInterval

    public init(client: SupabaseClient, signedURLTTL: TimeInterval = 60 * 60 * 24) {
        self.client = client
        self.signedURLTTL = signedURLTTL
    }

    public func fetchSampleDiscoveries() async throws -> [SampleDiscovery] {
        // Call RPC - no parameters needed, returns all samples ordered
        let response: PostgrestResponse<[SampleDiscoveryRecord]> = try await client
            .rpc("get_sample_discoveries")
            .execute()

        // Sign URLs for images and voiceovers
        return try await withThrowingTaskGroup(of: SampleDiscovery.self) { group in
            for record in response.value {
                group.addTask {
                    let imageURL = try await signURL(bucket: "discovery_images", path: record.image_path)
                    let voiceoverURL = record.voiceover_path != nil
                        ? try await signURL(bucket: "voiceovers", path: record.voiceover_path!)
                        : nil

                    return SampleDiscovery(
                        id: record.id,
                        title: record.title,
                        shortDescription: record.short_description,
                        description: record.description,
                        imageURL: imageURL,
                        voiceoverURL: voiceoverURL,
                        country: record.country,
                        locality: record.locality
                    )
                }
            }

            var results: [SampleDiscovery] = []
            for try await discovery in group {
                results.append(discovery)
            }
            return results.sorted { $0.id < $1.id }
        }
    }

    private func signURL(bucket: String, path: String) async throws -> URL {
        try await client.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: Int(signedURLTTL))
    }
}
```

#### 3.2.2 SampleDiscovery Model

**Location:** `WhatsThatDomain/Onboarding/SampleDiscovery.swift`

```swift
public struct SampleDiscovery: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let shortDescription: String?
    public let description: String?
    public let imageURL: URL
    public let voiceoverURL: URL?
    public let country: String?
    public let locality: String?
}
```

#### 3.2.3 PreOnboardingBottomSheetView.swift

**Location:** `WhatsThatPresentation/Features/Onboarding/PreOnboardingBottomSheetView.swift`

```swift
import SwiftUI
import WhatsThatShared

struct PreOnboardingBottomSheetView: View {
    enum SheetState {
        case expanded
        case collapsed
    }

    @Binding var state: SheetState
    let onContinue: () -> Void      // "Create Your Own" - new user flow
    let onSignIn: () -> Void        // "Account · Sign in" - returning user flow
    let screenHeight: CGFloat
    let bottomInset: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0

    private var expandedHeight: CGFloat { screenHeight * 0.35 }
    private var collapsedHeight: CGFloat { 80 + bottomInset }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            sheetContent
        }
        .frame(height: max(collapsedHeight, currentTargetHeight + dragOffset))
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -5)
        .gesture(dragGesture)
        .animation(.easeInOut(duration: 0.25), value: state)
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(palette.textSecondary.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var sheetContent: some View {
        VStack(spacing: BrandSpacing.medium) {
            if state == .expanded {
                welcomeContent
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Spacer(minLength: 0)
            actionButtons
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, bottomInset + BrandSpacing.medium)
        }
        .padding(.top, BrandSpacing.small)
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.small) {
            BrandPrimaryButton(title: "Create Your Own", action: onContinue)

            Button(action: onSignIn) {
                Text("Account · Sign in")
                    .font(.adaptiveSystem(size: 14, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.small) {
            Text("Welcome to What's That?")
                .font(.adaptiveSystem(size: 22, weight: .bold))
                .foregroundStyle(palette.textPrimary)

            Text("These are real discoveries from real places. Tap any to read the story and listen to the audio guide.")
                .font(.adaptiveSystem(size: 15, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("When you're ready, create your own.")
                .font(.adaptiveSystem(size: 15, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, BrandSpacing.xSmall)
        }
        .padding(.horizontal, BrandSpacing.large)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let translation = value.translation.height
                if state == .expanded {
                    dragOffset = max(-30, translation)
                } else {
                    dragOffset = min(30, translation)
                }
            }
            .onEnded { value in
                let translation = value.translation.height
                let velocity = value.predictedEndTranslation.height - translation
                let shouldExpand = state == .expanded
                    ? (translation < 50 && velocity < 200)
                    : (translation < -50 || velocity < -200)

                withAnimation(.easeInOut(duration: 0.25)) {
                    state = shouldExpand ? .expanded : .collapsed
                    dragOffset = 0
                }
            }
    }

    private var currentTargetHeight: CGFloat {
        state == .expanded ? expandedHeight : collapsedHeight
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }
}
```

#### 3.2.4 PreOnboardingDiscoveriesContainer.swift

**Location:** `WhatsThatPresentation/Features/Onboarding/PreOnboardingDiscoveriesContainer.swift`

Main container view that:
- Uses `SampleDiscoveryStoreObserver` for state management
- Shows grid of sample discoveries
- Shows bottom sheet overlay
- Handles error/offline state

#### 3.2.5 PreOnboardingOfflineView.swift

**Location:** `WhatsThatPresentation/Features/Onboarding/PreOnboardingOfflineView.swift`

Simple offline/error state view:

```swift
import SwiftUI
import WhatsThatShared

struct PreOnboardingOfflineView: View {
    let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(palette.textSecondary)

            Text("Connect to the internet for the full experience")
                .font(.adaptiveSystem(size: 17, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xLarge)

            BrandSecondaryButton(title: "Refresh", action: onRetry)
                .padding(.horizontal, BrandSpacing.xLarge)

            Spacer()
        }
    }
}
```

### 3.3 Files to Modify

| File | Change |
|------|--------|
| `RootContentView.swift` | Route to new container |
| `AppDependencyContainer.swift` | Create `SampleDiscoveryRepository` |
| `PreOnboardingCarousel.swift` | Keep only legacy initializer |

### 3.4 Files to Delete

| File | Reason |
|------|--------|
| `PreOnboardingDiscoveriesView.swift` | Replaced by container |
| `OnboardingDiscoveryRepository.swift` | Replaced by SampleDiscoveryRepository |
| `OnboardingDiscoveryStoreObserver.swift` | Replaced by SampleDiscoveryStoreObserver |
| `OnboardingDiscoveryService.swift` | Replaced by SampleDiscoveryService |

---

## Part 4: Migration Checklist

### Pre-requisites

- [ ] Decide analytics platform (Firebase/Mixpanel/Amplitude)

### Database Migration

- [ ] Create `sample_discoveries` table with public read RLS
- [ ] Seed 7 sample discoveries with content from JSON files
- [ ] Create `get_sample_discoveries()` RPC function
- [ ] Run migration on dev
- [ ] Run migration on prod

### Voiceover Generation

- [ ] Create voiceover generation script
- [ ] Generate voiceovers for all 7 discoveries using Fish Audio API
- [ ] Save MP3 files to output folder

### Storage Setup (Manual)

- [ ] Upload images to `discovery_images/samples/` (1.jpg - 7.jpg)
- [ ] Upload voiceovers to `voiceovers/samples/` (1.mp3 - 7.mp3)
- [ ] Verify public read access on storage buckets

### iOS Implementation

- [ ] Create `SampleDiscovery` model
- [ ] Create `SampleDiscoveryService` protocol
- [ ] Create `SampleDiscoveryRepository`
- [ ] Create `SampleDiscoveryStoreObserver`
- [ ] Create `PreOnboardingBottomSheetView`
- [ ] Create `PreOnboardingOfflineView`
- [ ] Create `PreOnboardingDiscoveriesContainer`
- [ ] Update `RootContentView` routing
- [ ] Update `AppDependencyContainer`
- [ ] Delete old onboarding files
- [ ] Build and test

### Analytics Integration

- [ ] Add analytics SDK (Firebase/Mixpanel/Amplitude)
- [ ] Implement event tracking for pre-onboarding events
- [ ] Verify events appear in analytics dashboard

---

## Part 5: Verification

### Build Command
```bash
USE_REMOTE_DEPS=1 xcodebuild \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

### Manual Testing Checklist

**Grid Display:**
- [ ] App opens to pre-onboarding with discovery grid (no header/tabs)
- [ ] Shows 7 sample discoveries
- [ ] Skeleton loading during fetch
- [ ] Images load correctly

**Bottom Sheet:**
- [ ] Starts expanded with welcome copy
- [ ] "Create Your Own" button visible
- [ ] "Account · Sign in" link visible below button
- [ ] Drag down collapses (only button + sign in link visible)
- [ ] Drag up expands (full welcome copy)
- [ ] Cannot be fully dismissed

**Detail View:**
- [ ] Tap opens detail overlay
- [ ] Title, description display correctly
- [ ] Audio playback works
- [ ] No delete/options buttons (read-only)
- [ ] Back button closes

**Navigation:**
- [ ] "Create Your Own" triggers sign-up flow
- [ ] "Account · Sign in" triggers sign-in flow
- [ ] After auth, normal discoveries page appears

**Offline/Error State:**
- [ ] With no internet, shows offline message
- [ ] "Connect to the internet for the full experience" text displayed
- [ ] "Refresh" button visible and works when connectivity restored

**Analytics (if implemented):**
- [ ] `pre_onboarding_opened` fires on app launch
- [ ] `sample_discovery_tapped` fires when tapping a discovery
- [ ] `sample_audio_played` fires when playing audio
- [ ] `create_your_own_tapped` fires when tapping CTA
- [ ] `sign_in_tapped` fires when tapping sign-in link

---

## Sample Discovery Data

### ID Mapping

| Sample ID | Original ID | Title | Source |
|-----------|-------------|-------|--------|
| 1 | 126 | Klimt's Golden Muse | Dev |
| 2 | 1565 | Venice's Winged Brand | Prod |
| 3 | 1570 | A Nation's Golden Anchor | Prod |
| 4 | 1618 | Feast in the House of Levi | Prod |
| 5 | 1640 | Venice's Golden Ascent | Prod |
| 6 | 1681 | The General of Vítkov | Prod |
| 7 | 1771 | Sobieski at Vienna | Prod |

### Content Source

Discovery content is exported to:
```
docs/development/features/08-onboarding-revamp/selected_discoveries/
├── 126-klimts-golden-muse/
│   ├── discovery.json    <- Use for migration
│   ├── discovery.md
│   └── image.jpg         <- Upload to storage
├── 1565-venices-winged-brand/
│   └── ...
└── ...
```
