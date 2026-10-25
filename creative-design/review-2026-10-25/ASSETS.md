# Asset inventory

All final assets are inside this package. No production screen depends on a file under the image-generation output directory. [manifest.json](assets/manifest.json) records dimensions, hashes and source paths for the copied assets and design renders.

## Production identity retained

| Asset | Package file | Source / use |
|---|---|---|
| Pip Signal color vector | `assets/pip-signal.svg` | Exact copy of `art/brand/pip-signal.svg`; editable SVG master, company mark |
| Pip Signal monochrome | `assets/pip-signal-mono.svg` | Exact copy of `art/brand/pip-signal-mono.svg`; template/icon source |
| Existing app icon | `assets/app-icon.png` | Exact copy of `src-tauri/icons/128x128@2x.png`; no icon redesign proposed |
| Pip frames | `assets/pip-{idle,wave,alert,note,sleep,write1,done,sad}.webp` | Exact copies from `public/crew/pip/3d/`; speaking/pose references |
| Spark frames | `assets/spark-{idle,wave,alert,note,sleep,write1,done,sad}.webp` | Exact copies from `public/crew/spark/3d/`; same interaction vocabulary |
| Icon paths | `assets/icons.js` | Extracted from current `src/icons.ts`; one source grammar |
| Token snapshot | `assets/production-tokens.css` | Exact copy of current `src/tokens.css`; review reproduction only |

The inline logo in `design.js` preserves the current source geometry and theme behavior. The new More glyph is a minimal three-dot line icon, defined once in the prototype; add that glyph once to the app icon source on implementation. The menu-bar graphic remains the current monochrome template. Status icons retain `src/states.ts` semantics.

Character images are transparent WebP, not new generated substitutes. The images include transparent margins, so specify the visible silhouette when matching optical size. Do not stretch them. Full production animation uses the existing pose library and timing rather than the eight sample frames copied for this review. New poses are not required by this proposal.

## New presentation art

`assets/desk-cover.png` is a 1536 × 1024 opaque PNG, made with the built-in ImageGen tool. It is the cream-paper/mint-tray still life on board 01 only. It supplies atmosphere to the design handoff; it is not app wallpaper, a new mascot, an onboarding dependency or a change to the art pipeline.

The exact prompt, tool and saved source are in [prompts.json](assets/prompts.json). The original output remains in the tool’s generated-image directory; the project copy is the file to hand to a developer. No CLI/API-key fallback was used. No other assets were regenerated.

## Editable UI masters and exports

- `index.html`: semantic page shell.
- `design.css`: all proposed layout, responsive and component styles.
- `design.js`: screen fixtures and disconnected local interactions.
- `screens.json`: ordered image export and scenario index.
- `render.mjs`: repeatable WebKit export and focused prototype checks using the repository’s existing Playwright dependency.
- `images/*.png`: 34 final design boards, 1440 × 1000 except compact at 720 × 1200.
- `images/native/*.png`: Today and Work log at 1100 × 760 and 640 × 480.

All UI labels are real editable text in the source; they are not baked into an AI-generated mockup. The images are references, and the source/specification governs behavior. No external fonts are required: use the platform UI, rounded brand and mono stacks already in the project.

The surrounding board labels, previous/next links, mock traffic lights and proposal footer are presentation chrome. They are excluded by `&native=1` and must not be implemented as app features.

## Rights and provenance

The existing name, Pip/Spark art and logo remain subject to the repository’s existing reserved-brand/art terms. This package does not change their license. The application code’s MIT terms do not automatically apply to those assets. Generated cover art is identified separately for provenance; no stock-photo license or third-party character asset was introduced.
