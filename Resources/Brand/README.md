# Sidefolk production assets

These are individual transparent assets, not crops for the app to discover in a presentation sheet.
`preview.png` is visual QA only. It is not bundled or used as a source.

## Files and native use

| Asset | Location | Usage |
|---|---|---|
| App icon | `../Icon/Sidefolk.icns` | Bundled as `Sidefolk.icns`; Info.plist already names it. |
| Raw square icon sources | `../Icon/icon-source-2048.png`, `../Icon/icon-1024.png` | Opaque, full-bleed flat white square, with character artwork; no rounded corners, bevel, shadow, rim or tile lighting. Use these for new platform exports. |
| Raw icon artwork | `../Icon/icon-artwork.png` | Native-resolution transparent character group, with no background tile; compose on any background. |
| Derived macOS icon | `../Icon/icon-macos-1024.png`, `../Icon/Sidefolk.iconset/` | Flat macOS outline/inset only. PNGs: 16/32/128/256/512 pt at 1x and 2x. No rendered edge effects. |
| Xcode asset catalog | `../Icon/Sidefolk.xcassets/` | Drop into an Xcode project. `AppIcon` contains macOS representations; `AppIconSource` and `IconArtwork` are reusable image sets. |
| Menu bar template | `../MenuBar/SidefolkMenuBar.pdf` | True vector alpha template; `NSImage.isTemplate = true`, size 18 × 18 pt. |
| Menu bar PNGs | `../MenuBar/SidefolkMenuBar{,@2x,@3x}.png` | 18/36/54 px; black ink, transparent shell and eye cutouts. |
| Logos | `exports/logo-{stacked,horizontal}-{color,navy,white}.png` | Tightly framed transparent lockups; preserve aspect ratio. |
| Family marks | `exports/mark-{color,navy,white}.png` | Standalone character group without tile or lettering. |
| Wordmarks | `exports/wordmark-{color,navy,white}.png` | Flat lettering, 4096 px color master; no bevel, glow or shadow. |
| Vector wordmark | `exports/wordmark-color.svg`, `exports/wordmark-color.pdf` | Actual fitted Bézier outlines, canonical flat brand colors, no font dependency or embedded raster. |

`scripts/build-app.sh` copies the production exports to `Contents/Resources/Brand/` and the templates
to `Contents/Resources/MenuBar/`. `BrandAsset` provides typed AppKit loading in the app, and SwiftUI
can display an image with `Image(nsImage: image).resizable().scaledToFit()`. Plain SwiftPM launches
can set `SIDEFOLK_RESOURCES` to the repository's absolute `Resources` directory.

Use the navy variants on light surfaces and the white variants on dark surfaces. The full-color
character's white shell is opaque. The menu bar uses alpha and macOS tinting, not the navy logo.
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
and ICNS. Text comes from the reference letter silhouettes, denoised and fitted to smooth cubic
Bézier curves; circular dots/counters are geometric ellipses. It is not an enlarged pixel crop or a
new font. The color master is 4096 px wide and the SVG/PDF paths scale independently of resolution.

`masters/` contains imagegen outputs used for the soft 3D artwork; `reference/folk-family.png` is the
user-supplied board. The primary logo retains the mint helper's laptop. The app icon and icon-only
mark follow the board's app-icon composition without a laptop. `generation-prompts.json` records
the built-in imagegen prompts; generated text was rejected. Source masters and reference are not
bundled. The rejected raised-tile app-icon master has been removed; all current app icons derive
from the clean transparent family mark. The animated desktop companion continues to use the native
vector rig (D2).
