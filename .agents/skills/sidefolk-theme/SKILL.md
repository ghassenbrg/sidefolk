---
name: sidefolk-theme
description: Make a finished, checked Sidefolk theme end to end, inside this repository and the sidefolk-addons gallery - understanding the ask (a concept in words, reference images, or "surprise me"), brainstorming three directions, mapping the concept to every colour role in light and dark with contrast and D78 colour meaning kept, type flavour, density, radii, materials and the companion's light, generating the page wash and nook art (Codex image gen), building it with `sidefolk theme new` and `sidefolk theme check`, reviewing UI snapshots with `--theme` in light, dark and Arabic, and delivering it as a local theme folder or a gallery theme. Use when asked to make, design or create a Sidefolk theme, a theme "like this picture" or these references, to brainstorm theme ideas, or to fix a theme the check rejects. Not for layouts (one layout per place, D84), companions (sidefolk-3d-character), or extensions (sidefolk-extension).
---

# Sidefolk theme

A theme **dresses** Sidefolk, it doesn't arrange it (D58, D64 narrowed by D84): colours by role in light and dark,
the display face, density, corner radii, motion, the sidebar's material, a paper grain, a picture washed in at the
top of every page, art behind the companion's card in Home's sidebar, empty-page art, and the colours of the
companion's light. Every place keeps its one layout. A theme is data: `theme.json` plus PNGs, nothing runs.

**The bar:** it is recognisably the concept on every screen, in light and dark; every text pair reads at 4.5:1;
danger is red, warning amber and success green (D78); the companion and its light stay the warm focal point; the
art is quiet enough that cards and words sit on it without a fight; it passes `sidefolk theme check` with no errors
and `templates/palette.py` with nothing listed, and its snapshots were read.

| Where | What |
|---|---|
| `Sources/SidefolkCore/Themes/` | `ThemeFile` (the format), `ThemeTokens` (roles, Harbor's values), `ThemeCheck` (the rules), `ThemeLibrary` (install, `theme new`) |
| `docs/DESIGN.md` | Lantern's tokens and roles; `--only design-system` draws them in any theme |
| `docs/DECISIONS.md` | D58 (themes are data), D64 → D84 (themes dress, one layout), D78 (colour meaning) |
| `Resources/Themes/` | the built-ins (D92): Paper Garden, Night Studio, Marshmallow (Harbor is in code); Paper Garden is the worked example of this skill (it began as Tea House) |
| `../sidefolk-addons/themes/` | the gallery's themes (`addon.json`, `theme.json`, `art/*.png`); empty since D92 |
| This skill's `templates/` | `roles.md` (every key, where it shows, its rule), `art-prompts.md`, `fit-art.py`, `palette.py` |

## 0. Plan

Say the plan in a line. Image generation uses the person's quota: two or three images (the light page wash, its dark
version, a gallery picture); the nook backdrop is cropped from the wash and the grain is drawn in code. A request to
make a theme is consent for those. If image generation is down, ship the theme without art (it is optional) and say so.

**Where to work:** `git status` and `git worktree list` first; with someone else's changes in a checkout, work in a
worktree of your own (`git worktree add -b team/<name> ../sf-<name> origin/main`, and the same in sidefolk-addons
for a gallery theme). Build once: `swift build` (gives `.build/debug/sidefolk` and `SidefolkApp`).

## 1. Understand the ask

- **A concept in words** ("a calm tea house"): pull out materials, light, time of day, mood and two or three
  colours.
- **Reference images:** read every one. Name what you take from each (a palette, a material, a light, a density),
  sample their colours (`python3 -c "from PIL import Image; im=Image.open('ref.png').convert('RGB').quantize(8); print(im.getpalette()[:24])"`),
  and say what you won't copy. Use them as mood, never as something to reproduce.
- **Nothing** ("surprise me"): pick a concept unlike the existing themes (below).
- **"Brainstorm":** propose **three short directions**, each: a name, the mood in one line, five swatches (page,
  card, sidebar, accent, glow) as hex, the type flavour (system, rounded or serif) and density, and the art idea.
  Recommend one and say why, then go on with it unless the person picks another.

Stay away from what exists (D92 keeps four, each its own atmosphere, and drops look-alikes): Harbor (neutral graphite
and paper, deep aqua: also the plain light and plain dark), Paper Garden (warm paper, hinoki wood, sage-matcha, serif,
bamboo shadows), Night Studio (indigo glass over a dusk landscape, periwinkle, mint), Marshmallow (candy colours over
cotton-candy clouds, rounded). A new theme earns its place only with an atmosphere none of them has; a sky on white
cards (the retired Daylight) or a darker Harbor (Night Shift) doesn't. Never copy a brand, a trademarked character or art, or a specific game's, film's or product's look; describe
qualities in plain words instead (no "Ghibli", no "like Notion").

## 2. Design

Start the folder (a local theme anywhere; a gallery one in `../sidefolk-addons/themes/<folder>/`):

