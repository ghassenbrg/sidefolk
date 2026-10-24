# Spark's frames

Spark, the worker companion, is 16 frames cut from two generated sprite sheets, the same poses
and the same pipeline as Pip ([art/pip/README.md](../pip/README.md)). The style reference is
[creative-design/v2/spark-concept-sheet.png](../../creative-design/v2/spark-concept-sheet.png),
chosen with the user on 24 October 2026 (docs/PLAN-V2.md, section 4).

| Sheet | Poses, left to right, top row then bottom |
|---|---|
| `sheet-a.png` | idle, blink, listen, think, work1, work2, alert (holding a "!" card), sad |
| `sheet-b.png` | note, write1, write2, done, wave, sit, sleep, dangle (held) |

`npm run sprites -- spark` writes `public/spark/<pose>.png`. A worker's color is a hue turn of the
mint parts in code (src/worker-colors.ts), so one set of frames serves every color; ivory and
charcoal stay as drawn and the status light keeps its exact color.

## Briefs used (codex-imagegen, 24 October 2026)

Sheet A, with the concept sheet and Pip's sheet A (layout only) as references: *Spark, a small
friendly robot with a big rounded ivory #FFFCF7 head shaped like a soft TV screen with a thin
charcoal #272A33 outline, a dark charcoal screen face with two tall rounded mint #6FCFB4 oval
eyes, a thin charcoal antenna with a round mint ball on top, a small rounded ivory body, small
round mitten hands and short stubby legs. Flat 2D vector illustration, crisp clean charcoal
linework, flat fills, no gradients, no texture, no shadows, no motion lines, no sparkles, no
text. Solid pure chroma green #00FF00 background. Landscape 3:2, a 4 by 2 grid of eight poses,
same scale, feet on one baseline.* Poses: idle; blink (eyes as flat lines); listening (head
tilted); thinking (mitten at the chin, three mint dots for eyes); working with a small laptop,
twice; needs you (card with an orange "!", orange antenna ball); sad (drooping eyes and antenna).

Sheet B, with sheet A as the reference: holding a note card (orange antenna ball); writing with
a yellow pencil, twice; done (happy arcs, arms up); waving; sitting awake; asleep sitting (grey
antenna ball); held up (arms up, legs dangling, eyes wide).
