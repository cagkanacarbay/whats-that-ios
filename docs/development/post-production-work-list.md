# Post-production Work List

A running list of features and improvements to build after the initial production release.

---

## UI Updates

**Update UI to match Audio Guide's style and colors:**
- [ ] Settings screen
- [ ] Credits sheet
- [ ] Content preferences sheet
- [ ] Voice model sheet
- [ ] Confirm image selection page

---

## App Update Notifications

- [ ] Implement a system to detect when a new app version is available
- [ ] Show an alert to users prompting them to update via the App Store

---

## Confirm Image Selection Page

- [ ] Add toggle to auto-generate audio

---

## Create Generation Framework

- [ ] Confirm UI
- [ ] Streaming UI (during generation)
- [ ] Final UI (after generation complete)
- [ ] Audio guides representation - allow users to directly view or create audio guides from this flow

---

## Database Cleanup

- [ ] Drop the `analysis` column from the `discoveries` table (currently unused and always empty)
- [ ] Remove the `get_discovery_analysis` function

---

## Legal Documents

- [ ] Privacy policy: Add Google to in-app purchases section when Android version launches
- [ ] Implement in-app policy change notification mechanism:
  - Track which policy version users have acknowledged (store in user preferences or backend)
  - Show modal/banner when Privacy Policy or Terms of Service version changes
  - Require acknowledgment for material changes before continuing to use the app

---

## Web Share Links

- [ ] Confirm location data is not exposed on shared discovery pages
- [ ] Add audio guide playback to share links (if audio guide exists for the discovery)


