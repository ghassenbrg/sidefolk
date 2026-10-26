#!/bin/bash
# Builds a signed, notarized, stapled Sidefolk DMG for distribution. docs/RELEASE.md is the checklist around it.
#
# Requires (none of these are in the repo):
#   SIDEFOLK_SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   SIDEFOLK_NOTARY_PROFILE  a notarytool keychain profile created once with:
#                            xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID>
# Optional: SIDEFOLK_SKIP_NOTARIZE=1 to stop after signing (for a local smoke test);
#           SIDEFOLK_UNIVERSAL=1 for one binary that runs on Apple silicon and Intel (see docs/RELEASE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

[[ -n "${SIDEFOLK_SIGN_IDENTITY:-}" ]] || fail "set SIDEFOLK_SIGN_IDENTITY to your Developer ID Application identity."
[[ "$SIDEFOLK_SIGN_IDENTITY" == Developer\ ID\ Application* ]] || fail "SIDEFOLK_SIGN_IDENTITY must be a Developer ID Application identity (got: $SIDEFOLK_SIGN_IDENTITY)."
security find-identity -v -p codesigning | grep -qF "\"$SIDEFOLK_SIGN_IDENTITY\"" || fail "identity not found in your keychain."
if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" != "1" ]]; then
  [[ -n "${SIDEFOLK_NOTARY_PROFILE:-}" ]] || fail "set SIDEFOLK_NOTARY_PROFILE (see the header of this script)."
fi
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; release from a clean, committed tree."

# Tests must pass before anything is signed.
swift test --no-parallel

APP="build/Sidefolk.app"
SIDEFOLK_SIGN_IDENTITY="$SIDEFOLK_SIGN_IDENTITY" scripts/build-app.sh release
# Re-sign with a secure timestamp (build-app.sh uses --timestamp=none for speed), inside out.
codesign --force --options runtime --timestamp --sign "$SIDEFOLK_SIGN_IDENTITY" "$APP/Contents/Helpers/sidefolk"
codesign --force --options runtime --timestamp --entitlements Resources/Sidefolk.entitlements \
  --sign "$SIDEFOLK_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# No debug entitlement may ship (it lets other processes attach to Sidefolk).
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "get-task-allow"; then fail "get-task-allow is in the signature."; fi

VERSION="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$PWD/$APP/Contents/Info" CFBundleVersion)"

notarize() {
  local id
  id="$(xcrun notarytool submit "$1" --keychain-profile "$SIDEFOLK_NOTARY_PROFILE" --wait --output-format json \
        | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$id" ]] || fail "notarytool gave no submission id for $1."
  if ! xcrun notarytool info "$id" --keychain-profile "$SIDEFOLK_NOTARY_PROFILE" | grep -q "status: Accepted"; then
    xcrun notarytool log "$id" --keychain-profile "$SIDEFOLK_NOTARY_PROFILE" >&2 || true
    fail "notarization of $1 was not accepted (log above)."
  fi
}

# The app is notarized and stapled first, so a copy dragged out of the DMG opens offline too.
if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" != "1" ]]; then
  ZIP="build/Sidefolk-$VERSION-$BUILD.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose "$APP"
fi

DMG="build/Sidefolk-$VERSION.dmg"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Sidefolk.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sidefolk" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$SIDEFOLK_SIGN_IDENTITY" "$DMG"

if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" == "1" ]]; then
  echo "Signed $DMG (not notarized)."
  exit 0
fi

notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Release ready: $DMG ($VERSION build $BUILD)"
