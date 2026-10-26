# Character

`SidefolkCharacter` draws the companions and the Folk Family on Core Animation (AppKit + QuartzCore
only). Thirteen companions can live on the desktop (D30): Mochi, the white rabbit with navy ear
tips and a scarf (the default and brand mascot, D29), the original Sidefolk robot (D2), Spark, and
the ten folks. All are live vector rigs on one engine. Contact sheets live in `Resources/Character/`,
the app icon in `Resources/Icon/`.

## Using it

```swift
let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
view.look = CharacterLook(.mochi)                  // dressed as it comes (Mochi in its aqua scarf)
view.look = CharacterLook(.scout, style: CharacterStyle(color: .coral, accessory: .scarf))
view.displayName = "Mochi"             // VoiceOver: "Mochi is listening"
view.state = .working(.notepad)        // springs to the new pose; setState(_:animated:) for no animation
view.play(.wave)                       // wave, hop, nod, shake, lookAround, blink
view.state = .hearing                  // the microphone is on: both ears up (D34)
view.speak(0.7)                        // talking: the mouth opens with the voice's level; speak(nil) closes it
view.setGaze(CGVector(dx: 0.6, dy: 0)) // -1...1, nil = straight ahead; tiny changes are ignored
view.badges = [.watching, .count(2)]
view.reducedMotion = true              // starts from the system setting
```

Changing `look` is live: a new style redresses the companion in place; another companion crossfades
in, in the same state, with the same badges. `CharacterSpecies.available` lists the companions
finished to the full bar; the app offers only those.

- **Size.** The art lives in a 200×200 canvas scaled aspect-fit into the view. At 200 pt the robot's
  body is about 124 pt wide, which is the intended size; 104 pt (body ≈ 64 pt) is the smallest that
  stays legible. Keep the view square; the margins hold effects (zZz, "!", confetti) and badges.
  Every companion stays inside the canvas in every state, lifted and stretched included (tested).
- **Floor.** The feet rest on a line 10% of the view's height above its bottom edge (canvas y = 20),
  centered horizontally. To stand the companion on the dock edge, put that line on it.
- **Clicks.** `hitTest` only claims points inside `characterPath` (body, head, ears, antenna, worn
  pieces, posed arms and any held prop, in view coordinates), so the rest of the view is
  click-through. Use the same path for the window's mouse region.
- **Anchor.** `characterFrame` is the body at rest in view coordinates (the robot: feet to fin, 17% in
  from each side; the others: their own body). Bubbles and panels attach to it and folks stand beside
  it, so a slim companion keeps them close.
- **Folks.** `FolkView(folk:frame:)` is the small on-duty folk: a 100×100 canvas (body ≈ 62% of the
  width), standing 10% above the bottom. `popIn()` / `popOut(completion:)` spring from the floor point.
- **Offscreen.** `CharacterRenderer` renders the same rigs to `CGImage` (states, folks,
  `appIcon(size:)`, `menuBarTemplate(size:scale:)`; set `isTemplate` on the `NSImage`).

## One engine, many bodies

`Director` runs a companion: state changes, the loops each state needs, props, effects, badges,
gestures, settling and pausing. It drives a `Figure`, the body: `RobotRig` for the robot, `SoftRig`
for everyone else. Both nest the same transform layers (pose › state loop › gesture › breath, and
face › face gesture › scan › blink), so the shared `Choreography` (poses for every state, built for
the robot), `Props` and `Effects` fit every body.

A `SoftRig` is built from a `Species`: data, not code paths. It says the body's shading, a torso and
an optional head (Mochi and Spark have necks; folks are one piece), the neck the head turns around,
feet, shoulders and an `ArmStyle`, the face (`SoftFace`: ink bead eyes, or a dark screen with glowing
eyes), `AppendageSpec`s (ears, antennae, a sprout), `Gear` worn on the back, head, face or body, an
optional `Held` signature thing, where a scarf goes (`Collar`), the anchor frame, where effects sit
clear of its ears (`markOffsets`) and a drawing `scale` (Mochi is drawn at 95% so its tall ears stay
in the window when it hops or is lifted). `Mochi.swift`, `Spark.swift` and `FolkSpecies.swift` are
the whole of each companion.

On top of the shared choreography a soft rig adds:

- **Faces.** `SoftExpressions` turns the robot's visor expressions into ink faces (`Ink`: beads with a
  catchlight, ^ ^, closed ‿, > <, a wink, brows for worry or sternness, a ω cat mouth) or keeps them
  for Spark's screen (resting on tall glowing ovals). Idle shows the companion's temper (Pip beams,
  Melody is content, Play is giddy, Guard is stern, Nova winks); other states share expressions with
  the eyes open on the task.
