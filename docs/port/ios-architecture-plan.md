# Native iOS Architecture Plan

This plan defines the target architecture, frameworks, and cross-cutting patterns for rewriting **What's That** as a native Swift application while preserving the product’s behavior.

---

## Goals & Guiding Principles
- **Feature Parity First:** Match the functional inventory in `feature-inventory.md`; enhancements are welcome but must not regress existing workflows.
- **Clean Architecture:** Separate Presentation, Domain, Data, and Infrastructure concerns to enable testability and parallel development.
- **Async-First Design:** Use Swift Concurrency (`async/await`) and actors for long-lived operations (AI streaming, audio playback, downloads).
- **Simulator-Centric Dev:** Every workflow (capture, AI analysis, IAP, notifications, audio) must be testable in the iOS simulator via mocks or sandbox services.
- **Offline Resilience:** Mirror existing caching (images, voiceovers, session state) with safe fallbacks.

---

## Proposed Tech Stack
- **Language / Runtime:** Swift 5.10+, iOS 17 minimum (for modern SwiftUI Observation API and StoreKit 2 features).
- **UI:** SwiftUI + NavigationStack/TabView, bridged to UIKit where necessary (camera preview, custom gestures, detail overlay coordination).
- **State Management:** ObservableObject + @StateObject at screen scope; Domain/ViewModel layer exposes immutable state structs updated via reducers/actors and `MainActor`-isolated mutations.
- **Networking & Backend:** `supabase-swift` 2.4.x (Auth, PostgREST, Storage) layered behind repository protocols; `URLSession` (native) for Supabase Functions + SSE with `AsyncStream` parsing, `URLSessionWebSocketTask` reserved for future realtime features. Sign-in uses Supabase OAuth flows.
- **Authentication Bridges:** `GoogleSignIn` / `GoogleSignInSwiftSupport` 7.0.x for Google OAuth buttons; Sign in with Apple via `AuthenticationServices`.
- **Camera & Media:** `AVFoundation` (capture) + `PhotosUI` (picker) + `CoreImage` (resize/compress). Wrap in actor-backed media manager.
- **Image Loading & Caching:** `Nuke` 12.2.x + `NukeUI` for SwiftUI integration, backed by disk cache aligned with Supabase signed URL lifetimes.
- **Markdown Rendering:** `MarkdownUI` 5.1.x with custom renderers for streaming tokens and feedback overlays; fallback to `AttributedString` when offline.
- **Location:** `CoreLocation` for GPS, `CLLocationManager` for background updates; optional `MapKit` snapshots for previews.
- **Push Notifications:** `UserNotifications` + APNs tokens stored in Supabase `push_tokens`. During simulator testing, inject stub tokens.
- **IAP:** StoreKit 2 (`Product.products(for:)`, `Transaction.updates`) with existing product IDs; server validation remains via Supabase function.
- **Audio Playback:** `AVAudioEngine` or `AVPlayer` for streamed narration, with background playback disabled (current behavior).
- **Persistence:** `FileManager` for cached images/audio; `AppStorage` / `UserDefaults` for simple flags (onboarding, theme). Evaluate SwiftData once shared caching requirements emerge.
- **Logging & Telemetry:** OSLog categories; forward critical analytics events to Supabase edge logging (deferred) and maintain simulator console traceability.

---

