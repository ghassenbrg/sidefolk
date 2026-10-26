# Status

Updated: 2026-10-26. Latest: asset-set preservation for the Mochi brand and Folk Family.

## Done and verified
- **Asset-set preservation (2026-10-26):** `Resources/ASSETS.md` indexes the named character,
  branding, icon, template, pose and reference sets. Preserved the three early robot generations
  previously found only in the image cache under `Resources/Brand/archive/robot/early-generations/`,
  and the user's rejected wordmark/icon examples under `Resources/Brand/reference/quality-feedback/`.
  `Resources/Brand/generated-image-index.json` records all 22 generated originals with repository
  paths and SHA-256 hashes; verified each against its untouched imagegen output. All character
  sources, comparison sheets, references and prompts remain in Git. No runtime changes or work
  left half done. Next: use the asset index when selecting or revising artwork.
- **Mochi brand rollout (2026-10-26, D29):** Mochi is the brand mascot and fresh-install default.
  Explicit saved choices, names and accents are preserved. Settings still offers the original
  Sidefolk robot with all four light colors and Spark. Replaced the production logo marks, blue
  app icon/ICNS/Xcode assets, menu-bar PNG/PDF/SVG and resource-free brand fallback with the rabbit.
  Kept the hand-authored wordmark; new family/portrait masters follow the supplied rabbit guide.
  Refined the app portrait against the close-up (tilted face, asymmetric ears, low scarf crop,
  simple blue gradient). Redrew the monochrome rabbit to follow its close-up’s ear curves, side
  paw, two rays and separated scarf tail. Native SVG/PDF/PNG share the same smooth geometry.
  All 16 Mochi poses now use white/navy/mint-aqua, graded from archived sources with exact alpha
  and dimensions preserved. The original robot rig and Spark art are unchanged. Robot brand
  masters are archived in `Resources/Brand/archive/robot/`.
  Verified 851 tests (842 core + 9 character), Xcode asset compilation, raw icon corners, vector
  templates, uncut logo bounds, all pose alpha channels, and light/dark Home/Companion snapshots
  in `build/qa-mochi-ui/` (including the robot selected in coral). Signed debug and release
  assemblies verified, including exact bundled assets and exclusion of source archives. Native
  SVG/PDF reviewed against the supplied monochrome crop in `build/qa-rabbit-vector.png`.
  Delivery: `build/Sidefolk-Mochi-brand-assets.zip`. No implementation work remains half done. Next: use
  `build/Sidefolk.app` for the founder's visual check; saved robot selections remain selectable.
- **Folk Family companion concepts (2026-10-26):** `folk-family/` contains 13 named folders:
  Sidefolk, redesigned legacy Mochi and Spark, plus Pip, Byte, Seed, Melody, Scout, Tempo, Play,
  Guard, Nova and Brew. Each has a clean transparent 1254×1254 PNG, untouched source PNG and name/
  metadata JSON. The supplied full identity sheet drives the family style; legacy Mochi/Spark
  references were recovered from `fc36151`. Includes a complete labeled `character-sheet.png`,
  `main-companions.png`, `folk-family-sheet.png`, exact imagegen prompts and references. Reviewed
  the sheets visually; verified all 13 names, dimensions, alpha, clear borders and source files.
  `scripts/companion-concept-sheets.swift` rebuilds clean exports and sheets without model calls.
  No concept-generation work remains half done. Next: the founder chooses which designs to take
  into pose sets/animation; these studies are static artwork, not installed animated skins.
- **Spec and design:** PRODUCT, ARCHITECTURE, DECISIONS (through D29), SECURITY (threat model T1–T24),
  MACOS-NOTES, VOICE, FOUNDING, CHARACTER, EXTENSIONS.
- **Character:** Core Animation rig with 11 states and 10 props, all 10 folks, app icon and menu bar
  template. Calm states settle after 20 s, loops are capped at 24 fps and pause while hidden (D20).
