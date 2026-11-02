#!/usr/bin/env python3
"""The seed packs the app carries for a fresh Mac (docs/DECISIONS.md D98).

    scripts/seed-packs.py fetch <folder> [--required]   each pack from the gallery, checked, and the app's list
    scripts/seed-packs.py verify <folder>               what an app holds: every pack on the list, intact and signed

Resources/SeedPacks/seed-packs.json in the repository names the extensions; the signed catalog says which version of
each to take. A pack is checked as Sidefolk checks a download: size and digest against the catalog, signature against
the gallery's team (Info.plist's SidefolkAddonsTeam). `fetch` writes `<folder>/seed-packs.json` with each pack's id,
name, version, file, bytes, sha256 and on, which is all the app reads.

--required is for a release: anything missing or refused stops the build. Without it (debug builds, `make app`) a gallery
that can't be reached or doesn't list them yet leaves the app without seed packs, with a warning, and tries the packs it
fetched last (build/seed-packs). $SIDEFOLK_SEED_GALLERY reads the gallery from a folder or another address instead, such
as a sidefolk-addons build's dist/ signed with scripts/build.py there.
"""
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIST = ROOT / "Resources/SeedPacks/seed-packs.json"
CACHE = ROOT / "build/seed-packs"
CATALOG_ID = "dev.sidefolk.addons.catalog"
TIMEOUT = 60


class Refused(Exception):
    pass


def info():
    with open(ROOT / "Resources/Info.plist", "rb") as f:
        return plistlib.load(f)


def requirement(team, identifier):
    # The same words as Sidefolk's AddonSource.requirement.
    return ("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] and "
            f'certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[subject.OU] = "{team}" and '
            f'identifier "{identifier}"')


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def get(gallery, name, to):
    if re.match(r"https?://", gallery):
        with urllib.request.urlopen(f"{gallery}/{name}", timeout=TIMEOUT) as r, open(to, "wb") as f:
            shutil.copyfileobj(r, f)
    else:
        shutil.copyfile(Path(gallery) / name, to)


def unpacked_bundle(zip_path, work, team, identifier):
    """Unzips a pack in `work` and checks the one bundle inside; returns its folder."""
    out = Path(tempfile.mkdtemp(dir=work))
    subprocess.run(["ditto", "-x", "-k", str(zip_path), str(out)], check=True)
    names = [p for p in out.iterdir() if p.name != "__MACOSX"]
    if len(names) != 1 or names[0].suffix != ".sidefolkaddon":
        raise Refused(f"{zip_path.name} isn't a Sidefolk add-on")
    check = subprocess.run(["codesign", "--verify", "--deep", "--strict", f"-R={requirement(team, identifier)}", str(names[0])],
                           capture_output=True, text=True)
    if check.returncode != 0:
        raise Refused(f"{zip_path.name} isn't signed by the gallery's team {team}: {check.stderr.strip()}")
    return names[0]


def version_key(version):
    core, _, pre = version.partition("-")
    numbers = tuple(int(n) for n in core.split("."))
    # A release ranks above its own snapshots, as Sidefolk orders them.
    return numbers, (1, 0) if not pre else (0, int((re.findall(r"\d+", pre) or ["0"])[-1]))


