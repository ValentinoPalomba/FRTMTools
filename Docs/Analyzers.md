# Analyzer Overview

FRTMTools ships with a shared analysis core that powers both the macOS app and the CLI.
This document summarizes what each analyzer inspects and how the data flows into the UI.

## IPA Analyzer

- **Bundle scan** – Recursively walks the app bundle capturing size, type, and nested
  structure (`FileInfo`). The walk now records every Mach-O binary (main app, frameworks,
  plug-ins) during a single pass.
- **Binary stripping audit** – Each Mach-O is tested with `BinaryAnalyzer`. The report
  lists unstripped binaries, estimated savings, and highlights them inside the tips panel
  and HTML dashboard.
- **Dependency graph** – Uses `DependencyAnalyzer` to build a module graph for the
  on-demand visualization.
- **Tips engine** – `TipGenerator` consumes the flattened file list and the stripping
  info to emit warnings (oversized binaries, duplicate files, ATS exceptions, etc.).

### Output Surfaces

| Surface | Data Highlighted |
| --- | --- |
| macOS App | Summary cards, category charts, tips, dependency graph |
| CLI (`frtmtools`) | Interactive HTML dashboard with per-binary stripping tables |

## APK Analyzer

- **Structure scan** – Parses the APK/AAB contents, flattens file sizes, and categorizes
  Dex vs native libs. Permissions, manifest components, and features are also extracted.
- **Android summary** – The new `AndroidSummarySection` renders cards for install size,
  download size, permissions, signature, launch activity, locales, screen support,
  features, and optional image extraction.
- **Manifest insights** – Deep links, exported components, third-party SDKs, and
  hardware features show up in dedicated cards with quick drill-downs.

## Category & Search Helpers

Both analyzers provide category breakdowns. `AppDetailViewModel` now caches filtered
categories per search query, dramatically reducing repeated tree traversals when the
user types inside the search field.

For more implementation detail see:
- `Sources/Analyzers/AppAnalyzer/Core` for analyzers
- `Sources/Analyzers/AppAnalyzer/Components` for shared SwiftUI widgets
- `Sources/Analyzers/AppAnalyzer/ViewModels` for platform-specific logic
