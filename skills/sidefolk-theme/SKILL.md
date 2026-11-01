---
name: sidefolk-theme
description: Design and build a theme for Sidefolk, the macOS desktop companion - from a concept in words, reference images, or "surprise me" (three directions to choose from), to every colour role in light and dark with readable contrast and colour meaning kept, type flavour, density, corners, materials and the companion's light, soft art for the page and the companion's nook, and a theme folder that passes `sidefolk theme check` and loads in Settings › Appearance. Use when asked to make, design or create a Sidefolk theme, a theme like a picture or some references, to brainstorm theme ideas, or to fix a theme the check rejects.
---

# Making a Sidefolk theme

A Sidefolk theme **dresses** the app, it doesn't arrange it: colours by role in light and dark, the display face,
density, corner radii, motion, the sidebar's material, a paper grain, a picture washed in at the top of every page,
art behind the companion's card in Home's sidebar, empty-page art, and the colours of the companion's light. Every
place keeps its one layout. A theme is a folder with `theme.json` and a few PNGs; nothing in it runs.

**Done means:** it reads as the concept on every screen, in light and dark; every text pair reads at 4.5:1; red
means an error, amber waiting and green done; the companion and its light stay the warm thing on screen; the art is
quiet enough that cards and words sit on it; `sidefolk theme check` says it can be used with no errors or warnings,
and `templates/palette.py` lists nothing.

The `sidefolk` helper is in `Sidefolk.app/Contents/Helpers/` and, once installed from Settings › Connections, in
`~/.local/bin`. This skill's `templates/` has `roles.md` (every key, where it shows, its rule; read it before §2),
`art-prompts.md`, `fit-art.py` and `palette.py` (Python 3; the art tools need Pillow).

## Install this skill

- **Claude Code:** `mkdir -p ~/.claude/skills && cp -R skills/sidefolk-theme ~/.claude/skills/` (or a project's
  `.claude/skills/`). Ask "make a Sidefolk theme around …" or type `/sidefolk-theme`.
- **Codex:** `mkdir -p ~/.codex/skills && cp -R skills/sidefolk-theme ~/.codex/skills/` (or `$CODEX_HOME/skills`).

## 1. Understand the ask

- **A concept in words:** pull out materials, light, time of day, mood and two or three colours.
- **Reference images:** look at each; say what you take from it (a palette, a material, a light) and what you won't
  copy. They are mood, never something to reproduce.
- **Nothing:** pick a concept unlike Sidefolk's own themes: Harbor (neutral, deep aqua), Night Shift (dense, dark,
  teal), Marshmallow (candy pastels), Field Notes (planner paper, serif), and the gallery's Daylight (a sky),
  Night Studio (indigo dusk), Paper Garden (paper and sage), Tea House (washi, wood, matcha).
- **"Brainstorm":** three short directions, each with a name, its mood in a line, five swatches (page, card,
  sidebar, accent, glow), the type flavour and density, and an art idea. Recommend one and go on with it unless the
  person picks another.

Never copy a brand, trademarked characters or art, or a specific game's, film's or product's look; describe
qualities in plain words.

## 2. Design

```sh
sidefolk theme new "Sunset Pier" ~/Themes/sunset-pier      # theme.json (a copy of Harbor) and a short guide
```

Give it an id of your own (`com.you.sunset-pier`; `dev.sidefolk.` ids are Sidefolk's and are refused). Then:

1. **Surfaces by area:** the page (`surfaceSunken`) is the concept's main colour; cards (`surfaceRaised`) the
   lightest in light, a step above the page in dark; the sidebar (`surface`) the theme's furniture; `well` (fields,
   chips) a step from cards; `line` barely there. Low saturation: the companion is the warm thing on screen.
2. **Ink** in three steps, tinted by the page's hue. `inkFaint` is the tightest pair.
3. **One accent** for action, deep enough for its label at 4.5:1; `link` is it as text, `accentSoft` a pale tint.
   Never red (error) or amber (waiting).
4. **Status keeps its meaning:** danger red, warning amber, success green. Start from Harbor's (in the new
   theme.json) and only nudge lightness and a few degrees of hue.
5. **The light:** `glow` (working) from the concept, not red, amber or the same as success; `waitGlow` amber.
6. **Dark is the same theme at night**, not another palette.
7. **Type and shape:** `display` system, rounded or serif (titles and big numbers only); `density` relaxed for calm,
   compact for tools; small radii for crisp, large for soft; `motion` calm unless it's playful.

## 3. Art (optional, but it's most of a theme's character)

Generate with the image tool you have (in Codex its built-in image generation; in Claude Code an image-generation
skill if one is installed). Follow `templates/art-prompts.md`: one style sentence reused in every brief, the light
page wash first, then its dark version from it as a reference. Keep raw images outside the theme folder.

| File | Key | Size |
|---|---|---|
| `art/page.png`, `art/page-dark.png` | `material.page`, `material.pageDark` | 1600 × 533: interest in the top half, the bottom third plain page colour, a soft top edge |
| `art/nook.png`, `art/nook-dark.png` | `companion.backdrop`, `companion.backdropDark` | 640 × 228, a calm crop of the wash |
| `art/grain.png` | `material.grain` | 256 × 256 seamless, drawn in code |
| `art/empty.png` | `art.empty` | 240 × 240 with real transparency |

Soft, low contrast, no text, logos, signatures or people, nothing bright at night. Fit them with
`python3 templates/fit-art.py` (sizes, `--fade-top`, `--tint`, `--colors 256`) and look at each. Each image ≤ 2 MB
and ≤ 2048 px a side; about 1.5 MB for all of them is plenty. The wash is drawn behind each page only, 420 pt tall,
faded downwards at 55%: design it for the page, not the sidebar.

## 4. Check

```sh
sidefolk theme check ~/Themes/sunset-pier
python3 templates/palette.py ~/Themes/sunset-pier
```

Fix until the check says it can be used with no errors and no warnings (give every role in both appearances), and
`palette.py` lists nothing (success as text, the accent against cards, the lights, the wells).

## 5. Look at it

Settings › Appearance › Theme › **Load from folder…** uses the theme and follows the folder: every save repaints
Sidefolk, and what's wrong is listed there. Look at Today, the companion's card in the sidebar, Settings, a card on
the desktop (ask the companion something), an empty page, in light and dark (Appearance › Light or dark). If you
can't see the screen, ask the person to look and tell you what reads badly. With a checkout of Sidefolk's source,
`SIDEFOLK_RESOURCES=$PWD/Resources swift run SidefolkApp --ui-snapshots <out> --theme <folder> --only window-home-today,desktop-sidecard,window-settings-attention`
renders those screens to PNGs you can read (add `--language ar` for right to left).

## 6. Deliver

Hand over the folder and the check's output. The person installs it with **Load from folder…** (Sidefolk keeps its
own copy; Remove from the theme's right-click menu) or shares the folder. To offer a theme for Sidefolk's gallery,
send it to Sidefolk's developer.

## Pitfalls

- A status colour off its hue is an **error**: the theme won't load.
- `success` is drawn as text but isn't in the check's contrast table; `palette.py` checks it.
- `layout` (beyond `icons`) and `companion.nook` are from older themes and aren't drawn.
- Night pictures come out blue from image models: tint them toward the theme's darks.
- A hard line along the wash's top edge shows as a seam under the page's title: fade it.
- A generated "transparent" PNG is often a painted checkerboard: check the corners.
