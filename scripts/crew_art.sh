#!/usr/bin/env bash
# Generates a crew character's pose sheets with Codex image generation (the codex-imagegen skill),
# from the user's reference photo in art/crew/refs/<id>.jpg (24 October 2026).
#
#   scripts/crew_art.sh <id> <3d|2d> <a|b>
#
# 3d sheet a: the photo plus Pip's 3d sheet a for the layout and poses. 3d sheet b: the character's
# own 3d sheet a. 2d sheets: the character's 3d sheet of the same letter, redrawn flat, so both
# styles have the same design and poses. Then `npm run sprites -- <id> <style>` cuts the frames.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="${CODEX_IMAGEGEN:-$HOME/.claude/skills/codex-imagegen/scripts/generate.sh}"
id="$1" style="$2" sheet="$3"
dir="$ROOT/art/crew/$id/$style"

case "$id" in
  spark) who="a small friendly robot: a big rounded ivory helmet head with a black glossy face screen and two glowing mint oval eyes, mint-rimmed ear pods, a thin black antenna with a mint ball, a small ivory body with a mint chest badge, charcoal mitten hands and charcoal feet" ;;
  pip) who="a small cream-white bunny with tall ears whose tips are charcoal, tiny black dot eyes, a tiny dot nose and a mint green knitted scarf" ;;
  pebble) who="a round charcoal penguin with a big cream belly, small black eyes, a yellow-orange beak, a small mint shield badge on the chest, short flippers and charcoal feet" ;;
  capy) who="a chubby tan capybara with small brown ears, a darker brown muzzle with a Y-shaped nose line, small black eyes, a mint hoodie with drawstrings and a front pocket, brown paws and feet" ;;
  nova) who="a small charcoal alien with a large rounded head, two big glowing mint eyes, a small smile, a curved antenna with a mint ball, a small body with a glowing mint triangle on the chest, short arms and stubby legs" ;;
  lumi) who="a floating cream-white cloud spirit with little round hands, two small black dot eyes and a mint halo ring above it with a small mint dot; it floats and has no legs, so its lowest point stands in for feet" ;;
  pixel) who="a charcoal and cream tuxedo cat with pointed ears with beige insides, square black glasses, black whiskers, a mint collar with a small square mint tag, a cream belly and paws, and a charcoal tail with a cream tip" ;;
  otis) who="a soft brown otter with a cream face and belly, black eyes, a dark brown nose, whiskers, a happy open mouth and a thick tail, who carries a small mint phone" ;;
  rune) who="a round charcoal owl with ear tufts, a cream heart-shaped face with black eyes and a small yellow beak, a mint monocle ring over one eye, a cream belly with small feather marks, charcoal wings and yellow feet" ;;
  sprout) who="a little cream ceramic-pot creature with two black dot eyes, small round arms, stubby legs and a two-leaf mint sprout growing from the open top of its head" ;;
  *) echo "unknown character $id" >&2; exit 1 ;;
esac

grid="Eight full-body poses in a 4 by 2 grid, landscape 3:2, every pose at the same scale with the feet on one baseline, clear empty space between poses, no pose overlapping another."
poses_a="Top row left to right: 1 idle, standing calmly facing the viewer; 2 the same idle pose with eyes closed as short curved lines (blink); 3 listening, head tilted to one side; 4 thinking, one hand at the chin, eyes looking up. Bottom row left to right: 5 typing on a small mint laptop held in front, looking at it; 6 the same typing pose with the other hand raised mid-tap; 7 needs attention, holding up a small cream card with a single bold orange exclamation mark; 8 sad, head down, drooping."
poses_b="Top row left to right: 1 holding a small cream note card in both hands and looking at it happily; 2 writing on a small notepad with a yellow pencil; 3 the same writing pose with the pencil moved a little; 4 done, both arms raised in joy, eyes as happy upward arcs. Bottom row left to right: 5 waving hello with one hand raised high; 6 sitting on the ground, awake and calm; 7 asleep sitting, head drooped, eyes closed; 8 being held up from above: arms raised straight up, legs dangling, eyes wide."
backdrop="Solid pure chroma green #00FF00 background everywhere, no floor, no ground shadow, no reflections, no other text, no watermark."
look3d="Keep its design, proportions, colors and its soft matte velvet clay 3D render style exactly as in the character photo (soft studio light, gentle shading)."
look2d="Redraw it as a flat 2D vector illustration: the same design, proportions, colors and poses as the reference sheet, crisp clean charcoal #272A33 outlines, flat fills with at most one soft flat shade, no gradients, no texture, no 3D shading."

[ "$sheet" = a ] && poses="$poses_a" || poses="$poses_b"
case "$style-$sheet" in
  3d-a)
    refs=(--ref "$ROOT/art/crew/refs/$id.jpg" --ref "$ROOT/art/crew/pip/3d/sheet-a.webp")
    brief="Character pose sheet for a desktop companion app. The first reference photo is the character to keep exactly: $who. $look3d The second reference only shows the layout and the poses; ignore its bunny. $grid $poses $backdrop" ;;
  3d-b)
    refs=(--ref "$dir/sheet-a.webp" --ref "$ROOT/art/crew/refs/$id.jpg")
    brief="Second pose sheet for the same character as the first reference sheet ($who): keep its design, size, colors and the soft matte velvet clay 3D render style exactly the same as in that sheet; the second reference is the original photo. $grid $poses $backdrop" ;;
  2d-a)
    refs=(--ref "$ROOT/art/crew/$id/3d/sheet-a.webp")
    brief="Pose sheet for a desktop companion app. The reference is a sheet of the character ($who) in eight poses. $look2d Keep the same eight poses in the same 4 by 2 grid order and the same scale. $grid $poses $backdrop" ;;
  2d-b)
    refs=(--ref "$ROOT/art/crew/$id/3d/sheet-b.webp" --ref "$dir/sheet-a.webp")
    brief="Pose sheet for a desktop companion app. The first reference is a sheet of the character ($who) in eight poses; the second is the same character already drawn flat, whose drawing style, design details and size must be matched exactly. $look2d Keep the eight poses of the first reference in the same 4 by 2 grid order. $grid $poses $backdrop" ;;
  *) echo "style is 3d or 2d, sheet a or b" >&2; exit 1 ;;
esac

"$GEN" --out "$dir/sheet-$sheet.png" "${refs[@]}" "$brief"
# Kept as WebP at quality 95: a twelfth of the PNG, no visible loss for cutting frames.
python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2], 'WEBP', quality=95, method=6)" "$dir/sheet-$sheet.png" "$dir/sheet-$sheet.webp"
rm "$dir/sheet-$sheet.png"