## Dependency Stack Snapshot (October 2024)
| Package / Framework | Purpose | Target Version* | Compatibility Notes |
|---------------------|---------|-----------------|---------------------|
| `supabase-swift` | Auth, PostgREST, Storage, Functions | 2.4.x (Aug 2024) | Swift Concurrency–first API, compatible with iOS 16/17. Confirm exact tag (`2.4.2` currently planned) once network access is available. |
| `GoogleSignIn` / `GoogleSignInSwiftSupport` | Google OAuth, SwiftUI sign-in button | 7.0.x (May 2024) | Ships via SPM; `SwiftSupport` target provides SwiftUI `SignInButton`. Requires custom URL scheme + Supabase redirect. |
| `AuthenticationServices` (Apple) | Sign in with Apple | Built-in | Native framework; no external package. |
| `Nuke` + `NukeUI` | Image loading, disk caching, SwiftUI views | 12.2.x / 1.5.x (Sep 2024) | Async/await pipeline with memory+disk caching. Works on iOS 15+. Verify `NukeUI` compatibility with SwiftUI 5. |
| `MarkdownUI` | Rendering streamed Markdown content | 5.1.x (Aug 2024) | Supports SwiftUI 5 and custom styling hooks for inline controls. Stress-test with long-form responses. |
| `swift-collections` | Ordered collections for caches/history | 1.1.2 (Mar 2024) | Provides `Deque` for paging caches; maintained by Apple. |
| `swift-algorithms` (optional) | Utility algorithms for pagination | 1.2.0 (Mar 2024) | Helps with chunking/pairing operations in domain layer. Adopt if pagination logic benefits. |
| `swift-sse` (adnah) | SSE parsing helper (fallback) | 0.4.2 (Jan 2024) | Optional: keep pinned only if native `AsyncStream` parser lacks coverage. Evaluate after prototyping. |
| `SwiftLint` | Linting (CI, local) | 0.54.0 (Sep 2024) | Install via Mint/Brew. Configure to align with Swift 5.10 ruleset. |
| `swift-format` | Formatting (CI) | Swift 5.10 toolchain | Use toolchain-provided formatter to keep style consistent. |

*Versions reflect latest stable releases available as of October 2024 with offline references. Re-verify on a networked machine using `swift package update --dry-run` before locking `Package.resolved`.

*Because this environment is offline, the versions above come from publicly available release notes cached earlier. Treat them as provisional until validated on a networked machine.*

Audit process: after confirming the versions with live repositories, lock them via `Package.resolved`, monitor upstream breaking changes quarterly, and re-run the audit before TestFlight submission. Document the verification date in `dependency-audit.md`.

---

## Layered Architecture

```
Presentation (SwiftUI Views, Coordinators)
    ↑
Domain (ViewModels, UseCases, Domain Models, Validation)
    ↑
Data (Repositories, Supabase/HTTP clients, Cache managers)
    ↑
Infrastructure (Auth manager, SSE client, StoreKit adapter, Location manager, Push service)
    ↑
Shared (Foundation utilities, image/audio cache, configuration)
```

- **Initial Module Mapping:** The `WhatsThatIOSPackage` Swift package now mirrors these layers:
  - `WhatsThatApp` – composition root that wires dependencies and exposes the SwiftUI entry point.
  - `WhatsThatPresentation` – SwiftUI views and observable view models that drive screen rendering.
  - `WhatsThatDomain` – domain models, repository protocols, and use cases (actors) coordinating business logic.
  - `WhatsThatData` – repository implementations that adapt infrastructure services to domain contracts.
  - `WhatsThatInfrastructure` – live Supabase/Auth services plus lightweight test doubles (e.g., stub transport) scoped to unit tests.
  - `WhatsThatShared` – configuration primitives and cross-cutting utilities used across layers.
  - Each module ships with a placeholder test target to enforce layering and provide scaffolding for future unit tests.

- **Presentation Layer:** Each tab/screen has a SwiftUI view backed by a `ViewModel` (ObservableObject), injected with domain use cases. Navigation is currently driven directly from the views (e.g., `DiscoveriesHomeView` owns the selection state for the discovery detail overlay); a dedicated coordinator remains a future refinement.
- **Domain Layer:** Protocol-oriented use cases (e.g., `CreateDiscoveryUseCase`, `FetchDiscoveriesUseCase`, `PurchaseCreditsUseCase`, `EnsureVoiceoverUseCase`). Contains pure Swift structs/enums describing states, errors, side effects (no UIKit/SwiftUI references).
- **Data Layer:** Repositories translate domain requests into Supabase SDK calls, Storage downloads, or local cache interactions. Use actors for thread safety (e.g., `DiscoveryRepository` actor to serialize pagination).
- Current implementation includes `SupabaseDiscoveryRepository` (backed by `supabase-swift` 2.34.0) for live data and `StubDiscoveryRepository` for previews/offline development.
- **Infrastructure:** Concrete services for SSE streaming, StoreKit, AVFoundation camera management, CoreLocation, APNs registration, background tasks. Provide protocol abstractions for mocking. `SupabaseClientFactory` now centralises creation of `SupabaseClient`, and `GoogleSignInService` wraps the new async `GIDSignIn` APIs — the production app now requires these live integrations (no stub fallbacks).
- **Shared:** Config loader (XCConfig-driven), Logger, JSON utilities (for metadata parsing), caching helpers.

