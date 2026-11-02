#!/bin/sh
# What a built app really holds, against the names in the add-ons' manifests (D98): `strings` on its binaries, and its files' names.
# The source guard (ExtensionFreeAppTests) can't see a name joined when the code is compiled; this can. Nothing can see one read at run time.
#   sh scripts/extension-free-binary.sh build/Sidefolk.app <add-ons checkout>
# Lists what it finds; with --strict, which the release path runs (D101), it fails on a find.
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
common = {"archives", "calculator", "clipboard", "currency", "feeds", "git", "images", "pdf", "weather", "your mac", "system vitals plus",
          "play", "games", "rock", "paper", "scissors", "heads", "tails",
          "easy", "fair", "hard", "true", "false", "menu", "last", "again", "random", "center", "harder", "easier", "coin", "dice", "toss"}
def titles(entries):
    for e in entries:
        yield e.get("title", "")
        yield from [v for v in e.get("input", {}).values() if isinstance(v, str)]
        yield from titles(e.get("items", []))
out = set()
for file in glob.glob(os.path.join(sys.argv[1], "extensions", "*", "sidefolk-extension.json")):
    m = json.load(open(file))
    names = [m["id"].split(".")[-1], m["name"]] + list(m.get("surfaces", {}))
    names += [s.get("title", "") for s in m.get("surfaces", {}).values()] + list(titles(m.get("entries", [])))
    # What a surface can be opened with names what it holds, as ids: `higher_lower`.
    names += [v for s in m.get("surfaces", {}).values() for values in s.get("arguments", {}).values() for v in values]
    for n in names:
        n = "".join(c for c in n.replace("_", " ").replace("-", " ").lower() if c.isalnum() or c == " ").strip()
        if n and n not in common:
            out.add(n.replace(" ", "[ ,_-]{0,2}"))
print("\n".join(sorted(out)))
PY
# Reading no manifest would look just like a clean app.
if [ -z "$(tr -d '[:space:]' < "$words")" ]; then
    echo "No extension's manifest under $addons/extensions: nothing to look for, so nothing was checked." >&2
    exit 2
fi
found=$(mktemp)
trap 'rm -f "$words" "$found"' EXIT
report() {
    # $1 what is being read; the rest of its lines come on stdin.
    if hits=$(grep -iwE -f "$words" | sort -u | head -40) && [ -n "$hits" ]; then
        echo x >> "$found"
        printf '%s:\n%s\n' "$1" "$hits"
    fi
}
find "$app" -type f -perm -u+x | while read -r binary; do
    file "$binary" | grep -q 'Mach-O' || continue
    strings -a "$binary" | report "$binary"
done
# The seed list and its packs are the approved exception (D98): the one place a fresh Mac's extensions are named.
find "$app" -not -path '*/Contents/Resources/SeedPacks/*' | sed 's|.*/||' | report "names in the bundle"
if [ "$strict" = 1 ] && [ -s "$found" ]; then exit 1; fi
