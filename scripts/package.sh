#!/bin/bash
# Packs build/Sidefolk.app into a disk image people install from (drag to Applications), with its
# SHA-256 beside it. It signs nothing new and doesn't notarize: scripts/release.sh does that for a
# public release, and uses this for the image. Prints the image's path as its last line.
#   scripts/package.sh [label]     build/Sidefolk-<version>[-<label>].dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Sidefolk.app"
[[ -d "$APP" ]] || { echo "package: no $APP; run scripts/build-app.sh release first" >&2; exit 1; }
VERSION="$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
NAME="Sidefolk-$VERSION${1:+-$1}"
DMG="build/$NAME.dmg"
STAGE="build/.dmg-$$"
rm -rf "$STAGE" "$DMG" "$DMG.sha256"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Sidefolk.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sidefolk" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
(cd build && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")
echo "$DMG"