def this_build():
    out = subprocess.run(["git", "rev-list", "--count", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    return int(out.stdout.strip()) if out.returncode == 0 and out.stdout.strip() else None


def runs_here(entry, build):
    """A version needing a newer Sidefolk than this build is left for the gallery to offer later (D83)."""
    m = re.fullmatch(r"\d+\.\d+\.\d+-snapshot\.(\d+)", entry.get("minimum_sidefolk", ""))
    return not m or build is None or build >= int(m.group(1))


def pick(entries, build):
    usable = sorted((e for e in entries if runs_here(e, build)), key=lambda e: version_key(e["version"]))
    if not usable:
        return None
    # A release of the app takes released packs when there are any; a snapshot of it, the newest.
    released = [e for e in usable if "-" not in e["version"]]
    production = os.environ.get("SIDEFOLK_RELEASE") and not os.environ.get("SIDEFOLK_RELEASE_LABEL")
    return (released if production and released else usable)[-1]


def catalog(gallery, team, work):
    zip_path = work / "catalog.zip"
    get(gallery, "catalog.zip", zip_path)
    bundle = unpacked_bundle(zip_path, work, team, CATALOG_ID)
    return json.loads((bundle / "Contents/Resources/catalog.json").read_text())


def fetch(folder):
    plist = info()
    team = plist["SidefolkAddonsTeam"]
    gallery = os.environ.get("SIDEFOLK_SEED_GALLERY") or plist["SidefolkAddons"]
    wanted = json.loads(LIST.read_text())["seeds"]
    build = this_build()
    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        addons = catalog(gallery, team, work)["addons"]
        stage = work / "stage"
        stage.mkdir()
        seeds = []
        for seed in wanted:
            entry = pick([a for a in addons if a["id"] == seed["id"] and a.get("kind") == "extension"], build)
            if not entry:
                raise Refused(f"the gallery has no version of {seed['id']} this build can run; publish it first")
            zip_path = stage / entry["file"]
            get(gallery, entry["file"], zip_path)
            if zip_path.stat().st_size != entry["bytes"] or sha256(zip_path) != entry["sha256"]:
                raise Refused(f"{entry['file']} isn't what the catalog describes")
            unpacked_bundle(zip_path, work, team, entry["id"])
            seeds.append({"id": entry["id"], "name": entry["name"], "version": entry["version"], "file": entry["file"],
                          "bytes": entry["bytes"], "sha256": entry["sha256"], "on": seed["on"]})
        (stage / "seed-packs.json").write_text(json.dumps({"seeds": seeds}, indent=2, ensure_ascii=False) + "\n")
        place(stage, folder)
        # What a later build can use offline; never when it was read from a folder someone is working in.
        if not os.environ.get("SIDEFOLK_SEED_GALLERY"):
            place(stage, CACHE)
    print(f"Seed packs: {', '.join(s['name'] + ' ' + s['version'] for s in seeds)}")


def place(stage, folder):
    shutil.rmtree(folder, ignore_errors=True)
    Path(folder).parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(stage, folder)


def verify(folder):
    team = info()["SidefolkAddonsTeam"]
    wanted = [s["id"] for s in json.loads(LIST.read_text())["seeds"]]
    seeds = json.loads((Path(folder) / "seed-packs.json").read_text())["seeds"]
    if sorted(s["id"] for s in seeds) != sorted(wanted):
        raise Refused(f"the app carries {[s['id'] for s in seeds]}, the list says {wanted}")
    with tempfile.TemporaryDirectory() as temp:
        for seed in seeds:
            zip_path = Path(folder) / seed["file"]
            if not zip_path.is_file() or zip_path.stat().st_size != seed["bytes"] or sha256(zip_path) != seed["sha256"]:
                raise Refused(f"{seed['file']} isn't what the app's list describes")
            unpacked_bundle(zip_path, Path(temp), team, seed["id"])
    print(f"Seed packs verified: {len(seeds)}")


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("fetch", "verify"):
        sys.exit(__doc__)
    folder = Path(sys.argv[2])
    if sys.argv[1] == "verify":
        try:
            verify(folder)
        except (Refused, OSError, ValueError, KeyError) as e:
            sys.exit(f"seed-packs: {e}")
        return
    required = "--required" in sys.argv[3:]
    try:
        fetch(folder)
    except (Refused, OSError, ValueError, KeyError, subprocess.CalledProcessError) as e:
        if required:
            sys.exit(f"seed-packs: {e}")
        if (CACHE / "seed-packs.json").exists() and not os.environ.get("SIDEFOLK_SEED_GALLERY"):
            place(CACHE, folder)
            print(f"seed-packs: warning: {e}; using the packs fetched last", file=sys.stderr)
        else:
            print(f"seed-packs: warning: {e}; this build has no seed packs, so a fresh Mac starts with no extensions", file=sys.stderr)


if __name__ == "__main__":
    main()
