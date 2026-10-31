#!/bin/bash
# Builds this extension and puts together the folder Sidefolk installs: the manifest, the icon if the manifest names
# one, and bin/ext-<name>. Nothing else goes in it (no sources, no .build): Install from Folder copies everything.
#   ./build.sh <sidefolk checkout> [out folder]      e.g. ./build.sh ~/git/sidefolk ~/Extensions
# The folder is <out>/<name>, the id's last part, as the validator expects.
set -euo pipefail
cd "$(dirname "$0")"
SIDEFOLK="${1:?usage: ./build.sh <sidefolk checkout> [out folder]}"
OUT="${2:-out}"
NAME="$(python3 -c 'import json; print(json.load(open("sidefolk-extension.json"))["id"].split(".")[-1])')"

# The Kit is Sidefolk's: copy it fresh, so the program speaks the protocol that checkout does.
rm -rf Kit && cp -R "$SIDEFOLK/extensions/Kit" Kit
swift build -c release --product "ext-$NAME"
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$OUT/$NAME" && mkdir -p "$OUT/$NAME/bin"
cp sidefolk-extension.json "$OUT/$NAME/"
ICON="$(python3 -c 'import json; print(json.load(open("sidefolk-extension.json")).get("icon", ""))')"
if [[ -n "$ICON" ]]; then cp "$ICON" "$OUT/$NAME/"; fi
cp "$BIN/ext-$NAME" "$OUT/$NAME/bin/"
echo "Built $OUT/$NAME"
