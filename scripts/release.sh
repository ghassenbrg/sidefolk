#!/usr/bin/env bash
# Builds a release: every check first, then a signed and notarized Sidefolk.app and DMG.
#
#   scripts/release.sh             # needs the signing variables (docs/RELEASE.md, step 1)
#   scripts/release.sh --unsigned  # a local build for trying, not for sharing
#
# The WebKit check needs the browser preview: run `npm run web` in another terminal first.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--unsigned" ]]; then
  for var in APPLE_SIGNING_IDENTITY APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID; do
    if [[ -z "${!var:-}" ]]; then
      echo "Set $var first (docs/RELEASE.md, step 1), or pass --unsigned for a local build." >&2
      exit 1
    fi
  done
fi

npm run typecheck
npm test
(cd src-tauri && cargo test)
if curl -s -o /dev/null http://127.0.0.1:1420/; then
  npm run check:webkit
else
  echo "Skipping the WebKit check: start 'npm run web' to include it." >&2
fi

if [[ "${1:-}" == "--unsigned" ]]; then
  npm run build
else
  npx tauri build --bundles app,dmg
  spctl -a -vv src-tauri/target/release/bundle/macos/Sidefolk.app
fi
ls -lh src-tauri/target/release/bundle/macos/ src-tauri/target/release/bundle/dmg/ 2>/dev/null || true
