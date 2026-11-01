# Status

Updated 2026-11-01. What is true now, what is being worked on, what is missing, and how to check it. What was built
before, and how each piece was verified at the time, is in [HISTORY.md](HISTORY.md), newest first.

## Where Sidefolk is

Version **0.1.0**, not released: everything published is a snapshot (D62 amended, D65), and the version stays 0.1.0
until the founder releases it. The latest is **snapshot 661** (2026-11-01, signed and notarized, on GitHub Releases),
with the Lantern revamp (D84, all five phases), the games look and the four puzzles (D79 amended).

- **On the desktop:** the companion (Mochi or Spark built in, 3D or 2D; eight more from the gallery) stands on its
  light pool, which shows its state (working, waiting with a count, Focus, Quiet). Everything it says is the
  **Sidecard**: whispers, cards that fold into the count, Ask (⌘⇧Space or a click) with its understanding row, and
  permission slips for approvals (firm ones never take Return). Pins (live values) and the agents lane sit beside
  it. The **Play panel** holds Playtime's eleven games and four puzzles.
- **Home:** Today, Calendar, Notebook (with You and the Trash), On duty, History, extension pages arranged by the
  person, and the **Gallery** (companions, extensions, themes). The Say bar (⌘K) is in the toolbar.
- **Settings:** eight tabs with search: General, Companion, Attention (Open, Focus, Quiet, quiet hours), Brain (AI
  and voice), Trust (approval modes, Full access with an end), Connections (Claude Code, Codex, other MCP clients,
  the `sidefolk` command), Add-ons and Appearance (theme, light or dark, density).
- **The menu bar** is the Pocket, a popover with the state, the Open/Focus/Quiet dial, Needs you, Next up, Agents
  and Ask.
- **Themes dress the app only** (colours, faces, density, materials, the light): four, all built in (D92): Harbor
  (Lantern, the default), Paper Garden (warm paper and wood), Night Studio (indigo dusk) and Marshmallow (candy
  clouds); retired ones move to their successor. New themes start with the `sidefolk-theme` skill.
- **Without AI:** notes, reminders, watches, live values, the calendar, search, games and extension commands. With
  the AI the person picks (Claude Code, Codex, an API key, Ollama or LM Studio), everything else, through Guard.
- **For other agents:** `sidefolk mcp` and the skill Connect installs (D42, D52); session hooks tell the person when
  Claude Code or Codex needs them (D12 amended).
- **Ten languages** for everything people read, extensions included (D28, D76).

**The add-on gallery** (github.com/ghassenbrg/sidefolk-addons, release `gallery`): companions Ember, Kiko, Nimbo,
Folio, Iris, Nori, Purl and Rune; extensions Git, Currency, Playtime, Images, PDF Tools, QR Codes, Archives, Dev
Toolbox, Feeds, Your Mac (System Vitals+), Clipboard, Keep Awake and Miraya; the three themes. Every add-on is in
snapshots. **Playtime 1.0.0-snapshot.5** needs Sidefolk snapshot 661 (its puzzles; older copies keep the version
they have, D83); **Miraya 1.0.0-snapshot.4** needs snapshot 593 (`output_mute`, D81).

## In progress

- **Calendar v2** (branch `team/calendar-v2`, not merged; D97): the Calendar works like a Mac calendar. Each calendar's
  own colour (contrast-checked fill, edge and text, lightness only), Sidefolk's reminders, tasks and routines as
  calendars of their own, a sidebar with a month and the calendars to show or hide (remembered, and hidden everywhere);
  Agenda, Day, Week, a Month that scrolls on row by row, Year; events say what their size has room for, all-day bars
  across days, overlaps side by side with "+N"; ⌘← ⌘→ ⌘T, two-finger swipes, pinch for the hour's height, arrows,
  Return and Delete; a double-click or a drag over empty time opens an editor (reminder, task in a collection, or
  event); dragging moves, an event's edge resizes, ⌘Z undoes; a details popover (Maps, people invited, notes, Open in
  Calendar). The Mac's events change through `calendar.create`, `.update` and `.delete` once the person allows it (a
  sheet, or Settings › Trust › Your calendar), never meetings with people, read-only calendars or whole series
  (SECURITY T34). Verified: `make test` (1720 + 38) with a clean add-ons clone, `CalendarPageTests` and
  `CalendarWriteTests`, UI snapshots (calendar views, details, editor, sheet) in light, dark, de and ar, and the debug
  app on `SIDEFOLK_SAMPLE_CALENDAR=1` driven by the new `calendar:` dev commands: drag-create with typing and Return,
  moving an event (the sheet, then ⌘Z), keyboard selection and details, Delete and ⌘Z, a swipe and a month scroll
  filmed, 3,000 extra events (a week of 522 read in 4 ms, idle CPU unchanged). Not tried: a real trackpad and pinch by
  hand, and the person's own EventKit data (the debug build has no calendar access; it ran on the sample). Next: merge.

