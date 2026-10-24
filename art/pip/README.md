# Pip's frames

Pip on the desktop is 16 frames cut from two generated sprite sheets. The style reference is
[creative-design/v2/pip-body-b.png](../../creative-design/v2/pip-body-b.png), the look chosen with
the user on 24 October 2026 (docs/PLAN-V2.md, section 4).

| Sheet | Poses, left to right, top row then bottom |
|---|---|
| `sheet-a.png` | idle, blink, listen, think, work1, work2, alert (holding a "!" card), sad |
| `sheet-b.png` | note (holding a reminder), write1, write2, done, wave, sit, sleep, dangle (held) |

## Making or changing them

1. Generate a sheet with Codex image generation (`codex-imagegen` skill), passing the style
   reference (and sheet A when making sheet B) with `--ref`. The brief must ask for: the same
   character and scale as the reference, a 4×2 grid with generous margins, feet on one baseline,
   a **solid pure chroma green #00FF00 background**, and no shadows, floating dot, motion lines or
   text. The briefs used are below.
2. `npm run sprites` (scripts/make_sprites.py) keys out the green, finds each figure, aligns
   feet and scale, adds the ivory sticker outline and writes `public/pip/<pose>.png`.
3. Check the frames on light and dark backgrounds before committing.

The status light, breathing, blinks, the hop and the sway are code (src/pip.ts), so the frames
stay simple and the light's colors stay exact.

## Briefs used

Shared style sentence (both sheets): *Match the attached reference exactly: same character Pip
(the charcoal #272A33 bunny with the logo head: two long rounded ears, small round ivory eyes; a
rounded charcoal body with an ivory #FFFCF7 belly patch; short mint #6FCFB4 scarf knotted at the
neck with one short end hanging; small round charcoal mitten hands; short legs with rounded feet;
a small round charcoal tail puff). Flat 2D vector illustration, crisp clean edges, flat fills, no
gradients, no texture, no drop shadow, no ground shadow, no floating status dot, no motion lines,
no sparkles. Solid pure chroma green #00FF00 background. Landscape 3:2, a 4 by 2 grid of eight
separate poses, each fully inside its own cell with generous margin, all at exactly the same scale
with the feet on the same baseline, facing the viewer.*

Sheet A poses: idle (arms relaxed, eyes open); the same idle with eyes closed as short downward
curves (blink); listening (ears perked, head tilted a little, eyes slightly bigger); thinking (left
ear folded at the middle, a mitten touching the chin, eyes looking up); working (a small charcoal
laptop held in front of the belly, eyes down, hands on the keys); the same with hands lifted
slightly; needs you (ears up, right mitten raised high holding a small ivory card with an orange
exclamation mark); sad (ears drooped, head lowered, worried eyes).

Sheet B poses (sheet A as the reference): holding a small ivory note card in both mittens (three
dark wavy lines, no letters); writing on it with a short yellow pencil; the same with the pencil
moved right; done (closed upward-arc eyes, small pink blush, both arms up); waving (right mitten
raised beside the head, happy eyes); sitting awake (legs forward, mittens on the lap); asleep
sitting (eyes closed, ears drooped); being held up (arms raised, legs dangling, eyes wide).