- **Brand assets (2026-10-26):** reference-faithful app icon (1024 PNG, ten iconset representations,
  ICNS); individual transparent stacked/horizontal logos, wordmarks and family marks in color,
  navy and white. Generated text effects and the contour trace were rejected; the flat wordmark
  now uses a hand-authored SVG following the reference, with SVG/PDF and 4096 px PNG exports.
  Native 18 pt menu template is a vector PDF plus 1x/2x/3x PNGs, bundled and loaded as an NSImage
  template through `BrandAsset`. `make brand-assets` rebuilds exports and a light/dark preview.
  Verified alpha, dimensions, SVG paths, PDF native loading, exact bundled bytes, signed debug
  assembly and visual review at native menu size and high zoom. No brand work remains half done;
  next step is the founder's visual sign-off on `Resources/Brand/preview.png`.
- **Raw icon source correction (2026-10-26):** replaced the raised-tile app icon with a clean
  transparent artwork PNG and flat, full-bleed 2048/1024 px square sources. No baked bevel, tile
  lighting, cast shadow or rounded source corners. The legacy macOS ICNS/iconset is derived with
  only a flat outline/inset. Added a drop-in Xcode asset catalog (`AppIcon`, `AppIconSource`,
  `IconArtwork`); removed the rejected rendered-tile master. Verification: source pixels/corners,
  export dimensions and catalog references, Xcode `actool` compilation, ICNS decoding and signed
  debug build resource bytes. No source work remains half done; use `Resources/Icon/icon-artwork.png`
  or `icon-source-2048.png` for the next platform export, rather than the derived macOS icon.
- **Wordmark quality correction (2026-10-26):** removed Vision contour fitting from the asset
  generator. `Resources/Brand/masters/wordmark.svg` contains 11 hand-authored letter/dot/ray paths
  with smooth outlines, straight stems and corrected f/o spacing. Color, navy and white SVG/PDF
  variants, PNGs and all six logo lockups use this master. Checked native macOS SVG rendering at
  4096 px and small sizes, vector-only SVG structure and cross-format raster agreement. No work
  remains half done; edit the master SVG for future lettering changes and run `make brand-assets`.
- **Core:** storage (GRDB, FTS5, secure_delete, 0600 files) and Guard (risk, caller, taint, user-typed
  links, hardened path policy, folder-bound command grants, approvals). Every tool input is checked
  against its schema. The executor provides audit and undo. Also attention policy and center (held
  notices survive a restart), settings, redacting logs and the runtime container.
- **Understanding:** local intent parser (reminders, notes, ideas, tasks, About you, watches, quiet,
  find) and WhenParser with recurrence (fuzz-tested: 600k random inputs, no crash), plus slash
  commands. None of these use AI.
