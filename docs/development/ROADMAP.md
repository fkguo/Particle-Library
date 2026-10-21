# Development roadmap and cross-platform rules

Particle Library is a cross-platform Flutter application. A change is not
finished just because it compiles on macOS: platform-specific UI, permissions,
storage and packaging must either be handled now or recorded here.

## Current platform status

| Target | Status | Next action |
|---|---|---|
| macOS | supported, release build verified | signing/notarization for public distribution |
| iPhone/iPad | simulator + development-signed Release install verified | TestFlight/App Store signing |
| Android | signed preview APK; arm64/API 35 smoke-tested | API 24 and 32-bit device smoke test; Play Store signing |
| Windows 10/11 x64 | packaged; smoke-test sign-off pending | complete the Windows QA checklist |
| Linux | not scaffolded | build on Linux/GTK, package |

## Planned work

### P1 — mobile/runtime portability

- Hide Zotero on Android/iOS (done for this release). Zotero's local API is
  loopback-only; a phone would query itself, not the user's desktop.
- Add an explicit platform capability layer instead of scattering
  `Platform.is...` checks through widgets.
- Verify PDFium, SQLite, file picker and 64 MB asset staging on Android.
- Decide whether mobile Zotero needs a configurable desktop host or a
  companion sync service; do not pretend loopback works on a phone.

### P2 — Android

- Generate `android/` on a branch; set `INTERNET` permission.
- Local Zotero is hidden unless a non-loopback host is configured.
- Test release signing, asset size, PDF viewer, file selection and notes DB.
- Add a CI job and document the tested toolchain.

### P3 — Windows/Linux

- Complete Windows smoke-test sign-off; generate and validate `linux/` on a
  native Linux host.
- Keep desktop plugin, persistence and keyboard validation platform-specific.

### P4 — iOS distribution

- Complete Apple signing and TestFlight.
- Verify iPhone and iPad layouts, PDF annotations, notes and Help.
- Add a release checklist for bundle ids, versioning and provisioning.

### P5 — annotation follow-ups

- Optional “Create reading note from selected highlights” flow.
- PDF changed/re-anchoring (quote + page fingerprint).
- More annotation types only if they can be represented without a block model.

## Rules for future changes

1. Do not add a platform-specific import to shared UI when a small capability
   helper can isolate it.
2. Any new plugin must have a documented supported-platform matrix.
3. New user-visible features need a mobile and desktop layout check.
4. New native permissions, entitlements or packages must be added to the
   corresponding platform scaffold, not only macOS.
5. Update the matrix above in the same change that adds or verifies a platform.
6. Do not claim a platform is supported until a real build and smoke test have
   been completed.
