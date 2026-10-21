# Platform support

Particle Library is a Flutter application with a shared UI. The actual support
status is stricter than “the Dart code compiles”: a platform is supported only
after it has a scaffold, signing/package configuration, a full build and a
smoke test on that platform.

## Matrix

| Platform | Scaffold | Build | Release | Remaining work |
|---|---|---|---|---|
| macOS 12+ (universal) | yes | verified | `.app` | Developer ID signing/notarization for public distribution |
| iPhone/iPad | yes | simulator + debug/release device install verified | Development-signed app | TestFlight/App Store needs paid team |
| Android | yes | release APK built | signed preview APK | API 24/32-bit device smoke test; Play Store signing |
| Windows 10/11 x64 | yes | release bundle and packaging implemented | installer + portable ZIP | native smoke-test sign-off |
| Linux | no | no | none | `linux/`, GTK build, package |

## Shared code that is already portable

- Flutter/Dart UI, search, notes and PDF logic;
- `sqlite3_flutter_libs`, `pdfrx`, `file_selector`, `url_launcher`,
  `path_provider` and `flutter_svg` all publish multiple platform
  implementations;
- The pinned `pdfium_dart` hook supplies the Windows PDFium DLL during builds;
  first-time builds need network access to fetch it.
- keyboard shortcuts use both Command and Control;
- non-macOS builds get an in-app Settings button (macOS opens Settings from the
  application menu).

## Platform-specific caveats

- **macOS menus:** Help and Settings are also wired into the native menu.
  All platforms additionally expose Help and Settings in the top bar (or in
  the compact `⋮` menu) so the app is not dependent on a native menu.
- **Zotero:** the bridge uses loopback `127.0.0.1`, so it only reaches a Zotero
  desktop on the same machine. Mobile builds need a configurable host or should
  hide the Zotero action.
- **PDF annotations:** stored app-side; PDFium support and file access must be
  verified per platform.
- **Snapshot:** the 64 MB SQLite asset must be bundled on every target; mobile
  store size limits and first-launch staging need measurement.
- **Windows:** release packaging is implemented; complete the Windows smoke
  checklist before claiming full support.
- **Signing:** this repository contains no certificates, provisioning profiles
  or store credentials.

## Adding a platform

Do it on a branch, not directly on `main`:

```bash
flutter create --platforms=android .
# or --platforms=windows / --platforms=linux
flutter pub get
flutter analyze
flutter test
flutter build <platform> --release
```

Then add a CI job and document the exact tested OS/toolchain versions. Update
this matrix only after a real build and a smoke test.
