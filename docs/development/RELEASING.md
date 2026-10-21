# Releasing Particle Library

## Bundle identifier

The app uses the reverse-DNS identifier
`io.github.fkguo.particlelibrary`, based on the GitHub Pages namespace.

Update it consistently in:

- `macos/Runner/Configs/AppInfo.xcconfig`
- `ios/Runner.xcodeproj/project.pbxproj` (Runner and RunnerTests)

This identifier is now stable. Keep it unchanged across updates: changing it
creates a new app data container, so local notes, favorites and settings from
the old ID are not automatically visible. Cross-ID migration requires an
explicit export/import.

## PDG snapshot

Do **not** publish the 64 MB `pdgall-2026.0.sqlite` as a GitHub release asset.
The authoritative copy is on the PDG API page:

<https://pdg.lbl.gov/2026/api/index.html>

The app bundles the snapshot for end users. Source builders and CI download it
from:

```text
https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite
```

CI uses the repository variable `PDG_SNAPSHOT_URL` (set to that official URL)
and verifies SHA-256
`c82dab0c0a7c5264f23508066cabb8df9eacc1dbfc83c8d20fade6053394ba8a` before
running tests.

Prepare local release assets with:

```bash
tool/release_assets.sh
```

The script builds/checks all four existing assets (DMG, ZIP, arm64 APK,
armeabi-v7a APK) and writes `SHA256SUMS.txt`. It does not publish or notarize.
Android builds need `JAVA_HOME` and the Android SDK configured as in
[ANDROID.md](ANDROID.md).

## Windows artifacts

Windows releases are distributed in two forms because `ParticleLibrary.exe`
cannot run by itself. The complete Flutter bundle includes native DLLs and the
`data/` directory.

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\windows_release.ps1
```

The script requires the verified PDG snapshot, passing `flutter analyze` and
`flutter test`, a successful Windows release build, and Inno Setup 6. It writes
these files to `dist/release/`:

- `Particle-Library-<version>-Windows-x64-Setup.exe`
- `Particle-Library-<version>-Windows-x64-Portable.zip`
- `SHA256SUMS.txt`

See [README-windows.md](../../README-windows.md) for build and installation
details. Never publish only the EXE.

## Signing and notarization

0.1.x previews are published ad-hoc signed with an explicit Gatekeeper warning
in the README. Production builds require a Developer ID Application certificate,
Hardened Runtime, `notarytool` and `stapler`, verified with `spctl`.

## Update channel

The app checks a static manifest before the GitHub API so it still works where
`api.github.com` is blocked or rate-limited:

```text
https://cdn.jsdelivr.net/gh/fkguo/Particle-Library@main/update.json
```

Update `update.json` in the repository before publishing a release; it must
contain the new `version`, release `url` and short notes.


Publish a tag `vX.Y.Z` (build number in `pubspec.yaml`'s `+N` suffix) and bump
`update.json` in the same commit. The updater tries jsDelivr, raw GitHub and
then the GitHub Releases API; a tag alone is not enough because the static
manifest is checked first. Validate the manual check on a release build before
announcing.

## Checklist

- [ ] bundle identifier unchanged and documented
- [ ] version, build number, `appVersion` and `update.json` bumped together
- [ ] snapshot bundled and SHA-256 verified; **not** uploaded as an asset
- [ ] `flutter analyze`, `flutter test` green with the snapshot
- [ ] preview clearly labelled ad-hoc/un-notarized (production requires notarization)
- [ ] iOS physical install and trust checked; TestFlight only with a paid team
- [ ] README/requirements and update channel consistent
- [ ] release notes and four-entry checksums attached
- [ ] Windows installer and portable ZIP built from the verified snapshot
- [ ] Windows smoke test completed; installer and ZIP checksums verified
