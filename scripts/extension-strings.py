#!/usr/bin/env python3
"""An extension's words in Sidefolk's ten languages (docs/DECISIONS.md D76, docs/EXTENSIONS.md › Languages).

  scripts/extension-strings.py sync <extension folder>…     strings/en.json from the program's L(…) calls
  scripts/extension-strings.py status <extension folder>…   what each language still needs
  scripts/extension-strings.py check <extension folder>…    exit 1 unless every language has everything

`sync` reads the sources (Sources/**/*.swift with the Kit's `L("…")` and `L(one: "…", other: "…", count:)`, or
*.py / *.js calling `L("…")`) and rewrites `text` in strings/en.json: new keys added, keys no longer used dropped from
every language. `check` wants, in each of the nine other languages, every `text` key, and a translation of each word
the manifest shows people (name, tagline, description, tool, watcher, page and palette titles, the network's purpose).
Sidefolk's validator (`sidefolk ext validate`) checks the rest: placeholders kept, plural forms, limits.
"""
import json
import re
import sys
from pathlib import Path

LANGUAGES = ["fr", "es", "de", "it", "pt-BR", "ja", "ko", "zh-Hans", "ar"]
STRING = r'"((?:[^"\\\n]|\\.)*)"'
PLAIN = re.compile(r'\bL\(\s*' + STRING)
PLURAL = re.compile(r'\bL\(\s*one:\s*' + STRING + r'\s*,\s*other:\s*' + STRING)


def unescape(s, where):
    if "\\(" in s:
        sys.exit(f"{where}: L(\"{s}\") interpolates; use a {{placeholder}} and pass the value instead")
    return re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m.group(1), 16)), s) \
        .replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def used(folder):
    """{key: text or {"one", "other"}} for every L(…) in the program's sources."""
    out = {}
    for path in sorted(p for p in folder.rglob("*") if p.suffix in (".swift", ".py", ".js", ".mjs") and "strings" not in p.parts):
        text = path.read_text(encoding="utf-8")
        for m in PLURAL.finditer(text):
            one, other = unescape(m.group(1), path), unescape(m.group(2), path)
            out[other] = {"one": one, "other": other}
        for m in PLAIN.finditer(text):
            key = unescape(m.group(1), path)
            out.setdefault(key, key)
    return out


def load(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save(path, data):
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False) + "\n", encoding="utf-8")


def manifest_words(folder):
    """The manifest's words people see, as paths into a language file: ("name",), ("tools", "x", "title")…"""
    m = load(folder / "sidefolk-extension.json")
    paths = [("name",)] + [(k,) for k in ("tagline", "description") if m.get(k)]
    if m.get("permissions", {}).get("network_purpose"):
        paths.append(("network_purpose",))
    paths += [("tools", t, "title") for t, meta in m.get("tools", {}).items() if meta.get("title")]
    for w, meta in m.get("watchers", {}).items():
        paths += [("watchers", w, "title")] + ([("watchers", w, "description")] if meta.get("description") else [])
    paths += [("pages", p, "title") for p in m.get("pages", {})]
    for p, meta in m.get("palettes", {}).items():
        paths += [("palettes", p, "title")] + ([("palettes", p, "placeholder")] if meta.get("placeholder") else [])
    return paths


def get(data, path):
    for part in path:
        data = data.get(part) if isinstance(data, dict) else None
    return data


def missing(folder, lang):
    english = load(folder / "strings/en.json").get("text", {})
    table = load(folder / f"strings/{lang}.json")
    gone = [".".join(p) for p in manifest_words(folder) if not get(table, p)]
    gone += [f"text: {k}" for k in english if k not in table.get("text", {})]
    return gone


def sync(folder):
    found = used(folder / "Sources") if (folder / "Sources").is_dir() else used(folder)
    en_path = folder / "strings/en.json"
    old = load(en_path).get("text", {})
    # Plural forms written by hand (a translator's "one" for a plain key) stay; the code's own win.
    text = {k: (v if isinstance(v, dict) else old.get(k, v) if isinstance(old.get(k), dict) else v) for k, v in sorted(found.items())}
    if not text and not en_path.exists():
        return print(f"{folder.name}: no L(…) calls")
    save(en_path, {"text": text})
    for lang in LANGUAGES:
        path = folder / f"strings/{lang}.json"
        if path.exists():
            data = load(path)
            if "text" in data:
                data["text"] = {k: v for k, v in data["text"].items() if k in text}
                save(path, data)
    print(f"{folder.name}: {len(text)} texts" + (f", {len(set(old) - set(text))} dropped" if set(old) - set(text) else ""))


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("sync", "status", "check"):
        sys.exit(__doc__)
    bad = False
    for arg in sys.argv[2:]:
        folder = Path(arg).resolve()
        if sys.argv[1] == "sync":
            sync(folder)
            continue
        for lang in LANGUAGES:
            gone = missing(folder, lang)
            if gone:
                bad = True
                print(f"{folder.name} {lang}: {len(gone)} missing" + ("".join(f"\n  {g}" for g in gone[:20]) if sys.argv[1] == "status" else ""))
        if not bad and sys.argv[1] == "check":
            print(f"{folder.name}: complete in {len(LANGUAGES) + 1} languages")
    sys.exit(1 if bad and sys.argv[1] == "check" else 0)


if __name__ == "__main__":
    main()
