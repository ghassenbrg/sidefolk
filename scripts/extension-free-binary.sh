#!/bin/sh
# What a built app really holds, against the names in the add-ons' manifests (D98): `strings` on its binaries, and its files' names.
# The source guard (ExtensionFreeAppTests) can't see a name joined when the code is compiled; this can. Nothing can see one read at run time.
#   sh scripts/extension-free-binary.sh build/Sidefolk.app <add-ons checkout>
# Lists what it finds and exits 0 until the old game code is gone (D101); with --strict it fails on a find.
set -eu
strict=0
[ "${1:-}" = "--strict" ] && { strict=1; shift; }
app=$1
addons=${2:-${SIDEFOLK_ADDONS_REPO:-../sidefolk-addons}}
words=$(mktemp)
trap 'rm -f "$words"' EXIT
/usr/bin/python3 -I - "$addons" > "$words" <<'PY'
import glob, json, os, sys
# The same words the source guard leaves out: the app's own as much as an extension's.
common = {"archives", "calculator", "clipboard", "currency", "feeds", "git", "images", "pdf", "weather", "your mac", "system vitals plus"}
out = set()
for file in glob.glob(os.path.join(sys.argv[1], "extensions", "*", "sidefolk-extension.json")):
    m = json.load(open(file))
    names = [m["id"].split(".")[-1], m["name"]]
    names += list(m.get("games", {})) + [g.get("title", "") for g in m.get("games", {}).values()] + list(m.get("surfaces", {}))
    for n in names:
        n = n.replace("_", " ").replace("-", " ").strip().lower()
        if n and n not in common:
            out.add(n.replace(" ", "[ _-]?"))
print("\n".join(sorted(out)))
PY
found=0
report() {
    # $1 what is being read; the rest of its lines come on stdin.
    if hits=$(grep -iwE -f "$words" | sort -u | head -40) && [ -n "$hits" ]; then
        found=1
        printf '%s:\n%s\n' "$1" "$hits"
    fi
}
find "$app" -type f -perm -u+x | while read -r binary; do
    file "$binary" | grep -q 'Mach-O' || continue
    strings -a "$binary" | report "$binary"
done
find "$app" | sed 's|.*/||' | report "names in the bundle"
# `found` doesn't leave the pipe above; ask again for the verdict.
if [ "$strict" = 1 ] && { find "$app" | sed 's|.*/||' | grep -qiwE -f "$words"; }; then exit 1; fi
