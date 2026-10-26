#!/bin/bash
# Picks the Xcode a GitHub runner builds with: $SIDEFOLK_XCODE (a version such as 26.6, or a path to
# an Xcode.app) when the repository variable sets it, else the runner's default. Then says which.
set -euo pipefail

want="${SIDEFOLK_XCODE:-}"
if [[ -n "$want" ]]; then
  app="$want"
  [[ -d "$app" ]] || app="/Applications/Xcode_$want.app"
  if [[ ! -d "$app" ]]; then
    echo "select-xcode: no Xcode $want on this runner. It has:" /Applications/Xcode*.app >&2
    exit 1
  fi
  sudo xcode-select -s "$app/Contents/Developer"
fi
xcodebuild -version | head -1
swift --version 2>&1 | head -1
