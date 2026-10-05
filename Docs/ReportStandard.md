# Report standard FRTMTools 1.3

Reference layout: `report_ISPmobile_20260908.html` provided on 2026-10-01.
The contract defines presentation and fields, not the reference app's values.

## Presentation

One unified HTML report per app, with the tabs **Sintesi**, **Analisi iOS**,
**Analisi Android**, **Insight**. The layout uses a restrained header, platform
metadata, KPI strips, horizontal bars/doughnuts, searchable/sortable tables with pagination,
status badges, severity filters, expandable finding evidence, remediation actions and individual PDF downloads.
Localization inventories are deferred and omitted, including when restyling cached records.
Charts and tables work offline. No methodology or source-list sections are shown.
PDFs use the same platform fields, with a layout suitable for pagination.

## Field catalogue

Every platform record contains `schemaVersion`, `platform`, `title`, `summary`,
`charts`, `checks` and `blocks`. Every block contains `key`, `title`, `headers`,
`rows`, `note`. Only automatically obtained measurements enter the presentation. Unknown summary
fields, unavailable columns and sections, manual findings and runtime-only checks
are omitted. The collector preserves raw diagnostics in `audit-evidence`.

| Section | Information when obtainable |
| --- | --- |
| Summary | Artefact, identifier, version/build/date, package and logical sizes, install/download estimates, files, components, findings, advisory count, check counts, confirmed exploits |
| Archive contents | Measured IPA/ZIP bytes/hash, compressed/uncompressed totals per top-level group; Payload remains distinct from Symbols and other contents |
| Size breakdown | App code, native components and resources, logical bytes/MiB, category percentages |
| Category distribution | Largest files, sizes and category; graphs use disjoint categories |
| External SDKs | Name/group, included version, current release, status/unknown version |
| Component security | Candidate advisory ID, component/version, severity if attested, prerequisites/limits, correction |
| Excluded advisories | Advisory excluded only for an explicitly observed component/version |
| Security assessment | ID, priority, area, title, CWE, evidence status, observed evidence, correction |
| Duplicates | Paths, copy count, size per copy, redundant bytes |
| Privacy | Observed manifests per component; presence/absence is not compliance |
| Entitlements | Key, observed value |
| Hardening | Platform protections and binary indicators, with scope limitations |
| Build quality | Debug, signing, development/test files, sharing/backup settings |
| Connections/debug | ATS/cleartext configuration and debugging information |
| Dead code | Omitted: not collected automatically |
| Android permissions | Permission, SDK restrictions, sensitive capability classification |
| Android components | Name/type/exported/required permission |
| Dynamic modules | Omitted with APK input; requires a collectable AAB inventory |
| Maintenance | Measured stripping, optional assets, runtime/performance and remaining checks |
| Actions | Correction, proposed team, expected evidence; no invented deadlines |

## Meaning of the numbers

- Check statuses: `PASS`, `WARN`, `FAIL`, `NA`, `UNKNOWN`. Their total equals the
  number of check records; they are not a security score.
- “Finding” counts configuration/compatibility findings and candidates; it does
  not mean a confirmed remotely exploitable vulnerability.
- Priorities are qualitative. Advisory severity is shown only if attested;
  app priorities are not a substitute for advisory CVSS.
- An absent estimate is not zero and is omitted. An unperformed verification
  stays out of the report and is never `PASS`.
- Package bytes, logical bytes, download and installed size remain separate.
- Charts' category bytes sum exactly to logical content; app code is split from
  the general native/other category without counting it twice.
- No old reference values, source-review counts, teams, deadlines or results are
  transferred to a different app.

## App grouping

Identifiers group reports by default. When iOS and Android use different IDs,
provide an explicit mapping:

```bash
frtmtools audit /path/to/builds --output /path/to/reports \
  --app-map Docs/InvestoPro-app-map.json
```

The included mapping pairs the supplied InvestoPro PRE identifiers. Other apps
can use a JSON object `{ "bundle.or.package.id": "App name" }`.
Individual reports remain available even when a unified view groups platforms.

## Automatic evidence policy (1.3)

Finding records must originate from the collector (`origin: cli`). Manual code-flow
reviews, manually curated advisory applicability/exclusions without collected metadata, dead-code counts,
runtime performance, unmeasured install/download estimates and exploit counts are
excluded. Public advisory facts appear only when actually returned by an API;
they remain candidates, without claims of reachable app exploitation.

The field catalogue above describes possible information. Sections without
collectable data are absent. Layout, categories, sorting and filtering remain
consistent for the sections actually populated.

## Automatic dependency assessment (1.3)

Exact official podspecs map framework versions to upstream tags. Repository
advisories are paginated; Maven OSV matches are enriched with full records.
NVD is queried with exact libwebp/SSZipArchive CPE identities, never a product keyword match.
Stable numeric ranges, explicit same-branch patch versions and narrowly parsed
`Affects versions <component>-X to <component>-Y` declarations determine candidate
or excluded states; unsupported syntax and inconsistent metadata stay unresolved.
Every advisory displays the measured version, compared version, ID/CVE/CWE,
affected interval, indicated patch, scope limitation and direct link when available.
A numeric match never establishes a reachable exploit in the app.

Constant READ+WRITE URI grants are extracted from SDK-decoded DEX instructions.
JSON fields and credential patterns are redacted indicators, not proof that the
values represent real people or active credentials. Static symbol/string indicators
are shown separately, without attributing a behaviour from their presence alone.
Raw findings, API snapshots and decompilation diagnostics remain in audit-evidence.