```sh
.build/debug/sidefolk theme new "Tea House" <folder>    # theme.json = a copy of Harbor, and a README guide
```

Then fill `theme.json` (every key in `templates/roles.md`):

1. **Surfaces first, by area:** the page (`surfaceSunken`) is the concept's main colour; cards (`surfaceRaised`) the
   lightest in light, a step above the page in dark; the sidebar (`surface`) is the theme's furniture (a wood, a
   slate); `well` a step from cards (darker in light, lighter in dark); `line` barely there. Keep surfaces quiet and
   low in saturation: the companion and its light are the warm things on screen.
2. **Ink:** three steps from the page's own hue (a green-black for a green theme, not pure black). `inkFaint` is the
   tightest pair: check it on `surface` and `well`.
3. **The accent:** the concept's one colour for action. Deep enough for a white label at 4.5:1 in light; light with
   a dark label in dark. `link` is the accent as text, `accentSoft` a pale tint for selection. Never red or amber.
4. **Status (D78):** keep Harbor's danger, warning and success and only nudge lightness and a few degrees of hue
   toward the mood. Keep success's hue away from the accent's and the glow's when they are both green.
5. **The light:** `glow` (working) from the concept but not red or amber and not the same as success; `waitGlow`
   amber (it means "waits on you").
6. **Light and dark are one theme:** the same hues, the dark one lit by the same materials at night, not a different
   palette.
7. **Type, density, shape, motion:** `display` system (crisp), rounded (friendly) or serif (editorial; three themes
   already use it); `density` relaxed for calm concepts, compact for tools; radii small for crisp, large for soft;
   `motion` calm unless the concept is playful. `material.sidebar` solid unless the concept is glass.
8. `companion.suggests` only when the art was drawn for one companion.

Check as you go (§4) rather than at the end: contrast is easier to fix one role at a time.

## 3. Art

Read `templates/art-prompts.md`, then generate with the image tool you have: in Claude Code the `codex-imagegen`
skill (`<skill>/scripts/generate.sh --out <scratch>/page-raw.png "<brief>"`, `--ref` for the dark one); in Codex its
built-in image generation. Keep raw images in a scratch folder, never in the theme folder.

| File | Key | Size | Note |
|---|---|---|---|
| `art/page.png`, `art/page-dark.png` | `material.page`, `material.pageDark` | 1600 × 533 | interest in the top half, the bottom third plain page colour, a soft top edge |
| `art/nook.png`, `art/nook-dark.png` | `companion.backdrop`, `companion.backdropDark` | 640 × 228 | a calm crop of the wash; quiet on the leading side, where the portrait and name sit |
| `art/grain.png` | `material.grain` | 256 × 256 seamless | drawn in code (`art-prompts.md` › Grain); only for paper-like concepts |
| `art/empty.png` | `art.empty` | 240 × 240, transparent | optional; skip it unless the transparency is real |
| `art/tile.png` | (none: the gallery reads the file) | 640 × 400 | the gallery's picture of the theme; gallery themes only |

Rules: soft, low-contrast, no text, letters, logos, signatures or seals; no people; nothing bright in the dark
versions. Fit each with `templates/fit-art.py` (cover crop, `--fade-top`, `--tint`, `--colors 256`), then look at
each fitted file. Budget: about 1.5 MB for all the art (each ≤ 2 MB and ≤ 2048 px a side is the hard limit).

The page wash is drawn behind a page only, clipped to it (D84's fix: an unclipped wash spread over Settings' sidebar
and took its clicks). Never design the wash to cover the sidebar or the toolbar: it starts under the page's title
band, so a hard line along its top edge shows as a seam there (`--fade-top`).

## 4. Build and check

```sh
.build/debug/sidefolk theme check <folder>                  # until "can be used" with no errors and no warnings
python3 <skill>/templates/palette.py <folder>               # what the check doesn't hold: accent 3:1, the lights, wells
```

