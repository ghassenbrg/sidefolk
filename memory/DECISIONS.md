# Decisions

Newest last. Each entry: what, why, and what would change it.

1. **Start over (Oct 2026).** The Electron dashboard app was a chat/to-do app with a pet
   sticker. Kept at tag `legacy-v0`; nothing ported but ideas.
2. **Product: an agent familiar.** The pet is the body, face and router for the user's agents,
   not an agent itself. It never replaces Claude's or Codex's own UIs; it links into them.
   Developers who run agents come first.
3. **Stack: Tauri 2 + TypeScript/three.js, thin Rust core.** Measured 3.65 MB app, 111 MB, 0.4%
   CPU hidden vs Electron 334 MB, 322 MB, 6.3%. The pet's mind lives in TypeScript; Rust only
   does windows, cursor, processes, sockets.
4. **macOS first,** Windows second.
5. **Observe agents with hooks, drive them with native protocols.** Claude Code HTTP hooks to
   127.0.0.1:47821; Codex through `codex app-server`. ACP is the planned adapter for other
   agents.
6. **Overlay = non-activating NSPanel** (`tauri-nspanel`) on every Space, click-through except
   on the pet's mesh and bubble. Keyboard focus only while typing in the bubble.
7. **One hero character:** an ivory chibi bunny with charcoal points, mint scarf, and a floating
   status light. Spec and rig contract in `art/HERO.md`.
8. **Character pipeline: Blender script → glTF.** `art/blender/build_hero.py` builds mesh,
   vertex colors, armature and actions headlessly and exports `public/models/hero.glb`. The
   script is the source of truth for the model and its clips until an artist takes over the
   `.blend`.
9. **Shared memory in `memory/`** so any agent can pick up the work.
10. **Daily-driver defaults (implemented 23 October 2026):** global shortcut ⌘⇧Space toggles hide / show at
    cursor; sleep after 2 minutes of OS idle time; Claude Code hooks installed into the user's
    global settings only from a tray click with confirmation and a backup. **Permission hold
    policy:** when a terminal, IDE or the Claude app is frontmost, that app asks at once; otherwise
    the pet holds the request for up to 60 s. Reason: global hooks reach every session, and a
    stalled terminal prompt would be worse than no pet.

11. **Installer preserves other integrations.** Use ordered JSON, remove only handlers pointing
    at Sidefolk's localhost URL prefix, back up exact bytes before atomic replacement, and refuse
    stale confirmations. Tests target a copy via `SIDEFOLK_CLAUDE_SETTINGS`; only a user's confirmed
    tray action may write real global Claude settings. Foreground lookup failure defers permission
    immediately, so an AppKit scheduling problem cannot stall the agent's own prompt.
12. **Direction: a crew (23 October 2026).** A main pet plus one crew pet per project or agent,
    shown in [docs/ROADMAP.md](../docs/ROADMAP.md). Reason: with several sessions running, the
    hard part is knowing which one is waiting; a pet per project can be recognized at a glance.
    A crew pet's mood shows its project's state. Idle crew pets wait in a den; at most three are
    on screen. Would change if daily use shows one pet with a sessions list works as well.
13. **Bindings.** Projects (git root of `cwd`) and agents (`source`) are the stable things to bind
    pets to; a session binding is a one-off that ends with the session. The most specific wins:
    session, project, agent, then the main pet. Every question names the pet and project in text,
    never by color alone, so the wrong session cannot be approved by mistake.
14. **Custom pets come from a species kit, not from images.** All species share the 15-bone
    skeleton and 13 clips; customization is colors per region, accessories and name. "Describe
    your pet" (text or photo → a vision model picks kit settings, once) is the AI part; glb
    import for creators. The first crew pets are the bunny in different colors and accessories;
    new species come later. Reason: image-to-3D output does not fit the rig and breaks the
    animations. Would change if image-to-3D can produce our rig reliably.
