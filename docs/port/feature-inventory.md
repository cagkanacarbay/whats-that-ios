# Feature Inventory (Current React Native App)

This document enumerates the functional surface area that the native iOS port must reproduce or improve. Code references point to the live React Native implementation for authoritative behavior.

---

## Onboarding & Session Bootstrapping
- Two-stage onboarding flow (`app/onboarding/pre.tsx`, `app/onboarding/post.tsx`) with teaser slides, value props, and post-onboarding actions. Flags stored in AsyncStorage via `useOnboardingFlags.ts`.
- Initial route gatekeeper (`app/index.tsx`) that decides between onboarding, auth, and main tabs based on Supabase session and onboarding flags.
- Post-onboarding slide triggers `expo-location` permission prompt and surfaces quick actions (“Take photo”, “Upload photo”).
- Splash + font loading handled in `_layout.tsx` (Expo `SplashScreen`, Tamagui theme wiring).
- Session context in `_layout.tsx` tracks Supabase auth state, feeds `useSession` hook, and holds global providers (Discovery, Location, ImageFlow, Credit, Audio, etc.).

## Authentication & Account Management
- Email/password sign-up & login screens (`app/SignUpScreen.tsx`, `app/LogInScreen.tsx`) with validation, Supabase auth, and Google sign-in (`expo-auth-session`) + Apple Sign in (to be implemented)
- Terms & Privacy acceptance: inline gating before account creation with Markdown modals (`app/terms.tsx`, `app/privacy.tsx`, `components/MarkdownViewer.tsx`).
- Forgot password flow (`app/forgot-password.tsx`) invoking Supabase `resetPasswordForEmail`; deep-link handler in `app/auth/reset.tsx` uses `supabase.auth.setSession`.
- Tab layout auto-redirects away from protected routes when session expires (`app/(tabs)/_layout.tsx`).
- Theme toggling & persistence via `ThemeContext.tsx` with system override toggle in settings.

## Discovery Creation Flow (Camera & Upload)
- Shared finite state machine in `ImageFlowContext.tsx` orchestrates permission requests, capture/pick, confirmation, analysis, error/cancel states for both camera (`app/(tabs)/takePhoto.tsx`) and upload (`app/(tabs)/uploadPhoto.tsx`).
- Camera capture uses Expo Camera; gallery import uses Expo Image Picker with EXIF extraction to seed location entries (`hooks/useInitiateImageFlow.ts`).
- Automatic photo library save for new captures when permission granted (`ConfirmImageSelection.tsx` + MediaLibrary interaction).
- Location acquisition with optional EXIF fallback, tracked per discovery via `LocationContext.tsx`; includes background updates, Google Places fetch trigger, and helper for Maps deep link.
- Confirm screen (`ConfirmImageSelection.tsx`) shows preview, current credit balance, low-credit warnings, location metadata, and entry point to buy credits. Builds `customContext` payload via `lib/discoveryContextBuilder.ts` (recent discoveries summaries).
- Confirm screen also registers push notifications on first run (`registerForPushNotificationsAsync`).

## AI Analysis & Streaming Pipeline
- Streaming UI (`components/custom/AskAIStreaming.tsx`) consumes SSE from `ask-ai-v7` Edge Function via `lib/askAiStreamingClient.ts`. Handles status events, token batches, complete/error states, and request cancellation.
- Fallback non-streaming implementation (`components/custom/AskAI.tsx`) remains in repo but is unused by current flows - Only take streaming. Currently only GPT in the edge function is set up to stream. In the future all other models Claude, (gemini to be added), 
will also set to stream. 
- Request coordination via `activeAnalysisTracker.ts` and `requestTracker.ts` prevents duplicates and handles background polling if the app is suspended mid-analysis.
- Location + nearby places context assembled on device and forwarded in request body; Edge Function re-validates session, consumes one credit, uploads image to Supabase storage, stores discovery, and optionally pushes Expo notifications.
- Error handling includes credit refund on server failure, content-moderation handling, and user alerts for insufficient credits or streaming failures.

