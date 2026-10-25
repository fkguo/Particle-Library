<p align="center">
  <img src="docs/assets/quark-idle.gif" alt="Particle Library Quark" width="150">
</p>

# Particle Library

<p align="center">
  <a href="https://github.com/fkguo/Particle-Library/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/fkguo/Particle-Library?style=flat-square"></a>
  <a href="https://github.com/fkguo/Particle-Library/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/fkguo/Particle-Library/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/fkguo/Particle-Library/blob/main/LICENSE"><img alt="License: MPL-2.0" src="https://img.shields.io/github/license/fkguo/Particle-Library?style=flat-square"></a>
  <a href="https://doi.org/10.5281/zenodo.23460981"><img alt="DOI" src="https://zenodo.org/badge/DOI/10.5281/zenodo.23460981.svg"></a>
  <a href="https://testflight.apple.com/join/my27SMAt"><img alt="TestFlight beta" src="https://img.shields.io/badge/TestFlight-public%20beta-blue?style=flat-square&logo=apple"></a>
  <img alt="macOS 12+" src="https://img.shields.io/badge/macOS-12%2B-blue?style=flat-square&logo=apple&logoColor=white">
  <img alt="Android 7.0+" src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?style=flat-square&logo=android&logoColor=white">
  <img alt="PDG 2026" src="https://img.shields.io/badge/PDG-2026-8A2BE2?style=flat-square">
  <a href="https://github.com/fkguo/Particle-Library/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/fkguo/Particle-Library/total?style=flat-square&label=downloads"></a>
</p>

**English** | [简体中文](README.zh-CN.md)

Particle Library is an offline app for the Particle Data Group Review of
Particle Physics, with notes, references, PDF reviews and annotations. The PDG
snapshot stays read-only and local, while notes, collections, favorites and PDF
annotations are stored separately from the data.

The first version was built over a weekend using **DeepSeek Harness** and
**DeepSeek-V4.1-Flash-1017**.

**Supported platforms:** macOS 12+ (universal), iPhone/iPadOS 15+, and
Android 7.0+ (API 24, preview APK; arm64 tested on a physical device). A shared responsive Flutter layout is used
across desktop and mobile.

