#!/bin/bash
# Collects every string people can read into Resources/Localization/Localizable.xcstrings.
# The compiler reports each SwiftUI text literal and String(localized:) with its exact key (so
# interpolations get the right %@ / %lld); xcstringstool merges them, keeping translations and
# marking strings that no longer exist as stale. Prints how complete each language is
# (scripts/translations.py moves translations in and out).
#   scripts/strings.sh            (make strings)
set -euo pipefail
cd "$(dirname "$0")/.."

catalog=Resources/Localization/Localizable.xcstrings
build=.build/strings
found=$(mktemp -d)
trap 'rm -rf "$found"' EXIT

# Our modules must be compiled again for the compiler to report their strings; dependencies stay cached.
find "$build" -type d \( -name 'SidefolkApp.build' -o -name 'SidefolkCore.build' -o -name 'SidefolkCharacter.build' \) \
  -prune -exec rm -rf {} + 2>/dev/null || true
swift build --product SidefolkApp --build-path "$build" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$found" > /dev/null

[[ -f "$catalog" ]] || printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' > "$catalog"
args=()
for f in "$found"/*.stringsdata; do
  grep -q '/Sources/Sidefolk' "$f" && args+=(--stringsdata "$f")
done
xcrun xcstringstool sync "$catalog" "${args[@]}"

python3 scripts/translations.py status
