#!/usr/bin/env python3
"""Pseudo-localization: renders every page in a made-up translation, to find text that isn't
localized (it stays plain English) and layouts that can't take longer words (they clip or overflow).

Each value becomes accented and about 40% longer, inside brackets: "Settings" -> "[Šéţţîñĝš ~~~]".
The pseudo text goes into a throwaway copy of the catalog under a real language code (French by
default; Arabic also turns the layout right to left), never into Resources/Localization.

  scripts/pseudo-l10n.py [--language fr|ar|…] [--out build/pseudo-fr]
  scripts/pseudo-l10n.py --catalog-only /tmp/pseudo.xcstrings   (just write the catalog)
"""
import argparse, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Resources", "Localization", "Localizable.xcstrings")

ACCENTS = dict(zip("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
                   "àƀçđéƒĝĥîĵķļɱñöþǫŕšţûṽŵẋýžÀƁÇĐÉƑĜĤÎĴĶĻṀÑÖÞǪŔŠŢÛṼŴẊÝŽ"))
# Format specifiers and line breaks pass through untouched, or the app would crash or misprint.
KEEP = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|%|\.\d+f|f)|\\n|\n")
PLURAL_FORMS = {"ar": ["zero", "one", "two", "few", "many", "other"], "ja": ["other"], "ko": ["other"], "zh-Hans": ["other"]}


def pseudo(text):
    parts, last = [], 0
    for m in KEEP.finditer(text):
        parts.append("".join(ACCENTS.get(c, c) for c in text[last:m.start()]))
        parts.append(m.group(0))
        last = m.end()
    parts.append("".join(ACCENTS.get(c, c) for c in text[last:]))
    body = "".join(parts)
    visible = len(KEEP.sub("", text))
    return "[" + body + " " + "~" * max(1, round(visible * 0.4)) + "]"


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def translate(catalog, language):
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        english = entry.get("localizations", {}).get("en", {})
        plural = english.get("variations", {}).get("plural")
        localizations = entry.setdefault("localizations", {})
        if plural:
            other = plural["other"]["stringUnit"]["value"]
            one = plural.get("one", plural["other"])["stringUnit"]["value"]
            forms = PLURAL_FORMS.get(language, ["one", "other"])
            localizations[language] = {"variations": {"plural": {
                form: unit(pseudo(one if form == "one" else other)) for form in forms}}}
        else:
            value = english.get("stringUnit", {}).get("value", key)
            localizations[language] = unit(pseudo(value))
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--language", default="fr")
    parser.add_argument("--out", help="snapshot folder (default build/pseudo-<language>)")
    parser.add_argument("--catalog-only", metavar="PATH", help="write the pseudo catalog here and stop")
    args = parser.parse_args()

    catalog = translate(json.load(open(CATALOG, encoding="utf-8")), args.language)
    if args.catalog_only:
        target = args.catalog_only
    else:
        target = os.path.join(tempfile.mkdtemp(prefix="sidefolk-pseudo-"), "Localizable.xcstrings")
    with open(target, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
    if args.catalog_only:
        return

    out = args.out or os.path.join(ROOT, "build", f"pseudo-{args.language}")
    command = ["swift", "run", "SidefolkApp", "--ui-snapshots", out, "--language", args.language, "--catalog", target]
    print(" ".join(command), flush=True)
    sys.exit(subprocess.call(command, cwd=ROOT))


if __name__ == "__main__":
    main()
