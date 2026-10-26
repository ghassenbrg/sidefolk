# Sidefolk production assets — Mochi rabbit identity

These are individual transparent assets, not crops for the app to discover in a presentation sheet.
`preview.png` is visual QA only. It is not bundled or used as a source.
The current references are `reference/mochi-brand-guide.png` and the app-icon/monochrome detail crops beside it. Mochi is the brand mascot; the original
Sidefolk robot remains a selectable, customizable companion in the app. Its earlier branding
masters are retained in `archive/robot/`.

See [the asset-set index](../ASSETS.md) for every character, source, reference and archive folder.
[generated-image-index.json](generated-image-index.json) inventories all 22 generated originals,
including the superseded robot studies, with repository paths and SHA-256 hashes.

## Files and native use

| Asset | Location | Usage |
|---|---|---|
| App icon | `../Icon/Sidefolk.icns` | Bundled as `Sidefolk.icns`; Info.plist already names it. |
| Raw square icon sources | `../Icon/icon-source-2048.png`, `../Icon/icon-1024.png` | Opaque, full-bleed blue-gradient square with the rabbit portrait; no rounded corners, bevel, shadow, rim or tile lighting. |
| Raw icon artwork | `../Icon/icon-artwork.png` | Transparent rabbit portrait with ears and scarf, no background tile. |
| Derived macOS icon | `../Icon/icon-macos-1024.png`, `../Icon/Sidefolk.iconset/` | Flat macOS outline/inset only. PNGs: 16/32/128/256/512 pt at 1x and 2x. No rendered edge effects. |
| Xcode asset catalog | `../Icon/Sidefolk.xcassets/` | Drop into an Xcode project. `AppIcon` contains macOS representations; `AppIconSource` and `IconArtwork` are reusable image sets. |
| Menu bar template | `../MenuBar/SidefolkMenuBar.pdf` | True vector alpha template; `NSImage.isTemplate = true`, size 18 × 18 pt. |
| Portable menu vector | `../MenuBar/SidefolkMenuBar.svg` | The same rabbit geometry in a square 18 pt SVG. |
| Menu bar PNGs | `../MenuBar/SidefolkMenuBar{,@2x,@3x}.png` | 18/36/54 px; native rabbit-ear, face and scarf template, automatically tinted by macOS. |
| Logos | `exports/logo-{stacked,horizontal}-{color,navy,white}.png` | Tightly framed transparent lockups; preserve aspect ratio. |
| Icon marks | `exports/mark-{color,navy,white}.png` | Standalone rabbit portrait/monochrome mark without tile or lettering. |
| Mascot vectors | `exports/mascot-{navy,white}.{svg,pdf,png}` | Hand-drawn rabbit mark, sharing geometry with the menu template. |
| Full-body mascot | `exports/mascot-color.png` | Mochi character study, transparent and unframed. |
| Wordmarks | `exports/wordmark-{color,navy,white}.png` | Flat lettering, 4096 px color master; no bevel, glow or shadow. |
| Vector wordmarks | `exports/wordmark-{color,navy,white}.{svg,pdf}` | Hand-authored Bézier outlines, canonical flat colors, no fonts, clipping masks, filters or embedded raster. |

`scripts/build-app.sh` copies the production exports to `Contents/Resources/Brand/` and the templates
to `Contents/Resources/MenuBar/`. `BrandAsset` provides typed AppKit loading in the app, and SwiftUI
can display an image with `Image(nsImage: image).resizable().scaledToFit()`. Plain SwiftPM launches
can set `SIDEFOLK_RESOURCES` to the repository's absolute `Resources` directory.

Use the navy variants on light surfaces and the white variants on dark surfaces. The full-color
character's white body is opaque. The menu bar uses alpha and macOS tinting, not the navy logo.
macOS owns the menu item's padding; do not add a background tile to the menu bar template.
The reusable square app-icon sources have opaque square corners. Only the separate legacy macOS
ICNS/iconset uses an inset rounded mask. This mask is flat geometry, without simulated thickness,
edge lighting, cast shadow or presentation framing. The source is never a screenshot of that export.

## Rebuild

From the repository root:

```sh
make brand-assets
scripts/build-app.sh debug
```

The generator crops, isolates alpha, normalizes colors, lays out each lockup and exports the iconset
and ICNS. `masters/wordmark.svg` is the editable, hand-authored source for the text, following the
reference's rounded letterforms. The earlier contour trace was rejected. The current source uses
11 simple named paths, straight stems, smooth curves, geometric counters and separately drawn rays;
it has no font dependency. The generator consumes its absolute M/L/C/Z commands directly for PNG
and PDF, so the logo variants share the exact same geometry. PNG wordmarks are 4096 px wide.

`masters/rabbit-family.png` supplies the full-color logo composition; `rabbit-portrait.png` supplies
the icon portrait. Their original imagegen outputs and exact prompts are retained alongside them. The current portrait comes from `rabbit-portrait-source-v2.png`, following `rabbit-icon-refinement-prompt.json`; it matches the detail crop’s tilted face and asymmetric ears.
`scripts/clean-image-alpha.swift` prepares their transparent mattes. The monochrome mascot comes
from `RabbitBrandMark` in the native character target, using the monochrome close-up’s ear angles, side paw, two rays, and separated scarf tail. It is authored geometry, not a raster trace. The existing hand-authored
wordmark remains unchanged. Source masters and references are not bundled.

On the desktop, Mochi is a live vector rig drawn after `masters/mascot-mochi.png` (D30); the
original robot's rig and Spark remain available. Saved explicit companion choices are preserved.
