# What making themes has taught us

This file is part of the skill and grows with it. Read it before designing. After every theme job, add what was new (see
"Keep this skill improving" in SKILL.md). Each lesson says what to do, then why, so a later case can be judged by the
reason. Newest first within a section; delete a lesson when it stops being true.

## You are a UI and UX designer, not a painter

- **Judge the working screen, not the picture.** Start from what the person does all day: find their place, read, decide.
  Beauty that costs any of that is a defect. *The founder, Harbor rework, 2026-11-03: "you are not just painting."*
- **Measure, then look.** Every contrast complaint in the Harbor rework could have been found with a number first: the
  logo's aqua at 1.6:1, sidebar icons at 1.7:1, a selected row at 1.1:1. `sidefolk theme check` covers solid surfaces;
  use `templates/art-contrast.py` for words over art.
- **Get an independent audit before showing the person.** A reviewer who didn't design it, sampling pixels on every screen
  in light and dark, found a dozen problems the designer had stopped seeing, some of the designer's own making.
- **Don't stop at text.** State needs 3:1 too: a selected row from its sidebar, a segment from its track, a list selection
  from its card, an icon from what it's on. A soft tint alone is about 1.2:1, so add an edge or a rail.

## Calm comes first: this is an everyday tool

- **Keep it soft enough to look at all day.** No strong glow, no saturated fields, nothing that hurts. Pure white text on
  near-black and electric blue both tired the founder. *"This is a tool for everyday use."*
- **Light is really light and dark is really dark.** A dark frame around a light page, or one scene for both, read as wrong.
  The sidebar and all art follow the appearance setting.
- **Keep the sidebar plain for navigating.** Art goes in its header, with the list below on a solid colour. Text and icons
  over a picture were hard to scan. *The founder's own idea; it worked at once.*
- **Put a big scene on one page only.** Other pages stay plain for work, with at most the sky behind the toolbar.

## Art

- **The picture has to serve its place.** Before generating, say what's on top of it and leave that area empty: the left
  half for words, the top quarter for window buttons and a logo, the centre of the ground for the companion.
- **Nothing floats.** The companion stands on something in a real place, framed from both sides, centred and seen straight
  on, like the jetty. A hill behind it read as "thrown in space".
- **Fit the place to the product's meaning.** A meadow was pretty but wrong for the default: Sidefolk works beside you, so
  its companion belongs in a tidy studio. Ask what the setting says about the app.
- **Don't repeat yourself across images.** Two scenes side by side must show different things in one world. Even a second
  house read as repetition.
- **Same place, two times of day.** Generate the light version, then pass it as `--ref` for the dark one with "keep the
  exact composition", which keeps them matched and gets night right.
- **Clean every generated cut-out.** "Transparent" images come back with specks and a rough fringe that only show on a real
  background. Keep the largest piece, smooth the edge, and check on white, dark and a colour before using one.
- **A full colour logo may fail at small size.** The aqua "folk" is 1.6:1 on a light sidebar. Use the brand's navy version
  on light and the reversed one on dark.
- **Palette swaps aren't redesigns.** When asked for a rework, show structural change: layout, components, hierarchy.

## Shipping

- **Moving a theme out of the app must not take it from anyone.** Keep its id and setting, fetch it by itself, and only say so
  when it can't come. Publish the gallery first. *The founder moved three themes to the gallery, 2026-11-03.*

## Checking

- **macOS ignores a text field's hint colour.** A `prompt` draws in the system's grey whatever style it's given: 3.15:1 on white.
  Sidefolk's fields use `.fieldHint`, in `inkFaint`. Measure the rendered pixels; reading the code said this was fine.
- **Hide a drawn hint from VoiceOver only if the field still says it.** Test in the tree: `swift scripts/dev.swift ax` now shows
  SwiftUI's fields, and it caught a search bar with no name at all.
- **Look in a real window.** Snapshots draw an inactive window, so they hid macOS's blue selection and made toolbar icons
  look disabled. Run the debug app (`swift scripts/dev.swift snap`) at least once.
- **Render right to left and a long language every time.** Arabic showed a scene that didn't mirror, with the art under the
  words. German showed "All day" cut off. Use `--language ar` and `--language de`.
- **Keep words off art by construction.** Limit their width to the scene's empty side rather than hoping a sample fits.
- **Try the narrow window.** Art collapsed into a flat band of colour until the scene dropped out under 860 pt.
- **Test what you claim.** Simulated clicks can do nothing and look like a pass or a failure. Run a control without your
  change, and tell the person what stays unverified.

## Working with the founder

- **Show real screenshots and keep working.** "Give me a proposition but keep working" means choose, build the pick, and
  show the alternatives beside it, without stopping to wait.
- **Reference the app's real things.** The founder judges by the icon, the logo and About. Check those before inventing a
  palette, and check the latest main, since images and skills change there.
