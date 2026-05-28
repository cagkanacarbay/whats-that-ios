# Phase 1 Testing Checklist

Manual testing checklist for verifying Phase 1 (Modal Presentation) is fully functional. Every item must pass before Phase 1 is considered complete.

---

## 1. Core Camera Flow

- [x] **1.1** Tap Camera tab → camera picker opens immediately
- [x] **1.2** Take photo → confirmation screen appears inside modal
- [x] **1.3** Tap "Discover" on confirm → streaming/analysis begins
- [x] **1.4** Stream completes → discovery result shown with title, description, markdown
- [x] **1.5** Tap X to dismiss → lands on Discoveries tab
- [x] **1.6** New discovery appears in Discoveries list

## 2. Core Gallery Flow

- [x] **2.1** Tap Gallery tab → photo library picker opens immediately
- [x] **2.2** Select photo → confirmation screen appears inside modal
- [x] **2.3** Tap "Discover" on confirm → streaming/analysis begins
- [x] **2.4** Stream completes → discovery result shown
- [x] **2.5** Tap X to dismiss → lands on Discoveries tab
- [x] **2.6** New discovery appears in Discoveries list

## 3. Cancel / Dismiss Paths

- [x] **3.1** Camera picker: tap Cancel → modal dismisses, lands on Discoveries tab
- [x] **3.2** Gallery picker: tap Cancel → modal dismisses, lands on Discoveries tab
- [x] **3.3** Confirmation screen: tap X/Cancel → modal dismisses, lands on Discoveries tab
- [x] **3.4** During streaming: tap X → session transfers to background, modal dismisses, lands on Discoveries
- [x] **3.5** After stream complete: tap X → modal dismisses, lands on Discoveries

## 4. Tab Re-Selection (Gap 4 Invariant)

- [x] **4.1** Dismiss modal → tap Camera again → picker re-opens (not stuck)
- [x] **4.2** Dismiss modal → tap Gallery again → picker re-opens (not stuck)
- [x] **4.3** Camera flow → dismiss → Gallery flow → dismiss → Camera flow (cycle works)
- [x] **4.4** After any dismiss, `selectedTab` is `.discoveries` (verify no blank screen)

## 5. Tab Trigger Placeholder (Gap 3 / Gap 6)

- [x] **5.1** Camera tab content shows branded spinner (not blank) during brief flash before modal
- [x] **5.2** Gallery tab content shows branded spinner (not blank) during brief flash before modal
- [ ] **5.3** No visible blank/white screen flash when tapping Camera or Gallery

## 6. Credits Exhausted Flow (Moved from MainTabView)

- [ ] **6.1** Intro user at discovery limit → confirm screen → credits exhausted fullScreenCover appears
- [ ] **6.2** Credits exhausted: shows 3 recent discoveries with audio playback
- [ ] **6.3** Credits exhausted: tap "Unlock More Stories" → credits sheet opens
- [ ] **6.4** Purchase credits → credits sheet dismisses → credits exhausted dismisses → confirm screen shows updated balance
- [ ] **6.5** Credits exhausted: tap "Not now" → modal dismisses entirely → lands on Discoveries tab
- [ ] **6.6** After purchasing credits, `isInIntroMode` updates (audio toggle unlocked)

## 7. Credits Sheet from Confirmation

- [x] **7.1** Tap credits badge on confirm screen → credits sheet opens
- [x] **7.2** Purchase credits → sheet dismisses → credit balance updates on confirm screen
- [ ] **7.3** `refreshStateAfterCreditsSheet()` fires (verify via balance update)
- [x] **7.4** Close credits sheet without purchasing → confirm screen unchanged

## 8. Audio Generating Modal (First Discovery)

- [ ] **8.1** First discovery stream completes → audio generating modal appears
- [ ] **8.2** Audio modal: tap "Create Another" → audio modal dismisses → creation flow modal dismisses → new picker presents
- [ ] **8.3** Audio modal: tap "Read This Discovery" → audio modal dismisses, streaming view stays
- [ ] **8.4** Audio modal only appears once (second discovery: no modal)
- [ ] **8.5** After audio modal shown, `hasSeenAudioGeneratingModal` is true

## 9. "Discover More" from Streaming View

- [x] **9.1** Streaming complete → tap "Discover More" → current modal dismisses → new picker presents (same flow type)
- [x] **9.2** Camera flow → "Discover More" → opens camera picker (not gallery)
- [x] **9.3** Gallery flow → "Discover More" → opens gallery picker (not camera)
- [x] **9.4** Previous session continues in background (toast appears when complete)

## 10. Permissions — Camera

- [ ] **10.1** First camera use: camera permission prompt appears
- [ ] **10.2** Grant permission → camera opens normally
- [ ] **10.3** Deny permission → error alert with "Go to Settings" link
- [ ] **10.4** Permission denied → alert Cancel → modal dismisses
- [ ] **10.5** Permission denied → "Go to Settings" → grant in Settings → return → tap Camera again → works

## 11. Permissions — Photo Library