15. **Developer work first, no quota by default.** Projects, agents and PRs come before general
    tasks such as weather checks, which return later as routines or plugins. Commands and
    reminders are understood locally (grammar and date parser, then Apple's on-device model); an
    agent is used only when the user asks.
16. **Shared memory is small, local and per project:** pets, bindings, a journal of agent events
    (30 days), reminders and a few facts about the user, in SQLite. It is not an agent memory and
    does not compete with CLAUDE.md or Codex's. Agents reach the user through a Sidefolk MCP
    server (notify, ask, remind, presence), installed with the same confirm-and-backup rules.
17. **CPU before crew.** One visible pet measured 16.9% CPU. The budget is under 5% for everything
    on screen; Phase 1 ends by cutting the single pet's cost before Phase 2 adds more pets.
18. **One small canvas per pet, not one shared renderer (24 October 2026).** Each pet draws into
    its own 320 px WebGL canvas that follows it. Pets stand far apart, so a shared canvas would
    have to cover the screen, and compositing that costs more than a few small ones. At most four
    are drawn (main pet + three crew); pets in the den draw nothing. Measured with the crew
    code and one pet out: 8.7% (two runs), the same as before. Several pets out at once has not
    been measured. Would change if many more pets are on screen at once.
19. **Small local files, not SQLite.** crew.json and reminders.json are written atomically; the
    journal is one JSONL file per UTC day, kept 30 days. The data is small, nothing needs queries,
    no native database dependency, and the user can read every file. Would change if briefings
    need real queries across months.
20. **A hidden pet comes back for a due reminder** (Rust `peek`, not saved as un-hidden)
    instead of a native notification: the user asked for the pet to appear and remind, and it
    needs no notification permission. Reminders fire through the project's pet when it has one.
21. **No token on the hook endpoint, yet.** Browsers are already refused (Origin and
    content-type checks), any local process that could forge a request could also read a token
    file, and requiring one would silently break hooks installed earlier. The MCP endpoint does
    require the per-install token (`<data dir>/token`, 0600) because it accepts questions and
    reminders. Would change when the hook installer can upgrade existing installs.
22. **Agent configs change only through the agents' own CLIs** (`claude mcp add --scope user`,
    `codex mcp add`), after a confirmation and a byte-for-byte backup of the file they edit;
    status is read from that file. Their formats and locations are theirs to change.
23. **Custom pets = species glbs + runtime recolor + accessories.** Species share the
    skeleton, clips and palette colors, so palettes recolor the same vertex colors on all of
    them. "Describe your pet" is local words first; a photo goes to Claude Haiku only when the
    user picks one. Imported glbs must pass the loader's contract check; a missing one falls
    back to the bunny. Settings live in a Settings window; the tray keeps everyday items.
24. **Pets have voices, made on the fly (24 October 2026).** Talking babbles soft Web Audio
    syllables (pitch per species and name, rising on questions) and reactions chirp; no sound
    files. On by default at 60% volume because the user asked for the pets to feel alive; one
    switch turns it off. "Speak out loud" (macOS `say`, any installed voice, pitch per pet) is
    off by default: agent text read aloud in an office is a surprise nobody wants.
25. **One window: the Sidefolk dashboard.** Home (waiting questions answerable in place, pets
    and sessions, reminders, connections), Activity, Crew, Reminders, Agents, Settings, About.
    The overlay publishes a live snapshot (`publish_status`, sent when it changes, checked once
    a second); the dashboard never changes crew.json or answers questions itself: it asks the
    pets (`pet_action`), so a dashboard answer runs exactly the code a click on the pet runs.
26. **Discoverability over memorizing.** Right-click menus on every pet, suggestion chips, and a
    line under the command field saying what Enter will do, including when it spends Codex
    quota. The user's first try sent a request to Codex without meaning to.
27. **The creative-design package is the UI's design system (24 October 2026).** The user
    asked for 100% compliance with `creative-design/`. Tokens (`src/tokens.css`), one status
    vocabulary (`src/states.ts`), the permission card order, 44 px targets, 3 px focus rings,
    motion timings and the copy table apply to both the overlay and the window.
    docs/DESIGN-COMPLIANCE.md is the checklist; new UI must keep it true.