- **Time:** the reminder scheduler fires due reminders and handles missed ones, snooze, done, edit and
  recurrence (undo keeps a monthly reminder's day). Only the user's own reminders can be critical or
  skip spacing. It reschedules after wake or a clock change, schedules fallback notifications at quit,
  and runs the morning brief.
- **Watchers:** web page change, site up/down, file appears or changes, new file in a folder, process
  exit and command (confirmed), plus extension watchers. Floors, backoff, cooldowns, quotas (checked
  atomically in the engine), SSRF protection; the user's own request may watch localhost and the LAN
  (D21). Watchers record which turn made them; other apps' watchers last at most a day. Routine checks
  reach the database at most every 5 minutes.
- **Brain:** Claude Code CLI (isolated: `--tools ""`, strict MCP, restricted settings, init-event
  check), Anthropic API and OpenAI-compatible providers. The context builder has budgets and keeps
  untrusted content out; extension tool descriptions never reach the model (D24).
- **Bridge:**
  - Unix socket API with peer-uid check, brain tokens and rate limits; a session's host app is trusted
    only if it is a real ancestor of the process that reported it.
  - `sidefolk mcp` gives external agents a small tool set (their names are labelled unverified; their
    approvals never take a keypress).
  - `sidefolk run -- <cmd>` (a failure shows the last stderr lines, D23), `sidefolk hook <Event>`
    (session tracking), `sidefolk status`, `sidefolk ext validate` (starts the program in its sandbox).
  - Claude Code and Codex installers that confirm first and keep a backup; the `sidefolk` command
    installs on PATH from Settings › Agents.
- **Extensions:** strict manifest, sandbox-exec profile, file hashes pinned and tampering detected,
  whole process tree tracked and stopped, crash isolation, MCP client and plain MCP servers. Changed
  tools are held until approved in Settings › Extensions ("Review changed tools…"). Samples: System
  Vitals and Hello Folk. Two bundled skills.
- **App:**
  - Companion window: click-through, drag and settle, on-duty folks (each introduces itself once),
    badges, gaze, presence modes, sleeping.
  - Ask panel: hint line, local intents, agent runs, inline questions, result and approval cards,
    undo, drop quick actions (Save, Remind me…, Watch, Ask…); newest request first.
  - Bubbles with a tail and buttons that never disappear; menu bar Now list; notifications; login item.
  - Home (Now with live work first, Notebook with search everywhere and ⌘F, Activity, Trash) and
    Settings (General, Companion, AI, Agents, Privacy & Permissions, Extensions).
  - Embodied onboarding (hello, agents, a real reminder, notifications, login), data export, delete
    everything (Keychain items included), diagnostics export with redacted logs.
- **Tests:** 851 in 93 suites (842 core + 9 character). `make test` runs serially (about 40 s).

## Reviews done (second round) and what came of them
UX/product, security, QA/plugin developer and performance reviews (reports were working files, not in
the repo). Everything P0/P1 is fixed; P2 polish mostly done. Security: H1, H2, M1–M10 fixed, L items
mostly fixed (details in SECURITY.md). Performance: settled desktop now costs WindowServer 0–5 points
instead of +41 on a 120 Hz display; Sidefolk itself 0.07% CPU, 24 MB; no database writes while idle.

## End-to-end checks done in the dev app (`SIDEFOLK_HOME` QA folders, `swift scripts/dev.swift snap`)
- Reminders fire on time with a bubble and the alert pose; notes and recall work without AI.
- A watch on a temp folder asked for folder access, then fired when the file appeared.
- `sidefolk run`, `status` and MCP over the bridge; a failing `sidefolk run` shows its last stderr
  lines with Copy command / Open folder; stderr still reaches the terminal (pipe and pty both checked).
- Live Claude Code brain (2 tiny haiku calls): answered a question, then saved a note and set a
  reminder in one request.
- Onboarding order, folk introduction (Scout), bubble tail, Ask panel order, notebook search across
  collections, Settings › Extensions: checked by snapshot.
- Release build (`make app`, build 212): signature verified, launches with an isolated `SIDEFOLK_HOME`,
  `sidefolk status` answers, idle measured (see above).

## In progress
Nothing. All second-round review follow-ups are merged.

## Known issues / not yet verified
- **Not exercised by hand:** hooks inside a real Claude Code session; the notifications permission
  prompt; login item from /Applications; multi-monitor and fullscreen behaviour; "Connect…" for
  Claude Code/Codex (it edits real config files, so only the user should click it).
- **Watching huge folders:** a folder with more than 20,000 items can't be watched (a bound on memory
  and stored state).
- **Following the pointer costs a little:** while the mouse moves, the global mouse monitor and Pip's
  eyes cost about 1–5% CPU in bursts; with no input the app is at ~0%.
- **Command watches made by the agent before 2026-10-26** carry the source "agent" and no longer run
  (the source can't tell a clean turn from a tainted one); recreate them. No user data exists yet, so
  this only matters for test installs.
- **Residual trust gaps (documented in SECURITY.md):** code running as you can still name its own
  ancestor or a known terminal as a session's host; extension tool names and titles (60 characters)
  reach the model.
- **Signing:** no Developer ID identity on this Mac, so `scripts/release.sh` (sign, notarize, staple)
  is ready but needs the founder's credentials. Builds are signed with the "Apple Development"
  identity or ad hoc.

## Next
1. The founder: hand checks listed above (hooks in a real Claude Code session, notifications prompt,
   login item, multi-monitor), then Developer ID signing and notarization (`scripts/release.sh`).
2. Next iteration: a human "Today" timeline with an end-of-day recap (from the strategy review);
   calendar awareness; voice input.