- **Docs cleanup** (branch `team/docs-cleanup` in both repositories, not merged): every doc, README and skill
  brought to the app as it is after D84; this file split into STATUS and HISTORY; finished plans removed.

- **Desktop polish** (branch `team/desktop-polish`, not merged): cards answer from the keyboard (⌃⌥Space), Ask's
  tabs and "Open in History", the drop card, the stack's arc and the voice's light, VoiceOver on the companion's
  corner (D84's note); Ask tidies itself by each result's weight, agents grouped by folder (D90). Verified with
  `make test`, UI snapshots (light, dark, de, ar) and the debug app. Next: merge; try ⌃⌥Space on a Mac whose input
  sources don't take it, and VoiceOver by hand (an AX client this Mac's tools aren't allowed to be).
- **Safety and correctness** (branch `team/safety`, not merged): a copy on any `SIDEFOLK_HOME` writes agent-config
  stand-ins in `<home>/agent-configs/`, never the person's Claude Code, Codex or `~/.local/bin/sidefolk` (D86, ported
  from a branch that never reached main); `connect:`/`disconnect:` dev commands; the audit's F12 rule (links open only
  as web pages) on release notes and extension errors; the QA branch's last four tests. Verified: full suite green
  (1626 + 38 tests), and a debug app on `build/safety-1` connected and disconnected both agents and the command
  while the real files kept their mtime and SHA-256. Next: merge.
- **Add-on updates in sight** (branch `team/addon-updates`, not merged, D89): the Gallery's Updates with Update all
  (per-item progress, "3 updated, 1 needs your review", widening ones stay with Review…), an extension page's
  "Update available" strip with What's new, Settings › Add-ons inline "New version · Update" and an Update all card,
  Home's sidebar dot and count, Today's one row, the Pocket's Needs you, a whisper after a day with the switch off.
  Verified: `AddonUpdateAllTests` (5), full suite, snapshots in light, dark, de and ar, and a debug app on a signed
  local gallery (two extensions and a companion, one widening): Update all updated two and left one for review.
  Next: merge.
