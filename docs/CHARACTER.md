# Character

`SidefolkCharacter` draws the companion and the Folk Family on Core Animation (AppKit + QuartzCore
only). The default companion, the Sidefolk robot, is layered vectors (D2); Mochi and Spark are
sprite companions drawn from pose images (D27). Contact sheets live in `Resources/Character/`, the
app icon in `Resources/Icon/`, the sprite art in `Resources/Companions/`.

## Using it

```swift
let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
view.look = .sidefolk(.coral)          // the robot, its light in a brand colour (default .aqua)
view.look = .sprites(mochi)            // let mochi = SpriteSet(folder: …/Companions/mochi); nil if a pose is missing
view.displayName = "Mochi"             // VoiceOver: "Mochi is listening"
view.state = .working(.notepad)        // springs to the new pose; setState(_:animated:) for no animation
view.play(.wave)                       // wave, hop, nod, shake, lookAround, blink
view.setGaze(CGVector(dx: 0.6, dy: 0)) // -1...1, nil = straight ahead; tiny changes are ignored
view.badges = [.watching, .count(2)]
view.reducedMotion = true              // starts from the system setting
```

Changing `look` is live: a new accent recolours the robot in place; another companion crossfades in
the same state, with the same badges. Internally the view hosts a `Performer`: the vector `Director`
or the `SpriteDirector`. Both draw into the same canvas, so everything below holds for either.

- **Size.** The art lives in a 200×200 canvas scaled aspect-fit into the view. At 200 pt the body is
  about 124 pt wide, which is the intended size; 104 pt (body ≈ 64 pt) is the smallest that stays
  legible. Keep the view square; the margins hold effects (zZz, "!", confetti) and badges.
- **Floor.** The feet rest on a line 10% of the view's height above its bottom edge (canvas y = 20),
  centered horizontally. To stand the companion on the dock edge, put that line on it.
