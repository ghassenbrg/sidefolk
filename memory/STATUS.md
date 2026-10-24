# Status

**Standalone asset — Codex, 24 October:** User requested a 3D model of the supplied
cream bunny with charcoal ear tips and mint scarf, specifically through BlendRelay
MCP. Source: `art/blender/mint-bunny/build_model.py` and adjacent README. Deliverables
are gitignored in `output/mint-bunny/`: editable `mint-bunny.blend`, character-only
`mint-bunny.glb`, front and three-quarter Cycles PNGs. Fourteen separate static mesh
parts, four character materials, 44,730 vertices / 89,408 triangles; no rig/clips.
BlendRelay geometry validation passed for all parts (no open/non-manifold edges,
degenerate faces/edges, nonfinite vertices). GLB structure checked (no studio/cube).
The saved blend reopened successfully after Blender crashed during an export using
a temporary context override; exporting from the active scene without that override
works. Final renders reviewed. This is a separate art asset, with no app integration
or roadmap change. No commit; pre-existing Rust edits were left alone. Next step only
if requested: user art review, then rigging/animation or optimization for a target.

Last updated: 2026-10-24 18:30 by Claude Code. The roadmap ([docs/ROADMAP.md](../docs/ROADMAP.md))
is implemented through Phase 5, Phase 6 in part, plus a UI/UX pass with voices and a
dashboard, and the creative-design system applied with "Open session" (below). Nothing since
commit `b0be266` is committed. All 18 designed characters and three art styles are built. The user asked for the implementation ("implement roadmap"); commit only when asked.

## NOW (24 October, 18:30, Claude Code): read this first

Phases 0–7 of docs/PLAN-V2.md are built and committed (latest d1c0c4d + this status); phase 8 is
in progress. The user's running app is the release build from d1c0c4d (relaunched 18:27, logs
empty). Checks at that commit: typecheck, 83 vitest, 29 Rust tests, `npm run check:webkit`.
CPU of the running build ≈1.3% (app + 3 web views, 60 s).