- **Watch history** (branch `team/watch-history`, not merged, D87): every check of a watch logged as runs, the last
  two versions of a page's or file's text, the watch's own page in Home (what changed inline or side by side, its
  timeline, Check now, Pause or Resume, Stop) and On duty's bars of the last 24 checks; `watch.list` says when each
  last changed. Verified with tests (migration, runs, versions, pruning, Your data), snapshots `window-home-watch*`
  and `window-home-onduty*` in light, dark, de and ar, and the debug app with a local file changed twice and a page
  on `python3 -m http.server` edited once. The branch also carries origin/main (snapshot 673, D86) and
  `team/interrupts` (D88, below), merged and tested together; the watch's Check now has its own key
  (`watch.checkNow`: "Jetzt prüfen", not Updates' "Jetzt suchen"). Next: merge into main.

- **What may interrupt you** (branch `team/interrupts`, not merged; D88): a level per source (Card, Whisper, Only in
  Today, Off) in Settings › Attention, applied before Focus and Quiet; "Fewer like this" and "Show these as whispers"
  in a card's ⋯ with Undo; Today's Kept for Today; "done today" counts only what changed something. Built, tested
  (`InterruptionsTests`, `InterruptionsCenterTests`, `DoneTodayTests`), snapshots read (`page-settings-attention-sources`,
  `page-today-kept`, light, dark, de, ar) and checked live (Claude Code at Only in Today, a `sidefolk hook` Stop: no
  desktop notice, Today's Kept for Today showed it). Not tried by hand: the ⋯ menu's two choices and their Undo (no
  click from the dev script; `interrupt:<key>:<level>` sets a level). Next: merge.

- **The companions' reaction moves** (branch `team/reactions`, not merged; D75 amended): sulk, shrug, tease, ready,
  wince, gasp and the quick accents are each a real move now, in 3D for all ten companions (shared in
  `engine/moves.js`, a still version under Reduce Motion) and in 2D (`Antics`). Verified: every move filmed for every
  3D companion at 0°, 40° and 90° and tuned from the films; the 2D sheets read; character tests green; live in the
  debug app (Playtime's tic-tac-toe open, `cue:sulk`, `cue:tease` on Mochi 3D, `cue:shrug` on Mochi 2D). Next: merge;
  no gallery companion changes.
- **Game items** (branch `team/games-items` in both repositories, not merged; D79 amended, the games' items):
  catching the companion in Which Cup? by clicking it, Garden Plots from the keyboard, a daily board per puzzle level,
  "Do it" after a hint, Korean rows one width, no faded stick on Last Stick's last board, scores in the bar's order in
  Arabic; then the Kit isolating `L`'s values (Arabic sentences that begin with a name), the Play panel acting on its
  first click, the menu of games opened by words in ten languages and by `games.open` without a game, the back arrow
  that always works (⌘[), and snapshot runs in several languages kept apart; carries origin/main. Next: merge, then
  set Playtime's `minimum_sidefolk` to the snapshot that ships it (the board button's `companion` key). Verified with UI snapshots (en, ar, ko, ja, light and dark), films in a debug app, `make test`
  and the add-ons' `swift test`, `build.py --unsigned` and `check.sh`.

- **Back up and restore** (branch `team/backup`, not merged, D91; it carries `team/addon-updates`, which carries
  `team/watch-history` and `team/interrupts`): Settings › Trust › Your data and the app menu write one
  `.sidefolkbackup` (database via `VACUUM INTO`, ExtensionData, drafts, skills, companions as data, folder extensions
  and themes for review, gallery add-ons by name, keys only sealed with a password) and restore it: checked, Replace
  with 7 days of Undo restore, swapped at the relaunch, gallery add-ons fetched again, folder code reviewed, MCP
  servers off. Verified: `BackupTests` (6), full suite, snapshots in light, dark, de and ar, and the debug app: a
  backup from `build/bk-1` restored into a fresh `build/bk-2` through the sheet (same notes, reminders and skill,
  History's line), then undone. Next: merge.

- **Themes, fewer and finished** (branch `team/theme-skill` in both repositories, not merged; D92): the
  `sidefolk-theme` skill (`.claude/skills/`, `.agents/skills/`, a public copy in `skills/`); the set cut from seven
  to four built-ins, each its own atmosphere: Harbor, Paper Garden (Field Notes, Paper Garden and the skill's Tea House
  merged), Night Studio (Night Studio and Night Shift merged) and Marshmallow (its stage as a wash and nook). Field
  Notes and Night Shift move to their successor at launch with a whisper (Night Shift's people keep compact
  spacing); Daylight, gone from the gallery, stays where installed and offers Harbor once (`ThemeSuccession`). The
  add-ons carry no themes now (publish.sh drops their packs); Tea House's branch `team/tea-house` is superseded.
  Also: the check holds success and chips' words to 4.5:1 and soft fills to their hue (D78 amended; kept copies only
  warn), the nook art is drawn again, `TodayHeader.swift` is gone, snapshot language runs work under Swift Build's
  linked `.build/debug`. Next: merge both branches together, then publish the add-ons (the founder).
- **Leftovers** (branch `team/leftovers` in both repositories, not merged): the Gallery's Updates under every filter and
  search, and a reviewed update says Updated (D89, checked live on a signed local gallery); Undo restore puts back the
  keys and the app's conveniences a restore replaced, which a backup now carries (D91); the Week view's "+N" and
  read-only note (D84); Connections name a dev copy's stand-ins (D86); a hop's rise eases into the window's headroom
  (D51 amended); Iris's tease, ready, waveQuick and spinQuick keep her arms in (add-ons, `companions/iris`); snapshot
  runs get their layout direction on their own command line (Arabic beside other runs came out left to right), the dev
  `snap` takes the toolbar (its white band), an extension page's error state. Verified: `make test`, the add-ons'
  checks, UI snapshots (light, dark, de, ar), films of Iris's four moves at 0°, 40° and 90°, `edges()` for every 3D
  companion, and the debug app. Next: merge; the gallery's next build gives Iris a new snapshot by itself.

**Integration:** `team/desktop-polish` carries origin/main (D86), `team/addon-updates` (with watch history and the
interrupt levels, D87–D89) and `team/reactions`, merged and tested together; `team/backup` and `team/games-items`
merge last.

## Next

1. **The founder plays the puzzles** (Garden Plots, Seesaw, Sudoku, Blossoms) and the games in snapshot 661.
2. **Miraya on a real TV:** live screen and sound with the three sound choices (only an emulator paired so far, D81).
3. **What D84 left out** (it needs something real first; AGENTS.md: no fake features): the evening wrap.
4. **Games not built** (D79): AI trivia packs, Connect Four.
5. **Before 0.1.0 is released** (the founder; docs/launch/CHECKLIST.md, docs/RELEASE.md): a licence
   ([research/licence.md](research/licence.md)), the name and domain, a privacy policy and support contact,
   Open-Meteo's terms if Sidefolk is paid, Anthropic's and OpenAI's approval of their logos, curated release notes,
   and fresh launch screenshots (`scripts/launch-screenshots.swift` still picks snapshot names from before D84).
6. **Later:** which extension ideas to build ([research/extension-ideas.md](research/extension-ideas.md));
   community companions as data (the gallery's 3D characters are code;
   [research/companion-marketplace.md](research/companion-marketplace.md)); whether the gallery's companions get
   folder-style 2D forms (D85); a hand-drawn Mochi pose for the About window and onboarding; the hero and wordmark
   checked by hand with each companion and accent colour.

## Known gaps

- **Small things seen in phase 5:** the greeting says "Good evening" after midnight.
- **Not yet tried by hand with the real thing:** the microphone (permission prompt, hold to talk, AirPods), a live
  ElevenLabs voice, Location Services naming the town, an update's swap and reopen between two published snapshots,
  Apple Notes on a large real library, Claude Code hooks and Codex's hook trust dialog in a real session, "Connect…"
  (it edits real config files, so only the person clicks it), the notifications prompt, the login item from
  /Applications, several displays and fullscreen apps, a real trackpad's two-finger swipe, a first launch on a clean
  Mac without the developer tools, macOS 15 and 26.
- **Using the internet (D47):** Feeds and Git still ask after outside content (Guard would need their address
  parameters); "Always" is never offered after outside content. A site the person allowed can receive what a
  steered model puts in a page's path.
- **Extensions can't hold secrets yet**, so Git can't reach private repositories or SSH remotes, and connectors
  (GitHub, Notion, Linear) wait for it.
- **Built-ins' limits:** QR Codes needs an Apple GPU; Currency covers the ECB's 30 currencies; the promise check
  reads English replies only; a folder with more than 20,000 items can't be watched.
- **Languages:** the `sidefolk` command line, `StatusSnapshot.sentence`, bridge protocol errors, manifest checks
  (`ManifestValidator`, `ValidationReport.text`) and `ExtensionError`/`MCPError` details stay English on purpose.
  Stored collection names ("Inbox", "About you") stay English and are shown through
  `NotebookCollections.shownName`. KeyboardShortcuts' recorder has no Arabic of its own.
- **Cost:** while the mouse moves, the global mouse monitor and the eyes that follow it cost about 1–5% CPU in
  bursts. Measurements at rest and with a game open are in D79 and D84 (phase 5).
- **Residual trust gaps** (SECURITY.md): code running as the person can name its own ancestor or a known terminal as
  a session's host; extension tool names and titles (60 characters) reach the model.
- **Signing:** the Developer ID certificate and notary credentials live only in GitHub's secrets, so the Release
  workflow signs and notarizes; local builds use the Apple Development identity or ad hoc.

## How to verify

- `swift build`, then `make test` (Swift Testing, serially). The extensions' sandbox tests run the gallery's
  extensions from `../sidefolk-addons`, or `SIDEFOLK_ADDONS_REPO=<a clean add-ons checkout>`: an add-ons checkout
  behind main fails the gallery, words and game tests.
- In the add-ons repository: `swift test`, `python3 scripts/build.py --unsigned`, `SIDEFOLK_APP=../sidefolk
  scripts/check.sh`, and `../sidefolk/scripts/extension-strings.py check`.
- UI: `SIDEFOLK_RESOURCES=$PWD/Resources swift run SidefolkApp --ui-snapshots <dir>` (add `--language de|ar|ja`,
  `--theme <id>` or `--only <prefix>`, e.g. `window-home`, `window-settings`, `desktop`, `panel-pocket`,
  `design-system`, `a11y`), read in light and dark against [DESIGN.md](DESIGN.md).
- The running app: `make dev`, or a debug app on a fresh short `SIDEFOLK_HOME` (`build/qa-<name>`), driven with
  `swift scripts/dev.swift` (its header lists every command: `ask:`, `respond:`, `home:<place>`, `settings:<tab>`,
  `pocket`, `attention:focus:60`, `game:`, `drag:`, `snap`…).
- Characters: `swift run sidefolk-render out/`; 3D companions in `companions-3d/` (its README, `serve.py`).
