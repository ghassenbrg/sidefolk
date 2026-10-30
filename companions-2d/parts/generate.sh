#!/bin/zsh
# Paints each companion's cut-out parts sheet with Codex image gen (codex-imagegen skill), three at a time:
#   companions-2d/parts/generate.sh [name ...]      (all of prompts.tsv when no name is given)
# The brief is the same for every companion but its parts list (prompts.tsv); the references are its target
# (targets/<name>.webp) and the whole style target. Sheets are kept as lossless WebP (<name>-sheet.webp).
cd "${0:A:h}/../.."
GEN=${CODEX_IMAGEGEN:-$HOME/.claude/skills/codex-imagegen/scripts/generate.sh}
brief() {
  print -r -- "Cut-out animation parts sheet (like a Spine or Live2D rig sheet) for $2 in the middle of the first reference image. The second reference shows its whole family; match their exact 2D cartoon style: flat colour fills, clean smooth dark outlines of even weight, one soft cel shadow tone, small glossy highlights, no gradients, no textures, no 3D rendering. Draw its parts SEPARATED from each other, laid out in a loose grid with generous empty space between them, never touching or overlapping, each part complete (including the areas that are normally hidden where parts overlap) and each with its own closed outline: $3. Same proportions and colours as the reference, front view, flat 2D. Background: one solid flat pure magenta (#FF00FF) colour everywhere, no floor shadow, no text, no labels, no numbers, no watermark."
}
names=(${@:-$(cut -f1 companions-2d/parts/prompts.tsv)})
for name in $names; do
  IFS=$'\t' read -r _ who parts < <(grep "^$name	" companions-2d/parts/prompts.tsv)
  "$GEN" --overwrite --out "companions-2d/parts/$name-sheet.png" --ref "companions-2d/targets/$name.webp" \
    --ref companions-2d/references/lineup-2d.webp "$(brief $name $who $parts)" > "build/gen-$name.log" 2>&1 &
  while (( ${#jobstates} >= 3 )); do sleep 2; done
done
wait
for name in $names; do
  png=companions-2d/parts/$name-sheet.png
  [[ -f $png ]] && python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2], lossless=True, method=6)" \
    $png ${png:r}.webp && rm $png
done
