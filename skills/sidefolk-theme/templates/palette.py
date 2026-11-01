#!/usr/bin/env python3
"""What `sidefolk theme check` doesn't hold a theme to (it holds every text pair, chips included, to 4.5:1 and the
status colours and their soft fills to their hues), but Lantern (D84) and colour meaning (D78) still want.
Run it after the check passes; nothing here stops a theme from loading, so fix what it lists by eye and judgement.

  palette.py <theme folder or theme.json>

- the accent is the one action colour: a filled button must stand out from a card and the page (3:1).
- the lights mean something too: waitGlow is "something waits" (amber), glow "working" (anything but red or amber),
  and glow must not read as success where they sit side by side (Today's counts).
- the accent must not look like a status: red reads as an error, amber as waiting.
- wells are a step from cards: darker in light, lighter in dark.
"""
import colorsys
import json
import sys
from pathlib import Path


def rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def lum(hex_):
    c = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb(hex_)]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(a, b):
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def hue_sat(hex_):
    h, l, s = colorsys.rgb_to_hls(*rgb(hex_))
    return h * 360, s


def in_hues(hex_, ranges):
    h, s = hue_sat(hex_)
    _, l, _ = colorsys.rgb_to_hls(*rgb(hex_))
    # A near-black, near-white or greyish colour has a hue on paper but none to the eye: an ink accent isn't amber.
    return s >= 0.3 and 0.2 < l < 0.85 and any(lo <= h <= hi for lo, hi in ranges)


RED, AMBER = [(0, 30), (330, 360)], [(30, 65)]


def main():
    path = Path(sys.argv[1])
    theme = json.loads((path / "theme.json" if path.is_dir() else path).read_text())
    notes = []
    for look, c in theme.get("colors", {}).items():
        def need(cond, message):
            if not cond:
                notes.append(f"{look}: {message}")

        def has(*roles):
            return all(r in c for r in roles)

        if has("accent", "surfaceRaised", "surfaceSunken"):
            for s in ("surfaceRaised", "surfaceSunken"):
                r = contrast(c["accent"], c[s])
                need(r >= 3, f"accent on {s} is {r:.2f}:1; a filled button wants 3:1 against what it sits on")
            need(not in_hues(c["accent"], RED), "accent looks red: it would read as an error (D78)")
            need(not in_hues(c["accent"], AMBER), "accent looks amber: it would read as waiting (D78)")
        if "waitGlow" in c:
            need(in_hues(c["waitGlow"], AMBER), "waitGlow should look amber: it says something waits on the person")
        if "glow" in c:
            need(not in_hues(c["glow"], RED + AMBER), "glow looks red or amber: it is the working light, not a status")
            if "success" in c:
                gh, gs = hue_sat(c["glow"])
                sh, _ = hue_sat(c["success"])
                d = min(abs(gh - sh), 360 - abs(gh - sh))
                need(gs < 0.1 or d >= 25 or abs(lum(c["glow"]) - lum(c["success"])) > 0.25,
                     f"glow and success are {d:.0f}° apart and as light: working and done look alike on Today's counts")
        if has("well", "surfaceRaised"):
            darker = lum(c["well"]) < lum(c["surfaceRaised"])
            need(darker if look == "light" else not darker,
                 "well should be " + ("darker" if look == "light" else "lighter") + " than surfaceRaised (fields inside cards)")
    print("\n".join(notes) if notes else "✓ Nothing more to look at: the accent, the lights and the wells read as Lantern wants.")


if __name__ == "__main__":
    main()