- **Ears.** Each `Appendage` turns around its base on three layers: pose (droop for error and sleep,
  perk for alerts, one ear up while listening), trail (a damped flop after a hop, nod or new pose, a
  swing after a shake) and sway (a slow idle swing, out of step between ears, fast while dragged).
  Soft ears with a `Fold` (Mochi's) lie back behind the head when asleep: seen from the front they
  shorten until only their round navy tips show over it.
  Floppiness scales all of it (Mochi's ears 1, Spark's stiff antenna 0.7, Seed's sprout 0.6).
- **Gaze.** The eyes slide, the face slides a little further (parallax) and the head turns and tilts
  toward the pointer around the neck; ears ride on the head.
- **Held things.** At idle a folk holds its signature (Scout's magnifier, Tempo's calendar, Play's
  controller, Guard's shield, Nova's brush, Brew's cup) with the arms the `Held` asks for; every
  other state puts it away and holds the state's prop.

The folks are exactly twice the on-duty folks (body outline, feet, eyes and mouth map ×2), so their
footprint is the robot's. Their accessories are the on-duty drawings (`FolkKit`), shown at that size
through a `Magnifier`, a layer that tells `Layers.setContentsScale` to rasterize its contents that
much finer so they stay sharp.

## Style: one colour and one thing to wear

Every companion takes the same `CharacterStyle` (D30): a brand colour (aqua, coral, mint, light
blue) and an accessory (none, or the knitted scarf, fitted to each body by its `Collar`). The
colour paints what it wears, and the companion's own accents where it has them: the robot's light
(eyes, brows and mouth on the visor, the ear pods, and the marks drawn in that light) and Spark's
headphones, antenna ball, badge and eyes. As a light a colour is three shades (`Light`: halo,
stroke, hot core; aqua keeps the reference's hand-picked ones); as a material (scarf, plastic) aqua
leans to mint, like the founder's renders. Mochi comes in its aqua scarf, the others in nothing.
Bodies, faces, celebration colours and badges never change.

## How it moves without burning CPU

The rigs are trees of `CAShapeLayer`s and `CAGradientLayer`s (glow is a layer shadow in the light's
color). States map to a `Pose` (numbers for body, arms, feet, eyes, brows, mouth, ear glow, ears,
catchlight, ground shadow). Changing state hands Core Animation one spring or ease animation per
changed property, starting from what is on screen, so interrupted transitions never jump. Eyes,
brows and mouths are round-capped strokes built from the same skeleton (one move, two cubics), so any
expression morphs into any other with a plain `path` animation.

Everything that repeats (breathing, idle sway, ear sway, typing, the waving arm, zZz, sparkles, the
badge spinner) is a `repeatCount = .infinity` animation added once when the state starts and removed
when it ends, capped at ~24 fps (`Motion.capFrameRate`). Separate nested layers carry pose, state
loop, gesture and breath transforms, so they never fight over a key path. Idle, listening and
sleeping stop all of it after `Director.settleAfter` (20 s, D20; blinks continue), and everything
stops while the window is occluded. There is no `CADisplayLink`, no per-frame timer and no SwiftUI;
the view is layer-hosting, so AppKit never redraws it. The only app-side timer is the blink
scheduler: one non-repeating `Timer` re-armed every 3–7 s (tolerance 0.4 s), skipped while the window
is occluded and not armed in states with closed eyes.

Talking (D34) adds no loop either: `speak(level)` hands the figure's mouth one short ease (0.07 s) to
an "o" whose height follows the level (`Figure.talk`, the same stroke skeleton, so it morphs from and
back to any mouth). The app calls it from the audio player's meter, about 20 times a second while
sound comes out, and only when the level changes by an eighth; `speak(nil)` gives the pose its mouth
back. When the audio stops, so does the mouth. `hearing` (the microphone is on) doesn't settle: it
lasts only while the talk key is held, and its waves say the microphone is live.

Measured with `sidefolk-render --live idle 25` (release build, 200 pt window) and `top` sampling every
2 s: 0.0% CPU in most samples, peaks of 1–3% when a blink is committed, about 11 MB and 3 threads.
Mochi measures the same (0.0% breathing and settled, 10 MB). `--live idle 31 <id>` prints the
attached animations every 5 s, "∞" marking loops: Mochi runs breath, sway and two ear sways until
20 s, then none. `--live cycle 32` walks every state, to catch loops that are not cleaned up.

Reduced motion: no breathing, sways, ear trails, hops or loops; state changes crossfade; a blink is a
quick fade; `wave` and `lookAround` become discrete pose changes; `hop`, `nod` and `shake` do nothing;
a speaking mouth holds half open instead of moving.

## Life: moments, postures, liveliness (proposed)

On the branch `poc/lively-companions`, waiting for the founder (research and numbers:
[docs/research/lively-companions.md](research/lively-companions.md)).

```swift
view.liveliness = .balanced                 // .minimal (D20 as it is), .balanced, .lively
view.perform(.boop)                         // any CharacterAntic; toward: a screen point aims peeks
view.setPosture(.sit, animated: true)       // idle only: .stand, .sit, .lie
view.pointerMoved(toScreen: p)              // from the host's pointer monitor: stroking pets it
view.noteInteraction()                      // pointer close, a click: it gets up, the quiet clock restarts
if view.reactsToNews { view.perform(.startle) }
```

- **Moments** (`Antics.swift`) are data: tracks of squash, stretch, nudge and turn on layers whose
  model transform is always the identity (`gesture`, `faceGesture`, `scan`, the soft rig's head tilt
  layers, arm `loop`s, ear `trail`s; `Figure.movers(_:)`), plus face beats (`Mood`, drawn by
  `Figure.express`) and gaze beats. Live, one keyframe animation per layer and a few one-shot
  timers; offscreen, `Director.hold(_:at:)` sets the same keys for frame strips. Each is fitted to
  the body's resting outline (`Layers.visibleBounds`) so nothing leaves the window (tested for every
  companion, every frame).
- **Postures** are poses on top of idle (`Moods.posture`): sitting brings the feet forward
  (`Pose.feetSplay`, drawn in front of the belly), lying down is lower with drowsy eyes and half
  folded ears.
- **Life** (`Life.swift`): one non-repeating timer while idle and on screen; `Mind` decides (typing
  holds it still, quiet time sits then lies down, variety, rare moments rare, sleepier at night).
  Senses (`Surroundings`): seconds since a key and the frontmost window's frame, no permission.
- **Hands:** `PettingDetector` (strokes back and forth) and `Fling` (a throw's arc to the floor).
- Minimal arms no timer and keeps `settleAfter` at 20 s; Reduce Motion starts nothing on its own
  and plays only a moment's faces.

## Custom companions (proposed)

`CustomCompanions.load(folder:)` reads a folder with `species.json` and `parts/*.svg` (format and
rules in the research doc) into a `CustomCompanion`; `CharacterLook(custom:style:)` draws it on a
`SoftRig` like any folk. `loadAll(home:)` reads `<home>/companions/*` and installed extensions'
`companion/` folders. Data only: strict keys, ranges, SVG shapes only, files inside the folder only,
and a geometry check in every state. `companions/template/` and `companions/miso/` are the examples.

## Reviewing changes

```sh
swift run sidefolk-render /tmp/sheets             # robot sheets, folks, menubar, icon, companions.png, and per companion:
                                                  # companion-<id>{,-small,-hit,-gaze,-styles}.png and compare-<id>.png
swift run sidefolk-render /tmp/sheets --only nova # one companion's sheets
swift run sidefolk-render --icon Resources/Icon   # icon-macos-1024.png, Sidefolk.iconset/, Sidefolk.icns (iconutil)
swift run sidefolk-render --live cycle 32 mochi   # a real window; check CPU with top -pid
swift run sidefolk-render --antics /tmp/antics --only mochi   # every moment: a strip and a GIF each
swift run sidefolk-render --live demo 47 mochi    # every moment live; click, stroke, drag, throw it
swift run sidefolk-render --check-companion companions/miso   # a custom companion's problems
```

`Resources/Character/` keeps the robot's sheets (states, states-small, gaze, hit), `folks.png`,
`companions.png` and every other companion's `companion-<id>-small.png` (all states, with badges);
copy refreshed ones from the output. The full-size sheets are 36 MB together and stay out of git.

Run it from the repository: `compare-<id>.png` puts the founder's reference render
(`Resources/Brand/masters/mascot-mochi.png`, `folk-family/<id>/<id>.png`) beside the live rig. The
hit sheets draw the click outline (pink) and the anchor frame bubbles attach to (blue).

`CALayer.render(in:)` ignores filters and sizes shadows in context pixels, so the renderer scales a
holder layer instead of the context, and the rigs avoid filters entirely. That keeps the offscreen
sheets faithful to the screen.
