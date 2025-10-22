# Discovery Detail – TextKit Bridge Plan

## Why we need a bridge
- Discovery detail currently uses `Markdown(description)` from MarkdownUI (see `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveriesHomeView.swift:1653`). That ultimately renders SwiftUI `Text`.
- `Text` supports only leading/center/trailing alignment and exposes no selection API, so:
  - full justification is impossible; paragraph-style attributes are discarded,
  - long-press and drag selection can’t be customized,
  - double-tap/gesture hooks per block aren’t available.
- Goal: a future-ready renderer that keeps Markdown fidelity, supports justification, and unlocks native TextKit selection & gesture control.

## Proposed architecture

### 1. Parse Markdown into attributed text
- Use Swift’s `AttributedString(markdown:options:)` (supports CommonMark/GFM) or keep MarkdownUI’s parser but emit `NSAttributedString`/`AttributedString` instead of `Text`.
- Map Brand theme styles (fonts, colors, spacing) into paragraph/inline attributes:
  - `NSMutableParagraphStyle`: `.alignment = .justified`, `.lineSpacing`, list indentation, etc.
  - `UIFontDescriptor` / `UIFont` for headings, body copy, code blocks.
  - `NSAttributedString.Key.foregroundColor` and background accents.
- Preserve semantic boundaries (`Heading`, `Paragraph`, `ListItem`) to support block-level selection gestures later.

### 2. Host in a TextKit view
- Introduce `JustifiedMarkdownView` using `UIViewRepresentable` (iOS) / `NSViewRepresentable` (macOS) wrapping `UITextView` / `NSTextView`.
- `UITextView` advantages:
  - built-in long-press & drag selection, copy/paste menu, text loupe.
  - flexible gesture recognizers (double-tap, custom highlight overlays).
  - TextKit layout manager handles justification using our paragraph styles.
- View responsibilities:
  - configure `textView.attributedText` with our parsed content,
  - disable editing but keep `isSelectable = true` and `dataDetectorTypes` as needed,
  - set `textContainerInset`, content padding to match existing layout metrics,
  - manage dynamic type (`adjustsFontForContentSizeCategory = true`).

### 3. Integrate with presenter
- Replace `Markdown(description)` inside `detailDescriptionView` with `JustifiedMarkdownView(markdown: description, palette: palette)`.
- Keep fallback to plain `Text` when Markdown parsing fails (e.g., older OS).
- Pass palette so the bridge can reuse existing Brand colors for text, links, blockquotes.

### 4. Gesture hooks & block selection
- Track block ranges during parsing (store `NSRange` per block).
- Add gesture recognizers on the `UITextView` to detect double-tap; use range mapping to expand selection to the nearest block (heading/paragraph).
- Expose callbacks (e.g., `onBlockSelected(BlockIdentifier)`) for future features like annotations or context menus.
- Consider overlaying highlight views for persistent annotations; TextKit provides glyph ranges we can convert to rects.

### 5. Accessibility & VoiceOver
- `UITextView` automatically supports text selection with VoiceOver.
- Ensure headings use appropriate `NSAttributedString.Key.accessibilityTextHeadingLevel` (available via `UIKit` APIs on iOS 17+).
- Maintain existing `textSelection(.enabled)` behavior parity.

## Impacted files/modules
- New bridge types in `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation` (bridge view & renderer helper).
- Brand styling helpers (either reuse `BrandMarkdownTheme` data or port its values into attribute builders).
- `DiscoveryDetailView` / `DiscoveriesHomeView` to swap the MarkdownUI view for the bridge.
- Potential unit tests in `WhatsThatPresentationTests` covering parsing & gesture mapping.

## Open questions / follow-up
- Choose parser path: reuse MarkdownUI’s AST or rely on `AttributedString(markdown:)` + custom styling.
- Generalize for other Markdown surfaces (creation preview, credits) once the bridge is stable.
- Evaluate caching pre-rendered attributed strings for performance if detail payloads are large.
