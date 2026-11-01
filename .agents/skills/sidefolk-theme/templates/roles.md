# Every key of a theme.json, and where it shows

`sidefolk theme new` writes a complete theme.json (a copy of Harbor). Change values; don't add keys: an unknown colour
role is ignored with a warning, an unknown top-level key is ignored silently. Source of truth:
`Sources/SidefolkCore/Themes/ThemeFile.swift`, `ThemeTokens.swift` (Harbor's values) and `ThemeCheck.swift`.

## Identity

| Key | Rule |
|---|---|
| `format` | `1` |
| `id` | lowercase letters, digits, dots, dashes, ≤ 80. A local theme: `com.<you>.<name>`. Only Sidefolk's gallery may use `dev.sidefolk.theme.<folder>` (the app refuses it from a folder: "one of Sidefolk's own") |
| `name` | 1–40 characters, the theme's name in every language (never translated) |
| `author`, `version`, `summary` | `version` is `1.0.0` for a new theme; the gallery numbers snapshots itself |

## Colours (`colors.light` and `colors.dark`, every role in both, `#RRGGBB`)

| Role | Where it shows | Rule |
|---|---|---|
| `ink` | titles, body text, numbers | ≥ 4.5:1 on every surface and on `accentSoft`, `warningSoft` |
| `inkMuted` | second lines, details, chip text | ≥ 4.5:1 on every surface |
| `inkFaint` | meta: times, counts, placeholders, the sidebar's section names | ≥ 4.5:1 on every surface (the tightest pair, usually on `surface` or `well`) |
| `surface` | Home's and Settings' **sidebar** (when `material.sidebar` is solid), Sidecard glass tint | the theme's "furniture": a wood, a paper, a slate |
| `surfaceSunken` | the **page**: the window's canvas under the cards, what the page wash fades into | the theme's main colour by area |
| `surfaceRaised` | **cards**: Today's cards, tiles, settings groups, the Sidecard | the lightest in light, a step up from the page in dark |
| `line` | hairlines: card edges, separators | barely there; Increase Contrast replaces it |
| `well` | fields, the search, chips, a segmented control's track (inside cards) | darker than cards in light, lighter in dark. Optional (falls back to `surfaceSunken`) |
| `accent` | the one action colour: primary buttons, selection, the focus ring, the sidebar's selected place | ≥ 3:1 on cards and page; never red (error) or amber (waiting) |
| `onAccent` | the label on a primary button | ≥ 4.5:1 on `accent` (a dark label on a light accent is fine in dark) |
| `accentSoft` | selection backgrounds, the calm strip on a slip ("Part of what you asked…") | a pale tint of the accent |
| `link` | the accent as text ("Open Calendar", "Answer") | ≥ 4.5:1 on every surface; usually a touch darker (light) or lighter (dark) than `accent` |
| `danger`, `dangerSoft`, `onDanger` | errors, failures, destructive actions, real risk ("Having trouble") | **red** (hue 0–30 or 330–360), check error otherwise |
| `success`, `successSoft` | done, allowed, won (a "Connected" label, ticks, "done today") | **green** (hue 70–200); also drawn as text, so ≥ 4.5:1 (not in the check: `palette.py`) |
| `warning`, `warningSoft`, `onWarning` | waiting on the person, late, "Another app is asking" strips, the waiting count | **amber** (hue 30–65), never an error |
| `glow` | the light pool under the companion while it works or listens; Today's "on duty" dot | light, never text; not red or amber; not the same as `success`. Optional (Harbor's aqua) |
| `waitGlow` | the light when something waits, the count on the companion's shoulder | light, never text; amber. Optional (Harbor's amber) |

Status hues are D78's and `sidefolk theme check` errors when they drift. Keep them close to Harbor's (danger
#B42318 / #FF8A80, warning #8A4B00 / #FFC266, success #13703F / #5FD69A) and tune only lightness and a little hue
toward the theme's mood: a moss-tinted green, a rust-leaning red.

## Type, shape, motion

| Key | Values | Notes |
|---|---|---|
| `type.display` | `system`, `rounded`, `serif` | only titles, the greeting, state words and big numbers; everything read is the system face |
| `type.text`, `type.exact` | always `system`, `mono` | other values are warnings |
| `type.scale` | 0.9–1.15 | 1.0 unless the concept is really airy (1.05) or dense (0.95) |
| `type.density` | `compact`, `regular`, `relaxed` | spacing × 0.85 / 1 / 1.15; the person can override it in Settings › Appearance |
| `shape.control` | 4–999 | buttons and fields (999 = capsules) |
| `shape.card` | 0–28 | cards and tiles |
| `shape.window` | 0–28 | the Sidecard, sheets, popovers |
| `motion` | `calm`, `bouncy`, `none` | Reduce Motion always wins |

## Materials, art, the companion

| Key | What | Size |
|---|---|---|
| `material.sidebar` | `solid` (the `surface` colour) or `translucent` (the Mac's own material) | |
| `material.grain` | a PNG tiled over Home's pages at 6% opacity, multiplied: paper or fibre texture | 256 × 256, seamless, light grey around 210/255; draw it in code |
| `material.page` | a PNG washed in at the top of every Home and Settings page: drawn 420 pt tall, scaled to fill the page's width, faded to nothing downwards, at 55% opacity, clipped to the page | 1600 × 533 (3:1); interest in the top half, the bottom third plain page colour, a soft top edge |
| `material.pageDark` | the same in dark; without it a dark page has no wash | same |
| `companion.backdrop` | a PNG behind the companion's card in Home's sidebar, at 35% opacity, filling the card | 640 × 228 (about 2.8:1); calm on the leading side, where the portrait and name sit |
| `companion.backdropDark` | the same in dark; without it the light one is used | same |
| `companion.suggests` | a companion the theme was drawn for (`mochi`, `spark`, `ember`…): offered in Settings, never chosen for the person | |
| `companion.nook` | written by `theme new`; not drawn since D84 (one layout): leave `cushion` | |
| `art.empty` | a PNG for empty pages, in place of a folk, at most 120 pt | 240 × 240, transparent background |
| `art.tile` | not drawn since D84. The gallery takes `art/tile.png` (by its file name, not this key) as the theme's picture | 640 × 400 |
| `layout` | only `icons`: `simple` or `colorful` (Home's sidebar icons). `preset` still picks icons for old themes; other keys are retired | |

Every image: a `.png` inside the folder, ≤ 2 MB and ≤ 2048 px a side. The app decodes and re-encodes each on install,
so only pixels survive. Budget for a gallery pack: about 1.5 MB in all (the three gallery themes are 0.5–1.8 MB).
