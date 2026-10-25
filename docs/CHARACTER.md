# Character

`SidefolkCharacter` draws the companion and the Folk Family as layered vectors on Core Animation
(AppKit + QuartzCore only). Contact sheets live in `Resources/Character/`, the app icon in
`Resources/Icon/`.

## Using it

```swift
let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
view.state = .working(.notepad)        // springs to the new pose; setState(_:animated:) for no animation
view.play(.wave)                       // wave, hop, nod, shake, lookAround, blink
view.setGaze(CGVector(dx: 0.6, dy: 0)) // -1...1, nil = straight ahead; tiny changes are ignored
view.badges = [.watching, .count(2)]
view.reducedMotion = true              // starts from the system setting
```

- **Size.** The art lives in a 200×200 canvas scaled aspect-fit into the view. At 200 pt the body is
  about 124 pt wide, which is the intended size; 104 pt (body ≈ 64 pt) is the smallest that stays
  legible. Keep the view square; the margins hold effects (zZz, "!", confetti) and badges.
- **Floor.** The feet rest on a line 10% of the view's height above its bottom edge (canvas y = 20),
  centered horizontally. To stand the companion on the dock edge, put that line on it.
- **Clicks.** `hitTest` only claims points inside `characterPath` (body, fin, ears, feet, posed arms
  and any held prop, in view coordinates), so the rest of the view is click-through. Use the same
  path for the window's mouse region.
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

## Reviewing changes

```sh
swift run sidefolk-render /tmp/sheets          # states, states-small (with badges), folks, gaze, hit, menubar, icon
swift run sidefolk-render Resources/Character  # refresh the committed sheets
swift run sidefolk-render --icon Resources/Icon # icon-1024.png, Sidefolk.iconset/, Sidefolk.icns (iconutil)
swift run sidefolk-render --live cycle 32      # a real window; check CPU with top -pid
```

`CALayer.render(in:)` ignores filters and sizes shadows in context pixels, so the renderer scales a
holder layer instead of the context, and the rig avoids filters entirely. That keeps the offscreen
sheets faithful to the screen.