## Discovery Browsing & Detail Experience
- Tab layout includes Discoveries list (`app/(tabs)/(home)/index.tsx`) using `DiscoveryContext.tsx` for pagination, caching, and infinite scroll.
- List items (`components/custom/DiscoveryItem.tsx`) fetch signed URLs on-demand, cache them, and measure for animated modal transitions.
- Infinite scroll preloading attempts via `useImagePreloader.ts`; current implementation has known race conditions documented in `project-documentation/development/tracking/TODO.md`.
- Discovery detail presented inside animated modal (`DiscoveryModalContext.tsx` + `components/custom/DiscoveryDetails`), with matched-geometry visual, inline Markdown rendering, share token data, map deep links, delete controls, and quick action buttons to capture/upload again.
- Inline feedback system (`components/custom/Feedback/*`) supports double-tap paragraph selection and reaction menu overlay (not yet persisted server-side) - Scrap this and related systems. This will be rethought entirely in the future. We don't need Feedback system as of now. 
- Dedicated discovery screen (`app/discovery/[id].tsx`) handles deep links / navigation outside modal context and supports deletion via Supabase.

### Discoveries Grid UI (must match exactly)
- Two-column masonry-style grid rendered via `FlatList` (`numColumns=2`) with consistent gutters defined in `DISCOVERY_SPACING`. Cards are Tamagui `Card` shells sized by `DISCOVERY_CARD_DIMENSIONS` with fully-bleed imagery.
- Item chrome is intentionally minimal: images fill the card, and a semi-transparent black title ribbon hugs the bottom with centered white text (13pt, medium weight, drop shadow) for readability on any photo.
- The screen background uses a subtle vertical gradient (`YStack` with `backgroundImage: linear-gradient(...)`) that fades from transparent to a soft overlay to prevent harsh edges around the cards.
- A floating header (`Animated.View`) sits at the top with a large “My Discoveries” title (32pt) and a settings cog. As the user scrolls, the header opacity animates out, creating a smooth blend between hero banner and content. Pull-to-refresh is styled with brand colors and offset so the header does not jitter.
- Skeleton state: while loading, the grid renders paired `DiscoveryItemSkeleton` components (8 placeholders) that mimic the card shape with a shimmering gradient.

### Discovery Detail UI & Content Hierarchy
- `DiscoveryModalContext` orchestrates a full-screen modal with matched-geometry animation from the tapped card. Container expands to fill screen while maintaining rounded edges until fully open; background dims with a 4-step opacity ramp to 0.9.
- Top 80% of the screen is dedicated to the discovery hero image. A gradient overlay fades from transparent to theme background, supporting overlaid metadata (title, date, short description) and floating action buttons for map (left) and share (right). The overlay uses Expo `LinearGradient` + `MotiView` character animation for streaming “Analyzing…” messages during AI runs.
- Below the image, the detail sheet displays Markdown-rendered analysis (using `FeedbackMarkdown` renderer despite feedback being deprecated) with bespoke spacing, custom heading weights, and inline feedback wrappers (to be removed but layout must remain consistent without them). Additional sections include contextual metadata (location chips, timestamps), quick action buttons (“Take another photo”, “Upload a photo”), and narration controls.
- Audio player integration: when narration is available, a sticky `PersistentAudioPlayer` (local mode) spans the bottom, matching the global player’s capsule design. Scrolling interacts with the player’s height so content never hides behind it.
- Full-screen zoom: tapping the header image opens a modal with `Zoomable` (pinch and double-tap) over a black canvas and a floating close button. Error states reuse branded logo fallback.

