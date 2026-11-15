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

The script builds/checks all three assets (DMG, ZIP, arm64 APK) and writes `SHA256SUMS.txt`. It does not publish or notarize. Android
builds need `JAVA_HOME` and the Android SDK configured as in
[ANDROID.md](ANDROID.md).

## Signing and notarization

0.1.x previews are published ad-hoc signed with an explicit Gatekeeper warning
in the README. Production builds require a Developer ID Application certificate,
Hardened Runtime, `notarytool` and `stapler`, verified with `spctl`.

Android APKs are signed with the release key described in
[ANDROID.md](ANDROID.md#signing). `tool/release_assets.sh` stops when the key is
missing and prints each APK's signer digest, which must equal the digest
recorded there. Never delete or regenerate that key.

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

### In-app updates

- **Hadron group headers** come from PDG Live and are stored in the notes
  sidecar by `tool/fetch_pdg_group_headers.py` (20 groups: ten meson, ten
  baryon). Re-run it when the PDG Live group headers change, then re-run
  `tool/fetch_pdg_notes.py` only for the per-particle notes it owns.

- **macOS** uses the vendored Sparkle framework. `SUFeedURL` points at
  `appcast.xml`; `SUPublicEDKey` is in `macos/Runner/Info.plist`. The Ed25519
  private key is deliberately not in the repository: keep it at
  `~/.config/particle-library/sparkle_ed25519.key` (or set `SPARKLE_ED_KEY`)
  and back it up; losing it means existing installations cannot verify future
  updates. After building the ZIP, regenerate the signed appcast and commit it:

  ```text
  tool/sparkle_appcast.py dist/release/Particle-Library-X.Y.Z-macOS-universal.zip \
    --version X.Y.Z --build N \
    --url https://github.com/fkguo/Particle-Library/releases/download/vX.Y.Z/Particle-Library-X.Y.Z-macOS-universal.zip \
    --output appcast.xml
  ```

  The appcast must be published before the release announcement. The native
  menu item `Particle Library → Check for Updates…` and the in-app update
  dialog both invoke Sparkle.

- **Android** downloads the APK named by `update.json`'s
  `downloads.android` (or the `assets` array of a GitHub API response), then
  opens the system package installer. The user must allow installs from this
  source once; Android never permits a silent install. Keep the APK URL on
  HTTPS and signed with the existing release key.

- **iOS** updates are delivered by the App Store/TestFlight; there is no
  self-update path.

## iOS / TestFlight

1. Bump the build number (`version: 0.2.0+16`); every TestFlight upload needs a
   new build number for the same marketing version.
2. `flutter build ipa --release` (Xcode automatic signing with the paid team).
3. The pdfrx PDFium xcframework ships without a dSYM, which makes App Store
   Connect warn about `PDFium.framework`. Add one to the archive:
   `tool/ios_pdfium_dsym.sh`
4. Upload the **archive** from Xcode Organizer (Window → Organizer → Distribute
   App → App Store Connect). Transporter uploads only the `.ipa` and cannot
   carry the dSYMs.
5. App Store Connect → TestFlight: wait for processing, answer export
   compliance, add the build to the external group and submit the first build
   of a new marketing version for Beta App Review. Internal testers need no
   review.

## Checklist

- [ ] bundle identifier unchanged and documented
- [ ] version, build number, `appVersion` and `update.json` bumped together
- [ ] snapshot bundled and SHA-256 verified; **not** uploaded as an asset
- [ ] `flutter analyze`, `flutter test` green with the snapshot
- [ ] preview clearly labelled ad-hoc/un-notarized (production requires notarization)
- [ ] iOS physical install and trust checked; TestFlight only with a paid team
- [ ] README/requirements and update channel consistent
- [ ] Android signer digest equals the one recorded in ANDROID.md; the key folder is backed up
- [ ] `appcast.xml` regenerated and signed for the macOS ZIP
- [ ] `update.json` contains the current macOS/Android download URLs
- [ ] release notes and three-entry checksums attached
