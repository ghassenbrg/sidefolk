# Sidefolk asset sets

All images listed here live inside this repository. Preserve source PNGs, supplied references,
prompts and earlier versions alongside the production exports. The app consumes exports and pose
sets; reference sheets and archived generations stay in the repository.

| Set | Folder | Contents |
|---|---|---|
| Folk Family character concepts | [folk-family](../folk-family/README.md) | 13 named character folders, each with its clean PNG, untouched `source.png` and `character.json`; three labeled comparison sheets, reference images and exact prompts. |
| Current Mochi brand | [Brand](Brand/README.md) | `masters/` holds the original family/portrait generations, refined portrait, clean artwork, vector wordmark and prompts. `exports/` holds individual logo and mascot variants. |
| Supplied brand references | [Brand/reference](Brand/reference/) | Original robot and rabbit guides, the rabbit app-icon and monochrome close-ups, and `quality-feedback/` for the rejected text/edge examples. |
| Original robot brand history | [Brand/archive/robot](Brand/archive/robot/) | Earlier clean brand masters plus `early-generations/` with the original glow/text and raised-icon attempts. |
| App icons | [Icon](Icon/) | Raw square sources, transparent portrait, macOS PNG sizes, `.iconset`, `.icns` and Xcode asset catalog. |
| Menu bar icons | [MenuBar](MenuBar/) | Shared rabbit design in vector PDF/SVG and 1x/2x/3x PNGs. |
| AI service logos (third party) | [Brand/third-party](Brand/third-party/README.md) | Simple Icons SVGs as downloaded, their vector PDF exports, source, version, licence and trademark notes. Not Sidefolk's brand. |
| Animated companion poses | [Companions](Companions/README.md) | Named Mochi/Spark pose folders; `masters/mochi-legacy/` preserves all 16 original Mochi poses before palette grading. |
| Character review sheets | [Character](Character/) | Mochi poses, character states, icon sizes and menu-bar review images. |

[Generated-image inventory](Brand/generated-image-index.json) records all 22 imagegen originals
from this chat, their repository locations and SHA-256 hashes. It includes superseded attempts,
so these do not depend on the image cache or temporary attachment paths.

Current art is described in [Brand/README.md](Brand/README.md). Earlier sources are design history;
keep them when updating assets and add a versioned source for each new generation.
