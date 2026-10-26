#!/bin/bash
# Assembles Sidefolk.app from the SwiftPM products.
#   scripts/build-app.sh [debug|release]
# Signing: $SIDEFOLK_SIGN_IDENTITY, else an "Apple Development" identity if present, else ad-hoc.
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

swift build "${SWIFT_FLAGS[@]}" --product SidefolkApp
swift build "${SWIFT_FLAGS[@]}" --product sidefolk
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/SidefolkApp" "$APP/Contents/MacOS/Sidefolk"
cp "$BIN/sidefolk" "$APP/Contents/Helpers/sidefolk"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" -e "s/__NAME__/$NAME/" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

[[ -f Resources/Icon/Sidefolk.icns ]] && cp Resources/Icon/Sidefolk.icns "$APP/Contents/Resources/Sidefolk.icns"
[[ -d Resources/Brand/exports ]] && cp -R Resources/Brand/exports "$APP/Contents/Resources/Brand"
[[ -d Resources/MenuBar ]] && cp -R Resources/MenuBar "$APP/Contents/Resources/MenuBar"
[[ -d Resources/Skills ]] && cp -R Resources/Skills "$APP/Contents/Resources/Skills"
# Sprite companions: one folder of poses each; their README stays in the repository.
if [[ -d Resources/Companions ]]; then
  mkdir -p "$APP/Contents/Resources/Companions"
  for dir in Resources/Companions/*/; do
    # Source archives are for regeneration, not installed companion sets.
    [[ -f "${dir}idle.png" ]] || continue
    cp -R "${dir%/}" "$APP/Contents/Resources/Companions/"
  done
fi
# One <language>.lproj per translation; macOS picks the user's language (or the one chosen in Settings).
[[ -f Resources/Localization/Localizable.xcstrings ]] && \
  xcrun xcstringstool compile Resources/Localization/Localizable.xcstrings --output-directory "$APP/Contents/Resources" > /dev/null
cp THIRD_PARTY_NOTICES.md LICENSE "$APP/Contents/Resources/" 2>/dev/null || true
[[ -d extensions ]] && cp -R extensions "$APP/Contents/Resources/Extensions"
# Dependency resource bundles (KeyboardShortcuts' recorder needs its strings) belong in Resources.
for b in "$BIN"/*.bundle; do [[ -e "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"; done
find "$APP/Contents/Resources" -name '__pycache__' -prune -exec rm -rf {} +

IDENTITY="${SIDEFOLK_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
fi
[[ -z "$IDENTITY" ]] && IDENTITY="-"

# Inside out: helper first, then the app (signing the app first invalidates nested code).
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP/Contents/Helpers/sidefolk"
codesign --force --options runtime --timestamp=none --entitlements Resources/Sidefolk.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($VERSION build $BUILD, signed: $IDENTITY)"
