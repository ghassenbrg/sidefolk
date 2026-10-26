# From doll to companion: making the companions feel alive

> **Status:** exploration and proof of concept on the branch `poc/lively-companions`, waiting for
> the founder's decision (26 October 2026). Nothing here is merged into `rework`. Everything named
> "built" below runs on that branch; everything else is a proposal. Pictures, GIFs, films and CPU
> logs are in `build/lively-poc/` (regenerate them with the commands at the end).

The founder's verdict on today's companions: the animation is basic and they feel like a doll. That
is fair. Since D20 they breathe for 20 seconds after something happens and then hold perfectly still,
blinking. Stillness was the right call for battery and for attention, but a body that only moves
when the app has news reads as a puppet: something else pulls the strings. Characters that feel
alive do small things *on their own*, notice what is around them, answer touch with weight, and
change over the day.

The proof of concept shows that all of that fits on the engine we already have (D2, D30): one
`Director`, vector rigs on Core Animation, no per-frame code. It adds **moments** (17 one-shot bits
of life, written as data), **postures** (sit, lie down), an **idle scheduler** that picks moments
with variety and holds still while you type, **reactions** to clicks, stroking, dragging and
throwing, **ambient** behaviour by time of day, and a **Liveliness** setting (Minimal, Balanced,
Lively) where Minimal is exactly today's companion. It works for all thirteen companions and for
**custom companions made from data** (a `species.json` and SVG parts), with a template and an
example cat, Miso. Measured cost: the companion's own process stays at 0.03–0.05% of a core at every
level; WindowServer pays roughly 4–13% of a core *while* anything animates, so Balanced averages
about 0.5% and Lively about 1.2% (see [Measurements](#measurements)).

**Recommendation in one line:** approve Balanced as the default with the moments, postures and
hands-on reactions; approve custom companions as data behind a "Made by you" section; keep sound
and 3D as later, separate decisions (details in [Recommendation](#recommendation)).

## Contents

1. [What makes a desktop character feel alive](#what-makes-a-desktop-character-feel-alive)
2. [What to avoid](#what-to-avoid)
3. [What the proof of concept does](#what-the-proof-of-concept-does)
4. [The Liveliness setting](#the-liveliness-setting)
5. [The options and what they cost](#the-options-and-what-they-cost)
6. [Sound](#sound)
7. [3D](#3d)
8. [Custom companions](#custom-companions)
9. [Measurements](#measurements)
10. [Recommendation](#recommendation)
11. [Trying it](#trying-it)

## What makes a desktop character feel alive

Each of these got something right, and several got something badly wrong.

| Reference | What made it alive | What went wrong, or the lesson |
|---|---|---|
| **Desktop Goose** (2020) | Agency: it decides things. It honks, wanders, tracks mud, drags notes and memes onto your screen and steals your pointer. Surprise every minute. | It is a prank you close after ten minutes, because it takes things from you (the pointer, the screen). Agency yes; interference never. |
| **Shimeji** (2000s) | The desktop is its world: it walks on the bottom of the screen and on window tops, climbs edges, falls, and you can pick it up and *throw* it. Physics makes it a thing, not a picture. | Many of them at once is noise. Walking costs a window move every frame. Being throwable is the part worth taking. |
| **Microsoft Agent: Clippy, Rover, BonziBuddy** (1997–2004) | Huge idle libraries: Rover scratched, sniffed, slept, chased his tail; Clippy got bored, tapped the screen, looked at what you typed. People remember the idles fondly. | Interrupting ("It looks like you're writing a letter"), guessing intent badly, hard to dismiss, and Bonzi was adware. The idles weren't the problem; unasked-for help and breaking flow were. |
| **Duolingo's cast** (Rive) | A strong personality per character, faces that react to every answer, mouths synced to speech from visemes, all from one state machine per character. | Streak guilt is manipulation; our VOICE.md already says "never guilt, nag". Expressive reaction to *what you just did* is the part to take. |
| **Tamagotchi** | Time passes for it: it gets hungry, sleepy, happy; it changes when you're away. | Care burden and guilt (it dies). Take moods that follow the clock and the day, without needs that punish. |
| **Animal Crossing villagers** | Personality types, routines by time of day, they *notice* you (a head turn, "!" or "♪" above them), and animalese: a voice made of pitched syllables, character without words. | They speak in long dialogues you must click through. Take the noticing, the routines and the tiny voice. |
| **VTuber rigs** (Live2D, VRM) | Layered 2D parts deformed by parameters, breathing and blinking parameters, *physics on secondary parts* (hair, ears) and mouths driven by the audio level. | They are performance rigs, driven by a camera. Our `SoftRig` is a small Live2D already; secondary motion on ears is the cheapest big win. |
| **Rive and Lottie** | Rive: a state machine with inputs (booleans, triggers, numbers) and pointer listeners, blended states, a GPU runtime; designers author it. Lottie: After Effects playback, segments only. | Both move the work to an art pipeline and add a runtime. Our engine already is a code state machine; Rive is the later path if an animator joins (see options). |

Underneath, the same handful of things recur, and they map onto animation's old principles:

1. **A baseline of life**: breathing, blinking. (We have it; D20 stops the breathing after 20 s.)
2. **Attention**: it looks at what matters, the pointer, the window you type in, the thing that just
   arrived. A character that looks at the right thing reads as thinking.
3. **Variety in idle**: things it does by itself, never in a visible loop, never the same twice in a
   row, funny ones rare enough to surprise.
4. **Weight and touch**: squash and stretch, anticipation, follow-through (ears that lag and flop).
   Being pokeable, pettable, throwable makes it a thing in the world.
5. **Time**: tired at night, settles down when nothing happens, stretches when it gets up.
6. **Personality**: the same moment played differently by a stern Guard and a giddy Play (the
   tempers of D30 already do this for faces).
7. **Memory and relationship** (later): it remembers you petted it, greets you in the morning.

## What to avoid

- **Interrupting or competing with work.** Nothing self-initiated while the person types; nothing
  large, nothing that moves the window by itself, nothing that takes the pointer or the keyboard.
- **Visible loops.** A fidget repeated every 30 s is worse than stillness. Random timing, a pool of
  moments, no repeats in a row, rare ones capped (one sneeze or double-take per 10 minutes).
- **Constant motion.** D20 still holds: motion is information. Moments are one-shots of 0.5–3 s;
  in Balanced the companion is still more than 95% of the time.
- **Guilt and needs.** No hunger, no sad face because you left, no "you haven't petted me".
- **Uncanny.** Faces stay in the brand's ink style; no realistic eyes, no lip-sync that almost
  matches. Smooth vector morphs, cartoon timing.
- **Leaving the window or covering things.** Every moment is fitted to each body so ears, hats and
  held things stay inside the window (tested for all thirteen, every frame).
- **Ignoring the person's settings.** Reduce Motion means no self-initiated motion at all; Minimal
  means today's companion.
- **Battery surprise.** The cost of each level is measured and shown in Settings in plain words.

## What the proof of concept does

All of it lives in `Sources/SidefolkCharacter` and works through the shared `Director`, so every
companion, the robot and custom ones get it at once.

### Moments (`Antics.swift`)

A moment is data: tracks on the rig's motion layers (the body around the floor point, the face,
the eyes, the head around the neck, each arm, each ear) as keys of squash, stretch, nudge and turn,
plus face beats (a mood at a time) and gaze beats. Live, each track becomes one
`CAKeyframeAnimation` on a layer whose model transform is always the identity, so moments never
fight the state's pose; offscreen, the same keys are sampled to render frame strips and GIFs. Each
moment is **fitted to the body** before it plays: its whole-body keys go only as far as that body's
resting outline (hats, ear tips and held things included) allows, so a tall Brew hops lower than
Pip. Moments can be mirrored, and aimed (a peek leans toward the window you work in).

| On its own | | Answers | |
|---|---|---|---|
| ear twitch | one ear flicks (most frequent, cheapest) | boop | clicked: squash, > < eyes, ears flop |
| stretch | tall, paws out, eyes shut, a shake after | pet | stroked: leans into the hand, ^ ^ and ω, ears back |
| yawn | head back, mouth wide, a paw up, sleepy blink | startle | a notification: a jump, wide eyes, ears up |
| scratch | head tilted, paw scratching, one eye shut | cheer | something got done: two hops, arms up |
| hop | a small happy hop | land | dropped: squash on impact, overshoot |
| wiggle | a shimmy | spin | thrown: a tumble in the air |
| peek | leans toward your window and looks, curious | dizzy | after a hard landing: ring eyes, wobble |
| glance | only the eyes, toward your window or the pointer | | |
| sneeze | ah… ah… CHOO (rare) | | |
| double take | looks away, back, away… snaps back wide-eyed (rare) | | |

Moods are drawn in each body's own strokes (ink beads for Mochi and the folks, light on Spark's
screen and the robot's visor), including new ring eyes for dizzy. See
`build/lively-poc/antics/antics-<id>.png` for strips and `antics-<id>/<moment>.gif` for each one.

### Postures

Idle can be standing, **sitting** (lower, wider, feet forward in front of the belly) or **lying
down** (lower still, half-closed eyes, soft ears half folded, hands empty). They are poses, sprung
to like any state; moments play on top. Any state other than idle stands. When the person comes
back (pointer close, a click), it gets up, with a stretch after lying down.

### The idle scheduler (`Life.swift`)

One non-repeating timer, re-armed every 28–65 s (Balanced) or 10–26 s (Lively), only while the
companion is idle, on screen and motion is allowed. Each tick a `Mind` (plain logic, tested)
decides:

- **The person is typing** (a key in the last 2 s; `CGEventSource`, no permission): hold still. At
  most once per 45 s, a glance at the window being typed in (its frame from `CGWindowList`, no
  permission: only bounds, never titles or contents).
- **Quiet for long** (nothing happened *to the companion*): sit after 100 s, lie down after 220 s
  (Balanced); halved at night (22:00–06:00). The app's own "Sleep when you're away" still takes
  over when the person leaves.
- Otherwise **a moment**, by weight: never one of the last two again; sneeze and double-take at
  most once per 10 minutes; only quiet ones sitting or lying; at night three times the yawns and no
  hops or wiggles; peeks only when there is a window to peek at.

### Reactions

- **Click:** boop (it plays on while the Ask panel opens).
- **Stroking:** three back-and-forth strokes over the body in 1.5 s, no button: pet, leaning
  toward the side being stroked (`PettingDetector`, tested).
- **Drag and drop:** the existing dragging state; on release, a landing squash.
- **Throw:** released faster than 1100 pt/s, the window flies on a short arc (`Fling`: sideways
  glide with drag, gravity, capped speed, always lands on the bottom of the screen), tumbling;
  lands with a squash, dizzy after a hard landing. The window moves for under a second.
- **News:** a notification that steps it forward startles it (Balanced and Lively); a finished task
  (the success pose) makes it cheer. Minimal keeps today's hop.

### Ambient

Time of day (sleepier at night, slower ticks), stillness while typing, glances at the active
window, and in Lively, eyes that follow the pointer across the whole screen (faintly when far).

### Where it is wired

- `CharacterView.liveliness`, `perform(_:toward:)`, `setPosture`, `pointerMoved(toScreen:)`,
  `noteInteraction()`, `reactsToNews`.
- The app: `AppSettings.liveliness` (default Balanced on this branch), Settings › Companion ›
  Behavior › Liveliness, and in `CompanionWindowController`: boop, petting, throw, landing,
  startle, cheer, lively gaze. Verified with the UI snapshots (`build/lively-poc/ui/`); the
  running app itself was not tried (another Sidefolk dev app was running on this Mac, and only
  one may run at a time).
- `sidefolk-render --live … --liveliness …` is the same behaviour in a window you can click,
  stroke, drag and throw.

## The Liveliness setting

| | Minimal | Balanced (proposed default) | Lively |
|---|---|---|---|
| Breathing after something happens | 20 s, then still (D20) | 20 s, then still | 20 s, then still (kept going it would cost WindowServer a tenth of a core all the time; see Measurements) |
| Moments on its own | none | every 28–65 s (×1.3 at night) | every 10–26 s, more kinds (hop, wiggle, double take) |
| Sits / lies down when quiet | no | after 100 s / 220 s (half at night) | after 150 s / 300 s |
| Glances at your window | no | while you type, at most every 45 s | same |
| Eyes on the pointer | within 260 pt | within 260 pt | across the screen |
| Startled by notifications, cheers when done | no (today's hop) | yes | yes |
| Boop, pet, throw, land | yes (only when you do it) | yes | yes |
| **Reduce Motion** (any level) | nothing starts on its own; moments show only their faces, crossfaded; no throw flight; state changes crossfade as today |

Minimal is today's companion exactly: no timer is armed and the loops and their 20 s settling are
untouched (tested: `minimalIsTheCompanionOfD20`). The only difference is that it answers your own
hand, which costs nothing until you touch it.

## The options and what they cost

| Option | Feel | CPU and battery | Art | Engineering |
|---|---|---|---|---|
| **Moments, postures, reactions on the vector rig** (built) | Large step: it acts on its own, has weight, notices | One-shots only: the app ≈ 0%; WindowServer only while a moment plays (≈ 0.5% of a core on average in Balanced) | None: drawn in code from the existing parts | Done as a POC; ~1 week to production polish |
| More moments as data (play with a prop, trip over, nap twitch, chase the pointer) | Each adds variety | Same | None | Hours each |
| Walking along the screen bottom and window tops (Shimeji) | Very alive | The window moves every frame while walking: app and WindowServer a few % for those seconds | A walk cycle (hop-walk suits stubby legs; code) | ~1 week; needs window geometry from `CGWindowList` (no permission) |
| True spring physics for ears and scarf | Ears that react to every move | A per-frame update (display link) while anything moves; today's precomputed damped keys are 90% of the look | None | Medium |
| Rive state machines | Designer-authored, richest motion | GPU rendering every frame while animating; similar to ours at rest if paused | Heavy: an animator per companion; our 13 vector rigs would be redrawn | Runtime dependency (`RiveRuntime`), new pipeline; loses props, styles and data species |
| Lottie | Polished canned clips | Similar | Heavy | No interactivity: rejected |
| Pre-rendered sprites or generated frames | | | Rejected by D2/D27/D30: AI can't make consistent frames; sprites can't hold props or follow the pointer | |
| 3D (SceneKit/RealityKit) | Depth, light, turning heads | A GPU frame for every moving frame and 1.4% in the app (measured below) | A modeller per companion, or a generation pipeline we don't have | See [3D](#3d) |
| Sound | Big for character, risky for annoyance | Negligible | Sound design | See [Sound](#sound) |

## Sound

Opt-in, off by default, and small:

- **Earcons** (functional): reminder chime (exists), a soft "pip" when a moment is a reaction you
  caused (boop), a short rising two-note when something is done. Under 300 ms, quiet, one at a
  time, never while the person is in a call or Focus is on, never at night unless asked.
- **Character sounds** (personality): a squeak on boop, a contented hum when petted, a tiny yawn,
  a "boing" on landing, an "achoo". Animal Crossing's lesson: pitched syllables give character
  without words. These can be **synthesized per companion** (pitch and timbre from the species:
  Mochi high and soft, Guard low), so custom companions get a voice from two numbers, with no
  recorded assets to license.
- **Tied to the voice feature** another team is building (push-to-talk, spoken replies, a mouth
  driven by the audio level): the rig already has a morphing mouth stroke on every face, and the
  same `Mood`/beat mechanism can drive it. Proposal: the voice engine publishes an audio level
  (0…1) at ~30 Hz while speaking; the `Director` maps it to the mouth (closed ‿ → small o → wide
  pill) with a little jaw squash on the body, as a short-lived loop that stops with the speech.
  While listening (push-to-talk held), the listening pose plus ears up; the idle scheduler pauses
  during any voice exchange. One audio session, one volume, one "Sounds" switch for all of it.
- **Settings:** Sounds: Off / Earcons only / Earcons and character. Respect the system's mute.

Not built in the POC on purpose: the audio pipeline belongs with the voice work, and a sound that
annoys once gets the whole feature switched off.

## 3D

**Feasible, but not worth switching to now.** A spike target, `sidefolk-3d`, builds Mochi from
SceneKit primitives (spheres, capsules, a torus scarf) in a transparent, borderless, always-on-top
window with breathing, ear sway, blinks, head turning toward the pointer and a click hop
(`build/lively-poc/3d/`).

- **Frameworks.** SceneKit renders into a clear `SCNView` in a transparent `NSWindow` with no
  trouble, but Apple has put it in maintenance (no new features since 2025). RealityKit is the
  future on macOS (`RealityView`, macOS 15+); a transparent background over the desktop needs
  checking on macOS 15 vs 26+. Either needs Metal and renders a full frame for every frame that
  anything moves.
- **Model formats.** USDZ for RealityKit (Reality Composer Pro, Blender's USD export), `.scn`/DAE
  for SceneKit; glTF via a converter. Rigging: skeletal (Blender armature) or blend shapes for faces.
- **Art pipeline.** Thirteen companions modelled, rigged, faced and shaded consistently, plus props
  and the scarf fitted to each: a 3D artist for weeks, or text-to-3D generation (Meshy, Tripo,
  Rodin) that today gives a static mesh, not a rig, and not on-brand. We have neither the artist
  nor the tools.
- **Cost.** See [Measurements](#measurements): while animating, the same order as the vector rig
  (here the app draws its own Metal frames: 1.4% of a core in the process, even hidden, plus GPU;
  WindowServer only composites). The vector rig costs nothing at rest; a 3D scene does unless it
  is paused, so D20-style settling would still be required.
- **Carrying the 2D look over.** The brand is soft vector shading with ink faces. In 3D: a toon or
  soft PBR material on white, faces as textures or decals (keep the ink strokes as 2D overlays so
  expressions still morph), outlines with an inverted-hull pass. Expect "a 3D toy of Mochi", not
  the brand drawings; the D25/D29 renders were soft-3D *looking*, which the vector rig already
  approximates (D2).

Verdict: keep the vector rig; consider 3D only as a premium, opt-in "figurine" mode once an artist
and a RealityKit pipeline exist.

## Custom companions

People can make their own companion as **data**: a folder with `species.json` and optional
`parts/*.svg`, drawn on the soft rig with every state, prop, moment, posture, style and scarf the
built-in ones have. Built: `CustomCompanion.swift`, `SpeciesFile.swift`, `SVGParts.swift`;
template in `companions/template/`, example **Miso** (a cream cat with a bell and a tail) in
`companions/miso/`, made by copying the template.

### Where they load from

- `$SIDEFOLK_HOME/companions/<id>/` (by default `~/Library/Application Support/Sidefolk/companions/`).
- An installed extension's `companion/` folder (`Extensions/<ext-id>/companion/species.json`): an
  extension may bring a companion; it is still read as data, never run. Proposal for the manifest:
  an optional `"companion": "companion"` key so the install sheet shows "Adds a companion: Miso".
- Settings › Companion shows them under **Made by you** with a Use button (or why one can't load);
  chosen, it wears the colour and scarf set above. On this branch they are read at launch.

### The format (`species.json`, format 1)

Coordinates are the engine's: a 200 × 200 canvas, y up, feet on y = 20, centred on x = 100. Points
are `[x, y]`. Every key not listed is an error (like extension manifests).

| Key | Required | What |
|---|---|---|
| `format` | yes | `1` |
| `sidefolk` | no | Oldest Sidefolk that shows it, `">=0.1"` |
| `id` | yes | `^[a-z][a-z0-9-]{1,31}$`, not a built-in companion's id; the folder's name |
| `name` | yes | 1–30 characters, plain text |
| `description`, `author` | no | ≤ 200 and ≤ 60 characters |
| `body.colors` | yes | 2–6 `#RRGGBB`, light to shadow (the soft radial shading) |
| `body.edge` | no | a thin outline colour (for white bodies) |
| `body.torso`, `body.head` | torso yes | a shape (below); no head = a one-piece body like the folks |
| `body.neck` | yes | where the head turns |
| `body.scale` | no | 0.6–1.1: draw smaller so tall ears stay in the window |
| `feet.at`, `feet.size`, `feet.colors` | at, size | two feet; `colors` like `body.colors` |
| `arms.shoulders`, `arms.shape` | yes | two shoulders; the arm hangs from the origin, hand down |
| `face.eyes`, `face.mouth` | yes | two eyes and the mouth, on the head |
| `face.nose` | no | `{center, size, color?}` |
| `face.scale`, `face.cheeks`, `face.temper` | no | stroke size (0.6–1.8), blush, resting face: calm, smiling, cheerful, beaming, content, giddy, stern, winking |
| `ears[]` | no | ≤ 4: `{part, base, angle (−1.2…1.2), side: left/right, floppiness 0–1}` |
| `gear[]` | no | ≤ 8: `{part, mount: head/face/body/back}` worn pieces (a tail goes on back) |
| `collar` | no | where the scarf wraps: `{center, halfWidth, sag?, height?, tail?}` (else from the torso) |
| `marks` | no | offsets for zZz, "?", "!", thought dots… clear of ears |

A **shape** is one of `{"roundish": {center, size, top?, squareness?}}` (Mochi's own soft squircle),
`{"ellipse": {center, radius}}`, `{"blob": [[x, y], …]}` (a smooth curve through 3–96 points),
`{"path": "M … Z"}` (SVG path data in canvas units) or `{"part": "parts/torso.svg"}`.

A **part** is a small SVG: `path`, `circle`, `ellipse`, `rect` and `g` only. The first shape takes
the body's shading (or its own fill), the others their `fill` (`#RRGGBB`), `currentColor` takes the
companion's style colour. Ears are drawn standing on the origin, rising to negative y (SVG's y goes
down); worn pieces on a 200 × 200 artboard with the floor at y = 180.

### Validation (`sidefolk-render --check-companion <folder>`)

1. Files: `species.json` ≤ 64 KiB; parts are `parts/<name>.svg`, ≤ 256 KiB, ≤ 16 files; regular
   files inside the folder only (links, `..` and anything outside refused).
2. Strict keys, types and ranges, with the key path in every error ("body.scale: 0.6 to 1.1").
3. SVG: no scripts, images, links, `use`, styles, filters, masks, text, animation, event handlers,
   transforms (flatten them) or arcs (convert to curves); external entities never resolved; at most
   24 shapes, 4000 commands per path.
4. Geometry: drawn in every state it must stay inside its window; what it wears inside the canvas;
   eyes and mouth on the head; feet near the floor (warning).

The example and the template pass; tests cover each refusal (`CustomCompanionTests`).

### Sharing and security

- A companion is **data only**: numbers, colours and shapes. Nothing in it can run, open a file or
  reach the network; the SVG reader is not a browser and keeps only shapes and fills. It needs no
  sandbox and no permission sheet, unlike an extension's program (D13).
- Sharing: zip the folder (a `.sidefolk-companion` document type later, double-click to install
  into `companions/` after the same check). An extension can carry one (above).
- Remaining risks: a huge or adversarial file (bounded by the limits above), offensive art (it is
  the person's own desktop; shared galleries would need moderation), and impersonating a built-in
  companion (ids of built-ins are refused; names are free).
- Next: a gallery folder of community companions, a "Make your own" guide with Figma export
  settings, an image-to-parts helper (needs an image-to-vector tool we don't have).

## Measurements

Release builds of `sidefolk-render --live idle 240 <id> --liveliness <level>` (a 200 pt window,
the same `CharacterView` the app uses) and of the 3D spike, on the dev Mac (macOS 27), sampled by
`top` every 2 s. `scripts/lively-poc/measure.sh` and `measure-alternating.sh` reproduce them (output in `build/lively-poc/cpu/`).

**The companion's own process** (`top -pid`, 240 s per level, Mochi, release; 113–114 samples):

| Level | CPU average | CPU peak | Memory | Time a moment was playing |
|---|---|---|---|---|
| Minimal | 0.03% | 0.8% | 11 MB | 0 of 47 five-second checks |
| Balanced | 0.05% | 0.8% | 12 MB | 3 of 47 (≈ 6%) |
| Lively | 0.05% | 0.5% | 11 MB | 7 of 47 (≈ 15%) |

The process itself costs nothing worth mentioning at any level: moments are a handful of animation
descriptions and timers, and Core Animation interpolates them out of process.

**WindowServer and the GPU** are where an animating companion really costs (D20 found the same):
on macOS the render server that draws our layer tree is WindowServer. The dev Mac was busy during
these runs (load average 7–9; WindowServer swung between 9% and 40% of a core on its own), so
single runs were useless. `measure-alternating.sh` keeps one process running and hides and shows its
window every 10 s; WindowServer while shown minus while hidden is the companion's share, and drift
cancels. Two sessions, 3–4 minutes per condition:

| While… | WindowServer (share of one core) | Whole GPU (utilization points) | Its own process |
|---|---|---|---|
| 2D: moments back to back (the demo, looping) | +4 to +13% | +7.5 | 0.1% |
| 2D: Mochi breathing (the 20 s after any change, every level) | +7 to +12% | +4.2 | < 0.1% |
| 2D: the robot breathing | +4% | +2.3 | 0.2% |
| 2D: settled (after 20 s, every level) | ≈ 0 (within noise) | ≈ 0 | 0.03% |
| 3D spike: Mochi alive (SceneKit, 30 fps) | +1 to +5% | +2.5 | 1.4%, hidden too |

What it means:

- **Cost follows the time spent animating.** Whatever moves costs WindowServer roughly 4–13% of a
  core while it moves, 2D or 3D; at rest, 2D costs nothing. So the average per level is the share of
  time something animates times that: **Minimal** adds nothing to today; **Balanced** ≈ 6% × ~8% ≈
  **0.5% of a core** on average; **Lively** ≈ 15% × ~8% ≈ **1.2%**. That is why every level still
  settles its breathing after 20 s: an early version let Lively's moments restart the breathing,
  which would have cost the full 7–12% all the time.
- **A finding for today's companion:** Mochi breathing costs about twice the robot. Its ears sway
  inside the rasterized body layer, so every frame re-rasterizes the whole body. Swaying the ears
  outside the rasterized layer (or not at all while breathing) should cut the 20 s after every
  change roughly in half, whatever is decided here.
- **3D** moves the drawing into the app (SceneKit renders its own Metal frames: 1.4% of a core in
  the process, even hidden, plus GPU) and leaves WindowServer only compositing. While animating it
  is the same order as 2D; it has no cheap "settled" state unless the scene is paused, and every
  companion would need modelling. No reason to switch for cost or for feel today.

Raw logs and summaries: `build/lively-poc/cpu/` (`summary-mochi.txt`, `alternating/summary.txt`).
Re-run on a quiet Mac before quoting the WindowServer figures outside the team.

## Recommendation

**Approve**

1. The moments, postures and idle scheduler on the shared Director, with **Balanced as the
   default** and Minimal as today's companion, Lively for those who want more. It is the change
   that turns the doll into a companion, at a cost that rounds to zero between moments.
2. The hands-on reactions: boop, pet, drop, throw, startle on news, cheer when done.
3. Custom companions as data, the format above, with "Made by you" in Settings and the
   `--check-companion` checker; extensions may carry one.

**Drop or defer**

- 3D: not now (art pipeline and frame cost; keep the spike for reference).
- Walking around the screen: later, after people live with Balanced for a while.
- Rive/Lottie: only if an animator joins.
- Sound: design it with the voice team; ship opt-in earcons first.

**Needs art or tools we don't have**

- An animator's pass on timing (the moments are hand-tuned numbers; a few, like stretch with
  Mochi's short arms, would gain from drawn poses).
- A sound designer, or a small synth voice per species (code, cheap) for character sounds.
- For 3D: a modeller, a USDZ rigging pipeline (Blender + Reality Composer Pro), and text-to-3D
  that can rig; none available.
- For custom companions from a picture: an image-to-vector (or image-to-parts) tool; our image
  generation can't produce consistent separated parts.

**Before shipping**

- Try it in the running app for a day (petting thresholds, throw speed, how often is too often).
- The chooser should show a custom companion as selected (it highlights the built-in it is based on).
- Pick up new companion folders without a restart (watch the folder, or reload when Settings opens).
- Strings for the new Settings words go into the catalog with the next `make strings`.
- Decide whether finished agent work (not only tool writes) should cheer.

## Trying it

```sh
git checkout poc/lively-companions
swift build -c release --product sidefolk-render
R=.build/release/sidefolk-render

# Mochi in a window: click it, stroke it with the pointer, drag it, throw it.
$R --live idle 600 mochi --liveliness lively
$R --live idle 600 mochi --liveliness balanced --pace 8      # the scheduler, 8× faster
$R --live demo 47 mochi                                      # every moment in turn
$R --live demo 47 guard ; $R --live demo 47 sidefolk         # any companion (ids as in --only)
$R --live demo 47 companions/miso                            # a custom one, by folder

# Pictures: strips and GIFs of every moment; sheets of a custom companion; check one.
$R --antics build/lively-poc/antics --only mochi
$R build/lively-poc/custom --only companions/miso
$R --check-companion companions/miso

# Films without screen capture (Core Animation's own frames), and CPU per level.
$R --live demo 47 mochi --liveliness balanced --film build/lively-poc/film-demo-mochi
scripts/lively-poc/measure.sh 240 mochi        # per level; measure-alternating.sh: WindowServer and GPU
scripts/lively-poc/films.sh                    # the films; record.sh: a real screen recording of the window

# The 3D spike.
swift run -c release sidefolk-3d --live 60
```

In the app (`make dev`, with a fresh `SIDEFOLK_HOME`): Settings › Companion › Behavior ›
Liveliness; copy `companions/miso` into `$SIDEFOLK_HOME/companions/` before launching to see it
under "Made by you".

What is in `build/lively-poc/` (ignored by the repository; regenerate with the scripts above):

- `antics/antics-<id>.png` and `antics/antics-<id>/<moment>.gif`: every moment of all thirteen
  companions and Miso, offscreen from the same numbers the live animations play.
- `films/*.mp4|gif`: Core Animation's own frames of the live window (springs, blinks and loops
  included): the demo for Mochi, Miso, the robot and Guard, Mochi under Reduce Motion, and the
  scheduler at 10× pace in Balanced and Lively. Someone was typing on the Mac during the scheduler
  films, so they show the typing rule as much as the moments: it sat, lay down and mostly held still.
- `recordings/rec-*.mp4`: real screen recordings (`screencapture -l`) of the window alone, on a
  paper backdrop: the Mochi and Miso demos.
- `custom/`: Miso's and the template's contact sheets (states, small, hit, gaze, styles).
- `ui/`: the app's UI snapshots with Miso under "Made by you" and the Liveliness control.
- `3d/mochi-3d.png`: the SceneKit spike.
- `cpu/`: logs and summaries of the measurements.
