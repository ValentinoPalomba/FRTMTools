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
| `frtmtools compare <first> <second>` | Produce an HTML comparison dashboard highlighting size deltas and changed files. |
| `frtmtools buildlog <path>` | Parse an Xcode `.xcactivitylog`, `.xcworkspace`, or `.xcodeproj` and generate a structured build report (HTML) styled like the app dashboards. |

All commands accept optional flags:

- `-o`, `--output <path>` – File path for the generated HTML. Defaults to the current
  directory (`dashboard.html` or `comparison.html`).
- `-h`, `--help` – Show the usage summary.

### Outputs

The CLI writes **HTML reports**. Package analysis produces a single dashboard file identical
to the macOS view (category charts, per-binary stripping tables, manifest insights, etc.).
The build log command generates a single HTML report file.

`buildlog` expects the `xclogparser` executable to be bundled with the CLI, placed next
to the `frtmtools` binary, or provided via `FRTMTOOLS_XCLOGPARSER_PATH`.

### Examples

```bash
frtmtools ipa Payload/MyApp.ipa --output /tmp/MyApp-dashboard.html
frtmtools apk ~/Downloads/sample.apk
frtmtools compare build-old.ipa build-new.ipa --output ~/Desktop/comparison.html
frtmtools buildlog MyApp.xcodeproj --output ~/Desktop/build-report
frtmtools buildlog ~/Library/Developer/Xcode/DerivedData/.../Logs/Build/LogStoreManifest.xcactivitylog --output ~/Desktop/build-report
```

### Automation Tips

- Store dashboards as CI artifacts so designers/reviewers can open the report without
  installing the app.
- Combine with `xcrun altool` or Play upload steps to verify app health before
  submission.