The check errors on: a missing or unreadable image, contrast under 4.5:1 for any text pair it lists (every text role,
success included, on every surface, the label on each fill, and each chip's words on its soft fill), a status colour
outside its hue (danger red 0–30/330–360°, warning amber 30–65°, success green 70–200°; their soft fills the same hue
or grey), a bad id or name. It warns
on: a missing colour (Harbor's is used), an unknown role, a value clamped. A new theme should have **no warnings**
either: give every role in both appearances. `palette.py` lists what Lantern still wants; fix all of it.

## 5. Review

Render the screens with the theme, light and dark, then Arabic (right to left). Language runs write into
`.build/debug`, so run them one at a time:

```sh
OUT=<scratch>/snapshots
SIDEFOLK_RESOURCES=$PWD/Resources .build/debug/SidefolkApp --ui-snapshots $OUT --theme <absolute folder> \
  --only window-home-today,desktop-sidecard,window-settings-attention,game-menu,window-settings-appearance,window-home-onduty
SIDEFOLK_RESOURCES=$PWD/Resources .build/debug/SidefolkApp --ui-snapshots $OUT-ar --language ar --theme <absolute folder> \
  --only window-home-today,window-settings-attention,desktop-sidecard-question,game-menu
SIDEFOLK_RESOURCES=$PWD/Resources .build/debug/SidefolkApp --ui-snapshots $OUT --theme <absolute folder> --only design-system   # every token and component
```

Read at least: `window-home-today-{light,dark}` (page wash, nook art, counts, cards, the sidebar), a few
`desktop-sidecard-*` (the Sidecard's glass and buttons on a wallpaper), `window-settings-attention-*` (Settings'
sidebar, the wash's top edge, selected cards), `window-home-onduty-empty-*` (an empty page: `art.empty` replaces its folk), and the Arabic Today. Crop and zoom where something looks off
(PIL `crop` then read the crop). Compare with the concept and references, write down what's wrong, change one
thing, render again. Two or three rounds is normal.

Look for: text on the wash or nook art that is hard to read; a seam where the wash starts; working, done and waiting
dots that look alike; the accent reading as disabled; a dark mode that is a different palette; art that draws the eye
from the companion.

**Live, optional:** `scripts/build-app.sh debug`, launch it with a fresh short `SIDEFOLK_HOME`, then
`SIDEFOLK_HOME=… swift scripts/dev.swift themeFolder:<folder>` and `snap`. The app follows the folder and repaints
on each save. It refuses ids under `dev.sidefolk.` from a folder, so for a gallery candidate follow a temporary copy
with a local id (`com.example.<name>`).

## 6. Deliver

**A local theme** (the person's own): id `com.<them>.<name>`, the folder anywhere. They install it in Settings ›
Appearance › Theme › **Load from folder…** (Sidefolk checks it, keeps its own copy in `<data>/Themes/<id>/` with the
images re-encoded, and follows the folder, repainting on each save) or start one there with **Start a theme…**.
Hand over the folder path and the check's output.

**A gallery theme** (Sidefolk's own, in `../sidefolk-addons/themes/<folder>/`):
- id `dev.sidefolk.theme.<folder>`, `author` "Sidefolk", `version` "1.0.0" in both files; delete the README.md that
  `theme new` wrote (`build.py` packs only `theme.json` and `art/<lowercase-dashes>.png`, and stops on anything else).
- `addon.json`: `id`, `kind: "theme"`, `name`, `tagline` (≤ about 45 characters), `description` (two or three
  sentences: materials, light, how it feels; light and dark), `author`, `version`, `license: "Proprietary"`,
  `minimum_sidefolk: "0.1.0"`. Themes have no `category` (that's extensions' shelf).
- `art/tile.png` is the gallery's picture.
- Prove it packs: `python3 scripts/build.py --unsigned` in sidefolk-addons; the theme appears as
  `dist/theme-<folder>-1.0.0-snapshot.<n>.zip` (build.py numbers snapshots; never edit the version while it's a
  snapshot). Then `rm -rf dist`: Sidefolk's `make test` reads an add-ons `dist/` as a signed gallery and fails on
  an ad-hoc one. Name it in the add-ons README's Themes row.
- **Publish only when the maintainer asks** (`scripts/build.py` signed, then `scripts/publish.sh`).

Commit (no Co-Authored-By), and in Sidefolk update docs/STATUS.md.

## 7. Pitfalls

- **Meaning is an error, not a warning:** a status colour off its hue stops the theme from loading (`ThemeCheck.meaningProblems`).
  Older gallery themes painted success with the accent (Paper Garden); don't.
- **Bright greens fail as text:** success is drawn as words ("Connected", a chip), so a minty light-mode green
  fails 4.5:1 on paper. Every theme Sidefolk had darkened its own when the check began to hold it.
- **A soft fill off its hue** (a purple `dangerSoft` in a violet theme) is an error: tint it red, amber or green, or
  keep it grey.
- **A copy already installed** is read leniently (these newer rules only warn there), so an old theme in someone's
  Sidefolk can look fine while the same folder fails `sidefolk theme check`: trust the command.
- **Retired keys:** `layout` presets, navigation, Today blocks and `companion.nook` styles are not drawn since D84;
  only `layout.icons` is read. Don't design for them.
- **The page wash** is 420 pt tall, scaled to fill the page width, faded downwards and at 55% opacity; anything in its
  lower half is lost, anything at its very top meets the title band. Wide pages (1600 pt windows) crop its sides less
  than you think: keep the interest off the centre.
- **Night pictures come out blue:** image models paint night blue-grey; tint them to the theme's darks.
- **The nook art** sits behind the companion's name and line at 35%: busy art makes them hard to read; crop a calm part.
- **A generated "transparent" PNG** is often a painted checkerboard; check the corners.
- **A relative `--theme` path** can render Harbor without a word: pass the folder's absolute path.
- **Parallel snapshot runs in two languages** collide in `.build/debug/*.lproj` ("Directory not empty"): one at a time.
- **`dev.sidefolk.` ids** can't be loaded from a folder; snapshots with `--theme` take any id.
- **Raw images inside the theme folder** get packed: keep them in scratch.
