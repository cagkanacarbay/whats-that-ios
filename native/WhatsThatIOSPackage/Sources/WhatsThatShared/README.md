# WhatsThatShared

Common cross-module utilities live here. Each subfolder collects related helpers:
- `Branding`: typography, colors, and markdown theming that define the visual identity.
- `Configuration`: app configuration surfaces and bundle-backed overrides.
- `Appearance`: environment-driven view styling helpers consumed by presentation.
- `Caching`: lightweight caches that remain free of platform-specific storage.
- `Formatting`: formatters shared across features to keep copy consistent.

Keep the code UI-framework agnostic where possible so other modules can reuse it.