### Modal Transition & Gestures (critical parity)
- Opening animation: `openDiscovery` measures card frame and animates a unified container via Reanimated. Width/height interpolate from card bounds to full screen; border radius eases from 12 → 0; position animates to (0,0). Image layer opacity stays at 1 while details fade in only after the container has settled (prevents flicker).
- Closing animation: when the user taps back or swipes from the left edge (`EdgeGestureDetector`), details fade out first (50ms) while image fades back in, then container springs back to the measured card frame using `withSpring` (damping 15, stiffness 100). The “double cleanup pattern” ensures React state resets before gesture springs complete, eliminating post-dismiss jitter.
- Interactive dismissal: horizontal edge drag tilts the card (`rotateY` up to -5°), scales down to 0.65, offsets vertically, and drops a soft shadow. Releasing beyond the threshold triggers the closing spring; otherwise the card springs back smoothly. All transforms share a single animated container to avoid competing animations.
- During streaming analysis (when discovery detail is shown immediately after Ask AI completes), the same open animation plays from the confirm screen image preview coordinates, keeping visual continuity. The Swift port must replicate this choreography precisely—native animations can be more refined but must preserve timing, easing curves, and sequence.

## Voiceover Narration & Audio Playback
- Voiceover assets stored per discovery in Supabase `voiceovers` bucket. `DiscoveryContext.tsx` orchestrates polling with exponential backoff, caching to disk, and fallback logic for legacy discoveries (< ID 868).
- Persistent audio player (`components/custom/PersistentAudioPlayer`) sits above tab bar, synchronised with voiceover ensure/fetch logic, and supports queue navigation, scrubbing, resume per discovery (positions saved in AsyncStorage).
- Detail screen integrates with audio context to start playback and disable global player when local view is active.

## Credits, Monetization & IAP
- Credit Context (`contexts/CreditContext.tsx`) manages balance, StoreKit/Google Play connection (via `react-native-iap`), purchase flow, and Supabase `grant_initial_credits`, `consume_credit_for_discovery`, `refund_credit` RPCs.
- Purchase credits screen (`app/PurchaseCreditsScreen.tsx`) lists packs, initiates purchases, and surfaces product fetching/loading states. Restore purchases not yet implemented (tracked as gap).
- Server-side receipt validation via `supabase/functions/validate-receipt` (Apple only today) with idempotency based on `store_transaction_id`.
- Credits shown in confirm flow, settings, and purchase UI with low balance warnings.

## Notifications, Updates & Background Behavior
- Push token registration stored in Supabase `push_tokens` table (`lib/notifications.ts`), with retries on Expo token service overload.
- `ask-ai-v7` optionally sends Expo push notification when discoveries finish processing if a token is supplied.
- Over-the-air updates handled via `expo-updates`; `_layout.tsx` periodically checks for updates on launch with retries and user alert after repeated failures.
- Debug screen (`app/update-debug.tsx`) exposes runtime info and manual update checks/reload triggers.

## Settings, Account Utilities & Support Surfaces
- Settings tab (`app/(tabs)/settings.tsx`) includes theme toggle, credit balance summary, reset password launcher, navigation to purchases, debugging links, cache reset hooks, onboarding reset toggles, and placeholders for legal docs.
- Edge gesture detector (`components/gestures/EdgeGestureDetector.tsx`) enables interactive dismiss on detail modal; should be re-imagined with native drag gestures.
- Privacy/Terms screens load Markdown from packaged assets via shared loader.

## Shared Infrastructure & Utilities
- `DiscoveryContext.tsx` centralizes discovery pagination, signed URL caching, voiceover management, error handling, and image cache invalidation.
- Local media caching via `lib/imageCache.ts` (FileSystem + AsyncStorage metadata) plus TODO list of performance bugs documented in tracking files.
- Location helper functions (`lib/locationHelpers.ts`, `lib/locationPerformance.ts`) supply geo-distance calculations and metrics.
- Supabase client (`lib/supabase.ts`) wraps environment config and is used across contexts/services.
- Known issues tracked in `project-documentation/development/tracking/known-issues.md` (e.g., Supabase password reset workaround, Tamagui testIDs, legacy voiceover gap).

---

All items above must be represented in the native Swift implementation, even if the UI/UX is refined. Deviations should be called out explicitly during implementation planning.
