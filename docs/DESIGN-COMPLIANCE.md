# Design system compliance

How the app meets [creative-design/DESIGN-SYSTEM.md](../creative-design/DESIGN-SYSTEM.md) and
[creative-design/APP-UX.md](../creative-design/APP-UX.md), rule by rule. Checked 24 October 2026.

**Status key.** Done: built and checked in the browser preview, by tests or both; every view
also loads without errors in WebKit, the app's engine (`npm run check:webkit`). Hand check:
built, but it can only be confirmed in the running app (agents here can't see the screen).
Every item in the package is built; what remains is checking with people (last section).

## Identity

| Rule | Where | Status |
|---|---|---|
| Pip Signal is the brand: charcoal bunny head, two ivory eyes, mint dot | `scripts/make_icons.py` (one geometry), `art/brand/pip-signal.svg`, `src/icons.ts` `mark()` | Done |
| Vector master and a one-color mark for 16–24 px | `art/brand/pip-signal.svg`, `pip-signal-mono.svg` (eyes cut out) | Done |
| Menu bar template icon is a monochrome silhouette | `src-tauri/icons/tray.png` (44 px template, eyes cut out), checked on light and dark at 2× | Done |
| App icon uses the mark | `art/icon/icon-1024.png` → `src-tauri/icons/*` | Done |
| Lowercase wordmark `sidefolk`; prose says Sidefolk | window sidebar and welcome (`.wordmark`, rounded system font) | Done |
| Clear space ≥ one dot diameter; the brand dot never shows live status | mark geometry; status uses badges, never the dot | Done |

## Palette, type, spacing

| Rule | Where | Status |
|---|---|---|
| Canvas, surface, ink, muted, border, control-border, mint, focus, terracotta (light and dark) | `src/tokens.css`, shared by the overlay and the window | Done |
| Charcoal text on mint, never white | `--on-mint` on every primary button and selected state | Done |
| Required control boundaries use `control-border` | buttons, fields, switches, segmented controls, cards' attention border | Done |
| System sans for UI, system monospace for commands and paths; no font download | `--font-ui`, `--font-mono` | Done |
| 12 / 14 / 16 / 20 / 28 px; body line-height 1.45–1.6 | `--text-*`, `--leading: 1.5` | Done |
| Spacing 4–32; radius 10 controls, 18 cards, 24 panels | `--space-*`, `--radius-*` | Done |
| 44 × 44 px minimum targets | buttons, chips, close ×, menu rows, fields, switches (hit area) in both surfaces | Done |
| Visible 3 px focus ring, 3 px offset, both themes | `:focus-visible` in both stylesheets | Done |
| Solid opaque cards, not wallpaper-dependent transparency | bubbles and cards use `--surface` with a border and shadow | Done |

## Status

| Rule | Where | Status |
|---|---|---|
| Runtime orb palette kept | `src/pet/orb.ts` unchanged colors; `--orb-*` tokens | Done |
| Badges: symbol + word for Idle, Thinking, Working, Needs you, Done, Failed, Asleep | `src/states.ts` (`STATES`, `badge()`), `src/icons.ts` glyphs | Done |
| Orb colors only decorate; words carry meaning | badge glyph discs only; text is ink | Done |
| Status never defined by coat color | status comes from sessions and requests (`petState`) | Done (tested) |
| Reduced motion: static badges and clear text, no pulses | `Orb.update(..., still)`, `Mind.react` skips hops, `--motion-* : 0ms` | Done; hand check in app |
| Failure says what failed and where to open details | "Claude stopped with a problem in api: …. Click me to open the session." | Done |

## Key surfaces

| Rule | Where | Status |
|---|---|---|
| Permission card order: pet · project → tool · session → question → exact action → explicit choices | `Crew.askCard` (`src/crew.ts`), `Bubble.renderCard` | Done (preview screenshot) |
| Project and session always shown | `who` and `context` lines; review view identity | Done |
| Long commands wrap or expand; the end is never hidden | hooks/codex keep up to 2000 characters (`ACTION_MAX`); `pre-wrap` + scroll | Done |
| Pending/expired requests disable actions and say why | review: "Sending…", locked buttons; gone → "no longer waiting… Nothing was sent from here." | Done |
| Petting never approves; Allow is not preselected or focused | click opens status only; no autofocus in cards; Decline first | Done |
| Den: list with portrait, name, project, status word and icon; filters All / Needs you / Resting; selecting shows status, sends nothing | Window → Crew (`src/dashboard/crew.ts`) | Done |
| Appearance picker: character first, then art family, palette, accessory; idle and alert previews; name and bindings kept | Crew → companion → Appearance (`LivePreview` idle + alert) | Done |
| Art families: Soft 3D, Ink & Geek, Pocket Anime | renderer looks in `src/pet/model.ts` (`STYLE`): smooth matte toon; flat fills + heavy charcoal line; hard cel band + thin warm line. Picker shows each with a preview | Done |
| A style never changes name, bindings, status light or approvals | styles are materials on the same model and rig | Done |
| Imported models still validated; no automatic model call to browse | import goes through `models.rs`; photo is an explicit button that names the quota | Done |
| Command bar: short concrete local suggestions | "Call Byte", "Remind me tomorrow at 3 to …", "Open session", "Send Byte home" | Done |
| Settings: Appearance, Crew, Agents (tools), Privacy, Accessibility; saved/error from persistence | Window → Settings; "Saved." only after `update_settings` returns | Done |

## Motion and voice

| Rule | Where | Status |
|---|---|---|
| Control feedback 120–160 ms; card enter/exit 180–220 ms | `--motion-control: 140ms`, `--motion-card: 200ms` (bubble enter and fade-out) | Done |
| Crew entrance 400–650 ms; celebration under 1.2 s | fade-in at the spot, `--motion-entrance: 520ms`; celebrate 1.1 s | Done; hand check in app |
| Repeated "needs you" coalesces by session; light never flashes faster with more events | `Agents.announced`; pulse rate is per state | Done |
| Reduced motion: immediate changes, cards kept, no hops or pulses | `reduce-motion` class + OS media query; `Mind.calm` | Done; hand check in app |
| Voice warm and factual; no guilt, urgency theater or "I missed you" | copy pass over overlay, window and installer dialogs | Done |

## App experience (APP-UX.md)

| Rule | Where | Status |
|---|---|---|
| Click a companion: its status, with a clear Open Sidefolk | `Crew.statusCard` (also **Open session**) | Done |
| Right-click not overloaded with setup | menu: open session, type, reminder, crew, Open Sidefolk, hide | Done |
| Home window: Home, Requests, Crew, Reminders, Settings; menu bar access when hidden | `src/dashboard/app.ts`; tray "N requests waiting…" + count beside the icon | Done |
| No token counts, CPU graphs or terminal output on the first screen | Home shows attention, companions, reminders | Done |
| First minute: Welcome (Get started / Try a demo) → comfort (Friendly / Professional / Minimal, name, changes shown before Apply) → Connect when ready (real status, installer with backup, Use reminders for now) | `src/dashboard/welcome.ts`; opens on first run (`main.rs`); demo is labelled and sends nothing (`src/demo.ts`) | Done |
| Default Pip / Slate / Dot per comfort | `src/dashboard/comfort.ts`; Slate and Dot built in Blender (`penguin.glb`, `capsule.glb`) | Done |
| All 18 characters: Pip, Byte, Patch, Loom, Moss, Relay, Stack, Nib, Pico, Sora, Yuna, Kite, Slate, Dot, Calder, Finch, Orbit, Vale, each with its silhouette, signature and coat | `art/blender/build_hero.py` (one glb per body), coats in `src/pet/look.ts`, `ROSTER` in `src/routing.ts` | Done |
| Each character's first art family (Stack, Nib, Pico in Ink; Sora, Yuna, Kite in Anime) | `ROSTER` looks | Done |
| Crew recipes: Starter Studio (Friendly), Workday (Professional), Quiet Desk (Minimal) | `ORDER` in `src/routing.ts`, driven by the comfort setting | Done |
| Under 8k triangles and 2 MB per pet; no fur, cloth or textures | `DETAIL` in the build script; largest 7.4k triangles; build log prints counts | Done |
| Character first, then art family, coat, extra | the picker lists characters in their designed looks | Done |
| Home leads with what needs attention; factual status; reminders; "You're all caught up" | `src/dashboard/home.ts` | Done |
| Requests grouped by project; review shows command, folder, technical details; Decline / Allow once; locks while pending; Sent only after acknowledgement; Retry on failure; declined reported as declined | `src/dashboard/requests.ts`, `answered` event from the overlay | Done (preview) ; hand check with a live request |
| Real requests keep their own choices | questions keep the agent's choices; free questions take a written answer | Done |
| Crew: roster → appearance and bindings; collection vs art style separate; Assign project with picker + confirmation; labelled Rename; den in plain words | `src/dashboard/crew.ts` | Done |
| Reminders: labelled title, explicit date and time, resolved date and time zone before saving, edit / complete / delete with Undo, inline errors | `src/dashboard/reminders.ts`, `remove_reminder` / `restore_reminder` | Done (preview) |
| Missed reminder after sleep shows the original due time | overlay card "Was due …" | Done |
| Desktop presence: Always visible / Only when needed / Menu bar only | `presence` setting; main pet rests too (`Crew.tick`); menu bar only hides the overlay and notifies | Done; hand check in app |
| Reduce motion, Sound cues, Hide from screen recordings (qualified wording), Notification detail (Full / Project and status / Status only) | Settings; `privacy.detail` drives every card, badge and notification | Done |
| Connected tools: add, inspect, disconnect with explanation | Settings → Connected tools; installer dialogs say what changes and what stops | Done |
| Language: AI tool, project this companion looks after, resting companions, connect this tool, work session, "Connection lost. Your answer hasn't been sent." + Retry, "You're all caught up." | copy across both surfaces | Done |
| Keyboard reachable, visible focus, headings, labelled inputs, text + icon for states, real buttons and disclosures | both surfaces | Done; screen reader hand check |
| Narrow window: wrapping navigation, stacked cards; 200% zoom keeps choices reachable | `@media (max-width: 720px)`; checked at 520 px | Done |
| Focus follows navigation to the new heading; results in a polite live region | `draw(focus)` focuses `h1`; toast and review result are `aria-live` | Done |
| Card text size independent of companion size | Larger text vs Companion size | Done |

## Beyond the package: opening work sessions

The user asked that a companion can open the work session behind it. **Open session** (status
card, menu, Home, Crew, Requests, Activity, `open session` / `continue Byte`) brings a live
Claude Code session forward where it runs (Terminal and iTerm switch to its tab; Ghostty, VS
Code and the Claude app come forward), and continues an ended session or a background Codex
thread with `claude --resume` / `codex resume` in the terminal you choose
(`src-tauri/src/sessions.rs`). "Answer in Claude Code's window" defers a request and takes you
there.

## How the 2D families were made

PRODUCTION.md proposes authored sprite atlases for Ink & Geek and a 2D-first Pocket Anime,
with a renderer adapter. The Studio board (images/08) shows each character's 2D version as
flat fills under an even dark outline, which is what the shared 3D models give with flat
shading and a heavy line. So the families are renderer looks, and every character gets all 13
states in every family with no extra assets to keep in sync. Hand-drawn sprite sets remain
possible later behind the same `style` key.

## Still for people, not code

- Usability research with real people, and native screen-reader runs: listed as hand checks in
  memory/STATUS.md.
