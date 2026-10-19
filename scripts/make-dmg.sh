#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d Artifacts/Sinnfaden.app ] || { printf 'Zuerst scripts/build-app.sh ausführen.\n' >&2; exit 1; }
KLAR_STAGE="$(mktemp -d -t klar-dmg)"
trap 'rm -rf "$KLAR_STAGE"' EXIT
ditto Artifacts/Sinnfaden.app "$KLAR_STAGE/Sinnfaden.app"
ln -s /Applications "$KLAR_STAGE/Programme"
cp docs/INSTALLATION.md "$KLAR_STAGE/Bitte zuerst lesen.md"
KLAR_BINARY_ARCH="$(lipo -archs Artifacts/Sinnfaden.app/Contents/MacOS/KLAR | tr ' ' '-')"
KLAR_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Artifacts/Sinnfaden.app/Contents/Info.plist)"
KLAR_DMG="$PWD/Artifacts/Sinnfaden-$KLAR_VERSION-$KLAR_BINARY_ARCH-development.dmg"
hdiutil create -volname 'Sinnfaden · Entwicklungsbuild' -srcfolder "$KLAR_STAGE" -ov -format UDZO "$KLAR_DMG"
hdiutil verify "$KLAR_DMG"