- [ ] **11.1** First gallery use: photo library permission prompt appears
- [ ] **11.2** Grant permission → photo picker opens normally
- [ ] **11.3** Deny permission → error alert with "Go to Settings" link
- [ ] **11.4** Permission denied → alert Cancel → modal dismisses

## 12. Permissions — Location (Conditional, 2nd Camera Use)

- [x] **12.1** First camera use → no location permission prompt on confirm
- [x] **12.2** Second camera use → location permission prompt appears on confirm
- [x] **12.3** Grant location → location badge updates on confirm screen
- [x] **12.4** Location only requested once (third camera use: no prompt)

## 13. Permissions — Notifications (Conditional, After Purchase)

- [x] **13.1** Before purchase: no notification permission prompt on confirm
- [x] **13.2** After purchase: notification permission prompt on confirm
- [x] **13.3** Notification permission only requested once

## 14. Post-Purchase Configuration

- [x] **14.1** Purchase credits → post-purchase config flow appears (voice selection + IPoP)
- [x] **14.2** Complete config → dismiss chain back to confirm screen
- [x] **14.3** Nested presentation works: modal → sheet (credits) → fullScreenCover (config) → dismiss chain

## 15. Mini Player Inside Modal

- [x] **15.1** Play audio → start camera flow → confirmation screen: mini player HIDDEN
- [x] **15.2** Play audio → start camera flow → streaming/analyzing: mini player VISIBLE
- [x] **15.3** Mini player tap during modal → modal dismisses (navigates to Audio Guides)
- [x] **15.4** Dismiss modal while audio playing → mini player visible on MainTabView as before
- [x] **15.5** No modal showing → mini player works normally on MainTabView

## 16. Toasts Inside Modal

- [x] **16.1** Start discovery A → "Discover More" → start discovery B → A completes → toast visible inside modal
- [x] **16.2** Toast "View Discovery" action → modal dismisses → navigates to discovery
- [x] **16.3** No modal showing → toasts work normally on MainTabView

## 17. Background / Foreground

- [x] **17.1** Background app during confirmation → return → modal still showing, state intact
- [x] **17.2** Background app during streaming → return → modal still showing, events replayed
- [x] **17.3** Dismiss modal during streaming → background session continues → toast on completion
- [x] **17.4** Background app during streaming → session continues → return → progress updated

## 18. Post-Onboarding Welcome Screen

- [x] **18.1** New user: "Take a Photo" on welcome → Camera tab selected → picker opens immediately (no extra tap)
- [x] **18.2** New user: "Upload a Photo" on welcome → Gallery tab selected → picker opens immediately
- [x] **18.3** Returning user: "Welcome back" copy variant shown correctly

## 19. Intro Mode System

- [x] **19.1** Intro user: audio toggle locked ON during confirmation
- [x] **19.2** Intro user: discovery limit enforced (3 free discoveries)
- [x] **19.3** After purchasing credits: intro mode exits, audio toggle unlocked
- [x] **19.4** `isInIntroMode` updates correctly after credits sheet dismiss

## 20. Edge Cases

- [x] **20.1** Rapidly tap Camera tab multiple times → only one modal presents (no doubles)
- [x] **20.2** Tap Camera while dismiss animation in progress → queued, presents after dismiss completes
- [x] **20.3** ViewModel properly resets between flows: Camera → dismiss → Gallery → dismiss → Camera (no stuck state)
- [x] **20.4** Stream error during analysis → error view shown → retry works
- [x] **20.5** Stream interruption → polling fallback kicks in → discovery found via polling
- [x] **20.6** Polling timeout → polling failed alert → "Retry" returns to confirm, "Cancel" dismisses

## 21. Quick Camera / Quick Upload from Discoveries Tab

- [x] **21.1** Discoveries tab: tap quick-camera button → Camera modal opens
- [x] **21.2** Discoveries tab: tap quick-upload button → Gallery modal opens

---

## Test Summary

| Section | Items | Passed | Failed | Skipped |
|---------|-------|--------|--------|---------|
| 1. Core Camera | 6 | | | |
| 2. Core Gallery | 6 | | | |
| 3. Cancel/Dismiss | 5 | | | |
| 4. Tab Re-Selection | 4 | | | |
| 5. Tab Placeholder | 3 | | | |
| 6. Credits Exhausted | 6 | | | |
| 7. Credits Sheet | 4 | | | |
| 8. Audio Modal | 5 | | | |
| 9. Discover More | 4 | | | |
| 10. Camera Permissions | 5 | | | |
| 11. Photo Library Permissions | 4 | | | |
| 12. Location Permission | 4 | | | |
| 13. Notification Permission | 3 | | | |
| 14. Post-Purchase Config | 3 | | | |
| 15. Mini Player | 5 | | | |
| 16. Toasts | 3 | | | |
| 17. Background/Foreground | 4 | | | |
| 18. Welcome Screen | 3 | | | |
| 19. Intro Mode | 4 | | | |
| 20. Edge Cases | 6 | | | |
| 21. Quick Actions | 2 | | | |
| **TOTAL** | **87** | | | |