**Blocked on the user (can't be done by an agent):**
1. Apple Developer ID keys → `scripts/release.sh` (docs/RELEASE.md step 1); updater keys and a
   release URL for auto-update (step 2).
2. Click "Allow notifications" (setup step 3 / Settings) so quit-time reminders schedule; then the
   checks in docs/REMINDER-CHECKS.md (quit, click, sleep/wake).
3. Hand checks in the real app: Settings → Connected tools → Allow… (terminal control) and Install
   (CLI); `ls -la` to Pip → Run in terminal; full access on a Claude Code session (`npm test`
   allowed, `rm -rf x` still asks); start a session; open session from Terminal / Ghostty / iTerm /
   Claude desktop; "give sidefolk a spark"; Characters import with a real drawing; notes +
   Draft a summary (one real Claude call); saved action "Run quietly".
4. Two or three colleagues for a week (phase 8 "done when").

**Fixed today on the user's report:** Mission Control desktop previews were black. Cause:
`hide_in_recordings` (content protection) on a full-screen overlay. Now off by default and
switched off once for existing installs (`recordings_reset`), with the trade-off explained.
Follow-up idea if they want both: size the overlay window to the companions instead of the
whole screen (also saves GPU).

**Phase 9 started (3d99851):** calendar heads-up. src-tauri/src/calendar.rs (EventKit via
objc2-event-kit: status, request on a blocking thread, upcoming events with video-link detection;
Info.plist usage strings), src/calendar.ts (`HeadsUp`: checks each minute while
`calendar_heads_up`, announces once with Join, "next meeting"), Settings → Calendar (asks macOS
when switched on; lead 2–15 min), Today lists next meetings. Release build 3d99851 is running.
Hand check: switch it on, allow in macOS's dialog, have a meeting with a Meet link in 5 min.

**Next for an agent (no user needed):** more of PLAN-V2 section 7 (morning brief, weekly wins
from notebooks, timers); clicking a Spark could open the field scoped to its project; a
character export as one file; sizing the overlay to the companions (fixes black Mission Control
previews even with "Hide from screen recordings" on, and saves GPU).

## PLAN PHASE: read this first (24 October, late)

The user reviewed the running build and found the UI/UX and usage messy (too many concepts,
not a real app, a "zoo" of characters with poor animation, Open session not working). They
asked to stop building and plan. [docs/PLAN-V2.md](../docs/PLAN-V2.md) is the plan; all six
section 11 decisions were made with the user on 24 October (Pip body B as personal companion,
Sparks as color-coded workers; order: reset, companion, app shell, reminders, session basics,
notes, sessions with Sparks, actions, beta; layered AI; Dock app; reset as listed; calendar right
after the MVP). Concept art for Pip and Spark is in creative-design/v2.

**Phase 0 (reset) is done (24 October).** v0.1 was committed as `9d4d52c` and tagged
`v0.1-zoo` (everything removed below is there). Then:
- One companion (`src/companion.ts` replaces crew.ts): no crew, den, wandering or walking to
  the cursor; Pip stays where it's put (drag still works). Click or right-click opens the one
  field; double-click and menus are gone. Every card has ×; requests closed with × stay in
  `Companion.requests` and the window's Requests until answered or expired.
- Commands are local only (`src/commands.ts`): remind, reminders, open session, open Sidefolk,
  rename, hide, help. Unknown text gets an answer and never reaches Codex.
- Removed: 17 characters and their Blender builders (hero.glb only), looks/coats/styles/
  accessories (look.ts), describe.ts, routing.ts, photo and glb import (models.rs), comfort
  presets, presence modes, card-detail levels, notifications plugin, demo, the window's Crew,
  welcome and Activity pages, 3D portraits, docs/CREATORS.md, docs/DESIGN-COMPLIANCE.md.
- Kept: hooks, permissions, MCP tools and installers, reminders, journal, sessions.rs (still
  has the Claude-desktop bug; fixed in phase 4), codex.rs (used again in phase 6), tokens, brand.
- Verified: typecheck, 32 vitest tests, 20 Rust tests, `npm run check:webkit`, and a WebKit
  behavior script (no movement in 40 s idle, click opens field, `ls -la` stays local, × keeps
  the request listed).

**Phase 1 done (commit 331e4a1):** Pip is 16 generated frames (art/pip, `npm run sprites`),
src/pip.ts adds breathing/blinks/hop/sway/status light; three.js and Blender removed.

**Goal set by the user (/goal):** keep working without asking until release-ready, choosing the
best option each time; stop at 95% context so the user can compact. Signing/notarizing needs
the user's Apple keys (the one step left for them).

**Phase 2 done (24 October):** Sidefolk is a Dock app (Settings → Hide from Dock), with menus
(Edit for copy/paste; View ⌘1 Today, ⌘2 Reminders; File ⌘N New Reminder lands on Reminders with
the field focused; each later section adds its own item), Reopen from the Dock, a full-height
window whose sidebar runs under the traffic lights, a "Tell Pip…" bar (src/dashboard/tell.ts)
that runs the companion's own commands and shows its reply, and a five-step setup guide
(src/dashboard/setup.ts: meet + name, try a real reminder, where it lives, AI tools (optional),
done → onboarded). First launch opens the guide; Settings → About and help → Run setup again.
Verified: typecheck, vitest, cargo test, `npm run check:webkit` (now also setup and
reminders:new). Not yet checked in the real app (release build pending; the user's release
build holds port 47821, so the dev app can't start while it runs).

**Final handoff — Codex, 24 October:** Stopped at 96% five-hour usage to stay below the
user's 97% ceiling. Four pieces committed: e6adaf4, 3eb51e4, 7629ec7, c67566f. Production
`npm run build` succeeded from c67566f (5.16 MiB), debug app stopped, release bundle reopened
from src-tauri/target/release/bundle/macos/Sidefolk.app. Only the smoke-test reminder
r1792821805766-0 was removed; existing user reminders/settings preserved. No global agent
config touched. Checks: 46 Vitest, 23 Rust (+3 opt-in skipped), live Claude-host test passed
separately, WebKit clean, Europe/Paris DST tests passed. No model calls.
Exact next steps: docs/REMINDER-CHECKS.md native permission/quit/click/sleep acceptance;
also test immediate quit after Save (OS scheduling is asynchronous). Phase 3 remains open
until those pass. Continue phase 4 local command preview/execution and session controls as
listed below, then phases 5–8. Signing/notarization and colleague beta require external input.

**Phase 3 implementation — 24 October, Codex; acceptance still pending:**
- `e6adaf4`: scheduled macOS local notifications via objc2 UserNotifications. Store-level
  scheduling covers UI/MCP adds, updates, remove/Undo; reconciles at launch. Only the next
  occurrence is queued. Permission is requested by the user's Allow button in setup step 3
  or Settings → Shortcut and startup. Unbundled dev executables skip the native API.
- `3eb51e4`: repeat picker/edit, 1–52 intervals, explicit clearing, window completion advances
  repeats. Preview stores preserve edits. Browser tests cover repeat add/edit/complete/clear,
  delete/Undo and companion key r→Save→Undo→empty list in both themes.
- Capture now previews Save / Change; Change keeps the text. Reminder Open goes to details
  and persisted history (last 50 actions). Window offers snooze; window changes clear stale
  companion requests. Voice-style offsets and date-first capture work locally.
- Verified: typecheck, 46 Vitest tests, DST tests under TZ=Europe/Paris, Rust tests, WebKit.
  Bundled debug app: hidden reminder arrived, Pip held a note, no keyboard focus theft
  (`overlay_key=false`, `unoccluded=true` in /tmp/sidefolk-native-check.log). Snooze persisted
  a future due time, reset fired, and added history. No screenshots or live model calls.
- **Native permission is `notRequested`.** Scheduling returns UNErrorDomain 1 until the user
  allows notifications. Do not mark phase 3 done: quit-time delivery/click-through and actual
  sleep/wake checks are still pending. Next native check: user clicks Allow notifications in
  setup/Settings, set a near-future reminder, quit, wait, click its notification, verify the
  details/history, then a real sleep/wake reminder. DST browser/unit checks already pass.
- Release rebuild/relaunch is in progress for this continuation; check the final handoff below.

**Phase 6 Sessions with Sparks (Claude Code, 24 Oct) — built:**
- Start sessions (7c1b22a): "start a claude session in api [with full access]" → card with folder
  and mode → `start_session` (claude / `--permission-mode auto`; codex / `-a never -s
  workspace-write`) in the chosen terminal. Window: Sessions page ⌘4 (d636865) with running,
  recently finished (Continue), New session form, Sparks.
- Sparks (2122d46, 0e675fe): src/workers.ts + src/worker-colors.ts; "give api a spark", "send the
  api spark home", Sessions → Sparks (color, look, remove). Saved in crew.json `workers`
  (project path, name, hue, look). Companion routes events/requests/notifies by project to the
  worker (`familiarFor`), status lists all companions. Spark art: art/spark (codex-imagegen,
  briefs in README), `npm run sprites -- spark`; color = hue-rotate on the frames only.
- CLI + MCP (2098137): `sidefolk here [--name X]` / `sidefolk home` (same binary; installed by
  Settings → Connected tools → Command line tool, admin prompt, /usr/local/bin symlink); MCP tool
  `spark` so agents can do it when the user asks.
- Custom characters (40e351c): public/character-template.png (scripts/make_template.py),
  src/character-import.ts (canvas: edge-connected background removal, 4×4 cells, scale to idle,
  feet line, ivory outline; only idle required, FALLBACK map), src-tauri/src/characters.rs
  (<data>/characters/<id>/pose.png + character.json; base64 in/out; save_template → Downloads),
  window: Settings → Your companion → Looks like / Make your own… (src/dashboard/characters.ts).
  Pip's look is crew.main.look; changing it reloads the overlay.
- Not tried in the real app yet: Sparks on the real desktop, CLI against the new build, look
  switching. Release build still c781432 — rebuild and relaunch before hand checks.

**Phase 5 Notes (Claude Code, 24 Oct) — built:** src-tauri/src/notes.rs (one Markdown file per
notebook in <data>/notes: `# Name`, entries `- YYYY-MM-DD — text _(project)_`; hand-written lines
kept; edits check the line still matches), src/notes.ts (companion: "note for X: …", "note: …",
"new notebook X", "notes"; picks/asks/creates the notebook; Undo card; `capture()` for reminders
about writing), src/dashboard/notes.ts (⌘3: list, search all, notebook page with add/edit/delete+
Undo, Copy as Markdown, Show in Finder, "Draft a summary…" → `draft_summary` with the user's
claude (`-p --tools "" --no-session-persistence`, empty temp folder) or codex (`exec -s
read-only`), labelled as using their plan). Reminders that mention writing ("every Friday at 4,
note what I achieved") offer "Write it now". One tiny live haiku call confirmed the claude flags.
Not tried in the real app yet.

**Phase 4 (Claude Code, 24 Oct) — built, waiting on the user's hand checks:**
- Plain commands (f4819d7): src/commands.ts `run` kind (everyday commands + PATH via
  `path_commands`; "make a note"/"find my keys" stay sentences; "run X in api" / "$ X");
  companion card "Run this in your terminal?" (Command + Folder) and the window Tell bar's
  confirm toast; Rust src-tauri/src/actions.rs `resolve_folder` / `run_command`.
- Full access per session (3ff1157): src/access.ts (`FullAccess` in overlay localStorage,
  `stillAsk` keeps rm -rf/sudo/force push/reset --hard/curl|sh/publish asking); "Allow everything
  from this session" on a request card; "Asks first / Full access" button on each session in
  Today; list mirrored to Rust (`sync_full_access`) so hooks.rs holds that session's requests for
  the companion even with a terminal in front. Codex CLI sessions in a terminal still ask in
  Codex (no hook); Sidefolk-started Codex threads get it in phase 6.
- Terminal control (c781432): "Allow…" in setup step 4 and Settings → Connected tools runs
  `allow_terminal_control` (osascript to the chosen terminal; Ghostty needs nothing).
- Release build from c781432 (5.19 MiB) relaunched; logs folder empty after launch.
- Hand checks for the user: Allow terminal control; type `ls -la` to Pip → Run in terminal;
  "run git status in sidefolk"; give a Claude Code session Full access and see `npm test`
  allowed while `rm -rf x` still asks; Open session from Terminal, Ghostty, iTerm, Claude desktop.
- Decided (user asked for a proposal, goal says choose): custom 2D characters = template sheet
  (4×4 boxes with feet line + prompt) + import in the window (cut, align, key, outline, preview
  with warnings) + only idle required (code fills missing poses) + shareable character packs;
  optional AI sheet from one picture via the user's Codex. Built in phase 6 with Sparks.

**Phase 4 started — host lookup:** CLI `.../claude.app/Contents/MacOS/claude` is skipped while
walking parents, so the real Claude desktop/terminal app is selected. Terminal/iTerm focus
reports success only when a matching tab was actually selected. macOS open failure is now
reported. Claude/Ghostty fallback explicitly says to select the session inside the app.
A live test with a running Claude desktop CLI process passed: parent resolved to
/Applications/Claude.app and frontmost bundle became com.anthropic.claudefordesktop.
No model call. Exact chat selection within Claude remains unsupported (honest fallback).
Next phase 4 work: local command preview/execution (no AI), per-session full access for
Sidefolk-started sessions, terminal/session-app defaults, Automation setup explanation,
end-to-end Terminal/Ghostty/iTerm checks. Then phases 5–8 from PLAN-V2 section 10.

- Then phases 3–8 per docs/PLAN-V2.md section 10 (detailed design notes for each are in the
  conversation summary).

- PLAN-V2 = review, direction (companion assistant, value before customization), MVP pillars
  in order (Reminders, Notes, AI sessions, Quick actions), brainstorm, keep/rework/park,
  roadmap phases 0–8 with "done when" checks run in the real app.
- Historical cause (fixed above): Open session picked the agent's own bundled binary
  (`…/claude-code/<ver>/…/claude.app/Contents/MacOS/claude`) as the host for Claude desktop
  sessions (`bundle_of` in src-tauri/src/sessions.rs takes the first `.app`), so nothing visible
  opens. Fix belongs to phase 5 (or phase 0 if the user wants it sooner).
- Everything below this section describes the build as it is (v0.1), still uncommitted.

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

Relaunch Sidefolk first (quit from the menu bar, then open the new build): the running copy
predates the design-system pass. Your data carries over; Settings → About and help → Welcome
tour replays the new first minute.

1. Welcome tour: pick Professional, see the listed changes, Apply; Slate replaces the bunny.
   (Crew → a companion → Character also offers Sheep: Loom.)
   Pick Friendly again to go back. Try a demo: Pip shows a labelled sample request.
2. Click a companion: status card with Open session / Open Sidefolk. Right-click: menu.
3. With a Claude Code session running, click **Open … session**: its terminal tab comes
   forward (Terminal and iTerm may ask once to allow automation). After the session ends,
   Continue opens `claude --resume` in your terminal (Settings → Connected tools).
4. A permission request with no terminal in front: the card reads Pip · project → Claude ·
   Work session → question → command → Decline / Allow once. Answer it from Requests in the
   window: "Sent to Claude Code" appears only after it went through.
5. Settings → Card detail → Status only: cards show no project names. Desktop presence → Only
   when needed (companions rest) and Menu bar only (no companions; a notification and a count
   in the menu bar for requests).
6. Reduce motion: no hops or pulsing light; companions appear without fading.
7. Crew → a companion → Appearance: idle and "needs you" previews, Save appearance; rename;
   Change project… asks to confirm the folder; Remove explains what happens.
8. Reminders: type "call the bank tomorrow at 10" (date and time fill in, time zone shown),
   edit, mark complete, delete and Undo.
9. Light and dark mode, Larger text, a narrow window.
10. Earlier checks still open: sounds at a comfortable volume, screenshot hiding, a reminder
    while hidden, the photo and import file dialogs.

## Open questions for the user

None blocking. Defaults chosen without asking (all changeable in Settings or the README):
crew offers only for git projects, three crew pets out at most, hide from screen recordings on,
welcome-back after 30 minutes away, Codex approvals declined after 10 minutes unanswered.

## Exact handoff / next step

- No dev app is running (stopped for the release smoke test). To run one isolated:
  `PATH="$HOME/.cargo/bin:$PATH" SIDEFOLK_DATA_DIR=$(mktemp -d) SIDEFOLK_CLAUDE_SETTINGS=<copy> npm run dev`.
- Daily-driver verification details from 23 October are in docs/PHASE1.md.
- Next step: the user's hand checks (above), then a commit when asked.
- The release bundle at src-tauri/target/release/bundle/macos/Sidefolk.app is the
  design-system build (5.40 MiB); the user's running copy is older until they relaunch.

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

## Design system applied, Open session (24 October, Claude Code)

The user asked to apply `creative-design/` "till we are compliant 100%", then (mid-turn) that a
pet can open its Claude/Codex session to keep working there, and reminded that Blender and
image generation are available. Checklist: docs/DESIGN-COMPLIANCE.md.

- Brand: Pip Signal mark from one geometry (`scripts/make_icons.py`): `art/brand/*.svg`, app
  icon, template tray icon; the old Blender icon render was removed.
- Tokens and components: `src/tokens.css`, `src/states.ts` (glyph + word statuses, card
  detail), `src/icons.ts`. Overlay restyled (`src/styles.css`), bubble cards rebuilt
  (`who`, `context`, `facts`, `note`, quiet choices), 200 ms enter/exit, fade-in entrance.
- Window rewritten as `src/dashboard/*` (five destinations, review with ack/retry/expired,
  crew with 3D portraits and live previews, reminders with explicit fields and Undo, plain
  settings with comfort presets, three-step welcome opened on first run, activity under Home).
  Old `settings-page.ts`, `dashboard-home.ts`, `settings.css` removed.
- Rust: settings `presence`, `detail`, `comfort`, `terminal`; `sessions.rs` (locate + open);
  permission asks carry `kind` and `expires` and keep commands up to 2000 characters;
  `remove_reminder` / `restore_reminder`, reminder text edits; `notify` (notification plugin),
  `answered`, `open_tab`; tray request count; plain installer dialogs.
- Characters: charcoal, terracotta and lavender coats, mint glasses; Loom (`sheep.glb`),
  Slate (`penguin.glb`) and Dot (`capsule.glb`) built in Blender; starter crew Byte, Patch,
  Loom, Slate, Dot.
- Then (user: "don't ask, work till done"): page errors from the window go to logs/page.log;
  `npm run check:webkit` (Playwright WebKit, dev dependency) loads every view in the app's
  engine and fails on errors: clean in light and dark, answer flow and overlay card included.
- Verified: typecheck, 64 vitest tests, 23 Rust tests, release build, `npm run check:webkit`,
  and in the browser preview: every window view (light, dark, 520 px wide), the review answer flow, reminder
  add/delete/Undo, the overlay permission card, status card and badge, portraits of all five
  bodies. Not verified: the running app (WKWebView, notifications, AppleScript focusing,
  `lsof` locating, presence modes); image generation was not needed (the character art is
  3D and built in Blender).

## All remaining design items (24 October, Claude Code)

User: "do all remainings". Built the twelve remaining roster characters in Blender (Moss,
Relay, Stack, Nib, Pico, Sora, Yuna, Kite, Calder, Finch, Orbit, Vale), the Ink & Geek and
Pocket Anime art styles (renderer looks, decision 34), the roster with crews per comfort style
(`ROSTER`, `ORDER` in src/routing.ts), a character-first picker with style previews, style
words in the command bar ("Byte become anime"), and the 8k-triangle budget for every model.
Verified: 70 vitest tests, 23 Rust tests, `npm run check:webkit`, contact sheets of every
character and style rendered in WebKit and reviewed against the boards, release build.
Hand checks to add: Crew → a companion → try a few characters and all three art styles; check
they read on light and dark wallpapers at the real desktop size.
