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
38. **The crew: ten characters, 3D and 2D as pictures (24 October 2026).** The user supplied ten
    reference photos (art/crew/refs) and asked for high-fidelity versions, a 3D/2D choice in
    Settings, and easier custom characters. Both styles are generated pose sheets cut into frames
    (art/crew/README.md), not live 3D: a three.js trial with the Blender film rigs looked far from
    the photos ("very bad"), while generated sheets match them closely, cost no GPU, and keep one
    pipeline for built-in and made characters. Spark colors turn only the shared mint accent
    (src/recolor.ts). Made characters import from per-pose files or any sheet grid, found by the
    space between poses. Would change if real-time customization (gadgets on bones) becomes a must;
    then a gadget layer anchored to the frames is the next step before any 3D runtime. Supersedes
    decision 36's "Pip (2D, body B)" character art; Pip is now the photo's bunny.
39. **v1 release contract (25 October 2026): [docs/V1.md](../docs/V1.md).** After two independent
    eight-seat audits (Claude: docs/audit-2026-10-25-claude/, Codex: docs/audit-2026-10-25/) a
    three-seat supreme council (CEO, CTO, CPO) ruled; the user told the agents to implement it.
    Developer-led v1 with a gated everyday path; one Pip (ivory clay, 3D only, logo unchanged);
    Sidefolk never answers a request itself (full access deleted); plain English never becomes a
    shell command (`$` only, Labs, off by default); stores never lose data (store.rs); state
    moves into Rust before the window is re-implemented against the approved mockups. V1 §15
    lists the earlier decisions it reverses (#21, #36 parts, #38, the terminal, TTS, accent,
    morning brief, CLI). Supersedes PLAN-V2 §6–10 and ROADMAP as the plan. Changes only through
    V1 §13 (one in, one out, founder's yes).
40. **Bare hours (V1-Q3) differ for one-offs and repeats.** A one-off "at 9" is the soonest
    09:00 or 21:00 between 07:00 and 21:59 (the other reading is kept as `alternative` for the
    P3 choice UI); a repeat keeps working hours (1–7 is the afternoon), so "every weekday at 9"
    stays 09:00. A date-only reminder whose 09:00 already passed asks when instead of saving a
    past time.
41. **Pip and Spark are always there (founder, 25 October 2026).** "For Spark character and Pip,
    they should be there always, whatever the decision was." Your companion is Pip (default) or
    Spark, chosen in Settings → Companion (crew.json `main.look`); both are 3D clay frames with all
    16 poses. Spark's status light follows its antenna tip per pose (src/pip.ts `tip`). Overrides
    the ruling's "Pip only" (V1 F-24, V1-C1, C8). Spark *workers* per project stay LATER (F-19)
    unless the founder says otherwise.
42. **P1 foundation choices (25 October 2026).**
    - `tauri-plugin-single-instance` is added (V1-X15): a second launch opens the running app's
      window instead of a second copy fighting for the hook port. This is the dependency line
      guardrail 6 asks for.
    - Permission requests live in Rust (`requests.rs`), not the overlay. Window answers go
      straight to Rust (`resolve_permission`, which says why it refused).
    - Pip's card shows Allow only when the whole operation fits on it (12 lines, 600
      characters); a longer one offers "Review all of it" in the window.
    - Opening a session releases its waiting requests to the session's own prompt.
    - No status polling: the overlay publishes on change, and the window refreshes on focus and
      on events (`integrations-changed` from `tray::refresh`, `requests`, `status`,
      `settings-changed`, `reminders-changed`, `notes-changed`).
43. **UI/UX team design proposal (25 October 2026, founder requested an open rethink).**
    `creative-design/review-2026-10-25/` contains the workday-desk direction, 34 image boards,
    editable prototype, system/behavior/implementation handoff and verification. Keep the logo,
    Pip/Spark, palette and v1 scope; recompose Today as attention + agenda + dated writing and
    keep Settings separate. New screen references and 13 CSS px window text are explicit design
    proposals, not silent amendments to V1-U2/U7 or a release-gate sign-off. The founder requested
    a developer-ready package; production implementation remains P5 after the planned state
    foundation. This adds no feature or dependency and supersedes no production approval yet.
