#!/usr/bin/env python3
"""Moves translations in and out of Resources/Localization/Localizable.xcstrings.

  scripts/translations.py status                      how complete each language is
  scripts/translations.py export fr todo.json [--all] what French still needs (or every string)
  scripts/translations.py check fr fr.json            validate a translation file, change nothing
  scripts/translations.py import fr fr.json           validate, then write it into the catalog

A translation file is one JSON object: {"English key": "translation"}, or for a count
{"%lld notes": {"one": "...", "other": "..."}}. Import is all or nothing: one bad entry and the
catalog is left as it was, so a translator can run `check` until it passes. The checks are the
ones a person misses: every placeholder kept (reordering needs %1$@ numbering), each language's
plural forms (GLOSSARY.md), the spaces a fragment is joined with, keys that no longer exist.
"""
import json
import re
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "Resources/Localization/Localizable.xcstrings"
LANGUAGES = ["fr", "es", "de", "it", "pt-BR", "ja", "ko", "zh-Hans", "ar"]
# Forms each language must give for a count; "many" is CLDR's form for large round numbers in the
# Romance languages, optional because the system falls back to "other".
REQUIRED = {"ar": {"zero", "one", "two", "few", "many", "other"}, "ja": {"other"}, "ko": {"other"},
            "zh-Hans": {"other"}}
ALLOWED = {"fr": {"one", "many", "other"}, "es": {"one", "many", "other"}, "it": {"one", "many", "other"},
           "pt-BR": {"one", "many", "other"}, "de": {"one", "other"}}
SPEC = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSaAp%])")


def load():
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def save(catalog):
    # Through a temporary file, so a `check` running meanwhile never reads half a catalog.
    temporary = CATALOG.with_suffix(".tmp")
    temporary.write_text(dump(catalog), encoding="utf-8")
    temporary.replace(CATALOG)


