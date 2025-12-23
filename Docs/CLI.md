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

All commands accept optional flags:

- `-o`, `--output <path>` – File path for the generated HTML. Defaults to the current
  directory (`dashboard.html` or `comparison.html`).
- `-h`, `--help` – Show the usage summary.

### Outputs

The CLI writes **only HTML**. Each invocation creates an interactive dashboard identical
to the macOS view (category charts, per-binary stripping tables, manifest insights, etc.).
When comparing two packages the output name defaults to `comparison.html`.

### Examples

```bash
frtmtools ipa Payload/MyApp.ipa --output /tmp/MyApp-dashboard.html
frtmtools apk ~/Downloads/sample.apk
frtmtools compare build-old.ipa build-new.ipa --output ~/Desktop/comparison.html
```

### Automation Tips

- Store dashboards as CI artifacts so designers/reviewers can open the report without
  installing the app.
- Combine with `xcrun altool` or Play upload steps to verify app health before
  submission.
