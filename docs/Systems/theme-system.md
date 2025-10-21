## Appearance & Theme System

The native app now ships with a user-configurable appearance system that supports **Match System**, **Light**, and **Dark** themes. This document explains how it works and how to integrate new features with it.

### Overview
- User preference is persisted via `@AppStorage(AppAppearance.storageKey)` using the `AppAppearance` enum (`WhatsThatShared/AppAppearance.swift`).
- `RootContentView` applies the preference with SwiftUI’s `.preferredColorScheme` and keeps `BrandTheme.activeMode` in sync so shared palette helpers remain accurate.
- The Settings sheet exposes an inline picker under **Settings → Appearance**, allowing testers to toggle the mode at runtime.
- When set to `Match System`, the UI follows the device appearance; `Light` and `Dark` force the respective palette regardless of device settings.

### AppAppearance enum
`AppAppearance` provides:
- A persisted `rawValue` for storage and an associated SF Symbol for the picker UI.
- Mapping to `ColorScheme?` for `.preferredColorScheme`.
- Mapping to `BrandTheme.Mode` so palette helpers (`BrandTheme.palette(for:)`) emit consistent colors.

### Updating existing screens
1. Read the color scheme you need from `@Environment(\.colorScheme)` (or call `BrandTheme.palette(for:)`) instead of hard-coding light-only colors.
2. Use the palette helpers in `BrandTheme.Palette` or `BrandColors.Light/Dark` when constructing new components.
3. Avoid caching `BrandTheme.activeMode`—it can change after the Settings picker updates, so re-evaluate as part of SwiftUI redraws.

### Adding new UI
- Reference `BrandComponents` for button/text styling examples that already respond to the palette.
- When building new views, prefer `BrandTheme.palette(for: colorScheme)` to derive semantic colors (background, text, actions, borders).
- If you need to store the current appearance in state, listen to changes in `@AppStorage(AppAppearance.storageKey)` or expose it through view models.

### Testing
- Smoke test the picker in Settings to verify the app redraws correctly in all three modes.
- Confirm custom controls handle both palettes (e.g., dark backgrounds, light text).
- For UI snapshots, capture at least one light and one dark image when the view depends on appearance.

### Extending the system
- To add new appearance options, extend `AppAppearance` and map the case to a new `BrandTheme.Mode` variant or introduce a custom palette.
- Keep `BrandTheme.activeMode` synchronized to ensure Markdown styling and other shared utilities pick up the change.

