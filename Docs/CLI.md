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

The CLI writes **only HTML**. Each invocation creates an interactive dashboard identical
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
