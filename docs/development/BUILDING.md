# Building Particle Library

This file is for contributors. End users should use the installers attached to
a GitHub **Release** when one is available; they do not need Flutter or Xcode.

## Current status

| Target | Status in this repository | Notes |
|---|---|---|
| macOS 12+, universal | **Verified** | Release `.app` built and used for UI testing on macOS 15.6 arm64. |
| iPhone/iPad | **Simulator and development-signed Release install verified** | A free Personal Team signed and launched both Debug and Release builds on an iPhone; TestFlight/App Store still needs a paid team. |
| Android | **Scaffolded; signed preview APK** | arm64-v8a only (no 32-bit); smoke-tested on Android 15/API 35, not on API 24. |
| Windows | **Not generated** | Needs a Windows host/MSVC and a `windows/` scaffold. |
| Linux | **Not generated** | Needs a Linux host/GTK and a `linux/` scaffold. |

Do not present an unverified target as a supported release. The code is
portable Flutter/Dart, but a successful build on macOS does not prove an
Android, Windows or Linux build.

## Prerequisites

- Flutter **3.47.7 stable** / Dart **3.13.5**.
- Xcode 26.3 for macOS/iOS; install the matching iOS platform under
  **Xcode → Settings → Components**.
- CocoaPods where a plugin requires it.
- The PDG snapshot at `assets/pdgall-2026.0.sqlite`; see
  [assets/README.md](../../assets/README.md). Download it from the
  [official PDG API page](https://pdg.lbl.gov/2026/api/index.html) or directly
  from `https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite`. It is not committed
  and is not a GitHub release asset.
- Expected snapshot: PDG 2026, schema 0.3, SHA-256
  `c82dab0c0a7c5264f23508066cabb8df9eacc1dbfc83c8d20fade6053394ba8a`.

The build also includes two committed, derived read-only assets:
`pdg_notes_2026.sqlite` (pdgLive summaries and old names, 209 references with
INSPIRE cite keys, citations, entry-to-review links, and particle-status marks)
and `review_index_2026.sqlite` (page-level review FTS). See
[assets/README.md](../../assets/README.md) for their contents and generators.

`flutter test`, `flutter run` and every platform build require the snapshot to
be present.

## macOS

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos

flutter build macos --release
open "build/macos/Build/Products/Release/Particle Library.app"
```

Optional Finder-friendly release copy:

```bash
rm -rf "dist/Particle Library.app"
mkdir -p dist
ditto "build/macos/Build/Products/Release/Particle Library.app" \
      "dist/Particle Library.app"
```

The bundle id is `io.github.fkguo.particlelibrary`. Keep it stable to preserve the
existing local data container, or change it before distribution.

## iPhone / iPad

Physical installation requires your own Apple signing identity. This repository
contains no certificates, provisioning profiles or team identifiers.

1. Install the iOS platform in Xcode.
2. Connect the iPhone and enable **Developer Mode**.
3. Open `ios/Runner.xcworkspace`.
4. In **Runner → Signing & Capabilities**, choose your team and use a unique
   bundle identifier (for example `com.yourname.particlelibrary`), with
   automatic signing enabled.
5. Build and run:

```bash
flutter pub get
flutter devices
flutter run -d <iphone-device-id> --release
# or
flutter build ios --release
flutter build ipa
```

6. On first launch, trust the developer certificate in
   **Settings → General → VPN & Device Management**.

A free Apple ID works for local testing but expires after seven days. A paid
developer account is needed for longer distribution or TestFlight. An unsigned
check (`flutter build ios --release --no-codesign`) only validates compilation;
it cannot be installed on a physical phone.

## Android, Windows and Linux

Android is a preview target; Windows/Linux are **not yet supported by this checkout**, even though most of
the Dart code is platform-neutral. To add one, do it on a branch and validate
the full stack (SQLite asset, PDFium, file picker, network, local Zotero API):

```bash
# Choose one; this generates the missing platform directory.
flutter create --platforms=android .
flutter create --platforms=windows .
flutter create --platforms=linux .
```

Before claiming support:

- **Android:** add `android.permission.INTERNET`; decide whether the local
  Zotero API needs a cleartext/localhost exception; test the 64 MB asset and
  Play Store size; verify `sqlite3_flutter_libs`, `pdfrx` and `file_selector`.
- **Windows:** build on a Windows machine with MSVC/CMake; verify SQLite,
  PDFium and file dialogs; provide a proper installer.
- **Linux:** build on a Linux host with GTK/CMake; verify SQLite, PDFium,
  file dialogs and packaging.
- Add CI for the new target; a macOS-only build is not enough.
- Re-run `flutter analyze` and the full test suite on each platform.

### Mobile and Zotero

The Zotero bridge currently talks to `http://127.0.0.1:23119`. On a phone,
`127.0.0.1` is the phone itself, not the desktop running Zotero; mobile Zotero
lookup is therefore not functional without a configurable Zotero host. The app
fails gracefully and the rest of the PDF/notes functionality still works.

## Tests

```bash
flutter analyze
flutter test
```

Tests use the bundled snapshot asset and do not require network access unless a
test explicitly opts into a live service.
