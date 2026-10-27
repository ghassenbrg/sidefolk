#!/bin/bash
# Builds a signed, notarized, stapled Sidefolk DMG for distribution. docs/RELEASE.md is the checklist around it.
#
# Requires (none of these are in the repo):
#   SIDEFOLK_SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   SIDEFOLK_NOTARY_PROFILE  a notarytool keychain profile created once with:
#                            xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID>
# Optional: SIDEFOLK_SKIP_NOTARIZE=1 to stop after signing (for a local smoke test);
#           SIDEFOLK_UNIVERSAL=1 for one binary that runs on Apple silicon and Intel (see docs/RELEASE.md);
#           SIDEFOLK_RELEASE_LABEL=snapshot.391 names the image Sidefolk-<version>-<label>.dmg;
#           SIDEFOLK_NOTARY_KEYCHAIN, the keychain holding the profile when it isn't the login one (CI);
#           SIDEFOLK_NOTARY_MINUTES, how long Apple may take over both submissions (default 180).
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }
# The CI log shows the script's own lines too, so a long quiet stretch says what it is waiting on.
phase() { printf '\n== %s\n' "$*"; }

[[ -n "${SIDEFOLK_SIGN_IDENTITY:-}" ]] || fail "set SIDEFOLK_SIGN_IDENTITY to your Developer ID Application identity."
[[ "$SIDEFOLK_SIGN_IDENTITY" == Developer\ ID\ Application* ]] || fail "SIDEFOLK_SIGN_IDENTITY must be a Developer ID Application identity (got: $SIDEFOLK_SIGN_IDENTITY)."
security find-identity -v -p codesigning | grep -qF "\"$SIDEFOLK_SIGN_IDENTITY\"" || fail "identity not found in your keychain."
if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" != "1" ]]; then
  [[ -n "${SIDEFOLK_NOTARY_PROFILE:-}" ]] || fail "set SIDEFOLK_NOTARY_PROFILE (see the header of this script)."
fi
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; release from a clean, committed tree."

# Tests must pass before anything is signed.
phase "Running the tests"
swift test --no-parallel

APP="build/Sidefolk.app"
phase "Building and signing $APP"
SIDEFOLK_SIGN_IDENTITY="$SIDEFOLK_SIGN_IDENTITY" scripts/build-app.sh release
# Re-sign with a secure timestamp (build-app.sh uses --timestamp=none for speed), inside out.
codesign --force --options runtime --timestamp --sign "$SIDEFOLK_SIGN_IDENTITY" "$APP/Contents/Helpers/sidefolk"
for program in "$APP"/Contents/Resources/Extensions/*/bin/*; do
  codesign --force --options runtime --timestamp --sign "$SIDEFOLK_SIGN_IDENTITY" "$program"
done
codesign --force --options runtime --timestamp --entitlements Resources/Sidefolk.entitlements \
  --sign "$SIDEFOLK_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# No debug entitlement may ship (it lets other processes attach to Sidefolk).
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "get-task-allow"; then fail "get-task-allow is in the signature."; fi

VERSION="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$PWD/$APP/Contents/Info" CFBundleVersion)"

PROFILE=(--keychain-profile "${SIDEFOLK_NOTARY_PROFILE:-}")
[[ -n "${SIDEFOLK_NOTARY_KEYCHAIN:-}" ]] && PROFILE+=(--keychain "$SIDEFOLK_NOTARY_KEYCHAIN")
# Empty when Apple can't be reached, rather than ending the script (pipefail).
notary_status() { xcrun notarytool info "$1" "${PROFILE[@]}" 2>/dev/null | sed -n 's/^ *status: //p' | sed -n 1p || true; }
notarize() {
  local id status="" left misses=0
  phase "Notarizing $(basename "$1") with Apple"
  id="$(xcrun notarytool submit "$1" "${PROFILE[@]}" --output-format json \
        | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | sed -n 1p)" || true
  [[ -n "$id" ]] || fail "notarytool gave no submission id for $1."
  echo "Submission $id. Apple has until $(date -r "$NOTARY_DEADLINE" '+%H:%M %Z')."
  # A network blip ends `notarytool wait` while Apple carries on, so it is asked again until the deadline.
  while :; do
    left=$(( NOTARY_DEADLINE - $(date +%s) ))
    (( left > 0 )) || break
    xcrun notarytool wait "$id" "${PROFILE[@]}" --timeout "$left" || true
    status="$(notary_status "$id")"
    case "$status" in
      "In Progress") misses=0 ;;
      "") (( ++misses < 20 )) || fail "Apple's notary service has been out of reach for 10 minutes (submission $id)." ;;
      *) break ;;
    esac
    sleep 30
  done
  case "$status" in
    Accepted) ;;
    "In Progress" | "")
      fail "Apple hadn't finished checking $1 after $NOTARY_MINUTES minutes. It carries on: \`xcrun notarytool info $id\` says when, then release again." ;;
    *)
      xcrun notarytool log "$id" "${PROFILE[@]}" >&2 || true
      fail "notarization of $1 came back $status (log above)." ;;
  esac
}

# The app is notarized and stapled first, so a copy dragged out of the DMG opens offline too.
if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" != "1" ]]; then
  # Apple usually answers in minutes, but a new team's first submissions can wait an hour or more for
  # a closer look. One budget covers the app and the image, so the CI job's timeout can cover it.
  NOTARY_MINUTES="${SIDEFOLK_NOTARY_MINUTES:-180}"
  NOTARY_DEADLINE=$(( $(date +%s) + NOTARY_MINUTES * 60 ))
  ZIP="build/Sidefolk-$VERSION-$BUILD.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose "$APP"
fi

phase "Packaging and signing the disk image"
DMG="$(scripts/package.sh "${SIDEFOLK_RELEASE_LABEL:-}" | tail -1)"
codesign --force --timestamp --sign "$SIDEFOLK_SIGN_IDENTITY" "$DMG"

if [[ "${SIDEFOLK_SKIP_NOTARIZE:-}" == "1" ]]; then
  echo "Signed $DMG (not notarized)."
  exit 0
fi

notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
# The checksum again: stapling changed the image.
(cd build && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
echo "Release ready: $DMG ($VERSION build $BUILD)"
