# Status

Updated: 2026-10-27. Version 0.1.0. Latest: every feature team merged into `main` (voice, live
reports, effort and real logos, approval modes, Apple Notes, built-in extensions and the extension
builder), all ten languages translated (2008 strings each), and a production review under way.

## Done and verified
- **Version 0.1.0** (`SidefolkVersion.current`); bundled extensions and the docs ask for `sidefolk >=0.1`.
- **Ten languages, translated (D28):** fr, es, de, it, pt-BR, ja, ko, zh-Hans and ar each have all
  2008 strings, plural forms included (Arabic's six). `scripts/translations.py` exports what a
  language needs, checks a file (placeholders, plural forms, fragment spaces, keys) and imports it
  (`--skip-bad` keeps what still fits after the English changed); `plural` gives a count its English
  forms. GLOSSARY.md fixes how each language addresses the person. Strings with two meanings have
  their own keys (size/risk "Medium", state/button "Done", "Watching", sky "Clear", RAM "Memory").
  "Nothing was changed." comes off a message with or without a space (Chinese, Japanese), and
  sentences and lists join as each language does (`Wording.sentences`, `Wording.list`).
  *Checked:* `--ui-snapshots --language <lang>` for it, ja, de and ar; Arabic is right to left.
- **Voice (D34):** hold ⌘⇧Space (or press and hold the companion) to talk; on-device recognition
  (SpeechAnalyzer, DictationTranscriber, the basic recognizer on macOS 15); the words go through the
  normal Ask flow; spoken replies (Off / Only when I spoke / Always) with Apple voices or ElevenLabs
  (own key); a talking mouth on every companion; Settings › Voice. Kokoro is left out (its model
  files go to ~/.cache and its v3 runtime crashed on macOS 27). *Checked:* recorded audio and
  speech-to-file round trips, the dev app at volume 0; not yet with the real microphone.
- **Live reports and frequent reminders (D35):** "every 10 seconds tell me the CPU", "temperature in
  Fukuoka every minute" (Open-Meteo, no key), web values and command output, as pills beside the
  companion and a Live section on Now; floors are raised to, never refused; reminders every N minutes
  or hours with an end. A 10 s CPU report costs 0.042% CPU against 0.036% without.
- **Effort and logos (D36):** a reasoning effort for each model slot, sent only where the provider
  and model take it (Codex `model_reasoning_effort`, Claude Code `--effort`, the API fields); real
  brand logos from LobeHub Icons (MIT), colour where the brand has it. Anthropic asks for approval of
  its marks before a public release.
- **Approval modes and away handling (D37):** Ask every time / Ask once per kind (default) / Auto /
  Full access (only through a confirmation sheet, always visible); "If I don't answer": keep waiting,
  skip the step and continue (default, 10 min, "Run it now" in Now), or stop. Waiting no longer counts
  against the run's time; "Allow for this request" covers a job's later steps.
- **Apple Notes and Reminders (D38):** list, read and copy notes into the notebook (move only with
  its own high-risk approval, into Recently Deleted); open reminders. Each part of a note is read on
  its own, so one Notes can't hand over (-1728, found on the founder's library) costs only itself.
- **Extensions without limits (D39):** built-in Git (clone, status, pull, log over https), World
  Clock, System Vitals (on) and Weather (off), installed and updated with the app; per-call folders,
  `git` by name and per-tool timeouts in manifests; icons for every extension; Sidefolk drafts an
  extension when it lacks a capability (validated, test-run with no permissions, installed only from
  the preview); `skills/sidefolk-extension/SKILL.md` for developers; the catalog study in
  docs/research/extensions-catalog.md.
- **Fixes from the founder's use:** Open session brings Claude's desktop app forward (its Claude Code
  runs from a background-only bundle) or says why it can't; bubbles lost a gritty window shadow; an
  answer that ends with a question offers Reply; Settings › Agents shows each agent's own mark.
