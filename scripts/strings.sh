#!/bin/bash
# Collects every string people can read into Resources/Localization/Localizable.xcstrings.
# The compiler reports each SwiftUI text literal and String(localized:) with its exact key (so
# interpolations get the right %@ / %lld); xcstringstool merges them, keeping translations and
# marking strings that no longer exist as stale. Prints how complete each language is.
#   scripts/strings.sh            (make strings)
set -euo pipefail
cd "$(dirname "$0")/.."

catalog=Resources/Localization/Localizable.xcstrings
build=.build/strings
found=$(mktemp -d)
trap 'rm -rf "$found"' EXIT

# Our modules must be compiled again for the compiler to report their strings; dependencies stay cached.
# A file left uncompiled would report nothing, and its strings would be marked stale. The build system
# names the folders SidefolkApp.build or SidefolkApp-p.build (SidefolkCore-t.build), by version.
find "$build" -type d \( -name 'SidefolkApp*.build' -o -name 'SidefolkCore*.build' -o -name 'SidefolkCharacter*.build' \) \
  -prune -exec rm -rf {} + 2>/dev/null || true
swift build --product SidefolkApp --build-path "$build" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$found" > /dev/null

[[ -f "$catalog" ]] || printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' > "$catalog"
args=()
for f in "$found"/*.stringsdata; do
  grep -q '/Sources/Sidefolk' "$f" && args+=(--stringsdata "$f")
done
xcrun xcstringstool sync "$catalog" "${args[@]}"

python3 - "$catalog" <<'PY'
import json, sys
strings = json.load(open(sys.argv[1]))["strings"]
live = {k: v for k, v in strings.items() if v.get("extractionState") != "stale" and v.get("shouldTranslate", True)}
langs = sorted({l for v in live.values() for l in v.get("localizations", {})} - {"en"})
print(f"{len(live)} strings")
for l in langs:
    done = sum(1 for v in live.values() if v.get("localizations", {}).get(l, {}).get("stringUnit", {}).get("state") == "translated")
    print(f"  {l}: {done}/{len(live)}")
PY
