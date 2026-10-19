#!/bin/bash
# Prepare reviewable, signed release files locally. This script never uploads.
set -euo pipefail
cd "$(dirname "$0")/.."
KLAR_APP="$PWD/Artifacts/Sinnfaden.app"
KLAR_TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
KLAR_PLIST="$KLAR_APP/Contents/Info.plist"
KLAR_RELEASE_KIND="${1:-regular}"
case "$KLAR_RELEASE_KIND" in regular|major|critical) ;; *) printf 'Usage: prepare-update.sh [regular|major|critical]\n' >&2; exit 1;; esac
[ -d "$KLAR_APP" ] || { printf 'Build and notarize the app first.\n' >&2; exit 1; }
KLAR_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$KLAR_PLIST")"
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$KLAR_PLIST" >/dev/null
case "$KLAR_FEED" in https://*/appcast.xml) ;; *) printf 'Release feed must end in /appcast.xml over HTTPS.\n' >&2; exit 1;; esac
KLAR_DOWNLOAD_PREFIX="${KLAR_FEED%appcast.xml}"
codesign --verify --deep --strict "$KLAR_APP"
codesign -dv "$KLAR_APP" 2>&1 | rg -q '^Authority=Developer ID Application:' || { printf 'A Developer ID signed app is required for publishing.\n' >&2; exit 1; }
xcrun stapler validate "$KLAR_APP"
KLAR_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$KLAR_PLIST")"
KLAR_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$KLAR_PLIST")"
KLAR_OUTPUT="$PWD/Artifacts/updates"
mkdir -p "$KLAR_OUTPUT"
KLAR_ARCHIVE="$KLAR_OUTPUT/Sinnfaden-$KLAR_VERSION-$KLAR_BUILD.zip"
[ ! -e "$KLAR_ARCHIVE" ] || { printf 'This release archive already exists; use a new build number.\n' >&2; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$KLAR_APP" "$KLAR_ARCHIVE"
if [ -n "${KLAR_RELEASE_NOTES:-}" ]; then cp "$KLAR_RELEASE_NOTES" "${KLAR_ARCHIVE%.zip}.md"; fi
KLAR_FLAGS=(--download-url-prefix "$KLAR_DOWNLOAD_PREFIX" --versions "$KLAR_BUILD" --maximum-versions 5)
case "$KLAR_RELEASE_KIND" in
  major) KLAR_FLAGS+=(--major-version "$KLAR_BUILD") ;;
  critical) KLAR_FLAGS+=(--critical-update-version "") ;;
esac
"$KLAR_TOOLS/generate_appcast" "${KLAR_FLAGS[@]}" "$KLAR_OUTPUT"
"$KLAR_TOOLS/sign_update" --verify "$KLAR_OUTPUT/appcast.xml"
printf 'Signed update files prepared in %s. Review before uploading; upload appcast.xml last.\n' "$KLAR_OUTPUT"
