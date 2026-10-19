#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${KLAR_SIGNING_IDENTITY:?Developer-ID-Application-Identität als KLAR_SIGNING_IDENTITY setzen}"
: "${KLAR_NOTARY_PROFILE:?Vorhandenes Notarytool-Keychain-Profil als KLAR_NOTARY_PROFILE setzen}"
case "$KLAR_SIGNING_IDENTITY" in
  'Developer ID Application:'*) ;;
  *) printf 'Für reguläre Verteilung ist ein Developer ID Application-Zertifikat erforderlich.\n' >&2; exit 1 ;;
esac
./scripts/build-app.sh
ditto -c -k --keepParent Artifacts/Sinnfaden.app Artifacts/Sinnfaden-notarization.zip
xcrun notarytool submit Artifacts/Sinnfaden-notarization.zip --keychain-profile "$KLAR_NOTARY_PROFILE" --wait
xcrun stapler staple Artifacts/Sinnfaden.app
xcrun stapler validate Artifacts/Sinnfaden.app
spctl --assess --type execute --verbose Artifacts/Sinnfaden.app
./scripts/make-dmg.sh
printf 'Notarisierte App geprüft. DMG-Bezeichnung bleibt bis zur manuellen Freigabe development.\n'
