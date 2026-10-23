# Status

Last updated: 2026-10-24 by Claude Code. The roadmap ([docs/ROADMAP.md](../docs/ROADMAP.md))
is implemented through Phase 5, Phase 6 in part, plus a UI/UX pass with voices and a
dashboard (below). Nothing since commit `b0be266` is
committed. The user asked for the implementation ("implement roadmap"); commit only when asked.

## Where things are

- Branch `main`, pushed to `origin/main` up to `b0be266`. Commits: `01e2f6e` Phase 0 spikes,
  `6ce076e` Phase 1 concept + panel + full-screen, `8d5197c` Blender hero + handoff setup,
  `fadac28` daily-driver pack, `b0be266` roadmap docs. The old app is the local tag `legacy-v0`.
- Phase 0 and Phase 1 logs: docs/PHASE0.md, docs/PHASE1.md (daily-driver pack and the CPU cut
  are at the end of PHASE1). The plan and its status: docs/ROADMAP.md.

## Roadmap implementation (24 October, Claude Code)

- [x] **Phase 1 exit, CPU:** 16.8% → 8.7% awake, hidden 1.0% (docs/PHASE1.md).
- [x] **Phase 2, Crew:** `src/familiar.ts`, `src/crew.ts`, `src/routing.ts`, `src/commands.ts`,
  `src/pet/look.ts`, `src-tauri/src/crew.rs`; project roots in `bus.rs`; Codex thread per
  folder + 10 min approval timeout; `hide_in_recordings` (content protection).
- [x] **Phase 3, journal and reminders:** `journal.rs`, `reminders.rs`, `src/when.ts`,
  `src/reminders.ts`, `src/away.ts`; start at login (autostart plugin); Foundation Models
  spike: `modelNotReady`.
- [x] **Phase 4, MCP:** `mcp.rs` (`sidefolk --mcp` shim, token), `mcp_setup.rs`,
  `src/agent-tools.ts`. One live Haiku call confirmed Claude Code → shim → Pip's bubble.
- [x] **Phase 5, make your own:** cat.glb and fox.glb from `build_hero.py`, customizer,
  `src/describe.ts`, photo via Haiku (`models.rs`), glb import, docs/CREATORS.md.
- [~] **Phase 6, production:** Settings window (`settings.html`, `src/settings-page.ts`,
  `prefs.rs`), first-run card, logs in `<data>/logs`, `LSUIElement`. Signing, notarizing and
  auto-update need the user's keys (docs/RELEASE.md). Windows not started.

Verification at the end: typecheck, 41 vitest tests, 20 Rust tests (+3 opt-in, all run once and
passed), web build, release build (4.83 MiB, `LSUIElement` true), release smoke test on a fresh
data folder (no page errors, journal written), `npm run measure` twice (10.2%, 7.1%).

## UI/UX pass, voices and dashboard (24 October, later)

The user asked for a friendlier UI, easy configuration, voices, and a dashboard to check
everything, "till it's prod ready". Version is now 0.1.0.

- Pets: right-click menu on every pet; command field shows what Enter will do (and when it
  costs Codex quota); suggestion chips; "New reminder…" form with a When? card; × on cards;
  dark-mode bubbles; larger text; pet size (small/medium/large); calm pets (also with reduced
  motion); keyboard focus outlines and dialog roles.
- Voices: `src/sound.ts` babble + chirps (Web Audio, tested); `voice.rs` speak out loud with
  macOS `say` (off by default). Settings: sounds, volume, speak, voice + Try.
- Dashboard (`settings.html`, tray "Open Sidefolk…"): Home (answer waiting questions in place,
  pet cards with sessions, reminders, connections), Activity timeline, Crew (call, customize,
  inline rename, two-click forget, add a pet for a folder), Reminders (natural-language form
  with preview, done, +1 hour), Agents, Settings (shortcut recorder), About & help.