28. **Pip Signal replaces the rendered bunny icon.** One geometry in `scripts/make_icons.py`
    draws the SVG masters, the app icon and the template menu bar icon; the window inlines the
    same shapes so the mark follows the theme.
29. **Five destinations: Home, Requests, Crew, Reminders, Settings.** Activity moved under Home,
    Agents and About into Settings. Appearance is edited in the window (idle + alert previews),
    so the bubble customizer and its chips are gone; quick commands ("wear glasses") remain.
30. **Companions fade in where needed (520 ms) instead of walking across the screen.** The
    spec's crew entrance is 400–650 ms; a walk from the edge took seconds. Supersedes the
    walk-on part of 12. Reduce motion makes it immediate and drops hops and pulses.
31. **Desktop presence and card detail.** Presence: always / only when needed (the main pet
    rests too) / menu bar only (overlay hidden, requests counted in the menu bar, macOS
    notifications, the only place Sidefolk notifies). Card detail: full / project and status
    / status only; the window always shows everything, and with less detail a pet's request
    card offers Decline / Review… instead of Allow.
32. **Starter crew Byte, Patch, Loom, Slate, Dot; roster names stay with their designs.**
    Loom (sheep, lavender coat) completes the package's recommended Starter Studio crew.
34. **All 18 characters, and art styles as renderer looks (user: "do all remainings").** The
    twelve remaining roster characters are Blender forms on the shared rig. Ink & Geek and
    Pocket Anime are materials (`STYLE` in src/pet/model.ts), not sprite sets: the Studio
    board's 2D versions are flat fills under an even line, which the 3D model gives directly,
    with all 13 states. `look.style` defaults to soft, so old crew.json files need no migration.
    Soft 3D became a smooth matte gradient so the three families differ at a glance.
35. **Crews follow the comfort style; meshes fit the budget.** New companions come from the
    style's crew (Starter Studio, Workday, Quiet Desk), then the rest of the roster, then plain
    names. Every sphere and ring is built at 55% of its written segments (`DETAIL`), keeping
    each pet under 8k triangles (the bunny was 18.6k). Slate
    (penguin) and Dot (capsule) were built in Blender on the shared rig so the Professional and
    Minimal presets are real. Later companions get plain names, not Finch/Loom/…, whose
    designs don't exist yet. Ink & Geek and Pocket Anime show "Coming later".
33. **Open session (user request).** Hook requests' TCP peer port → `lsof` → process tree →
    hosting app and tty, once per session. A live session is focused (Terminal and iTerm pick
    the tab via AppleScript); ended sessions and Sidefolk's background Codex threads resume in
    a terminal (`claude --resume`, `codex resume`). Session IDs are checked and paths quoted.
    A busy Codex thread is not resumed, so it never runs twice.
36. **v2 direction (24 October 2026, with the user): see docs/PLAN-V2.md section 11.** Sidefolk
    becomes a companion assistant: Pip (2D, body B) personal, Sparks color-coded workers per
    project/session; a real Dock app with parity between app and companion; MVP order reset →
    companion → app shell → reminders → session basics → notes → sessions → actions → beta;
    plain rules before any AI, then on-device, then the user's Claude/Codex; plain commands
    never go to AI; per-session full access. Supersedes the character and UI decisions 12, 27–35
    where they conflict.
37. **UI/UX redesign approved (24 October 2026).** The user approved
    `creative-design/review-2026-10-24/` for implementation, with the current logo
    unchanged and System/Light/Dark in Settings. Everyday navigation first;
    optional AI sessions; list-first creation flows; persistent action review;
    searchable, categorized Settings with all supported configuration reachable.
    Use existing tokens and status words in both app and overlay. System is the
    default theme, overrides persist, native appearance and cards share it.
    This approval supersedes the review package's earlier pending-review notes.
