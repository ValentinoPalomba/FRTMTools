# CLI Usage (`frtmtools`)

The CLI mirrors the macOS analyzer without the UI. Install via Homebrew:

```bash
brew tap valentinopalomba/frtmtools
brew install frtmtools
```

## Commands

| Command | Description |
| --- | --- |
| `frtmtools ipa <path>` | Analyze an `.ipa` or unpacked `.app` bundle and generate an HTML dashboard. |
| `frtmtools apk <path>` | Analyze an `.apk`/`.aab` package (Dex vs native libs, manifest insights, permissions). |
| `frtmtools audit <file-or-folder>` | Audit APK/IPA/APP artefacts with CWE candidates, HTML/PDF reports and evidence JSON. |
| `frtmtools compare <first> <second>` | Produce an HTML comparison dashboard highlighting size deltas and changed files. |
| `frtmtools serve` | Start a local web dashboard to upload packages, run analyses interactively, and keep a persistent history. |

All commands accept optional flags:

- `-o`, `--output <path>` – File path for the generated HTML. Defaults to the current
  directory (`dashboard.html` or `comparison.html`).
- `-h`, `--help` – Show the usage summary.

The interactive dashboard command accepts:

- `--port <port>` – Port for the local server (default: `8765`).
- `--host <host>` – Host for the local server (default: `127.0.0.1`).
- `--no-open` – Do not auto-open the browser.
- `--data-dir <path>` – Override the persistent storage directory.

### Outputs

The `ipa`, `apk`, and `compare` commands write HTML. Each invocation creates an interactive dashboard identical
to the macOS view (category charts, per-binary stripping tables, manifest insights, etc.).
When comparing two packages the output name defaults to `comparison.html`.

### Examples

```bash
frtmtools ipa Payload/MyApp.ipa --output /tmp/MyApp-dashboard.html
frtmtools apk ~/Downloads/sample.apk
frtmtools compare build-old.ipa build-new.ipa --output ~/Desktop/comparison.html
frtmtools serve
```

### Interactive Mode Notes

- Runs and their stored analyses are kept under `~/Library/Application Support/FRTMTools/Dashboard` by default.
- Use the dashboard UI to delete old runs (this also deletes the stored upload + analysis JSON).

### Automation Tips

- Store dashboards as CI artifacts so designers/reviewers can open the report without
  installing the app.
- Combine with `xcrun altool` or Play upload steps to verify app health before
  submission.

## Static audit (`audit`)

```bash
frtmtools audit ~/Downloads/builds --output ~/Desktop/audit
frtmtools audit Payload/MyApp.app --output ~/Desktop/audit --offline
```

Accepts a single APK, IPA, APP, xcarchive ZIP, or a folder containing APKs, IPAs
and extracted APPs. Folder traversal does not analyze the corresponding ZIP
again when an extracted app is available. AAB auditing is not supported by this
command; use the existing `apk` command for its dashboard.

Each app identifier gets a folder with `ios` and/or `android` subfolders.
Use `--app-map <json>` to pair differing platform identifiers explicitly.
Each artefact produces HTML, a standalone PDF, report JSON and supporting
`audit-evidence`. `index-audit.html` links every app; `audit-run.json` records
successful reports and failures. A failed input does not stop the other inputs;
the command exits nonzero if any input failed.

The presentation contains data, CWE classification, observed configuration,
corrections and checks still needed. Methodology and source listings are omitted.

### Automated checks

- Logical sizes, categories, largest files and SHA-256 duplicate groups.
- IPA/archive package size and SHA-256; compressed/uncompressed totals per archive
  group, separating the app Payload from Symbols and other external content.
- ELF NX/RELRO/bind-now/canary indicators and 64-bit PT_LOAD alignment for 16 KB.
- Android manifest, permissions, exported components, FileProvider path resources,
  debug and cleartext flags, signing-tool results and development certificate indicators.
- iOS Info.plist, ATS, entitlements, signature verification, privacy manifests,
  Mach-O imports and recursive framework version inventory, including frameworks
  embedded in app extensions.
- Measured stripping of **temporary binary copies**; signed originals stay intact.
- Mock assets, PDFium web assets and redacted JWT indicators with expiry checks.
- Maven coordinates inferred from metadata, OSV advisory candidates and stable
  Google Maven release lookups for selected SDKs.
- Latest GitHub releases and paginated public advisories for known iOS SDK families.
- Exact CocoaPods podspec lookup and upstream tag normalization (including nanopb).
- Numeric advisory range/branch-fix comparison: candidates, exclusions or unresolved
  applicability, with CWE, CVE, patched versions and direct links.
- NVD CPE/version comparison for explicitly identified libwebp and SSZipArchive frameworks.
- DEX class discovery and SDK-decoded smali inspection of constant READ+WRITE URI
  grants; no JADX installation needed. Up to 40 candidate classes per APK.
- Redacted credential patterns, JSON personal-field names and static code indicators.

Online mode sends only component coordinates/version metadata to public services.
It records network errors/rate limits as unavailable checks. `--offline` disables
all dependency network requests and marks that coverage as unverified.
GitHub requests use `GH_TOKEN`, `GITHUB_TOKEN` or existing `gh auth` credentials
when available; credentials are never included in evidence files. Responses,
retrieval dates, pagination completeness and lookup failures stay in evidence JSON.

### Requirements and limits

Python 3.9+ on PATH (standard library only); macOS/Xcode command-line tools for
native checks. APK input requires Android SDK cmdline-tools and build-tools.
Set `ANDROID_SDK_ROOT` or `ANDROID_HOME`; otherwise `~/Library/Android/sdk` is used.
PDF export uses macOS CoreText and requires no pip packages.

CWE labels and advisory matches are **candidates or configuration findings**, not
proof of exploitation. The audit now performs the reproducible static review
previously done by hand. It does not prove application call-path reachability,
real-world credential validity, message schemas/build options, exact native source
commits or runtime/backend behaviour. These require sources/SBOM or device tests;
unperformed tests are omitted. Unsupported ranges/prereleases and placeholder or
inconsistent versions remain unresolved rather than producing exclusions. Missing versions and failed services are not
classified as clean. The standalone audit does not overwrite the existing dashboard
commands or use package-specific app names, token values or size assumptions.

Regression checks:

```bash
python3 -m unittest discover -s script/tests -v
```

### Standard presentation

`audit` generates the versioned [Report Standard 1.2](ReportStandard.md), based
on the supplied unified HTML layout: Sintesi, Analisi iOS, Analisi Android,
Insight. Each app folder contains `report-unificato.html`; individual HTML/PDFs
and JSON remain in platform subfolders. Fields without automatically obtained evidence are omitted. Manual findings
and unperformed runtime checks do not enter the reports. No methodology or source-list sections are presented.

Example for the provided InvestoPro builds:

```bash
frtmtools audit /path/to/builds --output /path/to/reports \
  --app-map Docs/InvestoPro-app-map.json
python3 script/tests/test_report_standard.py
```