- Icons: app icon rendered from the bunny (`art/blender/render_icon.py` +
  `scripts/make_icons.py`), template menu bar icon.

Verified: typecheck, 46 vitest tests, 21 Rust tests, release build 5.51 MiB, hidden smoke test
on a fresh folder (no page errors), every dashboard section looked at in the browser preview
with sample data, overlay menu and prompt previews in the browser preview, `say` checked by
writing to a file. Not heard: the babble and chirps (no audio check possible here).

## Hand checks for the user

Relaunch Sidefolk first (quit from the menu bar, then open the app again): the running copy
is the build from before these changes.

1. Listen: poke a pet, let it say something. Babble and chirps at a comfortable volume?
   Dashboard → Settings → Sound and voice: Try a voice, turn on Speak out loud.
2. Right-click a pet; double-click and type (watch the line under the field).
3. Menu bar → Open Sidefolk…: Home shows your pets live; with a permission question open
   (no terminal in front), answer it from Home.
4. The crew on the desktop with two projects; questions come from the right pet.
5. Settings: record a new shortcut, pet size, calm, larger text.
6. Hide from screen recordings: a screenshot (⌘⇧4) should not show the pets.
7. A due reminder while the pets are hidden appears, and hides again after Done.
8. Customizer Photo… and Import… file dialogs open in front.

## Open questions for the user

None blocking. Defaults chosen without asking (all changeable in Settings or the README):
crew offers only for git projects, three crew pets out at most, hide from screen recordings on,
welcome-back after 30 minutes away, Codex approvals declined after 10 minutes unanswered.

## Exact handoff / next step

- No dev app is running (stopped for the release smoke test). To run one isolated:
  `PATH="$HOME/.cargo/bin:$PATH" SIDEFOLK_DATA_DIR=$(mktemp -d) SIDEFOLK_CLAUDE_SETTINGS=<copy> npm run dev`.
- Daily-driver verification details from 23 October are in docs/PHASE1.md.
- Next step: the user's hand checks (above), then a commit when asked.

## Creative direction package (24 October, Codex)

- User requested character/crew ideas across 2D/3D/nerdy/anime, logo and design system in
  `creative-design/`, then added professional workplace characters and a friendly app UX for
  technical and nontechnical people. **User selected Pip Signal (bunny head + mint dot)** over
  the initially suggested Side by Side mark. This selection supersedes the recommendation
  printed on the first exploratory logo board.
- Added `creative-design/index.html` lookbook, 18-character JSON roster and profiles, nine
  crew recipes, six professional Studio characters with paired 2D/3D concepts, 11 final image
  assets, exact generation prompts, visual tokens, production notes and `APP-UX.md`.
- Added `creative-design/app-prototype.html` (+ CSS/JS): clickable sample onboarding, Home,
  Requests, Crew/appearance, Reminders and Settings. In-memory sample data only; no backend,
  agent execution, real notifications or native setting changes. Latest existing dashboard
  work remains authoritative; these are proposals to refine it, not shipped features.
- Selected reference preserved at `creative-design/references/selected-pip-signal.png`;
  selected standalone logo is `creative-design/images/07-pip-signal-logo.png` on ivory. An
  alpha attempt had haze and is explicitly a draft. Vector logo and character rigs/sprites
  remain future production work.
- Verified HTML/Markdown links, nesting/IDs, JSON, all image files, JS syntax, palette contrast
  and prototype state flows in a simulated DOM. No screenshot/native GUI verification;
  `creative-design/VERIFICATION.md` records scope and limits. No runtime source changed by
  this design task, no app tests rerun, no commit made.
- Next design step: review the lookbook/prototype, then choose the first character production
  set (existing trio and/or professional Slate/Dot) and translate the selected Pip Signal logo
  into production vectors. Reconcile proposed navigation/settings with the latest dashboard
  implementation before coding it. Existing app hand checks above remain pending.
