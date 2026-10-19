#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
KLAR_ARCH="${KLAR_ARCH:-$(uname -m)}"
KLAR_CONFIG="${KLAR_CONFIG:-release}"
KLAR_APP="$PWD/Artifacts/Sinnfaden.app"
mkdir -p "$KLAR_APP/Contents/MacOS" "$KLAR_APP/Contents/Resources"
# Generate the source artwork before SwiftPM packages the resource bundle.
swift scripts/make-icon.swift "$KLAR_APP/Contents/Resources"
swift build -c "$KLAR_CONFIG" --arch "$KLAR_ARCH"
KLAR_BIN_DIR="$(swift build -c "$KLAR_CONFIG" --arch "$KLAR_ARCH" --show-bin-path)"
cp "$KLAR_BIN_DIR/KLAR" "$KLAR_APP/Contents/MacOS/KLAR"
# SwiftPM resolves resources inside the bundle's Resources directory.
for bundle in "$KLAR_BIN_DIR"/*.bundle; do
  if [ -d "$bundle" ]; then
    ditto "$bundle" "$KLAR_APP/Contents/Resources/$(basename "$bundle")"
  fi
done
swift scripts/configure-release.swift Config/Info.plist "$KLAR_APP/Contents/Info.plist"
# A SwiftPM binary framework must be embedded in the distributable app.
KLAR_SPARKLE="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$KLAR_SPARKLE" ] || { printf 'Sparkle framework missing.\n' >&2; exit 1; }
mkdir -p "$KLAR_APP/Contents/Frameworks"
ditto "$KLAR_SPARKLE" "$KLAR_APP/Contents/Frameworks/Sparkle.framework"
# Remove build-machine search paths so this app actually loads its embedded framework.
while IFS= read -r KLAR_RPATH; do
  case "$KLAR_RPATH" in
    "$PWD"/.build/*) install_name_tool -delete_rpath "$KLAR_RPATH" "$KLAR_APP/Contents/MacOS/KLAR" ;;
  esac
done < <(otool -l "$KLAR_APP/Contents/MacOS/KLAR" | awk '/LC_RPATH/{getline; getline; print $2}')
KLAR_SIGN_ARGS=(--force --sign "${KLAR_SIGNING_IDENTITY:--}")
if [ -n "${KLAR_SIGNING_IDENTITY:-}" ]; then KLAR_SIGN_ARGS+=(--options runtime --timestamp); fi
KLAR_EMBEDDED="$KLAR_APP/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sign inside out; retain the helper entitlements distributed by Sparkle.
for KLAR_COMPONENT in "$KLAR_EMBEDDED/XPCServices/Downloader.xpc" "$KLAR_EMBEDDED/XPCServices/Installer.xpc" "$KLAR_EMBEDDED/Autoupdate" "$KLAR_EMBEDDED/Updater.app"; do
  codesign "${KLAR_SIGN_ARGS[@]}" --preserve-metadata=entitlements "$KLAR_COMPONENT"
done
codesign "${KLAR_SIGN_ARGS[@]}" "$KLAR_APP/Contents/Frameworks/Sparkle.framework"
codesign "${KLAR_SIGN_ARGS[@]}" "$KLAR_APP"
codesign --verify --deep --strict "$KLAR_APP"
file "$KLAR_APP/Contents/MacOS/KLAR"
printf '\nApp erstellt: %s\n' "$KLAR_APP"