---

## Feature Mapping to Modules

| Feature | Presentation | Domain | Data / Services |
|---------|--------------|--------|-----------------|
| Onboarding | `OnboardingFlowView` with pager | `OnboardingViewModel` (flags) | `OnboardingRepository` (UserDefaults) |
| Auth | `AuthView`, `LoginView`, `SignupView` | `AuthViewModel`, `AuthUseCase` | `SupabaseAuthService` |
| Discovery Capture | `CaptureView` (Camera) / `LibraryPickerView` | `ImageFlowViewModel` state machine | `CameraService`, `PhotoLibraryService`, `LocationService` |
| Confirm Screen | `ConfirmDiscoveryView` | `PrepareAnalysisUseCase`, `CreditStatusUseCase` | `CreditsRepository`, `DiscoveryHistoryRepository`, `PushTokenService` |
| AI Streaming | `AnalysisStreamingView` with Markdown preview | `AnalysisSession` actor orchestrating SSE, retry, cancellation | `AskAIClient` (SSE), `ImageUploader`, `RequestTracker`, `SupabaseFunctionsClient` |
| Discovery List | `DiscoveriesHomeView` | `DiscoveryFeedViewModel` | `DiscoveryRepository` (pagination actor), `Nuke` image loading |
| Discovery Detail Modal | `DiscoveryDetailView` | Selection handled via `DiscoveriesHomeView` state (no separate view model yet) | Voiceover playback TBD (currently stubbed), native share + MapKit helpers |
| Inline Feedback | `FeedbackOverlayView` | `FeedbackViewModel` (local only for now) | Placeholder repository (no backend yet) |
| Audio Player | `PersistentAudioPlayerView` | `AudioPlayerViewModel` (actor) | `VoiceoverRepository`, `AVAudioPlayerService`, `PlaybackStore` |
| Credits & IAP | `PurchaseCreditsView` | `CreditsViewModel`, `PurchaseCreditsUseCase` | `StoreKitService`, `SupabaseCreditsRepository`, `ValidateReceiptClient` |
| Settings | `SettingsView` | `SettingsViewModel` | `AuthService`, `ThemeManager`, `CacheManager`, `OnboardingRepository` |
| Push Notifications | N/A (background) | `PushRegistrationUseCase` | `PushService` (APNs), `SupabasePushTokenRepository` |

---

## Key Flow Designs

### Discovery Creation (Camera/Upload → AI → Save)
1. `ImageFlowViewModel` enters `.requestPermissions` → `CameraService` / `PhotoLibraryService`.
2. Capture yields `CapturedMedia` struct (URI, metadata, EXIF). `LocationService` provides current location or EXIF fallback.
3. `ConfirmDiscoveryViewModel` composes preview state, fetches credit balance (via `CreditsRepository`), builds user context summary (`DiscoveryHistoryRepository`).
4. When user taps “Analyze”, `AnalysisSession` actor:
   - Prepares image (resize/compress).
   - Requests push token from `PushService` if needed.
   - Initiates SSE via `AskAIClient.startSession(payload)`.
   - Consumes SSE events, updating streaming text state (`AnalysisStreamingViewState`).
   - On completion, `AnalysisSession` notifies `DiscoveryRepository` to refresh list, then triggers modal presentation.
5. Errors bubble to `AnalysisSession` → `ImageFlowViewModel`, which transitions to `.error` with retry/exit options.

### Discovery Browsing & Modal Transition
- `DiscoveryFeedViewModel` maintains a paginated array of `DiscoverySummary` structs (now enriched with `shortDescription` + `detailDescription`), handles refresh/load-more, and deduplicates pages.
- `DiscoveriesHomeView` renders the two-column grid using SwiftUI `LazyVGrid`, injects a shared `@Namespace`, and stores selection state so the card image can be reused seamlessly inside `DiscoveryDetailView`.
- Remote imagery is handled by Nuke/AsyncImage; placeholders mirror the RN gradient + logo treatment until the fetch completes.
- `DiscoveryDetailView` reproduces the React Native overlay (gradient, title, subtitle, share/map buttons) and renders the Markdown body with `MarkdownUI`. Dismissal currently relies on the back button; gesture-based drag remains on the backlog alongside voiceover playback plumbing.