- **Tests:** 1107 (1095 core in 131 suites + 12 character). `make test` runs serially (about 45 s).
- **Languages, app pass (D28, 2026-10-26):** every string people read in Sources/SidefolkApp, the
  character's VoiceOver words and the core leftovers (Brain replies and checks, provider names,
  Claude Code/Codex messages) is in the catalog: `make strings` finds 1681 strings, English only.
  - *How:* the shared components (SettingsRow, SettingsToggle, SettingsGroup, EmptyState,
    InlineEmpty, PageTitle, SectionHeader, Chip, Eyebrow, ChoiceRow, CommitField) take
    `LocalizedStringKey`, so literal call sites are collected as written, and `Text` otherwise
    (`Text(verbatim:)` for names, paths and words already localized; Toast shows final text).
    Models and AppKit (menus, alerts, notifications, onboarding) use `String(localized:)`. No
    sentence is built from English pieces (one key per variant); counts are one Int key with English
    one/other forms (16 more, CatalogTests checks them). The delete-everything word is localized.
  - *Watch out:* a ternary passed to an *optional* `LocalizationValue`/`LocalizedStringKey` parameter
    loses its second literal from the catalog (compiler bug): give each branch its own
    `String(localized:)` or `Text(…)`. `fixedSize(horizontal: false, vertical: true)` on text in a
    window that sizes from its content (`sizingOptions = [.minSize]`) blows up the window's minimum
    height (Activity did); keep it inside scroll views.
  - *strings.sh fix:* the build system now names module folders `SidefolkApp-p.build`; the clean step
    missed them, so a second run collected only changed files.
  - *Snapshots per language:* `swift run SidefolkApp --ui-snapshots <dir> --language fr` (any of
    the ten; `--catalog <file>` for another catalog). It relaunches itself with `-AppleLanguages`
    and, under `swift run`, compiles the catalog next to the executable for that run only. Until
    translations land, every language renders English text (dates and system controls do change).
  - *Pseudo-localization:* `scripts/pseudo-l10n.py [--language fr|ar]` renders the snapshots with a
    throwaway catalog where every value is accented and ~40 % longer (`build/pseudo-<lang>/`). Found
    and fixed: bubble and question buttons now stack when they don't fit, the Ask hint and "New
    collection" take two lines, the companion's state picker becomes a menu, narrow Activity columns
    shrink a little, the About tagline centres. Left as is: long Settings tab names push the last tab
    into the toolbar's overflow (the translator comment asks for a short "Privacy" tab name).
  - *Right to left:* AppKit mirrors an app only when the Mac reads right to left, so Sidefolk in
    Arabic on an English Mac stayed left to right. `AppLanguage.applyLayoutDirection()` (main.swift,
    before NSApplication) sets `AppleTextDirection` in Sidefolk's own defaults for Arabic and removes
    it otherwise. Checked in pseudo-Arabic snapshots and in the dev app: Home, Settings, the Ask
    panel, the Now hero (companion moves to the left) and the chooser mirror; the bubble tail stays
    aimed at the companion (`tail.x` is physical; its overlay is laid out left to right); the
    companion, folks and panel placement are AppKit frames and never mirror.
  - Verified: `swift build`; full serial suite (886 core + 9 character); English snapshots compared
    pixel by pixel with rework's (only the intended changes); pseudo-fr and pseudo-ar snapshots
    reviewed; the debug app copy with pseudo tables switched to French and Arabic with the dev
    command `language:fr`/`language:ar` (it relaunches) and back with `language:system`.
  - Left in English on purpose: model-facing text (prompts, tool results and descriptions, the
    "Dropped file:" attachment text, the last-request payload's section names), typed-command words
    ("cancel", "tell me when " prefill, "remind me in 2 minutes to stretch"), `sidefolk` CLI output,
    bridge and socket errors, extension manifest checks, logs and diagnostics, product and company
    names, the stored collection names "Inbox"/"About you" (shown localized), sample data in
    snapshots, and isolation reasons for a broken Claude Code (diagnostics detail only).
- **Design pass (2026-10-26, D31–D33):**
  - *Wordmark (D31):* `scripts/wordmark.swift` builds every letter from round-capped strokes, rings
    and a dot, fitted to `Resources/Brand/reference/wordmark-reference.png` (S 97.8 %, letters
    96–98 %; overlay and difference in `Resources/Brand/wordmark-fit.png`, `--check` regenerates it,
    `--fit` recalibrates). All wordmark/logo exports and `preview.png` regenerated; new
    `wordmark-reversed` (white "Side", aqua "folk") and `family-color` exports.
  - *Menu bar (D32):* `MochiMenuGlyph` (outline head, filled ear tips, eyes, nose; face on the 2x
    grid) replaces the shrunk monochrome mark; six candidates compared beside system symbols in
    `Resources/Brand/menu-bar-candidates.png` (`scripts/menu-bar-candidates.swift`).
  - *In the app (D33):* Settings from a gear in the Home sidebar footer and the Ask panel header
    (plus the menu bar item and ⌘,); sidebar wordmark at 30 pt opening a new About window (also in the
    menu bar menu); Now greeting card with your companion drawn by its rig and "Ask <name>…"; first
    hello shows the family; empty collections show the companion with its notepad; the Ask panel shows
    the companion's face. Audit fixes: empty Watching/Running keep their button on the line; General
    no longer repeats the companion's name (it lives in Settings › Companion).
  - Verified: UI snapshots light/dark before (`build/design-before/`) and after
    (`build/design-after/`), the debug app (Home, About, Ask panel and the real status item via
    `swift scripts/dev.swift snap`), `swift build`, full serial suite after merging rework (885 core + 9 character).
  - Not done: the founder's look at the new wordmark and glyph (its strings are now in the
    catalog). Next: see "Design next" below.
