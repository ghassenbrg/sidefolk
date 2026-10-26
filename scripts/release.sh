#!/bin/bash
# Builds a signed, notarized, stapled Sidefolk DMG for distribution.
#
# Requires (none of these are in the repo):
#   SIDEFOLK_SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   SIDEFOLK_NOTARY_PROFILE  a notarytool keychain profile created once with:
#                            xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID>
# Optional: SIDEFOLK_SKIP_NOTARIZE=1 to stop after signing (for a local smoke test).
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

[[ -n "${SIDEFOLK_SIGN_IDENTITY:-}" ]] || fail "set SIDEFOLK_SIGN_IDENTITY to your Developer ID Application identity."
[[ "$SIDEFOLK_SIGN_IDENTITY" == Developer\ ID\ Application* ]] || fail "SIDEFOLK_SIGN_IDENTITY must be a Developer ID Application identity (got: $SIDEFOLK_SIGN_IDENTITY)."
security find-identity -v -p codesigning | grep -q "$SIDEFOLK_SIGN_IDENTITY" || fail "identity not found in your keychain."
if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" != "1" ]]; then
  [[ -n "${SIDEFOLK_NOTARY_PROFILE:-}" ]] || fail "set SIDEFOLK_NOTARY_PROFILE (see the header of this script)."
fi

# Tests must pass before anything is signed.
swift test --no-parallel

SIDEFOLK_SIGN_IDENTITY="$SIDEFOLK_SIGN_IDENTITY" scripts/build-app.sh release
# Re-sign with a secure timestamp (build-app.sh uses --timestamp=none for speed).
codesign --force --options runtime --timestamp --sign "$SIDEFOLK_SIGN_IDENTITY" build/Sidefolk.app/Contents/Helpers/sidefolk
codesign --force --options runtime --timestamp --entitlements Resources/Sidefolk.entitlements \
  --sign "$SIDEFOLK_SIGN_IDENTITY" build/Sidefolk.app
codesign --verify --deep --strict --verbose=2 build/Sidefolk.app

VERSION="$(defaults read "$PWD/build/Sidefolk.app/Contents/Info" CFBundleShortVersionString)"
DMG="build/Sidefolk-$VERSION.dmg"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Sidefolk.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sidefolk" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIDEFOLK_SIGN_IDENTITY" "$DMG"

if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" == "1" ]]; then
  echo "Signed $DMG (not notarized)."
  exit 0
fi

xcrun notarytool submit "$DMG" --keychain-profile "$SIDEFOLK_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
shasum -a 256 "$DMG"
echo "Release ready: $DMG"