43. **P2 reminders and work log (25 October 2026).**
    - `jiff` is added (guardrail 6) because Rust's standard library has no time zones. Series
      math is local wall-clock time across DST (`series.rs`): a skipped time fires at the next
      valid minute, a doubled time fires once.
    - A reminder now keeps three times: `anchor` (the series' first occurrence; it moves only
      when the series is edited), `occurrence` (the current one, before any snooze) and `due`
      (when it fires next).
    - Done and Skip move to the next occurrence counted from the anchor, never from a snooze.
    - Every 20 s, `tick` records an occurrence that came and went unanswered as Missed and keeps
      only the latest one.
    - macOS holds up to 60 alarms (`queue`), with ids `reminder-<id>@<ms>`.
    - The overlay and window answer through `answer_reminder`. The TS `nextDue` is now used only
      for previews.
    - Work log: "note:" and "log …" go to Log. Notebook names must match exactly; otherwise
      Pip offers the near names, a new notebook or Log, and never guesses.
    - `move_note` writes the entry to the target before removing it from the source.
    - Your week replaces the weekly wins summary; Log it stores only the project and the first
      prompt line.
44. **P3 Quick add (25 October 2026).**
    - **Corpus.** `src/corpus.test.ts` holds 300 phrases (150 everyday, 100 developer, 50
      adversarial), run on a fixed clock in Paris and Tokyo plus a DST night. It is 100% on the
      phrases as written, which the agents wrote. Real misses from the beta get added as lines.
      `CORPUS_REPORT=1` prints the score.
    - **Precedence.** `$` comes first (`$ echo tomorrow at 9` is a command), then small talk:
      about 20 replies in Pip's voice, kind `chat` with a pose.
    - **Bare hours.** A bare hour's `alternative` is the other time of day, never the same hour
      on another day. The companion and the window offer both as buttons.
    - **Same surface.** The window's Quick add finishes reminders, notes, navigation, opening
      things and small talk in the window. Only rename and hide go to the companion.
    - **Weekday lists** ("every Monday and Thursday") are `Repeat.days`, in Rust and TS. The
      form keeps them.
    - **Reminder form defaults** are the next full hour, or tomorrow 09:00 outside 07:00–21:59
      (B7).