- **Languages, core pass (D28, 2026-10-26):** every string people read that Sources/SidefolkCore
  builds is in the catalog (`make strings`: 1088 strings, English only, no translations yet):
  errors, result cards, undo labels, tool titles and approval summaries, Guard's reasons, attention
  notices (reminders, watches, jobs, sessions, morning brief, away summary), hint lines, watch and
  probe wording, permission lines, extension and integration notices. What models read stays
  English (tool results, descriptions, schemas, prompts; `WatchWords.*ForModel`,
  `TimeFormat.full`/`recurrenceForModel`). API to follow: `UserFacingError("literal")` is a catalog
  key, `UserFacingError(verbatim:)` takes final text; elsewhere text is localized where it is written
  with `String(localized:)`; counts are one key with an Int, with English one/other forms in the
  catalog (CatalogTests checks them; the test runner has no catalog, so "1 items" there is expected).
  `TimeFormat.day/when/recurrence` name weekdays and months in `calendar.locale` (tests pin
  en_US_POSIX; "Dec 1" in the US) and gained "Yesterday". `Wording` formats lists and sizes in the
  words' language. `Resources/Localization/GLOSSARY.md` is the translators' brief.
  Verified: full serial suite, catalog compiles with `xcstringstool`, plural lookup checked by hand.
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
- **Tests:** 895 (886 core in 103 suites + 9 character). `make test` runs serially (about 40 s).

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
- **Production review (D40–D42):** product and design, quality/performance/security, agents (MCP
  gaps, a Sidefolk skill installed by Connect for Claude Code and Codex) and a launch kit (README,
  release notes, launch posts, press kit, CHECKLIST), each in its own worktree.
- **Lively companions:** a proof of concept on the branch `poc/lively-companions` (moments,
  postures, an idle scheduler, Liveliness Minimal/Balanced/Lively, custom companions as data, a 3D
  spike); waiting for the founder's decision. Its write-up is docs/research/lively-companions.md on
  that branch.

## Known issues / not yet verified
- **Not yet tried by hand with the real thing:** the microphone (its permission prompt, hold to talk,
  AirPods), Apple Notes on a real library after the -1728 fix, "clone … under ~/git" with a real AI,
  the menu bar's Approvals submenu and orange Full access icon, a live ElevenLabs voice.
- **Languages:** the `sidefolk`
  command line, `StatusSnapshot.sentence`, bridge protocol errors, extension manifest checks
  (`ManifestValidator`, `ValidationReport.text`) and `ExtensionError`/`MCPError` details stay English
  on purpose. Collection names stored in the database ("Inbox", "About you") stay English; the app
  shows them through `NotebookCollections.shownName`. KeyboardShortcuts' recorder has no Arabic of
  its own (it shows "Space_Key").
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
- **Extensions can't hold secrets yet**, so Git can't reach private repositories or SSH remotes, and
  connectors (GitHub, Notion, Linear) wait for it.
- **Signing:** no Developer ID identity on this Mac, so `scripts/release.sh` (sign, notarize, staple)
  is ready but needs the founder's credentials. Builds are signed with the "Apple Development"
  identity or ad hoc.

## Next
1. Merge the production review (design, QA/security, agents, launch kit), translate their new
   strings (`make strings`, `scripts/translations.py export/check/import`), and build the release.
2. The founder: decide on lively companions; try the microphone, Apple Notes and Git clone by hand;
   Developer ID signing and notarization (`scripts/release.sh`); ask Anthropic about its marks.
3. Next iteration: secrets for extensions (then GitHub and connectors), calendar through EventKit, a
   "Today" timeline with an end-of-day recap.

## Design next (from the 2026-10-26 pass)
1. A hand-drawn Mochi pose for the About window and onboarding (Mochi waving with the folks around,
   on a transparent background) would replace the family art where the companion speaks.
2. Check the hero and wordmark with each companion and in each accent colour by hand.
