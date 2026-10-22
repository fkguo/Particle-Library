#!/usr/bin/env bash
# Rebuild the macOS "P1 Test" bundle in dist/ from the current working tree.
#
# dist/Particle Library P1 Test.app is a copied release bundle, not a build
# output: every code change needs a fresh `flutter build macos --release`.
# This script does the whole cycle (build with a visible stamp, replace the
# dist app and the /Applications copy, refresh the zip, relaunch).
set -euo pipefail
cd "$(dirname "$0")/.."

stamp="$(date +%m-%d_%H:%M)"
sha="$(git rev-parse --short HEAD)"
app="build/macos/Build/Products/Release/Particle Library.app"
dist="dist/Particle Library P1 Test.app"

echo "Building $sha ($stamp)…"
flutter build macos --release \
  --dart-define=PDG_BUILD_STAMP="$stamp" \
  --dart-define=PDG_BUILD_COMMIT="$sha" \
  --dart-define=PDG_REVIEW_TRACE=true

pkill -f "Particle Library P1 Test.app" 2>/dev/null || true
sleep 1
rm -rf "$dist"
cp -R "$app" "$dist"
rm -rf "/Applications/Particle Library.app"
cp -R "$app" "/Applications/Particle Library.app"
ditto -c -k --keepParent "$dist" "dist/ParticleLibrary-notes-p1-test-macos.zip"
nohup "$dist/Contents/MacOS/Particle Library" >/tmp/p1test.log 2>&1 &
echo "Refreshed $dist (Build $stamp ($sha))."