45. **P4 Claude Code trust (25 October 2026).**
    - **Transport.** Hooks and MCP calls reach the app over `<data>/hook.sock`: folder 0700,
      socket 0600, and the peer must be the same user. TCP 47821 now only serves legacy HTTP
      hooks and the dev endpoints.
    - **Hook line.** Claude Code runs
      `test -x '<exe>' && exec '<exe>' hook || exit 0 # sidefolk-hook`, which is Sidefolk's own
      binary in hook mode, not a separate `externalBin`.
      - One signed binary, nothing extra to notarize.
      - Hook mode runs before Tauri starts (about 10 ms) and fails closed: no app, a deleted app,
        bad JSON or a malformed answer means it prints nothing and exits 0.
      - The `# sidefolk-hook` marker is how setup tells current, legacy (HTTP) and needs-repair
        (moved app) apart. Setup refuses a translocated app.
    - **Routing.**
      - A request is held on Pip unless the user is looking at that session. Terminal and iTerm
        check the tty of the selected tab.
      - Ghostty, WezTerm, VS Code and Cursor count only if they are in front and host exactly
        one live session; Warp, the Claude app and tmux never count.
      - While a request is held, a 500 ms watch releases it (no answer printed) when the user
        goes to that session. The card closes with "Moved to your terminal".
    - **Health.** off / waiting (connected, nothing heard yet) / working / repair / unavailable
      (the socket couldn't open), with Repair in Settings.
    - **Uninstall.** In the window, the menu bar, and `sidefolk uninstall [--delete-data]`. It
      removes only our marked hooks and our MCP entries (with backups) and the login item. Data
      goes to the Bin only when asked.
      - Everything it touches is passed in (`uninstall::Places`), so tests never reach real
        files.
    - **Accepted after Codex's review:**
      - The trust boundary is the user account. The hook doesn't authenticate the process
        answering on the socket (a same-user process could edit Claude's settings anyway); it
        only accepts the exact answer shape.
      - Putting an older Sidefolk at the hook's path makes hooks start that old app; Repair
        notices a moved app, not a downgrade.
    - **Spikes:** docs/SPIKES-P4.md. Codex has stable, documented hooks, including
      `PermissionRequest`, which can answer. V1-D2 ("Pip never answers Codex approvals") stands
      until the founder decides.

46. **P5 Window and Pip (25 October 2026).**
    - Separate native Preferences (`preferences`); the existing `settings` window label remains
      the main app for compatibility. Both use settings.html, with explicit routing. Existing
      capability covers the second window; no dependency, entitlement or new permission.
    - Four Settings panes; aliases keep old deep links working. Claude hooks and MCP share one
      confirmed, backed-up connect/repair/disconnect flow. A durable pending-disconnect bit is
      saved before edits so failures and restarts cannot reverse the user's choice.
    - `window.css` replaces both old window stylesheets. Desktop controls use 28px targets and
      the contracted 13pt base; the newer 13 CSS px proposal has not been adopted. Overlay stays
      44px. Overflow menus, sheets, radio controls and failure states share the kit.
    - Undo survives navigation and later messages until used/dismissed; it awaits success and
      remains retryable on failure. It is scoped to the open webview, not persisted across quit.
      Notebook capture drafts survive navigation. Native text Undo keeps its normal meaning.
    - Summon focuses Quick add and preserves an already open draft. Reserved ⌘⇧Return focuses
      the newest card's container, never Allow. Rebinding summon never removes that shortcut.
    - Setup requires one saved reminder, then explicit desktop choices; Claude connection
      completion requires a real first event. Skip remains available. First-heard emits health.
    - New installs start Quiet. Default snooze is configurable and used on both surfaces.
      Journal policy is seven UTC calendar days, first prompt line only (500 characters), no
      tool/answer/output detail, with an off switch and confirmed Clear. Old records expire or
      can be cleared; no claim that old records were rewritten.
    - Errors use `voice.ts`; native installer dialogs use short static recovery copy and log
      raw diagnostics. Idle/listening/puzzled have no agent activity light.
    - Puzzled reuses the approved folded-ear listen frame with a distinct tilt/behavior;
      no new raster poses or six-frame quota. Pose fades, gaze and breathing supply movement;
      reduced motion changes immediately. Both Pip and Spark stay. The permitted six extra
      micro-frames remain a cap, not an obligation to regenerate the frozen artwork.
    - Recording protection stays off while the founder's Mission Control spike is pending;
      setup exposes the choice. Browser screenshots are evidence of layout only, not G4/G2.
47. **Founder adoption and agent control (25 October 2026).** The founder explicitly requested
    implementation of review-2026-10-25, replacing the old layout references and adopting its
    scoped 13 CSS px window density (overlay remains 16px/44px; larger text scales accessibly).
    Also authorized companion/Sidefolk control through MCP plus a portable agent skill, and
    economical parallel implementation through release readiness. Read/control/capture tools
    retain Rust state authority; no tool may approve agent requests, run shell or change global
    integration configuration. Integrations/skill installation remain explicit app confirmations.
48. **P6 release dependencies.** The v1 contract explicitly calls for the Tauri updater plugin,
    signed updates and a minimum-safe-version kill switch. Add the official updater dependency
    and matching build capability only for that release flow; direct semver supports typed,
    monotonic minimum-version policy and its versioned persistence. Signing/notarization keys and
    credentials must be supplied through normal local keychain/CI secret configuration, never
    invented placeholders presented as working or committed private keys. Missing credentials
    are a release blocker, not a reason to claim a signed build.

49. **Codex status and portable skill (25 October 2026).** F-14 uses documented Codex lifecycle
    hooks through an event-only `hook-codex` mode of the signed app binary. It always exits zero
    without printing decisions; PermissionRequest becomes only a needs-you status/Open action.
    Native-confirmed installation edits only marked hooks in CODEX_HOME/hooks.json, takes exact
    backups, rejects stale confirmation snapshots and translocation, and requires manual /hooks
    trust. MCP tools and skills connect independently. Skill provenance is allowlisted and
    durable; uninstall restores initial files, preserving user edits and conflicts for retry.
50. **Release review corrections (25 October 2026).** Quarantined update policy remains blocked
    across later restarts even without an active file; a stale lower feed cannot reset its floor.
    Missing Codex hook files snapshot the canonical existing parent to detect profile-link
    retargeting. Native uninstall confirms separately, stays open on incomplete cleanup, and
    reports its actual quit status. Integration/history/recovery commands are window-scoped;
    overlay Hide uses its own restricted command. No new dependency or broader permission.
51. **Reload continuity (25 October 2026).** Native memory retains a bounded, typed snapshot of
    session first prompts/latest states/outcomes. Rehydration is silent and preserves timestamps;
    changing Pip/Spark or size does not replay notifications or lose the session display. Pending
    MCP questions retain their payload and deadline in Rust, survive an overlay reload, reject
    late replies and cap concurrent calls. Notify/remind are never replayed as side effects.
    Ask shows an explicit deadline and supplied session identity (or says none was supplied).
    No transcript parsing, disk history expansion, background model call or dependency.