- **Clicks.** `hitTest` only claims points inside `characterPath` (the robot's body, fin, ears, feet,
  posed arms and any held prop; a sprite's opaque pixels; in view coordinates), so the rest of the
  view is click-through. Use the same path for the window's mouse region.
- **Anchor.** `characterFrame` is the body at rest in view coordinates (the robot: feet to fin,
  17% in from each side; a sprite: its idle pose's opaque bounds). Bubbles and panels attach to it
  and folks stand beside it, so a slim companion keeps them close.
- **Folks.** `FolkView(folk:frame:)` uses a 100×100 canvas (body ≈ 62% of the width), standing 10%
  above the bottom. `popIn()` / `popOut(completion:)` spring from the floor point.
- **Offscreen.** `CharacterRenderer` renders the same rigs to `CGImage` (states, folks,
  `appIcon(size:)`, `menuBarTemplate(size:scale:)`; set `isTemplate` on the `NSImage`).

## How it moves without burning CPU

The rig is a tree of `CAShapeLayer`s and `CAGradientLayer`s (glow is a layer shadow in the light's
color). States map to a `Pose` (numbers for body, arms, feet, eyes, brows, mouth, ear glow, ground
shadow). Changing state hands Core Animation one spring or ease animation per changed property,
starting from what is on screen, so interrupted transitions never jump. Eyes, brows and mouth are
round-capped strokes built from the same skeleton (one move, two cubics), so any expression morphs
into any other with a plain `path` animation.

Everything that repeats (breathing, idle sway, typing, the waving arm, zZz, sparkles, the badge
spinner) is a `repeatCount = .infinity` animation added once when the state starts and removed when it
ends. Separate nested layers carry pose, state loop, gesture and breath transforms, so they never
fight over a key path. There is no `CADisplayLink`, no per-frame timer and no SwiftUI; the view is
layer-hosting, so AppKit never redraws it. The only app-side timer is the blink scheduler: one
non-repeating `Timer` re-armed every 3–7 s (tolerance 0.4 s), skipped while the window is occluded
and not armed in states with closed eyes.

Measured with `sidefolk-render --live idle 25` (release build, 200 pt window) and `top` sampling every
2 s: 0.0% CPU in most samples, peaks of 1–3% when a blink is committed, about 11 MB and 3 threads.
`--live cycle 32` walks every state and prints how many animations are attached, to catch loops that
are not cleaned up.

Reduced motion: no breathing, sways, hops or loops; state changes crossfade; a blink is a quick fade;
`wave` and `lookAround` become discrete pose changes; `hop`, `nod` and `shake` do nothing.

## The robot's light colour

`CharacterAccent` (aqua, coral, mint, light blue: the brand palette) colours the robot's light: eyes,
brows and mouth on the visor, the ear pods, and the marks drawn in that light (zZz, listening waves,
thought dots, "?", alert ticks). Each colour is three shades (`Light`: halo, stroke, hot core); aqua
keeps the reference's hand-picked ones, the others derive theirs the same way. The shell, visor
glass, celebration colours and the badges never change. That is the whole customisation (D27).

## Sprite companions

Mochi (a bunny in a mint scarf) and Spark (a little robot with headphones) are the founder's earlier
characters, 16 poses each (`Resources/Companions/<id>/<pose>.png`, or `.webp` for the legacy cuts;
PNG wins when both exist). `SpriteSet(folder:)` returns nil when any pose is missing, and the app
then doesn't offer that companion.

**Placement.** Files may differ in pixel size and margins. Each pose is measured (opaque = alpha ≥
0.35, so soft edges and faint fringes don't count), scaled by the one factor that makes the idle
pose 158 canvas units tall (the robot's height), stood on the floor line by the bottom of its
opaque pixels and centered on its feet (the lowest eighth of its opaque pixels), then drawn once
into a 400×400 bitmap of the whole canvas (2 px per unit; the largest companion on Retina needs
about 1.6). Every pose then shares one frame, so one image layer swaps and crossfades them. Poses
are drawn on first use and kept. The click outline comes from the same bitmap: 2×2-unit cells whose
average alpha is ≥ 0.35, one rectangle per run.

**States** (`SpriteChoreography`):

| State | Pose | Motion while it lasts |
|---|---|---|
| idle | idle, blink frames from the blink scheduler | breath, slight sway; after 20 s sits down (`sit`) and holds still |
| listening / thinking | listen / think | breath; thinking sways |
| working(.notepad) | write1 ⇄ write2 every 0.4 s | breath |
| working(anything else) | work1 ⇄ work2 every 0.3 s (the little laptop) | breath |
| waiting (approval) | note (holds up the card) | breath, sway |
| alert | alert (card with "!") | hop on entry, a small bounce every 1.4 s |
| success / error | done / sad | hop / shake on entry |
| sleeping | sleep | slow breath, settles after 20 s |
| dragging | dangle, lifted 12 units, shadow shrinks | swings from the top of the head |
| celebrating | wave ⇄ done every 0.5 s | hops |

Gestures: `wave` shows the wave pose for 1.5 s, `lookAround` the head-tilting listen pose for 2 s
(both discrete, so also under reduced motion); `hop`, `nod` and `shake` move the whole sprite like
the robot's. There are no eyes to steer: `setGaze` leans the body up to 2° toward the pointer
(Settings calls the switch "Turn toward the pointer" for these two).

**Motion rules** are the robot's (D20): pose changes crossfade in 0.22 s; breathing (gentler than
the vector shell's: a stretched render looks rubbery sooner) and the state's loops are
`repeatCount = .infinity` animations capped by `Motion.capFrameRate`; pose pairs take turns through a
discrete `contents` keyframe loop, started after the crossfade; idle, listening and sleeping stop
everything after `Director.settleAfter` (an idle sprite sits down then, as in the legacy app, and
stands up when woken); everything stops while the window is occluded. Reduced motion: no loops, so
busy states hold their first pose, and no hops, nods or shakes.

Badges and the ground shadow sit where the robot's do. Sprites draw no effect marks: their poses
already carry them (the "!" card, closed eyes). `sidefolk-render --live idle 31 mochi` prints the
attached animations every 5 s: two loops (breath, sway) until 20 s, then none. Measured like the
robot (release build, 200 pt window, `top` every 2 s): 0.0% CPU breathing and settled, 12–13 MB.

## Reviewing changes

```sh
swift run sidefolk-render /tmp/sheets          # states, states-small (with badges), accents, folks, gaze, hit, menubar, icon,
                                               # and companion-<id>{,-small,-hit,-poses}.png for each sprite companion
swift run sidefolk-render Resources/Character  # refresh the committed sheets
swift run sidefolk-render --icon Resources/Icon # icon-macos-1024.png, Sidefolk.iconset/, Sidefolk.icns (iconutil)
swift run sidefolk-render --live cycle 32      # a real window; check CPU with top -pid
swift run sidefolk-render --live idle 31 spark # the same for a sprite companion; prints looping animations
```

Run it from the repository: sprite companions are read from `Resources/Companions`. The hit sheets
draw the click outline (pink) and the anchor frame bubbles attach to (blue).

`CALayer.render(in:)` ignores filters and sizes shadows in context pixels, so the renderer scales a
holder layer instead of the context, and the rig avoids filters entirely. That keeps the offscreen
sheets faithful to the screen.