def dump(value, indent=0):
    """JSON the way Xcode writes a catalog (" : ", empty objects on three lines), so diffs stay small."""
    pad, inner = "  " * indent, "  " * (indent + 1)
    if isinstance(value, dict):
        if not value:
            return "{\n\n" + pad + "}"
        items = [f"{inner}{json.dumps(k, ensure_ascii=False)} : {dump(v, indent + 1)}" for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        return "[\n" + ",\n".join(inner + dump(v, indent + 1) for v in value) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def live(catalog):
    return {k: v for k, v in catalog["strings"].items()
            if v.get("extractionState") != "stale" and v.get("shouldTranslate", True)}


def english(key, entry):
    """The English text: a string, or {form: text} for a count."""
    unit = entry.get("localizations", {}).get("en", {})
    if "variations" in unit:
        return {form: v["stringUnit"]["value"] for form, v in unit["variations"]["plural"].items()}
    return unit.get("stringUnit", {}).get("value", key)


def translated(entry, lang):
    unit = entry.get("localizations", {}).get(lang)
    if not unit:
        return None
    if "variations" in unit:
        forms = unit["variations"]["plural"]
        if all(f["stringUnit"].get("state") == "translated" for f in forms.values()):
            return {form: f["stringUnit"]["value"] for form, f in forms.items()}
        return None
    s = unit.get("stringUnit", {})
    return s["value"] if s.get("state") == "translated" else None


def placeholders(text):
    """{argument position: type}, or a string saying what is wrong with them."""
    found, numbered, plain = {}, False, False
    for m in SPEC.finditer(text):
        if m.group(3) == "%":
            continue
        kind = (m.group(2) or "") + m.group(3)
        kind = {"d": "lld", "ld": "lld", "i": "lld"}.get(kind, kind)
        if m.group(1):
            numbered, position = True, int(m.group(1))
        else:
            plain, position = True, len(found) + 1
        if found.get(position, kind) != kind:
            return f"argument {position} is used as two different types"
        found[position] = kind
    if numbered and plain:
        return "mixes numbered (%1$@) and plain (%@) placeholders; number them all"
    return found


def check_text(lang, key, form, source, text, problems):
    where = f"{key!r}" + (f" [{form}]" if form else "")
    if not isinstance(text, str) or not text.strip():
        problems.append(f"{where}: empty")
        return
    want, got = placeholders(source), placeholders(text)
    if isinstance(got, str):
        problems.append(f"{where}: {got}")
    elif got != want:
        # Arabic and others may write "one", "two" and "zero" without the count itself; the
        # other arguments must then be numbered so they don't take the count's place.
        dropped_count = (form in {"zero", "one", "two"} and 1 in want and 1 not in got
                         and got == {p: t for p, t in want.items() if p != 1}
                         and (not got or re.search(r"%\d+\$", text)))
        if not dropped_count:
            problems.append(f"{where}: placeholders {fmt(got)} but the English has {fmt(want)}")
    for side, a, b in (("starts", source[:1], text[:1]), ("ends", source[-1:], text[-1:])):
        if (a == " ") != (b == " "):
            problems.append(f"{where}: the English {side} {'with' if a == ' ' else 'without'} a space; keep it the same")


def fmt(found):
    return "none" if not found else ", ".join(f"{p}:%{t}" for p, t in sorted(found.items()))


def validate(lang, translations, catalog):
    strings, problems = live(catalog), []
    if lang not in LANGUAGES:
        return [f"unknown language {lang!r}; one of {', '.join(LANGUAGES)}"]
    if not isinstance(translations, dict):
        return ["the file must be one JSON object: {\"English key\": \"translation\"}"]
    for key, value in translations.items():
        if key not in strings:
            problems.append(f"{key!r}: not a key in the catalog (stale, or the key was retyped)")
            continue
        source = english(key, strings[key])
        if isinstance(source, dict):
            if not isinstance(value, dict):
                problems.append(f"{key!r}: is a count; give its forms as an object, e.g. {{\"one\": …, \"other\": …}}")
                continue
            required = REQUIRED.get(lang, {"one", "other"})
            allowed = ALLOWED.get(lang, required)
            if missing := required - value.keys():
                problems.append(f"{key!r}: missing plural forms {sorted(missing)}")
            if extra := value.keys() - allowed:
                problems.append(f"{key!r}: {lang} has no plural forms {sorted(extra)} (use {sorted(allowed)})")
            for form, text in value.items():
                check_text(lang, key, form, source.get(form, source["other"]), text, problems)
        elif isinstance(value, dict):
            problems.append(f"{key!r}: is not a count; give one string")
        else:
            check_text(lang, key, None, source, value, problems)
    return problems


def unit(text):
    return {"stringUnit": {"state": "translated", "value": text}}


def apply(lang, translations, catalog):
    for key, value in translations.items():
        localizations = catalog["strings"][key].setdefault("localizations", {})
        localizations[lang] = ({"variations": {"plural": {f: unit(value[f]) for f in sorted(value, key=plural_order)}}}
                               if isinstance(value, dict) else unit(value))
        catalog["strings"][key]["localizations"] = dict(sorted(localizations.items()))


def plural_order(form):
    return ["zero", "one", "two", "few", "many", "other"].index(form)


def status(catalog):
    strings = live(catalog)
    print(f"{len(strings)} strings")
    for lang in LANGUAGES:
        done = sum(1 for v in strings.values() if translated(v, lang) is not None)
        print(f"  {lang:8} {done}/{len(strings)}")


def export(lang, out, everything):
    catalog = load()
    items = []
    for key, entry in live(catalog).items():
        current = translated(entry, lang)
        if current is not None and not everything:
            continue
        item = {"key": key, "english": english(key, entry)}
        if "comment" in entry:
            item["comment"] = entry["comment"]
        if isinstance(item["english"], dict):
            item["forms"] = sorted(REQUIRED.get(lang, {"one", "other"}), key=plural_order)
        if current is not None:
            item["current"] = current
        items.append(item)
    Path(out).write_text(json.dumps(items, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(items)} strings for {lang} in {out}")


def main(argv):
    if len(argv) >= 1 and argv[0] == "status":
        return status(load())
    if len(argv) >= 3 and argv[0] == "export":
        return export(argv[1], argv[2], "--all" in argv[3:])
    if len(argv) == 3 and argv[0] in ("check", "import"):
        lang, path = argv[1], argv[2]
        try:
            translations = json.loads(Path(path).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            sys.exit(f"can't read {path}: {e}")
        catalog = load()
        problems = validate(lang, translations, catalog)
        for p in problems:
            print(p)
        if problems:
            sys.exit(f"{len(problems)} problems; nothing was written")
        missing = len(live(catalog)) - sum(1 for k, v in live(catalog).items() if k in translations or translated(v, lang) is not None)
        if argv[0] == "import":
            apply(lang, translations, catalog)
            save(catalog)
        print(f"{len(translations)} {lang} strings {'written' if argv[0] == 'import' else 'pass'}; {missing} still missing")
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
