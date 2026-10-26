#!/bin/bash
# Assembles Sidefolk.app from the SwiftPM products.
#   scripts/build-app.sh [debug|release]
# Signing: $SIDEFOLK_SIGN_IDENTITY, else an "Apple Development" identity if present, else ad-hoc.
# SIDEFOLK_UNIVERSAL=1 builds for Apple silicon and Intel in one binary (release builds for the public).
#
# The bundle is assembled and signed beside the old one, then swapped in. A copy that is running keeps working:
# rm -rf under it used to take away its resources mid-build, and a failed build left no app at all. The bundle it
# replaced is kept (as build/.Sidefolk-replaced-<time>.app) until nothing runs from it, then removed by a later build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/SidefolkCore/Version.swift)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ "$CONFIG" == "release" ]]; then
  APP="build/Sidefolk.app"; BUNDLE_ID="app.sidefolk.Sidefolk"; NAME="Sidefolk"
  SWIFT_FLAGS=(-c release --only-use-versions-from-resolved-file)
else
  APP="build/Sidefolk-dev.app"; BUNDLE_ID="app.sidefolk.Sidefolk.dev"; NAME="Sidefolk Dev"
  SWIFT_FLAGS=(-c debug)
fi
[[ "${SIDEFOLK_UNIVERSAL:-}" == "1" ]] && SWIFT_FLAGS+=(--arch arm64 --arch x86_64)

swift build "${SWIFT_FLAGS[@]}" --product SidefolkApp
swift build "${SWIFT_FLAGS[@]}" --product sidefolk
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

BASE="$(basename "$APP" .app)"
STAGE="build/.$BASE-building-$$.app"
mkdir -p build
rm -rf "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Helpers" "$STAGE/Contents/Resources"
cp "$BIN/SidefolkApp" "$STAGE/Contents/MacOS/Sidefolk"
cp "$BIN/sidefolk" "$STAGE/Contents/Helpers/sidefolk"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" -e "s/__NAME__/$NAME/" \
  Resources/Info.plist > "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

[[ -f Resources/Icon/Sidefolk.icns ]] && cp Resources/Icon/Sidefolk.icns "$STAGE/Contents/Resources/Sidefolk.icns"
[[ -d Resources/Brand/exports ]] && cp -R Resources/Brand/exports "$STAGE/Contents/Resources/Brand"
[[ -d Resources/MenuBar ]] && cp -R Resources/MenuBar "$STAGE/Contents/Resources/MenuBar"
# Provider logos (D36): the PDFs only; their SVG sources and credits stay in the repository.
[[ -d Resources/Brand/third-party/logos ]] && cp -R Resources/Brand/third-party/logos "$STAGE/Contents/Resources/ProviderLogos"
[[ -d Resources/Skills ]] && cp -R Resources/Skills "$STAGE/Contents/Resources/Skills"
# One <language>.lproj per translation; macOS picks the user's language (or the one chosen in Settings).
[[ -f Resources/Localization/Localizable.xcstrings ]] && \
  xcrun xcstringstool compile Resources/Localization/Localizable.xcstrings --output-directory "$STAGE/Contents/Resources" > /dev/null
cp THIRD_PARTY_NOTICES.md LICENSE "$STAGE/Contents/Resources/" 2>/dev/null || true
[[ -d extensions ]] && cp -R extensions "$STAGE/Contents/Resources/Extensions"
# Dependency resource bundles (KeyboardShortcuts' recorder needs its strings) belong in Resources.
for b in "$BIN"/*.bundle; do [[ -e "$b" ]] && cp -R "$b" "$STAGE/Contents/Resources/"; done
find "$STAGE/Contents/Resources" -name '__pycache__' -prune -exec rm -rf {} +
find "$STAGE/Contents/Resources" -name '.DS_Store' -delete

IDENTITY="${SIDEFOLK_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
fi
[[ -z "$IDENTITY" ]] && IDENTITY="-"

# Inside out: helper first, then the app (signing the app first invalidates nested code).
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$STAGE/Contents/Helpers/sidefolk"
codesign --force --options runtime --timestamp=none --entitlements Resources/Sidefolk.entitlements \
  --sign "$IDENTITY" "$STAGE"
codesign --verify --deep --strict "$STAGE"

# Swap: two renames a moment apart, so the path always holds a complete, signed bundle.
if [[ -e "$APP" ]]; then mv "$APP" "build/.$BASE-replaced-$(date +%s)-$$.app"; fi
mv "$STAGE" "$APP"
trap - EXIT
# Earlier bundles go once no process has their program open (a running copy maps it, so lsof lists it).
for old in build/."$BASE"-replaced-*.app; do
  [[ -e "$old" ]] || continue
  lsof -t "$old/Contents/MacOS/Sidefolk" >/dev/null 2>&1 || rm -rf "$old"
done
echo "Built $APP ($VERSION build $BUILD, signed: $IDENTITY)"
