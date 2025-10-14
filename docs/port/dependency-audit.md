# Dependency Audit (October 2024)

This reference captures the research performed to ensure every external package or framework we rely on is current, stable, and compatible with iOS 17/18 and Swift 5.10. It complements the summary table inside `ios-architecture-plan.md` and is intended to be refreshed each quarter or before any major release.

---

## Summary Table
| Category | Package / Framework | Target Version* | Notes & Validation |
|----------|--------------------|-----------------|--------------------|
| Supabase integration | `supabase-swift` 2.34.0 | Current release (Oct 2024). Provides Auth, PostgREST, Storage, Functions, and Realtime clients with structured-concurrency APIs. |
| OAuth (Google) | `GoogleSignIn` / `GoogleSignInSwift` 7.1.0 | Latest iOS SDK. Brings async `signIn(withPresenting:)` API and SwiftUI button support. Requires AppAuth/GTM dependencies. |
| Sign in with Apple | `AuthenticationServices` (built-in) | n/a | Native framework—no external versioning. Confirm entitlement setup. |
| Image pipeline | `Nuke` 12.8.0 + `NukeUI` 1.5.x | October 2024 release with async/await pipeline and SwiftUI integrations. Tune cache size to respect signed URL expiry. |
| Markdown rendering | `MarkdownUI` 2.4.1 | Ships with GitHub/DocC themes and NetworkImage dependency for remote image support. |
| Collections utilities | `swift-collections` 1.3.0 | Apple-managed package (Sept 2024). Provides `Deque` used by paging caches. |
| Algorithms (optional) | `swift-algorithms` 1.2.1 | Complements `swift-collections` for chunking/sampling sequences. Adopt if pagination math benefits. |
| SSE helper (optional) | `swift-sse` 0.4.2 | Lightweight parser (January 2024). Keep only if native `AsyncStream` implementation proves insufficient. |
| Tooling | `SwiftLint` 0.54.0 | September 2024 release. Integrate via Mint/Homebrew; align rules with Swift 5.10. |
| Formatting | `swift-format` (Swift 5.10 toolchain) | n/a | Use toolchain formatter on CI. Ensure config matches lint rules. |

*Offline research as of October 2024. Re-run verification on a networked machine (`swift package update --dry-run`) before producing `Package.resolved`.

*Versions were gathered from public release notes and cached references. Because this environment has no outbound network access, we have not fetched the manifests directly. Treat them as “to be confirmed” and update once you run `swift package update` on a networked machine.

Development note: `WhatsThatIOSPackage/Package.swift` reads the environment variable `USE_REMOTE_DEPS`; setting it to `1` enables these packages so they can be resolved when network access is available.

---

## Verification Checklist
1. **SPM Resolution Audit (Pending)** – Run `USE_REMOTE_DEPS=1 swift package update --dry-run` (ensure module cache paths are writable) and capture the output in this doc.
2. **Sample Project Compile (Pending)** – Link every dependency in a scratch target, confirm build on Debug/Release.
3. **Runtime Smoke Tests (Planned)**
   - Supabase auth + storage roundtrip using staging credentials.
   - StoreKit Test session with purchase + restore flows (built-in StoreKit 2 APIs).
   - MarkdownUI stress test with 12k-character transcript; ensure streaming updates don’t re-layout excessively.
   - Nuke/NukeUI load + disk cache eviction triggered by signed URL expiry simulation.
4. **Security Review (Planned)** – Monitor CVE feeds once versions confirmed; log issues + mitigations.
5. **Release Cadence Monitoring** – Subscribe to GitHub release feeds (Supabase, Nuke, MarkdownUI, Swift Collections) once online; document automation owner.

---

## Action Items Going Forward
- Re-run this audit before TestFlight submission and again prior to App Store launch.
- If Supabase publishes a 3.x line, schedule a spike to validate migration path before upgrading; do not auto-update.
- Track Apple platform betas (iOS 18) for StoreKit 2, GoogleSignIn, and Markdown rendering regressions.
- Document any forks or patches (none currently required) and store them under `Tools/patches/` if added later.

Maintaining this checklist ensures our dependency stack stays healthy and minimizes last-minute surprises during release cycles.