**Public TestFlight beta (iPhone/iPad):**
[Join the beta](https://testflight.apple.com/join/my27SMAt). iOS is currently
distributed through TestFlight only.

## Screenshots

| χc1(3872) | π electric polarizability |
| --- | --- |
| <img src="docs/assets/screenshots/desktop-x3872.jpg" alt="χc1(3872) particle page" width="640"> | <img src="docs/assets/screenshots/desktop-polarizability.jpg" alt="Pion electric polarizability measurement page" width="640"> |
| Particle page with left section outline, identity, quantum numbers and right context sidebar. | Measurement page with left outline, definition, source, PDG average and right context sidebar. |

| iPhone |
| --- |
| <img src="docs/assets/screenshots/iphone-search.jpg" alt="Particle Library search on iPhone" width="300"> |
| Responsive layout on iPhone. |

English UI, PDG 2026 snapshot, dark desktop theme and light iPhone theme.

## What is included

- **Offline PDG data** — read-only SQLite snapshot with SHA-256 integrity checks,
  first-launch staging, schema validation and lossless raw-field views.
- **Search and navigation** — particle names and aliases, Greek/LaTeX forms,
  MC numbers, PDG identifiers, topics, decays, references and free text.
- **Review full-text search** — search all 121 PDG Reviews offline, jump to the
  matching page, and see the section heading and table/figure caption for
  each hit.
- **Entity pages** — particles, topics, decay modes, series/properties and
  references, with summaries, all measurements, measurement values, footnotes,
  history, references and source records.
- **Scientific data semantics** — `PDG Average` / `PDG Fit` are treated as
  distinct summary kinds; limits, ranges, confidence levels, scale factors and
  "used in average/fit" flags remain visible instead of being normalised away.
- **Math typesetting** — inline PDG ASCII expressions, particle symbols,
  decay equations and units are rendered as mathematics where the source is
  unambiguous; otherwise the original text is preserved.
- **History and trends** — edition-by-edition summary values and a trend chart
  with asymmetric errors.
- **Notes** — local Markdown notes with anchors, backlinks, collections, tags,
  search, JSON/Markdown export/import, conflict protection, and a
  picker shared by every "add to note" action.
- **Tags** — filter, browse, rename and delete tags across all notes.
- **Full backup** — one ZIP with settings, favorites, notes, highlight anchors
  and cached review PDFs; import auto-detects the format and merges safely. On
  mobile, export opens the system share sheet.
- **Literature** — local reference metadata plus optional Crossref title
  lookup, INSPIRE search, BibTeX/cite-key lookup and a Zotero local bridge.
- **Zotero index (desktop only)** — an explicit, manually refreshed local cache of the Zotero
  library makes INSPIRE result matching fast and avoids one lookup per row.
- **PDG reviews** — on-demand PDF cache, selective cache cleanup, PDF text
  highlights stored as local notes with review anchors, and an annotation
  sidebar. Highlights are searchable, taggable and included in note export.
- **PDF highlights are notes** — each highlight creates a normal local note
  anchored to the review, so search, tags, backlinks, export and the recycle
  bin apply without a second annotation database.
- **Desktop workspace** — independently collapsible left outlines and context
  sidebars, draggable dividers, resizable panes and a compact mobile layout.
- **Bilingual UI** — Chinese and English interface with system/light/dark themes.
- **Update check** — a background release check plus a manual
  **Check for updates** action in Settings → About; it opens the download page.

## Requirements

- macOS 12 or later (universal; verified on macOS 15.6 Apple Silicon).
- iOS/iPadOS 15 or later.
- Android 7.0+ (API 24) for the preview APK.

A released build bundles the PDG snapshot. Building from source additionally
requires Flutter/Xcode and the snapshot; those are **contributor** requirements,
documented in [BUILDING.md](docs/development/BUILDING.md).

Source builders can download the exact snapshot used here:

- [pdgall-2026.0.sqlite](https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite)
- [PDG API download page](https://pdg.lbl.gov/2026/api/index.html)

## Install

Open the **[latest release](https://github.com/fkguo/Particle-Library/releases/latest)**.

- **macOS 12+ (universal)**: download
  `Particle-Library-*-macOS-universal.dmg` (or the `.zip`). It is ad-hoc
  signed, not notarized. Verify `SHA256SUMS.txt` first.

  **If macOS blocks the first launch** (Gatekeeper), use one of these:

  ```text
  Right-click the app → Open → Open
  ```

  or:

  ```text
  System Settings → Privacy & Security → Open Anyway
  ```

  The app is not notarized, so this prompt is expected. Do not disable
  Gatekeeper globally.
- **iPhone/iPad (TestFlight beta)**: join the public beta at
  [testflight.apple.com/join/my27SMAt](https://testflight.apple.com/join/my27SMAt).

  1. Install **TestFlight** from the App Store.
  2. Open the join link on the iPhone/iPad and tap **Accept**.
  3. Install **Particle Library** from TestFlight and open it.

  Requires iOS/iPadOS 15+ and an Apple ID. iOS is currently distributed through
  TestFlight only; builds expire after 90 days. This is a pre-release beta. This
  TestFlight link covers iPhone/iPad; macOS and Android are distributed through
  GitHub Releases.
- **Android 7.0+ (API 24)**: one signed APK for arm64 phones/tablets:
  `Particle-Library-*-Android-arm64-v8a.apk` (32-bit devices are no longer
  built). See [Android build notes](docs/development/ANDROID.md).

  **Android 0.2.0 and later use a new signing key.** The 0.1.x key was lost,
  so Android treats 0.2.x as a different app and will not install it over
  0.1.x. 0.2.x builds can be updated in place. Before uninstalling: in 0.1.x
  open Settings → Data → Export full backup; uninstall the old app, install
  the current 0.2.x build, then import that backup. Uninstalling without a
  backup deletes the local notes, and Android auto-backup is off.
- **Windows/Linux/web**: not built for this release.

The macOS app bundles the PDG snapshot; the release build is self-contained for
end users. Source builders download
[`pdgall-2026.0.sqlite`](https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite)
directly from the [official PDG API page](https://pdg.lbl.gov/2026/api/index.html).

The bundled snapshot is the official PDG file; the app verifies its pinned
SHA-256 before opening it. The checksum and build steps are documented in
[`assets/README.md`](assets/README.md). The app also ships two separate,
read-only derived assets:

- `pdg_notes_2026.sqlite` — additional pdgLive enrichment: entry summaries and
  old-name notes, the 209 pdgLive-related references with INSPIRE record IDs
  and cite keys, citation links, and entry-to-review links;
- `review_index_2026.sqlite` — a page-level full-text index built from the 121
  PDG Review PDFs.

The 209 references are those cited by the pdgLive notes. For other official
references, the app fetches BibTeX/cite keys from INSPIRE on demand.

## Build from source

- [Building Particle Library](docs/development/BUILDING.md)
- [Platform support matrix](docs/development/PLATFORMS.md)

The short macOS path (verified):

```bash
# Download the official snapshot first; see assets/README.md:
# curl -LO https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite
# mv pdgall-2026.0.sqlite assets/
flutter pub get
flutter test
flutter build macos --release
open "build/macos/Build/Products/Release/Particle Library.app"
```

## Tests

```bash
flutter analyze
flutter test
```

The test suite covers the snapshot contract, display semantics, math parsing,
notes/tags, PDF annotation coordinates and persistence, Zotero cache parsing,
and UI helpers. Tests run offline by default; live-service tests are opt-in.

## Local data and privacy

- The PDG snapshot is read-only and checksum-verified.
- Notes live in a separate SQLite database in the app support directory;
  settings, favorites and recent searches live in a JSON file there.
- The Zotero index also lives in the app support directory.
- Review PDFs are downloaded from the PDG website on demand.
- Zotero is accessed read-only through its local API at
  `http://127.0.0.1:23119`; the Zotero index is updated only when you press the
  button in Settings.
- On macOS/Android, update checks contact jsDelivr, raw.githubusercontent.com
  and api.github.com; they do not auto-install anything. On iOS, updates are
  delivered through TestFlight or the App Store.
- No telemetry, analytics or account service is used, and none is planned.

## Repository layout

```text
lib/            Flutter application
test/           unit and widget tests
assets/         icons/theme assets; the PDG snapshot is supplied separately
macos/          macOS runner
ios/            iOS runner
android/        Android runner and release signing
tool/           release/packaging helper scripts
docs/           build, release and user documentation
```

## Citation

If you use Particle Library in academic work, please cite the latest version of
the Review of Particle Physics by the Particle Data Group:

```text
F. Takahashi et al. (Particle Data Group),
Review of Particle Physics,
Int. J. Mod. Phys. A 41, 2630011 (2026).
https://doi.org/10.1142/S0217751X26300115
```

This app also has a DOI which always resolves to the latest archived version:

```text
Guo, Feng-Kun. Particle Library.
Zenodo. https://doi.org/10.5281/zenodo.23460981
```

GitHub also displays this metadata from [`CITATION.cff`](CITATION.cff).

## Documentation

- [Documentation index](docs/README.md)
- [Build instructions](docs/development/BUILDING.md)
- [Android notes](docs/development/ANDROID.md)
- [Platform support](docs/development/PLATFORMS.md)
- [Licensing notes](docs/development/LICENSING.md)
- [Update checks](docs/development/UPDATES.md)
- [Releasing](docs/development/RELEASING.md)
- [Privacy policy](docs/app-store/PRIVACY.md)

Build, platform, release, licensing, update and privacy docs are in English;
the user README is bilingual.

## License

- **Application code:** Mozilla Public License 2.0 (MPL-2.0); see [LICENSE](LICENSE).
  Source: <https://github.com/fkguo/Particle-Library>.
  Copyright 2026 Particle Library contributors.
- **PDG data snapshot:** CC BY 4.0, with attribution to the Particle Data
  Group. The MPL-2.0 license does **not** cover the data.
- **PDG review PDFs:** downloaded from the PDG on demand and subject to PDG's
  terms.
- **Third-party packages:** see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Particle Library is an independent project. PDG data are used under CC BY 4.0
with attribution.