### Voiceover Management & Audio Playback
- `VoiceoverRepository` actor handles signed URL generation via Supabase storage, caches audio & timing files, applies exponential backoff rules mirroring React logic.
- `AudioPlayerController` actor (wrapping `AVAudioPlayer`) maintains queue, playback state, and per-discovery position (persisted in `UserDefaults`).
- `PersistentAudioPlayerViewModel` observes `AudioPlayerController` via `AsyncStream` to update UI.

### Credits & StoreKit
- `StoreKitService` loads products and initiates purchases with StoreKit 2 (`Product.purchase()`). Completed transactions call Supabase `validate-receipt`. Pending transactions handled via `Transaction.updates`.
- `CreditsRepository` queries `user_credits`, showing real-time balances in confirm + settings. Consumption happens server-side; client polls after each analysis to stay in sync.
- Restore purchases flow: call `Transaction.currentEntitlements` (StoreKit 2) and re-validate receipts against Supabase.

### Push Notifications
- `PushService` requests UN authorization, registers for APNs, and posts token to Supabase `push_tokens`. Provide simulator guard (no actual token; send sentinel value and skip backend registration).
- On discovery completion, `ask-ai-v7` continues to send Expo push today. Long-term, plan to add APNs support on server or maintain Expo channel (investigate bridging strategy).

---

## Navigation & UI Details
- **Tab Structure:** `TabView` with four tabs (Camera, Discoveries, Upload, Settings). Camera/Upload tabs auto-prompt capture flow on focus; handle “Cancel” states gracefully.
- **Modal:** Current build keeps the overlay inside `DiscoveriesHomeView` and relies on the shared namespace to transition between list and detail; consider migrating to a dedicated coordinator or UIKit bridge if gesture/scroll conflicts emerge when we add interactive dismissal.
- **Markdown Rendering:** Use `AttributedString` Markdown parser or integrate a lightweight renderer (e.g., `MarkdownUI`) to support headings, lists, inline styling. Hooks for feedback overlay.
- **Feedback Overlay:** Represent as overlay view triggered on double-tap (SwiftUI `Gesture`), storing bounding boxes and presenting reaction picker.
- **Theming:** Support dark/light theme toggles using `ColorScheme` environment and persisted preference.

---

## Error Handling & Observability
- Define domain-specific error enums (`AnalysisError`, `CreditError`, `VoiceoverError`) with user-friendly descriptions.
- Centralize error presentation in ViewModels, ensuring consistent alerts/snackbars.
- Log critical failures with OSLog; consider forwarding to Supabase `project-documentation/development/tracking` equivalent or analytics.
- Maintain parity with existing refund logic—if SSE session fails post credit consumption, the server already refunds. Client should surface appropriate message (e.g., “We refunded your credit”).

---

## Accessibility & Localization
- Support Dynamic Type in SwiftUI views (use scalable fonts).
- Provide VoiceOver labels for discovery cards, playback controls, and feedback UI.
- Maintain color contrast parity with theme tokens.
- Current app is English-only; structure copy using `Localizable.strings` to allow future expansion.

---

## Configuration & Environment Management
- Store environment values in `.xcconfig` files (Debug/Release) and expose via `Configuration` struct.
- Provide development overrides for local Supabase projects if needed.
- `AppConfiguration` (see `WhatsThatShared`) represents runtime values (Supabase URL/key, Google client ID) and is passed into `AppDependencyContainer.bootstrap`, which now fails fast if those values are missing.
- Use Swift package for secrets? Keep secrets out of source control (use CI/fastlane to inject for builds). When resolving third-party packages locally/CI, export `USE_REMOTE_DEPS=1` and point module caches at a writable directory.

---

## Extensibility Hooks
- **Android parity (future):** Keep domain layer platform-agnostic to support potential Kotlin Multiplatform or shared backend logic.
- **Feedback persistence:** Domain layer already isolates the feature; later we can wire to Supabase table once available.
- **Map View:** Data layer already exposes `get_discoveries_with_location`; add MapKit visualization in later phase.

This architecture positions the native project for maintainability, testability, and feature growth while faithfully reproducing the current app’s behavior.
