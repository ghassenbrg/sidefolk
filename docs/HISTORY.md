# History

What was built and how it was checked, newest first. These entries were moved out of [STATUS.md](STATUS.md) on
2026-11-01 with their text unchanged, so they use the names of their day: Settings › AI, Privacy, Extensions, Voice
and Agents (now Brain, Trust, Add-ons and Connections), the Ask panel, bubbles and Glance (now the Sidecard), Now,
Conversations and Activity (now Today, On duty and History), theme layouts (retired by D84). Branches named here are
merged. What holds today is in [STATUS.md](STATUS.md), [DECISIONS.md](DECISIONS.md) and [DESIGN.md](DESIGN.md).


## 2026-11-03: Dev ideas, batch 3: watchers run apart from where they show (items 6, 7; D116)

Display modes, order, All watchers, value formatting, agent tools, and no count for the person; other agents ask past 25. The founder's question took the handover's recommended answer.

Verified: `swift test` against a clean add-ons checkout, with `WatchManagementTests` and the limits' tests rewritten. In the debug app on a fresh home: five live values made by typing, three beside the companion and two quiet; a synthetic drag moved the third row first and it stayed; "$" and "GPU" on the page and the pins (`34% GPU`, `$17.07 GB`), and the Arabic page with its numbers intact; 200 live values every 10 s cost 1.7 % CPU against 1.4 % for 5; a value set to come and go stood beside the companion at a reading and was gone seconds later. A review found Sidefolk's own agent could give itself room under Full access, routines and extensions had lost all ceiling, the first moments spent the attention budget and filled History (now a pin kept nowhere), a fourth value from before would have vanished, and sparklines read digits from what was set around a value; all fixed. Not run: a person's hand on the drag, a live agent calling `watch.more_room` (its permission and the room are tested, and Guard's asking is the usual path), and many web or command watchers at once.

## 2026-11-03: Dev ideas, batch 2: "done" is checked against what ran, and a reminder marked done finishes its task (items 3, 4, 5; D115)

**Item 3:** `ReplyCheck` on every brain's reply, `UnbackedClaim` in ten languages, a tool's own error never shown as done on the quick path. **Item 4:** `ReminderScheduler.complete` finishes the open task wherever the reminder is marked; the rules both ways are D115's table. Other linked pairs were looked for and listed there. **Item 5:** already fixed by D90, nothing built. On a debug build, "what's my memory usage" showed in Ask and had gone three minutes later, with "Older answers are in History" beneath; a normal result stays its half hour (`ResultLifetimeTests`).

Verified: `swift test` against a clean add-ons checkout, all passing, with new suites `ReplyCheckTests` (claims, failures, retries, refusals, read-only calls, opening things, words about something else, claims and denials in every language; notes, tasks, reminders and watchers through a scripted brain) and `ReminderTaskSyncTests`, tools and Undo in `ReminderLinkToolTests`, the quick path in `LocalIntentRunnerTests`. In the debug app with `brain:scripted`: "I've saved that to your notes." with no tool shows the correction beneath it. A review found the first version too eager, printing a correction under ordinary sentences and after read-only calls, and asking the model again after a page had opened (which could open it twice); the check was narrowed to firm claims when no call worked. It also found a race (settling first would make a marked-done reminder return with its task), and a task's title quoted to other agents (T4); both fixed. Not run: a live model, Claude Code's or Codex's CLI (the check sits above them, and only the extra turn is `LoopBackend`'s).

## 2026-11-03: Dev ideas, batch 1: the companion's card stays put, and a button takes its click anywhere (items 1, 2)

**Sticky card:** the nook sits above Home's sidebar list rather than in it, so only the list scrolls. **Click targets:** SwiftUI's `.plain` takes a click only on what is drawn, whatever frame it has, which is what the founder felt. Every plain button in the app became `.sfBare` (anywhere in its frame) or `.sfIcon` (only a symbol: at least 28 square, or 22 in tight rows, with click and hover on the same area); `ButtonHitAreaTests` keeps `.plain` out; the rule is in DESIGN.md.

Verified: a harness of synthetic clicks measured the cause (plain: only the lines, even with a 28 pt frame; a `contentShape` or padding reaching past a view's frame takes nothing, and where two overlap neither fires, which is why the size is real layout). In the debug app with 30 collections (`homeSmall`, `scroll:1`, `calendar:click`): the card stayed with the list at its end, at the smallest window, in all four themes and in Arabic; a click at the gear's empty corner opened Settings and one just outside didn't. `swift test` against a clean add-ons checkout: 1871 + 38 passed. A review found two things, fixed: the Notebook's search box jumped at the first letter, and the check circle's outset never worked (now `.sfIcon(side: 22)`). Not changed: a disabled hero button and a downloading theme card dim as they did under `.plain`, which measured about the same. Not run: hover by a real pointer, and scrolling with real fingers.

## 2026-11-03: Snapshot 867 released (snapshot B, D101)

The app's commit 885264d7 on `main`, built by run 41512382685: 1870 + 38 tests passed on CI against the add-ons branch, notary "status: Accepted" for the app and the DMG, four seed packs verified. The downloaded DMG's digest, staple and `spctl` were checked again, and the app says 0.1.0-snapshot.867. Gallery published after it (Playtime 1.0.0-snapshot.9, needing 867), holding release `gallery-next` deleted, `seed-packs.py fetch --required` passed on the published gallery. Before merging, the lead reran 1870 + 38 and 214 add-on tests on the final branches. By hand in a debug app of 867: the menu from "show me the games", Which Cup?, Daily Word, the coin overlay and the Playtime page; removal left no games in Home; Playtime 1.0.0-snapshot.9 installed from the real signed gallery and played Tic-tac-toe with the plain signed frame. Still not run: an update from an older copy through the real gallery, real speakers, VoiceOver, a real pointer on the overlay, live model calls.

## 2026-11-03: Snapshot B compared with the old games, game by game (D101's amendment)

Every finding from running the old and new side by side. Blockers: a result before the build-up on Ask's card, aloud and in the AI's words; every listing of extensions costing about 4 s with Playtime (AI requests, launch). Majors: 190 menu sentences and 82 of 84 who-guesses sentences lost; a toss from Ask flying far from the companion; Continue gone after ✕; props left on the menu; 17 rows and a minute for "game sounds on"; the Game Center's look; a model starting AI trivia on free text; old scores back after a reinstall; a crash that looked like catch-me's and was the Sidecard's (`CardPlacement`). Live in a debug app with the unsigned pack: sentences, the coin in the air and landed, Back to the menu, the Game Center in English and Arabic, History rows, launch CPU. Catch-me loop: 0 of 32 died after the fix, 3–6 of 20–30 before. `make test` with the add-ons branch, 1870 tests in 249 suites and 38 character tests; the add-ons' `swift test`, 214 in 20 suites; `build.py --unsigned` (26 add-ons), `check.sh` 17 extensions ok; `swift build -c release --product SidefolkApp`; `translations.py status` 3445 in all ten; `extension-free-binary.sh --strict` clean on a release app, exit 2 with no manifests. **Not checked:** sound through real speakers; VoiceOver heard; a real pointer on the overlay; Reduce Motion live on every game; the signed frame and signed-only words (`row`, `ai_title`: tests only, debug installs aren't signed); the Update button through a real signed gallery to the end; AI answers with a live model (the hold and `trusted_only` by tests); the companion's menu only by reading its code, since a snap can't open it.

## 2026-11-03: what STATUS carried until snapshot B (snapshot A, Playtime's move, games v2, Calendar v2)

As each stood; the branches named are merged, or part of `team/playtime-move`.

- **Extensions own everything, snapshot A** (branch `team/ext-move` in both repositories, merging `team/ext-details`,
  `team/ext-scene` and `team/ext-abilities`, plus a review's fixes; D98, D99, D100, SECURITY T40, T41; not on main): the rule and its
  guard (`ExtensionFreeAppTests`, reading the add-ons' manifests; game code reported until `transitionOver` flips in D101), details in
  manifests, four seed packs, pack assets, the Scene, surfaces, rich pages with an inline scene, commands with slots, entries, drops,
  settings, AI help, a History row, and a tool's reply that opens its own surface or page. The old game code still runs beside them.
  Verified: `make test` with the add-ons worktree, 1881 tests in 254 suites and 38 character tests; the add-ons' `swift test`, 148 tests; `build.py --unsigned` and `check.sh`, 17 extensions ok; `swift build -c release --product SidefolkApp`; 3733 strings in all ten languages. Live in a debug app on a probe extension: an overlay with a 5 s timer ended by `timeout` at 60 s; a panel
  whose program takes 1.5 s, closed mid-move, got no more moves; a field at y=-44 is gone and a `focus` field took the keyboard; a scroll box
  kept its `scroll_to` in view and a click at a scrolled place was the right row; a scene in a page with `{companion}`; snapshot
  `page-extension-scene` in light, dark and Arabic. Not run: a page scene's click by a real pointer (its unit test covers the action); a scene's stand-in for someone with no account picture;
  the input-method path of `submits`; VoiceOver heard live; Codex's refusal with a real file (its check is tested, no quota spent).
  **Known gaps before a release:** never yet notarized with packs inside (RELEASE.md › Add-ons first proves it before the gallery changes);
  every `minimum_sidefolk` is the placeholder 786 in all 17 add-ons until the lead sets the real number (`build.py --sidefolk-build N` stops on it).
  **Next:** Playtime rebuilt on these (D101, in progress below), then snapshot B removes the old code and flips the
  guard, `extension-free-binary.sh --strict` with it, and adds a run with no extension installed asserting no games UI.
- **Playtime moved, the table props** (branch `team/playtime-props` in both repositories; not on main): Which Cup?, Copy Me, Quick Paws and Last Stick are on the stage, compared live with the old panel. What plays by itself is `Stage/Playback.swift`. Three defects in snapshot A's surfaces fixed in the app (D101, amended), so this pack wants that app. **Next:** merge it with the other groups' parts.
- **Playtime moved, the foundation** (branch `team/playtime-move` in both repositories; D101; not on main): the stage (Playtime's parts library), one surface, menu, commands, entries, settings and what carries over, the Game Center as its page, AI trivia on AI help, its art and sounds in the pack. Higher or Lower is whole, filmed against the old panel, in German and Arabic too. **Half done on purpose:** `StagePads`, `StageCups`, `StageReflex`, `StageSticks`, `StageLetters` and `StagePuzzle` draw a placeholder card (`unmoved`) until the groups fill them; rock, paper, scissors and the desktop coin, dice and hands aren't moved yet. **To add a game:** catalog entry (`Looks.swift`), its driver (`GameTable.drivers`), its command, sound and level settings in the manifest and `strings/`, its parts' file, a line in `PlaytimeStageTests`.

- **CI's silent test deaths, fixed** (2026-11-01): from about snapshot 724 the core test process died on GitHub's
  runners about two minutes in, with no failing test (release runs 41267300489 to 41270779706, and CI). The kernel
  killed it (EXC_GUARD: an NSPipe closed a guarded descriptor). Cause: `childSeesOnlyStandardDescriptors` did
  `dup2(…, 77)`, silently closing an NSPipe descriptor SystemTool (Backup's zipinfo and ditto, hdiutil) still held
  until its delayed release; the pipe then closed 77 again after a guarded descriptor had it. The test now takes a
  free number (`F_DUPFD`). Found with `ci-tests.yml` (docs/RELEASE.md) and a close()/pipe() interposer locally.
- **Games look v2** (branch `team/games-look-v2`, merged on `team/final` for the next snapshot; D79 amended, the games look v2): every game's Play
  panel, the All Games menu and the reward card reskinned along the founder's Imagine Skin concepts: the scene behind
  the whole panel with night paintings for dark mode, header, score, hint and tiles as cards on the games' own
  surfaces, a level chip never red, the menu's cards side by side (`GameCards.swift`, shared with Playtime's page in
  Home), the reviewed flat reward card, puzzle boards in frames (Garden Plots' soil, Blossoms' rounded beds); 14
  night scenes and two icons (Art about 1.5 MB). Verified: `make test` with an add-ons clone, `GameArtFilesTests`,
  UI snapshots of every game and moment in light and dark, en, ar, ja and de (all under 720 pt), a debug app with
  Playtime from a local build (the cups' shuffle and an end card filmed, idle CPU 2–3 %). Next: the founder's
  call on Seesaw's pieces (the revision's crescent and sun versus D79's "no sun and moon").

- **Game Center and game commands** (branch `team/game-center` in both repositories, merged on `team/final` and `team/gameplay-ai`; D93; carries
  `team/games-look-v2`): Playtime's page in Home is a Game Center Sidefolk draws from Playtime's records (a hero with
  the companion and Continue / today's daily / Surprise me, the day's boards, every game as a card in its group with
  its best, record and last played, Wins / Solved / Best streak / Played, last games, badges from the records, and the
  games' settings: tone, sounds, Sneaky, a level per game); games steered without AI in ten languages ("rematch",
  "make it harder", "trivia about space, hard, 10 questions", "guess a number between 1 and 1000", "you guess my
  number up to 500", "pause the game", "resume the game", "show my stats", "turn game sounds off", "back to the
  games"), `games.open`'s last/again/random/center and relative levels, a new `games.settings`; Sneaky in Settings ›
  Companion; and Home's large titles (the toolbar's title only once the page's own has scrolled away, content cut at
  the toolbar, no "Playtime / Playtime"). Verified: `GameCommandsTests`, `GameCenterTests`, full `make test` (1718 + 38) and
  the add-ons' `swift test` (120), `build.py`, `check.sh`; UI snapshots `page-game-center*` and
  `window-home-*` (scrolled too) in light, dark, de and ar; a debug app on `build/gc-1` with Playtime from a local
  build: "play tic-tac-toe on hard" (Hard), "make it easier" (Fair), "pause the game", "resume the game",
  "Spielgeräusche an", "guess a number between 1 and 1000", "jouons au morpion difficile", "더 쉽게 해줘", "show my
  stats" (Home on the center, Continue Tic-tac-toe), scrolled pages cut at the toolbar. Merged with `team/gameplay-ai`; D95's AI trivia switch is a row of
  `GameSettingsSection`. Playtime's `minimum_sidefolk` names the snapshot that ships D93 (the lead sets it).

- **Games v2, gameplay and AI** (branch `team/gameplay-ai` in both repositories, merged on `team/final`; D95, D96; carries
  `team/game-center` and `team/games-look-v2`, merged with origin/main): the companion plays like a person at every
  level (Hard tic-tac-toe never loses, Hard Last Stick wins every winning position, memory that fades, reflexes that
  lean late, round numbers whenever the numbers are big), Higher or Lower on 10, 100, 1,000, a million or any top, two
  people on one Mac in nine games and rock, paper, scissors (covers for secrets, the companion referees, head-to-head
  kept apart), and trivia on any topic made by the person's AI through `sidefolk/trivia.request` (on by default with
  AI, 20 calls a day, packs cached for the day, facts labelled as not checked). Connected to the Game Center: "play
  tic-tac-toe with my friend" and "two players" in ten languages (a `players` slot through `games.open`), a "2 players"
  button on each card, Head to head, the AI trivia switch among the game settings; the range and mode slots reach
  Higher or Lower. Verified: `make test` with the branch's add-ons (1729 + 38), the add-ons' `swift test` (141),
  `build.py --unsigned` and `check.sh`; snapshots of the Game Center and of every two-player and AI-trivia board in
  light, dark, de and ar (each within 720 pt); a debug app: "play tic-tac-toe with my friend" opened it on the names,
  "guess a number up to 1000" straight into a game on 1 to 1,000 (par 10). AI trivia is tested with scripted models
  only; no live call was made. Next: Playtime's `minimum_sidefolk` set to the snapshot that carries
  D93, D95 and D96 (the lead).

- **Spoken replies muted by Siri's listener** (branch `team/voice-ja`, merged on `team/final`; D34 amended): the founder heard
  nothing after switching to Japanese. Not the language: Playtime's sounds had left an audio engine running, so
  macOS's Siri voice trigger (corespeechd) kept the microphone on, and it counted as "another app is recording". Now
  macOS's own listeners don't count, game sounds let the hardware go after 3 s, and every reply decision and playback
  is logged (`voice` › `reply …`). Debug `brain:scripted:<answer>` answers without a network. Reproduced and verified
  in a debug app in Japanese on `build/vj-1`: before, a game sound then a spoken request logged `reply muted
  why=micInUse`; after, `reply speak` with `mic_listening=corespeechd` while another app played, Kyoko for Japanese
  lines with Samantha chosen, `reply played`; Japanese, Chinese, Korean and Arabic voices all synthesize. Tests:
  `VoicePolicyTests`, `SpokenLineTests`, `ElevenLabsTests`, `SpeechPlayerTests`. Next: the founder
  tries Japanese with a game played first and music playing, with the snapshot that carries it.

- **Calendar v2** (branch `team/calendar-v2`, merged on `team/final`; D97): the Calendar works like a Mac calendar. Each calendar's
  own colour (contrast-checked fill, edge and text, lightness only), Sidefolk's reminders, tasks and routines as
  calendars of their own, a sidebar with a month and the calendars to show or hide (remembered, and hidden everywhere);
  Agenda, Day, Week, a Month that scrolls on row by row, Year; events say what their size has room for, all-day bars
  across days, reminders as one-line pills (a reminder repeating through the day once in the Week, "· every 30 min"),
  overlaps side by side never under 60 pt with "+N" listing the rest (snapshots `window-home-calendar-{week,day}-crowded`); ⌘← ⌘→ ⌘T, two-finger swipes, pinch for the hour's height, arrows,
  Return and Delete; a double-click or a drag over empty time opens an editor (reminder, task in a collection, or
  event); dragging moves, an event's edge resizes, ⌘Z undoes; a details popover (Maps, people invited, notes, Open in
  Calendar). The Mac's events change through `calendar.create`, `.update` and `.delete` once the person allows it (a
  sheet, or Settings › Trust › Your calendar), never meetings with people, read-only calendars or whole series
  (SECURITY T34). Verified: `make test` (1721 + 38) with a clean add-ons clone, `CalendarPageTests` and
  `CalendarWriteTests`, UI snapshots (calendar views, details, editor, sheet) in light, dark, de and ar, and the debug
  app on `SIDEFOLK_SAMPLE_CALENDAR=1` driven by the new `calendar:` dev commands: drag-create with typing and Return,
  moving an event (the sheet, then ⌘Z), keyboard selection and details, Delete and ⌘Z, a swipe and a month scroll
  filmed, 3,000 extra events (a week of 522 read in 4 ms, idle CPU unchanged). Not tried: a real trackpad and pinch by
  hand, and the person's own EventKit data (the debug build has no calendar access; it ran on the sample). Next: the founder tries it on a real trackpad and his own calendars.

- **The release review** (2026-11-01, `team/final` and the add-ons' `team/gameplay-ai`): everything above walked in a
  debug app (`build/fr-1`, `SIDEFOLK_SAMPLE_CALENDAR=1`, Playtime from a signed local gallery of the add-ons branch,
  `brain:scripted:` answers, no live call): the menu by words, every game and puzzle, tic-tac-toe and Quick Paws for
  two, Higher or Lower to 1,000, back, rematch, harder, pause and resume, the Game Center top to bottom, AI trivia on
  Any topic (a scripted pack played, an unusable answer falling back to the bank), each Calendar view, drag-create,
  a sample Mac event moved through the permission sheet and undone, details, 3,000 crowded events, a swipe and the
  month's scroll, spoken requests in English and Japanese after a game with sounds on (`reply played` both times),
  Today, On duty, History, a watch, Settings' tabs and search, the Pocket, the Gallery's Update all, the backup and
  restore sheets, the four themes, a reminder card. Fixed on the way: Today's day line and legend in the calendars'
  own colours (D97; every event was the accent while the legend promised another colour); the legend's words never
  cut (Arabic's "التقو…"); a Game Center card no longer says "Not played yet" beside "Played 3 minutes ago"; two or
  three choice cards share their row (Higher or Lower's two ways sat in its left half); in Playtime, the thermometer's
  word follows its colour (a half-full tube said "Freezing"), a Quick Paws round for two that nobody took is played
  again under its number (it counted on to "Round 9"), "your AI" starts a sentence with a capital, and why no AI
  questions came is the companion's line rather than a note that pushed the two-player choice off the panel.
  Verified: `make test` with the add-ons branch, the add-ons' `swift test`, `build.py --unsigned` and `check.sh`,
  `make strings` complete in ten languages.


Released or on main since snapshot 661 (D86–D92, the leftovers, the docs cleanup) is in [HISTORY.md](HISTORY.md).

## 2026-11-02: extensions own everything, the abilities (D98, D99, D100)

As each branch reported before they were merged on `team/ext-move`.

- **Extensions own everything: the rule, guard, details, seed packs** (branch `team/ext-details` in both repositories; D98;
  not merged). `ExtensionFreeAppTests` reads all of `Sources` against `scripts/extension-free-allowlist.json`: extension
  details fail now, game code and Miraya's drop action are reported until `transitionOver` flips in D101's last step. Examples,
  tool summaries, services and `replaces` moved to manifests, words to `strings/`; `BuiltInExtensionWords`, `BuiltInExamples`,
  `BuiltInToolSummary`, `BuiltInServices`, `ExtensionOverlap` and `BundledExtensions` are gone. World Clock, System Vitals,
  Weather and Calculator moved to sidefolk-addons as seed packs (`Resources/SeedPacks`, `scripts/seed-packs.py`); samples are
  made-up extensions. Verified: `make test` and the add-ons' `swift test`, `build.py --unsigned` and `check.sh`; a debug app
  with packs signed locally: a fresh data folder with no gallery installs the four and World Clock answers; a data folder
  from the old app keeps a switch and a data file, converts to `official`, and then updates from a local gallery by
  itself; a removal stays gone after a relaunch; snapshots `sheet-install-services*`, `page-settings-trust`,
  `page-settings-extensions*` in en, de, ar. **Before a release with this:** publish the gallery first (a release takes the
  packs from it and stops without them) and raise `minimum_sidefolk` in the add-ons (now 786, for all but Miraya) to the
  snapshot that ships this. Not tried: a real notarized build carrying the packs (Apple scans archives inside the app;
  the packs are signed and timestamped with the hardened runtime, as it wants). Next: D100's Entries takes Miraya's drop
  action; D101 flips the guard.
- **Surfaces, Scene and pack assets** (branch `team/ext-scene` in both repositories, D99, SECURITY T40; first of the "extensions own
  everything" abilities, snapshot A): an extension can open a framed panel or overlay drawn natively from data, with images and
  sounds from its pack; the old Play panel is untouched. Verified: `make test`, `samples/scene-sample` in tests and the debug app (shuffle,
  drags, keyboard, coin filmed with `surfaceFilm:`), snapshots `surface-*` in light, dark, German and Arabic, idle CPU flat. Next: Playtime on
  it (D101), with D100's commands and settings; the gaps are at the end of D99.
- **What any extension can declare** (branch `team/ext-abilities` in both repositories; D100, T41): richer page parts (hero with a scene, stat strip, card grid with pack pictures, tabs, badges, recent, settings rows), commands with slots in every language (names with parts, enums, carrying words, conflict rules), entries in the companion's menu, the Pocket and Ask, drop actions (Miraya's Play on TV moved to its manifest), extension settings with a one-time carry-over, AI help (`permissions.ai`, cap, switch, frame), a History row; the Kit in both repositories; sample `extensions/hello-abilities`. Verified: `ExtensionAbilitiesTests`, `ExtensionPageRichTests`, `CommandFrameTests`, a Kit program in the sandbox, `make test` with the add-ons worktree, add-ons `swift test`, `build.py --unsigned`, `check.sh`; snapshots `page-extension-rich*` in light, dark, de, ar; a debug app on the sample: install sheet, page, commands, a scripted AI request, a drop, Settings' search, History, Ask's tab, removal. Next: merge with `team/ext-scene` (D99: `PagePictureReader` becomes `PackAssetReader`, `assets` is the same key) and rebuild Playtime on it (D101). The old game code is untouched.

## 2026-11-01: calendar input fix

- **Calendar month controls receive clicks:** the continuous month's extra, hidden week was visually clipped
  but still took header double-clicks, opening a draft for a previous-month day and blocking the view controls.
  Both the month rows and the page content now constrain hit testing to their visible viewports; the header keeps
  its height and sits above the content. The first containment commit was made on an older checkout (before D97);
  this integration preserves current main's Calendar v2 and verifies the reported failure on that implementation.
  *Checked:* permanent native mouse regression (`--ui-snapshots build/calendar-input --check-calendar-input
  --language en`) fails before the fix and passes afterward: initial/partial scrolling, header/weekday
  double-clicks, Day/Week/Month switching, overflow links, and a visible empty day's double-click. Normal and small
  window captures are in `build/calendar-input-*`; full tests with a clean gallery checkout: 1746 core + 38
  character, all green. **Published as [snapshot 780](https://github.com/ghassenbrg/sidefolk/releases/tag/v0.1.0-snapshot.780)**
  from main commit `e20c27f6`, signed with Developer ID and notarized; disk image and checksum uploaded and the tag
  verified against that commit. Main CI passed. Release run `41305325341` attempt 1 stopped at the existing
  `childThatLeftTheGroupStopsWithTheExtension` cleanup timeout (the local full suite and five targeted rechecks
  passed); attempt 2 passed every gate and published. The original affected user setup remains a manual retest.

## 2026-11-01: released in snapshots 673 to 724, or on main after it

These were STATUS's "In progress" until the release review; D92 (themes), the leftovers and the CI fix are on main
for the next snapshot. Their "Next: merge" is done.

- **Docs cleanup** (branch `team/docs-cleanup` in both repositories): every doc, README and skill
  brought to the app as it is after D84; this file split into STATUS and HISTORY; finished plans removed.

- **Desktop polish** (branch `team/desktop-polish`): cards answer from the keyboard (⌃⌥Space), Ask's
  tabs and "Open in History", the drop card, the stack's arc and the voice's light, VoiceOver on the companion's
  corner (D84's note); Ask tidies itself by each result's weight, agents grouped by folder (D90). Verified with
  `make test`, UI snapshots (light, dark, de, ar) and the debug app. Next: merge; try ⌃⌥Space on a Mac whose input
  sources don't take it, and VoiceOver by hand (an AX client this Mac's tools aren't allowed to be).
- **Safety and correctness** (branch `team/safety`): a copy on any `SIDEFOLK_HOME` writes agent-config
  stand-ins in `<home>/agent-configs/`, never the person's Claude Code, Codex or `~/.local/bin/sidefolk` (D86, ported
  from a branch that never reached main); `connect:`/`disconnect:` dev commands; the audit's F12 rule (links open only
  as web pages) on release notes and extension errors; the QA branch's last four tests. Verified: full suite green
  (1626 + 38 tests), and a debug app on `build/safety-1` connected and disconnected both agents and the command
  while the real files kept their mtime and SHA-256. Next: merge.
- **Add-on updates in sight** (branch `team/addon-updates`, D89): the Gallery's Updates with Update all
  (per-item progress, "3 updated, 1 needs your review", widening ones stay with Review…), an extension page's
  "Update available" strip with What's new, Settings › Add-ons inline "New version · Update" and an Update all card,
  Home's sidebar dot and count, Today's one row, the Pocket's Needs you, a whisper after a day with the switch off.
  Verified: `AddonUpdateAllTests` (5), full suite, snapshots in light, dark, de and ar, and a debug app on a signed
  local gallery (two extensions and a companion, one widening): Update all updated two and left one for review.
  Next: merge.
- **Watch history** (branch `team/watch-history`, D87): every check of a watch logged as runs, the last
  two versions of a page's or file's text, the watch's own page in Home (what changed inline or side by side, its
  timeline, Check now, Pause or Resume, Stop) and On duty's bars of the last 24 checks; `watch.list` says when each
  last changed. Verified with tests (migration, runs, versions, pruning, Your data), snapshots `window-home-watch*`
  and `window-home-onduty*` in light, dark, de and ar, and the debug app with a local file changed twice and a page
  on `python3 -m http.server` edited once. The branch also carries origin/main (snapshot 673, D86) and
  `team/interrupts` (D88, below), merged and tested together; the watch's Check now has its own key
  (`watch.checkNow`: "Jetzt prüfen", not Updates' "Jetzt suchen"). Next: merge into main.

- **What may interrupt you** (branch `team/interrupts`; D88): a level per source (Card, Whisper, Only in
  Today, Off) in Settings › Attention, applied before Focus and Quiet; "Fewer like this" and "Show these as whispers"
  in a card's ⋯ with Undo; Today's Kept for Today; "done today" counts only what changed something. Built, tested
  (`InterruptionsTests`, `InterruptionsCenterTests`, `DoneTodayTests`), snapshots read (`page-settings-attention-sources`,
  `page-today-kept`, light, dark, de, ar) and checked live (Claude Code at Only in Today, a `sidefolk hook` Stop: no
  desktop notice, Today's Kept for Today showed it). Not tried by hand: the ⋯ menu's two choices and their Undo (no
  click from the dev script; `interrupt:<key>:<level>` sets a level). Next: merge.

- **The companions' reaction moves** (branch `team/reactions`; D75 amended): sulk, shrug, tease, ready,
  wince, gasp and the quick accents are each a real move now, in 3D for all ten companions (shared in
  `engine/moves.js`, a still version under Reduce Motion) and in 2D (`Antics`). Verified: every move filmed for every
  3D companion at 0°, 40° and 90° and tuned from the films; the 2D sheets read; character tests green; live in the
  debug app (Playtime's tic-tac-toe open, `cue:sulk`, `cue:tease` on Mochi 3D, `cue:shrug` on Mochi 2D). Next: merge;
  no gallery companion changes.
- **Game items** (branch `team/games-items` in both repositories; D79 amended, the games' items):
  catching the companion in Which Cup? by clicking it, Garden Plots from the keyboard, a daily board per puzzle level,
  "Do it" after a hint, Korean rows one width, no faded stick on Last Stick's last board, scores in the bar's order in
  Arabic; then the Kit isolating `L`'s values (Arabic sentences that begin with a name), the Play panel acting on its
  first click, the menu of games opened by words in ten languages and by `games.open` without a game, the back arrow
  that always works (⌘[), and snapshot runs in several languages kept apart; carries origin/main. Next: merge, then
  set Playtime's `minimum_sidefolk` to the snapshot that ships it (the board button's `companion` key). Verified with UI snapshots (en, ar, ko, ja, light and dark), films in a debug app, `make test`
  and the add-ons' `swift test`, `build.py --unsigned` and `check.sh`.

- **Back up and restore** (branch `team/backup`, D91; it carries `team/addon-updates`, which carries
  `team/watch-history` and `team/interrupts`): Settings › Trust › Your data and the app menu write one
  `.sidefolkbackup` (database via `VACUUM INTO`, ExtensionData, drafts, skills, companions as data, folder extensions
  and themes for review, gallery add-ons by name, keys only sealed with a password) and restore it: checked, Replace
  with 7 days of Undo restore, swapped at the relaunch, gallery add-ons fetched again, folder code reviewed, MCP
  servers off. Verified: `BackupTests` (6), full suite, snapshots in light, dark, de and ar, and the debug app: a
  backup from `build/bk-1` restored into a fresh `build/bk-2` through the sheet (same notes, reminders and skill,
  History's line), then undone. Next: merge.

- **Themes, fewer and finished** (branch `team/theme-skill` in both repositories; D92): the
  `sidefolk-theme` skill (`.claude/skills/`, `.agents/skills/`, a public copy in `skills/`); the set cut from seven
  to four built-ins, each its own atmosphere: Harbor, Paper Garden (Field Notes, Paper Garden and the skill's Tea House
  merged), Night Studio (Night Studio and Night Shift merged) and Marshmallow (its stage as a wash and nook). Field
  Notes and Night Shift move to their successor at launch with a whisper (Night Shift's people keep compact
  spacing); Daylight, gone from the gallery, stays where installed and offers Harbor once (`ThemeSuccession`). The
  add-ons carry no themes now (publish.sh drops their packs); Tea House's branch `team/tea-house` is superseded.
  Also: the check holds success and chips' words to 4.5:1 and soft fills to their hue (D78 amended; kept copies only
  warn), the nook art is drawn again, `TodayHeader.swift` is gone, snapshot language runs work under Swift Build's
  linked `.build/debug`. Next: merge both branches together, then publish the add-ons (the founder).
- **Leftovers** (branch `team/leftovers` in both repositories): the Gallery's Updates under every filter and
  search, and a reviewed update says Updated (D89, checked live on a signed local gallery); Undo restore puts back the
  keys and the app's conveniences a restore replaced, which a backup now carries (D91); the Week view's "+N" and
  read-only note (D84); Connections name a dev copy's stand-ins (D86); a hop's rise eases into the window's headroom
  (D51 amended); Iris's tease, ready, waveQuick and spinQuick keep her arms in (add-ons, `companions/iris`); snapshot
  runs get their layout direction on their own command line (Arabic beside other runs came out left to right), the dev
  `snap` takes the toolbar (its white band), an extension page's error state. Verified: `make test`, the add-ons'
  checks, UI snapshots (light, dark, de, ar), films of Iris's four moves at 0°, 40° and 90°, `edges()` for every 3D
  companion, and the debug app. Next: merge; the gallery's next build gives Iris a new snapshot by itself.

## 2026-10-31 to 2026-11-01

- **Four puzzles in the Play panel (D79 amended, the puzzles; branches `team/puzzles-b` in both repositories, on
  origin/main with the games look and Lantern):** Garden Plots (Shikaku), Seesaw (Takuzu with hearts and stars), Sudoku (6 × 6, 9 × 9
  on Hard) and Blossoms (Star Battle), our own names and look, nothing of LinkedIn's. Generators with unique solutions
  and logical hints (Playtime `Sources/Games/Puzzles`), a daily board per puzzle kept as far as played, then practice;
  best times, streaks, Home rows and the Today tile's streaks; a new checked `puzzle` part with `area` and `place` moves
  drawn in PuzzleView (beds, boxes, = and ×, plots dragged, notes, conflicts in the calm loss tone with a !, hints, a
  clock); four looks with scenes and icons; every word in ten languages, Playtime still 1.0.0. *Checked:* add-ons
  `swift test` (118), `build.py --unsigned` + `check.sh` against this app (all ok); `make test` with
  SIDEFOLK_ADDONS_REPO on the add-ons branch (the sandbox bot plays all fifteen games to their end in en, ja and ar,
  the puzzles by their hints); UI snapshots of each puzzle's start, a broken rule, a hint, the solve's build-up and end
  card and a Hard board, light and dark, in en, de, ar and ja (the tallest panel 656 pt); a debug app (build 621,
  SIDEFOLK_HOME build/qp-1) with Playtime from the branch: a plot dragged cell by cell (`drag:` dev command) and the day's
  Garden Plots solved, filmed. *Next:* the founder plays them, then merge.

- **The Lantern revamp, phase 5: polish (D84, branch `team/lantern-2`):** the whole app walked
  in the debug app (`build/qp-1`, `qm-*`) and fixed: the Calendar pushed Home's whole window under its toolbar (its
  least height), Today's reminder card lost Done, a card replacing a shorter one was cut at the top, onboarding made an
  "All clear", the Say field's ring had flat bars, empty On duty and You had two primaries, History/Today named another
  app's notice "Mochi" with Pip's face, an old Settings search hid the tab asked for, Title Case buttons, "Activity" in
  Trust, "10 min" (now "In 10 min"). Leftovers done: held whispers settled after "While you were…" (`AttentionCenter`,
  test `whatTheCardToldNeverComesBack`), `ThemeCheck` reads only `layout.icons` (old keys still decode), no
  `.roundedBorder` left (`.lanternField()`, `WhenField(boxed:)`), pins at rest show number and unit (`PinValue`, test),
  Reduce Transparency and Increase Contrast versions (`\.solidSurfaces`, `Theme.line` in high contrast,
  `.contrastEdge`), VoiceOver hears cards arrive. *CPU* (top, 12 × 5 s, debug apps on fresh homes, companion resting
  with 2 pins and 2 agents): origin/main 1.4% at rest, 1.4% with Home open; this branch before the fix 1.6% / 4.1%
  (the nook's breathing light redrew Home every frame), after 1.4% / 1.5%. *Checked:* `make test` with
  SIDEFOLK_ADDONS_REPO on the clean add-ons checkout (1612 core and 38 character tests pass; new `whatTheCardToldNeverComesBack`, `aPinAtRestKeepsItsNumberAndUnit`, the layout tests rewritten as `anOlderLayoutLoadsAndOnlyItsIconsAreRead`); `make strings`, all ten languages complete; UI
  snapshots of every place in light, dark, German and Arabic (`window-home-*`, `window-settings-*`, `desktop-*`, `panel-pocket-*`) and `--only a11y`, read against the a-home, b-desktop and c-settings mockups; Playtime built from the add-ons checkout
  and installed from a folder to see a game open. *Not done:* the per-source interruption table (no such levels),
  Ask's "Open in History" header, the companions' own reactions, the evening wrap and drop card; "done today" counts
  other agents' reads; the greeting says "Good evening" after midnight. *Next:* merge `team/lantern-2` to main and
  release a snapshot (the lead's call).
- **The Lantern revamp, phase 2: the desktop (D84, branch `team/lantern-2`):** the companion stands on
  its light pool (idle, working, waiting with the count on its shoulder, alert while a card is out, failed, Quiet's moon)
  driven by `DesktopLight`; bubbles became the Sidecard (`Sidecard/`: whisper with its 6 s line, Undo for an agent's
  undoable change, click to grow; cards with ≤ 3 answers and ⋯; cards fold into the shoulder's count after 30 s; hover
  the count to fan the stack, click it or the companion for Ask on top of it; "All clear"); Ask is the Sidecard's Ask
  size (Say field, understanding row from `ParsedIntent.understanding()`, ⌘↩ AI, ⌥↩ note, Glance as its resting state,
  requests as cards); approvals are permission slips (`Ask/PermissionSlip.swift`, `slipTone`/`takesReturn`: firm never
  takes Return), alone above the head when Ask was closed; pins and the agents lane kept to the founder's small-corner
  rule (icon + number, round agent faces with a status dot, tips on hover, the extras step back while you type under
  them; 281 × 159 pt with three folks, two pins and two agents, the same corner as before); Quiet's digest when it ends;
  the brief as a card; toss captions as whispers. *Checked:* `make test` with SIDEFOLK_ADDONS_REPO on the clean add-ons
  clone (1591 core, 36 character; new `DesktopTests`, `quietEndsWithOneDigest`); UI snapshots `--only desktop` in
  English, German and Arabic, light and dark (sidecards, slips, Ask, the states board, the floor at rest, hovered and
  stepping back, measured); the debug app (`build/qa3`–`qa6`) with real events: a reminder firing (card, amber light,
  count, fold into the stack, fan), a folder watch firing, Claude Code and Codex sessions through `sidefolk hook`
  (faces, "needs you" card), another app's approval over MCP (firm slip alone, ⌘↩ hint, deny), folder access (calm
  slip, Allow's menu), `ask:` with the understanding row, Quiet's moon, a CPU and a memory pin with their tips.
  *Merged with phase 3 and 4 (`team/lantern-4`):* Focus on the desktop (grey light, half circle or a grey count of what
  waits and is held), held whispers back as phase 4's one card when Focus or Quiet ends, Today's approvals as permission
  slips (`ApprovalCard` retired, slips ignore answers for 0.8 s instead of looking disabled), an agent's notice signed
  "Claude Code · sidefolk". *Half done / not built:* the evening wrap, the drop choice card, the stack's arc animation,
  voice's level-reactive pool, keyboard answering of cards outside Ask; the 3D companion's own reactions (phase 5).
  Other teammates' debug apps receive `scripts/dev.swift` commands sent without SIDEFOLK_HOME: set it, or a stray
  `approve` reaches yours. *Next:* phase 5 (polish), or the items above.
- **The Lantern revamp, phase 4: Settings, the menu bar Pocket, sheets (D84, branch `team/lantern-4`):**
  Settings is a sidebar window with search and eight tabs (General, Companion, Attention, Brain, Trust, Connections,
  Add-ons, Appearance); every setting kept a home and the old tab names still open the right place; every
  "Settings › AI/Privacy/Extensions/Voice/Agents" sentence (errors, notices, the install sheet, the AI's context)
  now names the new tab, translations moved along. Search (`SettingKey` catalog + Core's `SettingsSearch`) finds
  rows by title, detail and section, shows switches and short choices in place, and jumps to the row (the tab opens,
  scrolls, the row glows). New and real: **Focus** (whispers wait and come back as one "While you were focused" card,
  `AttentionEnvironment.focus`, `AppSettings.focusUntil`), **ends** for Focus and Quiet, **quiet hours**, what a
  **full-screen app** does, **density**, and **Full access with an end** (`GuardPolicy.fullAccessEnds`, read through
  `current(at:)` by Guard, the store and the executor's clock). Trust leads with the four modes as cards with an
  example each; the Full access sheet asks when it ends. The **menu bar Pocket** (a popover: state, the
  Open/Focus/Quiet dial with its end, Full access with Turn Off, a waiting version, Needs you, Next up, Agents, Ask; ⋯
  or right-click for Settings, Check for Updates…, About, Quit) replaces the long menu; the icon's corner shows a
  waiting dot, Focus or Quiet, fades while the companion hides. **Install sheets** are a two-step passport (D71's
  words and tones kept, Install armed on step 2); the update window and About are on Lantern; onboarding's Connect…
  opens Settings › Connections instead of editing agents' files at once. Strings in all ten languages, counts with
  plural forms. *Checked:* `make test` with SIDEFOLK_ADDONS_REPO on the clean add-ons checkout (1595 core and 36 character tests; the one external-agents test that read the old "Other agents" words updated and rerun alone), new tests
  `AttentionModeTests`, `FullAccessEndTests` (Guard asks again once the hour is over), `SettingsSearchTests`; UI
  snapshots `window-settings-*` (every tab, search, no results, the smallest window), `page-settings-attention-*`,
  `sheet-full-access`, `sheet-install-*` and `*-touch`, `panel-pocket-*`, `window-update-*`, `window-about`, light and
  dark, English, German and Arabic, read against the c-settings mockups; the debug app (`build/qa4`): `settings:<tab>`,
  `settings:jump:debugLogging` (scrolled to it), `settings:full-access`, `attention:focus:60` then `pocket` (Focus
  until …, the dial and the corner mark), the About window. *Half done / not done:* the mockups' per-source "what may
  interrupt you" table (no source has its own level; left out as not real); the Pocket's dial and Full
  access's Turn Off were not clicked in the debug app (no clicks from here; covered by the same paths the dev commands
  use); the skill file's note still says "Settings › Agents" (changing it would mark every installed skill outdated);
  Reduce Transparency/Contrast versions are phase 5. Merged with phase 3 (`team/lantern-merge`): "Get Add-ons" and the
  Companion tab's "Get more" open Home's Gallery (`AppServices.openGallery()`); Home's sidebar pill offers Open, Focus
  and Quiet with their ends. *Next:* merge phase 2, then the phase 5 polish.
- **The Lantern revamp, phase 3: Home (D84, branch `team/lantern-3`):** one layout in every theme. A new
  sidebar (the companion live in its nook on its light, in the desktop's state and pose; Today ⌘1, Calendar ⌘2, Notebook
  ⌘3, On duty ⌘4, History ⌘5; You, collections and the Trash in the Notebook; extension pages arranged by drag with "Get
  add-ons"; Quiet at the foot), the Say bar (⌘K) in the toolbar with its panel (plain sentence, chips, AI or not, ↩ ⌘↩ ⌥↩,
  what it finds). Today rebuilt with the day first (`DayBrief` sentence, counts, day line, Needs you capped at three with
  the rest folded, held while Quiet is on, all clear and first day states; On duty glance; captured today). New On duty
  (`OnDuty`: watches, live values, repeating reminders and routines, agent sessions, commands, background extensions, with
  Pause/Resume/Stop), History (`HistoryTimeline`: Activity, conversations, alerts and agent receipts in one timeline with
  filters, span, search, Undo, the record folded, conversations in place), You (facts with their origin, Edit, Forget,
  suggestions with Keep: `ProfileFacts.keep`/`write`), the Agenda first in the Calendar, the Gallery in Home on Settings'
  models (Settings' Companion and Extensions tabs lost their Gallery page). Retired: theme navigation/Today/Activity/editor
  layouts (keys still decode), All Extensions, Conversations and Activity pages. Reminder lines in History read their time
  as a date. 177 new strings in all ten languages. *Checked:* UI snapshots `window-home-*` (today, wide, narrow, small,
  quiet, colorful, extensions, say, say-ai, say-search, every place, history record/conversation/agents, gallery, every
  empty state) read in light and dark, and today/say/onduty/history/you/gallery/agenda in German and Arabic (RTL mirrors,
  the day line runs right to left); the debug app (build/qa-1) driven with `respond:skip`, `ask:` reminders and a fact,
  `home:history|you|onduty|history:agents`, `find:` (the panel says "On this Mac, no AI"), `snap`; new core tests
  `HomePlacesTests` (6); `make test` with SIDEFOLK_ADDONS_REPO on the clean add-ons clone (1587 core and 36 character tests pass). *Half done / next:* Today's
  approval cards are phase 2's `ApprovalCard` until the permission slip lands; Focus in the sidebar's pill waits for phase
  4's Attention; the Week view's "read only" note and "+1" overlaps; a watch's detail page (A9) needs a check log that
  isn't kept. The Trash shows days left (amber in the last three).
- **The games look like games (D79 amended, branch `team/games-look` in both repositories):** after the
  founder's two direction boards, every game in the Play panel has its own colour, illustrated scene and icon (a
  manifest `look`, with a translated `tagline`), "You vs <companion>" with both faces (the Mac account's picture when it
  has one), the person's own companion standing whole in the scene saying the prompt, chunky toy buttons and tiles, Copy Me's
  pads picturing their moves (a pad's `art`), memory faces and trivia topics drawn as the things, the Boop button,
  Take 1/2/3, and an end card with trophy, rays and confetti that holds the level picker. The panel stays under 720 pt. The panel's home is a menu of game cards ("Play against
  Mochi", "Puzzles"), with Resume and Wins/Streak/Played from Activity (`GameStats`): Play menu › All Games… or a game's
  back button. Restrained on review: soft scenes, still companion art with a one-shot hop, nothing looping (idle CPU
  about 4–4.5 % against 3.7 % with the panel closed), cups that pass in front of each other. Art: about 0.8 MB in
  Play/Art (Codex image generation, one style). Playtime (still 1.0.0) names the looks
  and taglines in all ten languages. *Checked:* `make test` with SIDEFOLK_ADDONS_REPO on the add-ons branch (1585 core
  and 38 character tests), add-ons `swift test` (100), `build.py --unsigned` + `check.sh` against this app (all ok),
  `extension-strings.py check` (complete); UI snapshots of every game's start, turn, build-up, verdict and end, light and
  dark, in English, Arabic and Japanese, plus the menu, read as contact sheets against the direction; a debug app
  (build 614, SIDEFOLK_HOME build/qg-1) with Playtime installed from the branch: the menu, the cups' shuffle, Copy Me's
  playback, a shuffle after the restraint pass and an end card filmed frame by frame. *Next:* the founder looks; a new game plugs in with a `GameLook` case, a
  `GameStyle.of` row and two pictures (D79 amended). A Sidefolk before this refuses the new Playtime (unknown keys).

- **2D forms for companions added from a folder (D85, 2026-10-31):** a folder companion (D60) may bring a `2d/` form
  in the custom companion format, which gained paintings (`paint`), the flat cartoon look (`body.look`), a screen
  face in lights of its own (`face.screen`, `glow`, `mouthGlow`) and face colours and sizes. Settings › Companion
  shows its Look switch (3D first, kept per companion), its tile says 2D or 3D, and a form that doesn't load or leaves
  its window keeps the folder from being added. All new strings are in the ten languages. *Checked:*
  `CustomCompanionTests`, `LocalCompanionsTests`, `CompanionLibraryTests`; `sidefolk-render --check-companion` on a
  draft form; a debug app (build 582) switching a folder companion between 3D and 2D on the desktop and in Settings,
  with placeholder paintings, then with a real painted form (2026-11-01: a private companion's, made by
  `companions-2d/README.md`'s steps outside the repositories; filmed, and live in the app). *Next:* none in the
  repositories has one yet; the founder decides whether the gallery's companions get folder-style 2D forms too.

- **3D engine options for big-headed and screen-faced companions (2026-10-31):** the screen face gained `mouthGlow`
  (the mouth in a light of its own), `layout.mouth.scale` and `softGlow` (halos blurred with a shadow instead of
  three stepped passes that read as rings up close); petting leans by `petLean` (a big head leaned out of its
  window). All default to the old behaviour: Spark is unchanged (checked in the playground). `companions-3d/serve.py`
  queues 128 connections (the default 5 reset module fetches). *Checked:* a companion added from a folder using
  them, in the playground and a debug app; every move, posture and state kept inside the app's square framing.

- **The Lantern revamp, phase 1: foundations (D84, branch `team/lantern-1`):** the founder approved the
  revamp (Lantern; themes dress, one layout per place; firm cards never take Return; History, Brain, Trash in the
  Notebook; the Gallery in Home; half circle = Focus, moon = Quiet; Full access with an end time; Latin companion names
  in Arabic; only what exists is shown). Built: Harbor is Lantern (navy ink, neutral canvas and cards, the deep aqua
  action colour #0B7783 / #3CD6DB with its label at 5.3 / 8.8:1), new optional theme roles `well`, `glow`, `waitGlow`
  (older themes keep their look, no warning), Lantern's type scale, sizes, depth, glass, motion, folk accents and the
  Focus/Quiet symbols; shared components (buttons with sizes and states, chips with their tone's ink, what-it-touches
  chips, `SegmentedPicker`, `ListRow`, status badges, counts, state tiles, pins, folk avatars, field chrome and the
  search, the Say bar's shell with key hints and the understanding row, the Sidecard surface with its tail, whisper,
  card, slip strip and stack, the light pool and shoulder badge), all listed with their files in docs/DESIGN.md.
  Applied app-wide where it was a direct swap: every button (SFButtonStyle), every segmented picker but the companion
  stage's, sentence-case eyebrows, card depth, the search and CommitField as wells, approval risk tags as chips.
  *Checked:* `make test` with SIDEFOLK_ADDONS_REPO on a clean add-ons clone at its origin/main (1581 core and 36
  character tests pass; the sibling add-ons checkout is 23 commits behind with a stray dist/, so its gallery, words and
  game tests fail there), the new `design-system-foundations|controls|sidecard` UI snapshots light and
  dark in English, German and Arabic read against the mockups' design-system boards, and Today, Settings › General, the
  Ask panel and the install sheet read in light and dark. *Half done:* 16 text fields still `.roundedBorder`; the
  theme-only Today blocks (console, planner) keep capitals; the layout keys of D64 still read (retire in phase 3).
  *Next:* phase 2, the desktop: place `LightPool` and `ShoulderBadge` under the companion (CompanionWindow), turn bubbles
  into `Whisper`/`SidecardCard`, the Ask panel into the Sidecard's Ask size on `SidecardSurface`, the stack, the
  permission slip (`SidecardStrip` calm/firm, `TouchChip(Touch(request.effect))`, ⌘Return on firm), pins as
  `PinCapsule`. Then phase 3 (Home) and 4 (Settings) on docs/DESIGN.md.

- **Miraya screen redesign and audio routing:** the approved responsive screen covers discovery, source selection, pairing, sharing and pause, with settings below the main choices. Mac only, TV only and Mac and TV are saved sound destinations; TV only uses a separately disclosed host-owned output-mute lease with crash recovery. *Checked:* Sidefolk and Miraya suites, sandboxed installation and destination choices, light/dark wide/narrow snapshots, an isolated Android TV emulator pairing with matching codes, and actual Mac output mute and restoration on closure and parent death. All nine localizations are complete; the unsigned gallery build and checks pass. *Still to verify:* live screen and sound playback with a physical TV. *Next:* exercise screen, window and region sharing and all three sound destinations on that setup; Released (D81): merged with D76 (its 14 new sentences in all ten languages), Sidefolk snapshot 593, then Miraya `1.0.0-snapshot.4` in the gallery (kept at 1.0.0, the founder's call). A Sidefolk before 593 refuses that snapshot (`output_mute` unknown).

- **Redesigned helper folks (D73, 2026-10-31):** the ten helpers now use paintings cut from the approved
  `folk-family/redesign-2026-10-31/folk-redesign-reference.png` in the desktop and app windows. Their roles,
  placement, accessibility and whole-body pop/breath/settle remain; the original vector rig is a fallback.
  `scripts/cut-folk-redesign.py` rebuilds the paintings; the companions are unchanged. *Checked:* all ten
  bundled artwork cases and the rendered contact sheet against the reference, a dark-background cutout review,
  `make test` (1502 core and 36 character tests), and Tempo beside Mochi in an isolated debug app with a real
  reminder. The running `/Applications/Sidefolk.app` is still snapshot 538; a fresh local `build/Sidefolk.app`
  (build 554) contains all ten paintings and is signed with the same Developer ID, but is not a published,
  notarized release and has no `SidefolkRelease` stamp, so its built-in updater will not replace it. *Next:*
  choose whether to replace the installed snapshot with the local build or ship a normal snapshot first.

## Summary of the snapshots up to 588 (as written on 2026-11-01)

Updated: 2026-11-01. Version 0.1.0. Latest: add-ons installed before the renumbering get the gallery's version (D80); snapshot 588 and the
gallery with the ten new games in the Play panel (D79, Playtime 1.0.0-snapshot.2); before that snapshot 581 with translations (D76), the companion chooser
(D77), colour meaning (D78) and new resting poses; before that Sidefolk and add-on updates chosen apart (D70), honest install sheets and
approval cards (D71), paired TVs without a card (D72), the helper folks redesigned (D73), extension pages that read
like app screens with Miraya's rebuilt (D74), and a crash fix (a download cancelled before it started). Before that: snapshot 538 and the gallery: the Calendar, extension pages
arranged by the person, Your Mac, Clipboard to replace Maccy and Miraya as an extension (D66-D69). Before that: the add-on gallery (D55): Ember, Kiko, Nimbo, Folio and nine
extensions moved to github.com/ghassenbrg/sidefolk-addons, signed packs Sidefolk downloads on demand (not
published yet: the founder runs scripts/publish.sh there). 1374 core and 34 character tests pass, serially.
Before that: the founder's list after snapshot 478: other agents change and
delete notes, with Settings › Privacy › Other agents choosing what they may do; Empty Trash; Light, Dark or Same
as Mac; spoken replies briefly or in full; releases only by default, offered again daily (D52); 3D companions
that really sleep; a notebook with collection icons, emoji and colours, pinned notes and notes formatted as you
write (D53); and a brainstorm on companions made by people and a gallery to get them
(docs/research/companion-marketplace.md). 1367 core and 34 character tests pass. Before that: 3D companions
(D51) and snapshot 478, published, signed and notarized.

## Done and verified (to 2026-10-31)
- **Agent sessions: "needs you" only when they ask (D12 amended):** finished notices are gentle, one per session,
  withdrawn on resume; "waiting for your input" counts as finished. *Checked:* `TrackerTests` (new
  `waitingForInputIsFinishedNotNeedsYou`), full `make test`.
- **Games: switching who guesses, more words, and toy-like art (D75, D79):** the founder couldn't switch Higher or
  Lower's mode (a closed game reopens its session; Play again kept the mode) and wanted more than one Daily Word a day.
  Playtime 1.0.0-snapshot.3 (published): both modes on the start board each time (last one preselected), a Switch
  button (S) in a game and on the end card; after today's word, "Play another word" practice rounds (random, no repeat
  until the list runs out, never in the streak, tallied apart). App: generated art for the cup, gem, balloon and trophy
  (`Play/Art`, 36 KB, chosen by the board parts' existing data; extensions still send no images), raised pads, keys and
  tiles with a press squash, an arcade reflex button, candy sticks, a felt cup table, confetti and a "New best!" sticker
  with the verdict only (Reduce Motion: none). *Checked:* add-ons `swift test` (100), `build.py` and check.sh; app
  `make test`; before/after snapshots of every game in light and dark, the thermometer in Arabic. *Not checked live:*
  the pads' playback, the cups' shuffle with pictures and confetti timing in motion.
- **An add-on version can need a Sidefolk snapshot (D83):** the founder's 590 showed Miraya snapshot.4's update failing
  on `output_mute`. Catalog minimums may name a snapshot (`AddonCatalog.fits`, `SidefolkVersion.running`); the validator
  reads `>=0.1.0-snapshot.N`; an install blocked only by unknown keys or the minimum says to update Sidefolk. Gallery:
  `addon.json` `minimum_sidefolk` (Miraya: 593). *Checked:* `make test` on a clean add-ons checkout; new tests
  `aSnapshotMinimumLeavesOlderSnapshotsOut`, `keysFromANewerSidefolkAskForAnUpdate`, snapshot requirements.
- **Copies from before the renumbering get the gallery's version (D80):** the founder's Mac kept Playtime 1.2.0
  (and git, currency, dev-toolbox, qr-codes 1.1.0, archives, feeds, images, pdf 1.0.0) from before D65, never offered
  `1.0.0-snapshot.<n>`, so snapshot 588's games never arrived. `AddonCatalog.offers(_:over:on:)` offers the gallery's
  version over a release the gallery doesn't list at or above; used by the updater, companion and theme updates, the
  gallery's Update state and the waiting list. *Checked:* `make test` with SIDEFOLK_ADDONS_REPO on a clean add-ons
  checkout (new: `aReleaseTheGalleryNeverListedIsOfferedItsVersion`, `aCopyFromBeforeTheRenumberingGetsTheGallerysVersion`).
  *Next:* ships with the next snapshot; until then a stuck add-on is removed and installed again from the gallery.
- **Games, phases 2 and 3 (D79, amends D75), merged into main (both repos):** all ten new games
  play in the Play panel from Playtime, beside trivia: Tic-tac-toe, Copy Me, Quick Paws, Which Cup?, Higher or Lower
  (both ways), Guess My Animal (it learns), Balloon Words, Last Stick (it teaches), Memory Pairs and Daily Word (one
  word a day per language, its streak on Playtime's Today tile). App: new board parts drawn, timed and fed by Sidefolk
  (`GameBoardParts`: pads with playback, cups with the shuffle, a reflex timed from the key's timestamp, meter, number
  pad, letter rows that flip, keyboards per script with Korean syllable grouping, a text field for input methods,
  sticks, lives), a board's `after_ms` for the companion's turn, a build-up before every verdict (`GameSuspense`
  extended: points, winning lines, cups, reflex times, guesses, flipped cards, end cards, with the previous words and
  keys), game titles from `strings/`, 24 sentences a game (ten languages), `zh-Hant` → `zh-Hans` in both language
  layers, the chance card's stripe no longer Play's red. Playtime: an engine adapter and a screen per game over the
  `Games.*` engines, one `EventCues` table, records in its folder, `Games.Random.fresh()`, Home listing every game
  with its best; trivia kept from phase 1 with the 400 questions × 10 languages as `TriviaPack`s and per-companion
  strengths (the Quiz engine removed); all words, the engines' phrases included, in `strings/` through `L()`
  (team/i18n merged in both repos first). *Checked:* `make test` with SIDEFOLK_ADDONS_REPO (1543 tests, among them a
  bot playing every game to its end over the channel in the sandbox in English, Japanese and Arabic, checking each
  build-up hides its verdict, and each game opening from its sentences in several languages); add-ons `swift test`
  (93); `build.py --unsigned` and `check.sh` (all ok; dist/ removed after); UI snapshots of Playtime's real boards
  (`--game-boards`, written by its `writeSampleBoards` test) for every game and moment, light and dark, in English,
  German, Japanese, Korean, Chinese and Arabic, read; the debug app (`build/qg1`) with Playtime from that build: a
  round of each game through dev commands with frames read (the companion thinking, Copy Me's playback, the cups'
  shuffle, a reflex timed, a Daily Word row flipping, trivia's beat and verdict). *Not done / next:* catching the
  companion by clicking it in Which Cup? (a "Check its paw" button does it); AI trivia packs; the bank has no
  "Did you know?" lines; new companion moves still borrow the nearest moment (D75); sounds and VoiceOver not heard;
  on a shared Mac, clicks on the panel from someone else reach the game (it never takes keys unless opened by the
  person). Playtime stays 1.0.0, shipped as its next snapshot (founder's call, D65).
- **Games beside the companion, phase 1 (D75), merged into main with D79 (both repos):** the Play panel (board parts,
  keys, focus rules, kept 10 minutes, one of Ask or Play at a time), `games` in the manifest and its validator, the
  game channel with its limits, `games.open`, companion cues from fixed lists with their pacing and Sidefolk's own
  lines in three tones, game sounds made in code (off by default, a speaker per game), Settings › Companion › Games,
  one Activity row per game. Founder's rules built in: no result before its reveal ends (`GameSuspense` build-up, the
  Ask card, spoken line and AI reply wait for a toss to land) and one colour per meaning (`GameVerdict`: success green,
  a calm sand loss tone `GameColors.lost`, neutral draw, always with a symbol). Rock, paper, scissors is Sidefolk's own
  best of three in the panel, its hand drawn and sealed before the person picks; both RPS bugs the founder found are fixed (the
  pumping fists looked like rocks; "paper wraps rock" drew paper over the person's rock). Coin with the companion's
  face, called or not; dice on a felt tray with real shapes; hands that clash; result chips and an Again pill; the
  companion reacts. Playtime with games (sidefolk-addons): trivia in the panel with no AI (topics, 5/10/endless, relaxed or
  15 s, the companion's sealed pick by how well it knows the question, a lifeline, facts, records, a Home page), words
  in ten languages through the Kit's new `Localized`, rules as engines under `Sources/GameKit` (`GameEngine`,
  `GameScreen`, `TriviaPack`) for the engines and content branch to drop into. *Checked:* `make test` with
  SIDEFOLK_ADDONS_REPO on the add-ons worktree (including Playtime played over the channel in the sandbox), `swift
  test`, `build.py --unsigned` and `check.sh` there; UI snapshots `--only game-,desktop-toss` in English, German and
  Arabic, light and dark; the debug app with Playtime installed from a local build, frames filmed through a throw,
  an answer and a called coin. *Half done / next:* the new companion moves (sulk, shrug, tease, ready, accents) borrow
  the nearest existing moment until made and filmed for every 3D companion; trivia's questions stay the 52 English
  ones until the content packs merge (they implement `TriviaPack`); Sneaky's switch shows once a game offers it;
  phase 2 parts and the new games (done in D79). A Sidefolk without games refuses Playtime's games snapshots at install, so
  the app ships before they are published.
- **Resting poses that suit each 3D companion (sit, lie, sleep), on branch team/poses in both repos:** the founder
  found Spark lying in the shared lie (rolled onto its side, a Mochi pose) looking broken: big helmet upright over a
  sideways body, legs sticking out. All ten were reviewed in the playground (front, ¾, side, head close up, and the way
  in and out filmed). Shared (engine): `POSTURES.lie` is now on the tummy, chin up to watch you, legs swinging behind,
  long tails laid down, the character's `stand` applied first (T- and A-pose arms came out sideways), and a small rise
  on the way down and up (blended with sitting, feet went through the floor); postures get `(t, P, C, w)`. Mochi keeps
  its sheet's side lie (`lieOnSide`). Spark: lie = kicked back on its hands, legs out; sleep = standby, sitting slumped,
  antenna drooping, face dimmed to a faint pulse (decal colour) and the headphone glow down. Add-ons: Ember sits
  higher with thighs and hips eased so the fur under the tail no longer goes through the floor, arms down (sit, doze);
  its right ear tip was weighted to tail.3 (rig_ember.py measured the tail's endless line: now `seg_dist`), fixed in
  ember.glb in place (599 vertices to ear/head, above the tail tip only). Kiko sits 0.08 lower (sit and doze floated).
  Purl flops back with its head lolled (lie) and slumps over its lap (sleep); Rune settles heavily, hands on the ground,
  and sleeps head sunk with the gem dimmed; Iris rests on its base tipped to one side and nods forward asleep, lens cap
  shut (rolled over, its lens warped). Nori, Ember and Kiko lie with the new shared lie. Folio and Nimbo: fine as they
  were. Older apps keep the old shared lie for Ember/Kiko/Nori (add-ons import no new exports). Tools:
  `restSheet`/`restFilm` in playground/sheet.js. Verified: before/after sheets and films for all ten; the debug app
  with Spark and Kiko (from the worktree), sit and lie by themselves and asleep, snapped (thresholds lowered only in a
  local build, not committed). Not checked live: the other eight in the app; Liveliness Lively's timings.
- **Extensions in all ten languages (D76), on branch team/i18n (app and sidefolk-addons):** an extension's words live in
  `strings/<language>.json` beside its manifest (manifest words people see, and its program's sentences under `text`),
  checked by the validator (known languages, strict keys, the manifest's limits or half as long again, placeholders,
  CLDR plural forms). Sidefolk shows the person's language everywhere (Settings, Home, tiles, palettes, heads-ups, tool
  titles, the install sheet, the gallery via the catalog's `localized`) and sends `language` with every tool call,
  watcher check, page and palette request. Kit: `L`, `L(one:other:count:)`, `Format`, `Language.with`, `KitWords`, and
  team/play's `Localized.swift` carried as it is (L looks plain words up through it). Extension text drawn right to left
  keeps numbers, sizes and paths the right way round (`BidiText`; "3024 × 1964" was reversed). Page details have 240
  characters. Every official extension but Playtime speaks all ten: World Clock, Calculator, Weather, System Vitals,
  Your Mac, Clipboard, Keep Awake, Miraya, Git, Currency, Images, PDF Tools, QR Codes, Archives, Dev Toolbox, Feeds
  (about 1,000 texts, plus their manifest words). `scripts/extension-strings.py sync|check`. *Checked:* `make test` with
  `SIDEFOLK_ADDONS_REPO` pointing at the add-ons worktree, 1521 of 1522 (the one left is AddonStoreTests'
  signed-gallery check, which needs a Developer ID build of the gallery; only an unsigned one was made); add-ons
  `swift test` (44); `build.py --unsigned` and `check.sh` (all ok, `Languages: en … ar`, Kit identical); the debug app
  (`build/qa1`) with Your Mac, Clipboard, Keep Awake and Miraya installed from that build's folders, in German,
  Japanese and Arabic: pages, Today tiles, install sheets read (German switch details were cut at 160 characters, now
  240; Japanese sentences no longer get a space between them in Your Mac). UI snapshots of the extension pages in
  Arabic rendered. *Not checked by eye:* a palette (snap doesn't capture it); gallery cards (needs a signed gallery).
  Merged with D75 in D79 (one section in EXTENSIONS, `zh-Hant` → `zh-Hans` in both layers). The app's install sheet subtitle wraps a folder path oddly in Arabic (the app's own text, not D76's).
  Packs change, so each official extension goes out as its next snapshot (versions unchanged, D65).
- **The companion chooser (D77):** Settings › Companion has Yours and Gallery at
  the top, as Extensions has Installed and Gallery. Yours is one grid of every companion the person can wear (built in,
  from the gallery, made by you, from a folder), each with a 3D/2D chip, where it came from, and a visible "…" menu
  (also Control-click): Wear, Update to …, Show in Finder, Remove… or Move to Trash… with a confirmation that says what
  goes, whether it can come back and who takes its place; built-ins and extension-made ones say why they can't be
  removed. Add Your Own (3D from a folder, D60's warning kept; 2D in the companions folder) and Get More (how many the
  gallery has) are tiles in the same grid; "Made by you" and "Control-click" are gone. Gallery: search, 3D/2D, maker,
  Hide yours, Name/Smallest/Newest (Newest only when the catalog dates entries), lazy pictures, details with Get and
  Get and Wear, progress in place, Settings › Updates' channel with Show Snapshots. Gallery companions this copy has no
  case for are worn by name on their `body`'s rig; the catalog may carry `published` and `body`; a gallery install never
  replaces the person's own folder companion of that name. Shared with Extensions › Gallery: `GalleryStatus`,
  `GalleryLastSeen`.
  *Checked:* `CompanionLibraryTests` (one list from four sources and its order, retired names left out, the worn one
  found, each menu's actions and why Remove is missing, the replacement when removing the worn one, search incl. words in
  the person's language, filters, orders offered only with data, bad `published`/`body` dropping an entry) and
  `AddonStoreTests.aCompanionWornByNameKeeps…`; UI snapshots with sixty sample gallery companions, a made-by-you and a
  folder companion (`page-settings-companion-yours|gallery|-search|-filters|-none|-downloading`,
  `sheet-companion-detail-get|owned|downloading|update`, `-add`, `-menus`, `-remove`) light and dark, English, German
  and Arabic; strings in all nine languages; the debug app (build/qa-ch, `SIDEFOLK_ADDONS` at a copy of the dist): a
  folder companion added and worn, Show Snapshots, Rune and Nori downloaded through the gallery's path from the real
  signed packs, the details sheet, the folder one removed through its confirmation (Mochi took its place) and Miso moved
  to the Trash. `make test`: 1518 core tests with 7 failures, all from the sibling sidefolk-addons checkout another
  teammate is changing (Miraya's manifest asks for `permissions.output_mute`, unknown on this branch; its staged
  qr-codes isn't signed), and 36 character tests pass.
  *Not yet:* the open "…" menu and the remove alert as drawn by macOS (snap can't draw an open menu or the alert's words:
  `sheet-companion-menus` and `-remove` show their items and words instead); a gallery companion this copy has no case
  for, downloaded and worn for real (the published gallery has none; the store test and the sample cover it); keyboard
  and VoiceOver by hand. *Next:* review on team/chooser, number the decision; in sidefolk-addons, `build.py` could write
  `published` so Newest appears.
- **Colours have meanings (D78):** red is now only for an error, a failure, a
  destructive action or real risk; amber for what waits (late reminders, "needs you" counts and chips, the badge on the
  companion, a countdown running out, medium risk, what the rules stopped); green for good outcomes; the accent for
  news (a page that changed is no longer red) and the now line on every time line (no longer red); calm ink for "no",
  skipped, paused, "Not available", working, watching and a stopped run. New theme roles `warning`, `warningSoft`,
  `onWarning` (Harbor: the brand sun, deepened to #8A5800 in light; Night Shift, Marshmallow and Field Notes their own),
  Core's `StatusTone` for the mapping, `Theme.color/soft` and `ChipTone(_:)` to paint it, and a theme check that
  refuses danger that doesn't look red, warning amber or success green. Rules in ARCHITECTURE › Colour meaning; tone
  meanings for extension authors in EXTENSIONS. *Checked:* UI snapshots before and after in Harbor, Field Notes and
  Night Shift, light and dark (pairs in the session scratchpad `colors/pairs/`), the character sheet's amber count,
  `sidefolk theme check` on the gallery's Daylight, Night Studio and Paper Garden (usable, with Harbor's amber and a
  warning naming the roles), StatusTone, ThemeCheck and transcript tests; `make strings` unchanged (no new words).
  `make test`: everything of mine passes; Miraya/gallery tests fail on the shared sidefolk-addons copy being edited
  (`permissions.output_mute`), unrelated. *Not built:* a late reminder in the snapshot sample data (late visuals are
  checked in code and tests only); Field Notes' link is rust, close to its danger,
  so news reads reddish there (a theme decision for the founder). *Next:* the gallery themes may add their own
  warning roles (sidefolk-addons).
- **Updates for Sidefolk and for add-ons, chosen apart (D70), on branch team/updates:** Settings › General › Updates
  now has "New versions of Sidefolk" (Don't check / Tell me, the default / Install automatically) and "Update add-ons
  automatically" (on by default); Versions to offer covers both. Install automatically downloads and checks exactly
  as Update does, then restarts once the person has been away five minutes with nothing running (no conversation,
  approval, voice, Ask panel or job: `InstallMoment`), or swaps in as they quit; the new copy says "Updated to …"
  once with What's New; anything that can't go that way tells instead, as before. Add-ons: companions and themes
  update by themselves; a gallery extension too, but only if its update widens nothing (no new permission, judged
  on the permissions themselves; no tool riskier than before; no `background`); otherwise it waits for Review… in
  Settings › Updates (the install sheet with "New permission: …") with one heads-up per version; a disabled one
  updates and stays off. With the switch off, Settings counts what waits (Update All), and a companion card gets an
  update mark. Old settings load as they were (`automatic: false` is Don't check). Also fixed: a download cancelled
  before it began (a Settings page closed while the gallery's catalog was on its way) threw an Objective-C exception
  and ended the app (`UpdateDownloader`); `scroll:<0…1>` lets `snap` see below the fold.
  *Checked:* AutoUpdateTests (the calm-moment rule, settings decoding, "Updated" once), AddonUpdaterTests (the rule
  on its own: same permissions, added permission, narrowing, network reason, riskier new and raised tools,
  background; against a folder gallery and a real host: same permissions installs, added permission and a riskier
  tool wait, the reviewed one installs through the sheet's path, a disabled extension updates and stays off, Releases
  doesn't see a snapshot, the switch off only lists, companions and themes follow the switch),
  UpdateInstallerTests (`atQuitTheCopyGoesInWithoutReopening`); `make test`: 1476 core tests, one failure, `theSignedGalleryPassesTheRealChecks` (it runs only with the signed
  sidefolk-addons dist beside this checkout and still expected "System Vitals+", named "Your Mac" since D67; fixed,
  passes alone), and 35 character tests pass; strings in all nine languages;
  UI snapshots of Settings › General and the ready window, light and dark, English and German; the debug app
  (build/qa-2): Settings › Updates for a copy built on this Mac, the add-on rows, the review heads-up, the ready
  window and the "Updated" note (`addons:review|waiting`, `update:ready|updated`), in English and German.
  *Not yet:* a real automatic install (needs two published releases, as D46's swap does: RELEASE.md › Updates says
  how); a real add-on update in the debug app against a local gallery (the same code ran in the tests against a
  folder gallery and a real host); Review… and Update All clicked by hand (agents can't click; Review in the debug
  app with the made-up entries would fetch from the live gallery, so it wasn't pressed).
  *Next:* review on team/updates, merge; then, after the next two snapshots, prove "Install automatically" by leaving
  the Mac alone (the log says `calm moment: installing`).
- **Install sheets and approval cards, honest but not scary (D71, branch team/trust):** the founder was scared by two
  red warnings installing his own Miraya, and by a raw-JSON card in Full access. The install sheet now says where it
  comes from first (gallery: signed and checked; folder: not checked; draft: written by Sidefolk), the same risky
  combinations in a calm *Good to know* box for Sidefolk's own signed extensions and a red *Read this before
  installing* box for everything else, what guards each permission beside it (per-call folders, Screen Recording's
  shared switch, programs' helpers, *Can't use the internet*), *After you install* (sandbox, background work without
  cards, Guard, Local Network, how to remove), what it adds folded, and an update that asks for more in its own box.
  Approval cards say an extension's arguments in words with *Exact request* folded, and why they ask after outside
  content (what was read first, what this call could do, that Full access or Auto doesn't decide it); Guard unchanged.
  *Checked:* `make test` (1478 core and 35 character tests; one failure not from this change: `AddonStoreTests.theSignedGallery…`
  expects "System Vitals+", and the published pack is now named "Your Mac"); new `InstallReviewTests`, `ApprovalReasonTests` (with an executor run: Miraya's TV list
  taints, the share card names Miraya, Full access still asks, no Always); UI snapshots `sheet-install-gallery`,
  `-unknown`, `-update`, `-extension`, `-draft`, `desktop-ask-outside` in light, dark, German and Arabic; the debug app
  (`SIDEFOLK_ADDONS` at the published dist, read only) with the real Miraya pack as a gallery download and as a folder.
  *Not yet:* the gallery's Get button end to end (the sheet was opened with `reviewFolder:` on a copy in
  `Addons/Downloads`), a real update sheet in the app (fixture only), VoiceOver by ear. A debug app on a fresh home
  without `SIDEFOLK_ADDONS` crashes at launch: `UpdateDownloader.download` creates a task on a session its cancellation
  handler already invalidated (`ThemeSettingsGroup` → `AddonGalleryModel.load`); not fixed here, the updater is
  another branch's. *Next:* the founder reads the Miraya sheet and a tainted card in a build; the stale keys the change
  left are marked stale in the catalog, as the tooling does.
- **A TV the person paired needs no card after outside content (D72, branch team/paired in both repos):** in Full
  access or Auto, "mirror my screen to the living room TV" asked every time because the run had read Miraya's TV list.
  Now, for Sidefolk's own agent after outside content in those modes, a tool of Sidefolk's own extension declaring
  `"reach": "paired"` (+ `"device"`: the parameter) is checked with the running program (`sidefolk/paired.check`, only
  the device's words sent, 5 s); when it names a paired TV, the call is bound to that TV's id and runs (Activity chip
  **Paired device**, `full_access_paired` / `auto_mode_paired`). Unpaired, unconfirmed, third-party or folder-installed
  copies, "Ask every time", "Ask once per kind", clean turns and typed commands: unchanged. A link not typed by the
  person, a file not in a folder allowed for that call, programs, file changes, high risk keep the card. Miraya
  (sidefolk-addons): declares it on share_screen, play_on_tv (`tv`), stop, pause, resume, seek, tv_volume; a paired TV
  comes before any other device the same words fit (also when no TV is named); a paired id resolves only to that
  pairing; the pin check is `TVConnection.accepts` (unchanged behaviour: exact SHA-256 of the certificate before the
  token is sent). Kit: `ext.paired`. Strings in all nine languages.
  *Verified:* `make test` with `SIDEFOLK_ADDONS_REPO` at the team/paired add-ons (1481+35 pass; `PairedDeviceTests`,
  `MirayaPairedCheckTests` run the real Miraya program in its sandbox through the executor with a tainted run),
  sidefolk-addons `swift test` (incl. a name collision and a spoofed id failing the pin), `build.py --unsigned` and
  `check.sh` against this app, the Activity chip in `--ui-snapshots`. *Not verified:* a real tainted agent run in the
  debug app (needs a live model) and a real TV (no TV or emulator used). *Next:* the founder tries it with a paired TV;
  maybe extend D47's "Always" to paired calls in "Ask once per kind".
- **Extension pages read like app screens; Miraya's page rebuilt (D74):** the
  founder found Miraya's page confusing (every button alike, nothing highlighted, "Show windows" only revealed more
  buttons). *Platform, for any extension:* a `hero` leading the page (state, large title, a large code, a picture, live
  facts, up to three large actions; it takes the banner's place), one primary button a page (`ExtensionPage.parse`
  demotes later ones), `plain` and `disabled` buttons, destructive filled red when nothing is primary, `choice` styles
  `cards` / `tiles` / `rows` with badges, per-row actions and `key`, a `transport`, sections in a side column
  (`place: side`) or folded (`collapsed`). Layout rules moved to SidefolkCore (`ExtensionPage+Layout.swift`); drawing in
  `Home/ExtensionPageHero.swift`, `ExtensionPageChoices.swift`, `PageRegions`; the Kit (both copies) has `Hero`,
  `Transport`, `Action`, `Option`, `Badge`, `.picker`, `Section(place:collapsed:)`; docs/EXTENSIONS.md and the
  extension skill (both copies) say how. Today's tile button keeps its style (Start filled, Stop red).
  *Miraya (sidefolk-addons):* `MirayaPage` builds a page per state from a `Now` snapshot (no TV, ready, new TV, problem,
  pairing, authorizing, connecting, sharing, paused, playing); `Shots.swift` takes 480 × 300 stills of displays and
  windows (and dimmed parts of a screen) with ScreenCaptureKit only while the page is open, every 20 s at most, never
  while sharing, and only if recording is already allowed; `set_option` also takes `kind`, `display`, `window`, `area`
  (main.swift; no manifest or Tools.swift change); `choices.json` gains optional keys.
  *Checked:* UI snapshots of all ten Miraya states (made from Miraya's own `MirayaPage.make` output,
  `Dev/SampleMirayaPages.swift`), light and dark, narrow (640) and wide (1560), German and Arabic (the side column and
  hero mirror right to left); Your Mac, Keep Awake and Clipboard pages unchanged; the debug app with Miraya built from
  the branch (unsigned, outside the repo): the real page in the sandbox (no TV here: the no-TV state) and a setting
  changed through Guard (asked, approved, saved). New tests: `ExtensionPageLayoutTests` (five), Miraya's sandbox test,
  sidefolk-addons `MirayaTests` (each state's JSON, one primary everywhere, limits, the dimmed part). *Not yet:* any
  state with a real TV (pairing, sharing, a video) in the running app, only through fixtures; window and display stills
  in the running app (the debug app isn't allowed to record here); clicks by hand on tiles, rows and folding; Arabic
  extension text with numbers ("3024 × 1964" reads reversed in RTL: extension text has no direction of its own, an
  older issue of every page). *Next:* the founder looks at the page with a TV and Screen Recording on; then merge.
- **3D companion lay down while alerting (fix):** the 2D director resets the posture to standing on any non-idle
  state but sends no cue, so a 3D companion that had lain down stayed lying, eyes open, when a bubble or alert
  arrived. `engine.js` `setState` now stands up for every state except idle (and `sleeping`, which lies by design).
  *Not yet checked in the running app:* lying down needs minutes of quiet; the next step is `make dev`, wait (or
  set `lieAfter` low), then `swift scripts/dev.swift ask:` / trigger a bubble and snap.
- **Home design brainstorm (sandbox only):** explored a connected Now, Notebook and Activity experience and three
  theme directions; see `sandbox/home-design-themes/PROPOSAL.md` and concept boards (local, not in git). *Next:* review
  the concepts with the founder before changing the app.
- **The founder's review of snapshot 515, on branch team/merge (D66, D67, D68):** five team branches merged into
  `team/merge` (from extension-services; sidefolk-addons `team/merge` has its side), with strings in all nine languages.
  - *Fixes:* a gallery pack is named by its bundle, not "Resources" (no "did you copy a template" warning; the install
    sheet says "from the Sidefolk gallery"); a gallery companion turned from 3D to 2D gets its painted rig, not its
    undrawn 3D stand-in made visible (`CharacterLook.identity`).
  - *Today and Calendar (D66):* `WrapRow` keeps words their room in narrow columns (Watching's empty state read "Not /
    watchi / ng"; Agents at work, Recently, headers, queue rows, Planner and Stage too); Your day (`DayLine`) puts every
    chip at its time (they were slid left to fit) with labels that never touch; Home › Calendar (⌘5): month, week and a
    14-day list of reminders (repeats expanded), their notes, what was done and the Mac calendar's events, moved,
    added and edited through Today's paths; `WhenField` everywhere a time is set: typing first, a picker beside it.
    `WhenParser` read ISO years in the person's calendar; now Gregorian.
  - *Extension pages (D67):* pages fill the window (Your Mac used half of it); the Extensions group folds and is
    arranged by the person; All Extensions; a page's main switch on its tile and sidebar row (Keep Awake); System
    Vitals+ is Your Mac with its own icon, and System Vitals rests while it's on; icons in Home simple or colourful
    (theme `layout.icons`, Settings › General); one rounded `ExtensionBadge` everywhere.
  - *Clipboard (D68):* pictures and screenshots with thumbnails, a preview beside the list, Maccy's keys, pins in their
    own section, 100–5,000 copies, four search modes, ignore rules, skip next, paste or only copy, the palette in the
    menu bar menu; the source app answered once per copy. Not built: pin letters, app icons in rows, match highlights.
  - *Skill:* `.claude/skills/sidefolk-extension/` (mirrored in `.agents/skills/`) takes an agent from "is it an
    extension?" to a shipped one, with Water Tally, a template verified from a copy outside the repo (built, tested,
    `sidefolk ext validate`, installed in a debug app). The older public `skills/sidefolk-extension` has the same name
    and is stale (says clipboard is impossible, no gallery): refresh it.
  - *Checked:* each branch's own tests and `make test`; on the merge, `make test` with the merged add-ons (1460 core, 35 character, all pass); UI snapshots of Today
    at each theme's tightest width, the Calendar in all themes, Your Mac wide and narrow, the Clipboard palette with
    pictures; debug apps with real data (Keep Awake's power assertion taken and released, Clipboard on a private
    pasteboard, Iris 3D→2D in Settings). *Not yet:* by hand: drags (Calendar, sidebar), right-click menus, ⌘Z, the ⌘↓
    picker, real ⌘V paste with Accessibility, Clipboard's source app end to end; Arabic for extension pages; the install
    preview doesn't name `background` or palettes (docs/EXTENSIONS.md says it does). *Miraya (D69):* the Mac side of Miraya as a gallery extension, named and drawn as Miraya;
    new `permissions.screen`, `udp`, `network_purpose`. Checked against Miraya's TV app in the Android emulator: the
    code matched on both screens, approval on the TV, reconnecting without a code, a file played with seek, resume
    and stop; in a sandbox probe, screen → H.264 → UDP → decoded. *Not yet:* a mirrored picture on a real TV (the
    emulator's network blocks direct UDP): with Sidefolk allowed in Screen Recording and Local Network, say "mirror my
    screen"; an HTTPS link played; sound on the TV only, a drawn area, Stop on the tile. *Released:* merged into main in both repositories; snapshot 538 (8b584618, Developer ID,
    notarized) and the gallery published the same day (Your Mac, Keep Awake and Clipboard as 1.0.0-snapshot.2, Miraya
    1.0.0-snapshot.1; the downloaded catalog checked against the build and its signature). *Next:* the founder tries
    538 by hand (Calendar drags, sidebar arranging, ⇧⌘C, "mirror my screen" on a real TV).
- **A release stays beside the next version's snapshots (D65 amended):** once an add-on is released and its next
  version starts snapshots, the gallery lists both (the release first) and Settings › Updates picks:
  `AddonCatalog.entry(_:on:)`, `companion(_:on:)`, `offered(on:)`; sidefolk-addons e99c207 keeps the latest release's
  pack in `build.py` (`latest`, `kept_release`). *Checked:* `aReleaseAndTheSnapshotAfterItAreBothListed`, `make
  test`, the helpers on made-up versions and keeping a live pack, and a signed build against the live gallery giving
  exactly its packs (so nothing to republish). *Not yet:* a real release in the gallery; nothing is released.
- **Every add-on in snapshots; the gallery follows Settings › Updates (D65 amended):** companions and themes are
  `1.0.0-snapshot.<n>` until released, like extensions (sidefolk-addons 17020a4; a theme's packed `theme.json`
  carries the snapshot version). The gallery (a GitHub pre-release now, not "Latest") was published once more with
  all 23 add-ons at `1.0.0-snapshot.1`; the twelve extension packs were kept byte for byte. On Releases (the
  default) the gallery shows and updates released versions only, so today it shows none and says why, with Show
  Snapshots (Extensions › Gallery, the companion picker, themes); on Releases and snapshots it shows everything and
  offers newer snapshots. Installed add-ons stay whatever their version. *Checked:* every live pack downloaded and
  matched against the signed catalog; the add-ons' `check.sh` against this app; ReleaseVersionTests
  (`aChannelOffersSnapshotsOnlyWhenChosen`), AddonStoreTests (a theme from snapshot to snapshot to release, by
  channel; the AI's gallery lines by channel); `make test`; the debug app with the live gallery: the companion
  picker on Releases (no gallery companions, the note) and on snapshots (all eight). *Not yet:* clicking Show
  Snapshots by hand (agents can't click); Extensions › Gallery and the themes list looked at (same note and model).
- **Extensions that keep running and act; Clipboard and Keep Awake (D63):** `background` extensions, clipboard and
  power permissions, palettes on a shortcut that paste, page switches and buttons, nudges. Clipboard (⇧⌘C, Maccy's
  replacement with secrets masked and forgotten) and Keep Awake (Mouse Jiggler's, with nothing moving) are in
  sidefolk-addons (1.0.0 snapshots, minimum 0.1.0). *Checked:* ExtensionServiceTests (manifest, sandbox lines, palettes and nudges with a
  fixture, Keep Awake for real), the add-ons' ClipboardKeepAwakeTests, UI snapshots (`panel-extension-palette`,
  `page-extension-awake`), and the debug app: five copies captured and classified, the palette listing them, "keep my
  Mac awake for 30 minutes" holding `PreventUserIdleDisplaySleep` and "let my mac sleep" releasing it. *Not yet by
  hand:* Return pasting into another app and the nudge (both need Accessibility granted to the debug build); pictures
  in the palette show no thumbnail.
- **Extensions add pages; System Vitals+ (D62):** `pages.<name>` in a manifest puts a page in Home's
  sidebar (Extensions) and, with `widget`, a tile on Today; the extension answers `sidefolk/page.render` with
  parts Sidefolk draws itself (gauge, stat, chart, bars, facts, note, ask) and its watchers are switches under the
  page. Sidefolk keeps the charts' past (`PageHistory/`) and reads `history`/`widget` pages once a minute. System
  Vitals+ is in `sidefolk-addons/extensions/system-vitals-plus` (gallery, minimum 0.1.0): page, 8 tools with commands,
  7 watchers, nothing leaves the Mac. *Checked:* ExtensionPageTests (parsing, history, manifest, System Vitals+ in
  the real sandbox), the add-ons' SystemVitalsPlusTests, `scripts/check.sh`, `make test`, UI snapshots
  (`page-extension-mac`, `page-now-extension-tile`, light and dark), and the debug app with the extension installed
  from a folder (`dev.swift installFolder:` / `page:`). *Not yet:* the page in Arabic looked at; page text is English
  only.
- **Sidefolk stays 0.1.0, extensions are in snapshots too; snapshot 515 (D62 amended, D65):** the founder keeps
  snapshots on 0.1.0 until 0.1.0 ships, so `SidefolkVersion` is back to 0.1.0, v0.2.0-snapshot.513 was deleted and
  v0.1.0-snapshot.515 (8d5ac0d0, notarized) is the first public build that installs extensions with pages. Extensions
  are in snapshots until released (D65): all twelve are `1.0.0-snapshot.1` asking `>=0.1`, published once from
  sidefolk-addons 535abb3 with all 23 add-ons, themes included (two sessions publishing apart had deleted each
  other's packs, since publish.sh removes what its own dist/ lacks). *Checked:* every live pack downloaded and matched
  against the live catalog; the numbering (same files keep the snapshot, changed ones get the next, a new version
  starts at 1); snapshot 515's own `sidefolk ext validate` on the live System Vitals+, Clipboard and Keep Awake packs;
  `make test`; the add-ons' tests. *Not yet:* installing from the gallery inside snapshot 515 by hand; the gallery
  shows the raw `1.0.0-snapshot.1` (`ReleaseVersion.shown` would read "1.0.0 snapshot 1").
- **Gallery companions update by themselves (D55, amended):** a companion from the gallery gets its newer version
  90 s after launch and every six hours after, without asking; the one on the desktop swaps in place. Extensions
  keep their Update button. Launch's tidy no longer deletes a download already under way (a chosen companion coming
  back at launch failed with "unpacked doesn't exist"). *Checked:* AddonStoreTests (an update installs; a newer
  engine waits; a bad pack keeps the old copy; tidy keeps this run's downloads), and live: a test gallery with a
  red-scarf Nori 1.0.1 over an installed 1.0.0 swapped on the desktop 90 s after launch. *Not yet:* Settings shows
  no "updated" note.
- **Iris, Nori, Purl and Rune in 3D (D61):** four gallery companions from the founder's sheets, add-ons in
  `sidefolk-addons/companions/` (built and signed, not published). Iris, Purl and Rune were modelled again after
  a first pass that missed their sheets; Nori kept its model and lost the glossy strip over its glasses. Rig kit:
  `regutter()` (no pale seam cracks) and `mark()` (a part mask the material reads as `part`); the playground's
  `sheet.js turnaround()` saves front, ¾, side and back to compare with a sheet. *Checked:* turnarounds and the
  16-cue sheets of all four against their sheets in the playground; the dev app (all four animate, Rune waves);
  `make test`. *Not yet:* the founder's review; Iris's arms pull a little yellow from the body's sides when raised;
  the stand-ins were resized to the new models but not looked at in the app. The app's side (cases, stand-ins,
  role lines, strings, tests) went in with the 2D work (8d3db65c, D59). The founder approved the four; *Next:* the
  founder runs `scripts/publish.sh` in sidefolk-addons (this session's permissions blocked the upload); the app
  offers them once a release has their cases (older copies skip companions they don't know).
  *Review round (the founder on Nori):* fixed the tail tearing a sheet off the head in a flip, the feet dragging the
  tail, the cream nape and torn paw and tail-tip edges, grey brows, bright eyes and a wide mouth (now a ω); Purl got a
  linen weave, Rune granite speckle and an amber gem with depth, Iris one dark brow arc and a dark mouth. *Checked:*
  every move filmed front and side, close-ups of all four, the 8-mood sheet of Iris, the dev app (`build/review4`).
  Then the same pass on Iris, Purl and Rune (no Meshy credits): Iris turns as a whole when it looks round
  (`turnWhole`), Rune's open mouth is smaller; Purl's 36 moves were already clean.
- **3D companions added from a folder; likeness faces (D60):** Settings › Companion › Made by you › Add from
  Folder… checks a companion's folder (addon.json and exactly its four files, sizes and kinds), warns that its
  character file runs as code, installs it beside the gallery's companions and wears it
  (`AppSettings.localCompanion`, over a borrowed stand-in rig). The 3D page now has a Content Security Policy: only
  `companion3d:` files. The ink face gained `layout.lids`, `layout.mouth.lips` and `layout.brow: false` for faces
  that live in the texture. The founder's own two (themselves and Kana) are in `~/git/sidefolk-private/`, outside
  every repository (README there; 165 Meshy credits). The playground's `?c=` takes any companion the server finds.
  *Checked:* LocalCompanionsTests (6) and the full suite; both companions' review sheets and face close-ups in the
  playground (Mochi and Spark unchanged); in the debug app, both added from their folders, on the desktop
  (animating, a wave, Mochi's page still loading under the new policy), in Made by you and in the Ask panel's
  header. *Not yet:* a UI snapshot of Made by you with a local companion; the two avatars in that list aren't
  aligned (Use is wider than the check mark).
- **Every companion in 2D: painted cut-out rigs (D59):** all ten can be 2D or 3D (Settings › Companion › Look). The
  look follows one style target (`companions-2d/references/lineup-2d.webp`). After the founder found the hand-drawn
  vector parts "very ugly" next to it, nine became painted cut-out rigs: Codex image gen paints each one's parts
  (blank-faced head, body, arms, ears, tail, feet; `companions-2d/parts/generate.sh`), `cut.py` keys and cuts them,
  and the rig moves them on vector outlines measured off the target, the face drawn live on top. Mochi stays the flat
  vector drawing the founder approved. Necks fixed after the founder's note: bodies sit up and wide under the chin,
  shoulders raised, no pinched neck; and legs: painted paws and boots are drawn in front of the legs (they were hidden
  behind them), sized to the target's. Nori repainted after the founder's second note (a chubby pear-shaped body, the
  whole lower face cream, thick arms hanging close), drawn at nearly full size. Its legs then cut short (`"keep"` in
  `parts/nori.json`, the cut's corners rounded off behind the paws) and its paws made bigger and set side by side, as
  in the target. Its body widened (`widen` in `Species.painted`) so it isn't thin under its head without a scarf.
  Sleep redone after the founder found it "just shrinks": no squash any more (asleep or lying down); the body settles
  onto planted feet, the head droops aside and nods with each breath, arms hang in front, closed eyes in plain ink, a
  small round mouth; Nimbo, Folio and Iris lean and sink whole. Checked in the sleeping tile of every companion and
  films of Nori and Nimbo falling asleep; the lying-down posture only by its test, not by eye. Spark, Ember, Iris,
  Nori and Purl needed parts painted again (wide heads, a drawn face); the Ember head edit was refused by the image
  model's safety filter, so `blank.py` took the face off. How to make one: `companions-2d/README.md` (the base for a
  2D-character skill). *Checked:* `overlay-<id>.png` (rig over its target) for all nine, contact sheets of every state
  and prop, the lineup, the full suite (1391 core, 34 character), the dev app (painted Ember, Nori and Spark on the
  desktop and in Settings, art loaded from the bundle in the app's Resources). *Not yet:* the founder's review; a 2D
  companion's motion filmed for each one (Ember and Nimbo were, before painting); Iris's closed eye is an ink arc on
  the glass, not a shutter; folks and custom companions keep the soft look. *Next:* the founder reviews the ten
  (`swift run sidefolk-render out/`, or the dev app), then the 2D-character skill from the README.
- **Themes, steps 1–10 built: a theme arranges the app's own pieces, each theme as faithful as its board (D57,
  D58, D64):** reasons in `docs/research/themes.md`, plan in `docs/research/themes-plan.md`, each board's elements
  against the app in `docs/research/themes-fidelity.md`, boards locally in `sandbox/theme-sandbox/`. Steps 1–8:
  tokens, Today, the one bar, Your day with the calendar, watch tiles and agents, theme files with a check, install
  and live reload. Steps 9–10 (D64): Today is rows of columns of blocks (header, queue, day, watching, agents,
  recent, notes, art, companion), each in several styles, that a theme's `layout` arranges; presets desk (Harbor,
  now two columns as its board), board, console, stage, planner; rail with a status bar, pill tabs and ribbon tabs;
  collections as a column, jars or washi tabs; Activity as a table, log or diary; a Markdown editor with tabs and an
  outline; the one bar's Will do panel (`IntentPlan`: action, parts, tool, risk, no model call); sparklines from
  recent report values; each agent's steps. Built in: Harbor, Night Shift, Marshmallow, Field Notes
  (`Resources/Themes`); gallery: Daylight, Night Studio, Paper Garden, packed in sidefolk-addons `themes/` (not
  published: the founder's step), installed through `AddonStore.install(theme:)` and the shelf in Settings ›
  General › Theme. Art by image generation (Daylight's night sky, Night Studio's dawn, Marshmallow's Moonlight
  stage), grain drawn in code. 122 new strings in all nine languages. *Checked:* the full suite in a clean
  worktree (ThemeCheckTests with every preset and every built-in, IntentPlanTests, a gallery theme install and
  update, report value history); `--ui-snapshots --theme` for all seven themes in light and dark, side by side with
  their boards; French and Arabic (right to left); the debug app with a fresh home: Night Shift chosen, its Console
  and status bar drawn from the bundled theme, Settings listing the four built-ins with the "drawn for Spark" offer.
  *Not built:* editing the Will do chips with Tab, a progress bar for runs (no run reports progress), Glance per
  theme, blocks from extensions (reserved as `extension:`). *Next:* publish the three gallery themes
  (`scripts/build.py` then `publish.sh` in sidefolk-addons), then the create-a-theme skill from this work.
- **Gallery packs newer than the catalog (D55):** republishing rebuilt every pack under the same name, so a copy
  that had fetched the catalog in the 30 minutes before refused Folio, Kiko and Nimbo ("didn't arrive as the
  gallery describes it"). Now a pack that doesn't match makes the store fetch the catalog again and retry with
  the new entry, and sidefolk-addons' `build.py` keeps the published pack of every version already released
  (stopping when files changed without a new version), `publish.sh` uploading only new ones. *Checked:* a test of
  a rebuilt pack under an older catalog; a signed build kept all 13 published packs byte for byte; check.sh on
  the staged files. *Not yet:* the gallery release still has the catalog without `source` digests until the
  next publish (harmless: older Sidefolk ignores the key).
- **Robot retired, gallery shelves and search, add buttons in sight (D56):** the original robot companion and its
  rig are gone (saved settings move to Mochi). Settings › Extensions › Gallery: search, shelves (Everyday, Files,
  Developers, Fun) with counts, grouped by shelf; Install from Folder… and Add MCP Server… at the top of the page.
  CI's failure was a real race in `DailyChore.stop` (a run already past its check finished after stop); stop now
  waits for it. *Checked:* tests (shelves, search, a saved robot becoming Mochi), the dev app (Gallery with
  shelves, Installed with the new header, the companion picker without the robot). *Not yet:* the gallery release
  still has the catalog without shelves until it is published again (sidefolk-addons scripts/publish.sh). The
  README's companions picture is rendered again without the robot.
- **The add-on gallery (D55):** built in now are Mochi, Spark, the robot, the folks and four extensions (World
  Clock, Calculator, System Vitals, Weather). Ember, Kiko, Nimbo, Folio and Git, Currency, Playtime, Images, PDF
  Tools, QR Codes, Archives, Dev Toolbox and Feeds are packs in `sidefolk-addons` (`scripts/build.py` signs each
  and the catalog with the Developer ID; `scripts/publish.sh` uploads them to its `gallery` release). Settings ›
  Companion shows the gallery's companions as dashed cards with the seal and size (a click downloads and picks
  one; Control-click removes); Settings › Extensions › Gallery lists the extensions (Get → the install preview,
  Update, Added). Moved built-ins already installed stay, as add-ons; a chosen companion that moved comes back by
  itself. *Checked:* AddonStoreTests (catalog rules, a companion installed, replaced and removed, packs that
  aren't what the catalog says, the real signed packs from `sidefolk-addons/dist` through the real check, another
  team refused, adoption of moved built-ins, the AI's line); the moved extensions' sandbox tests against the
  sibling checkout, skipped cleanly without it; in the dev app with `SIDEFOLK_ADDONS=…/dist`: Ember (chosen
  before) came back from the signed pack and drew in 3D, the companion gallery and the extensions Gallery shown.
  *Not yet:* the `gallery` release isn't published, so a copy built now finds no gallery online until the
  founder runs `scripts/publish.sh` in sidefolk-addons; clicking Get in the native window wasn't driven by hand
  (the same code ran from launch and in tests); the add-ons repo's CI only builds and tests (signing stays on the
  founder's Mac).
- **Profile pictures; folks are helpers only (D54):** six profile pictures (Codex image gen from each 3D render
  and sheet) in the Ask panel's header and beside each reply in Home › Conversations; 2D and custom companions
  show their drawn face on a disc. Folks are no longer in the companion gallery; a saved folk becomes Mochi.
  *Checked:* the Ask panel in the dev app (Ember, Nimbo, 2D Mochi), UI snapshots of Conversations and Settings ›
  Companion, CompanionChoiceTests.
- **Other agents change and delete notes; settings (D52):** `notes.update` and `notes.trash` reach Claude Code,
  Codex and other MCP clients (to the Trash only; only the person empties it). Settings › Privacy › Other agents:
  saving, changing and reading each Allow / Ask each time / Off (defaults Allow, Allow, Ask); Off hides the tools
  and refuses with words naming the setting. The skill and MCP instructions say so (installed copies refresh on the
  next Connect). Home › Trash › Empty Trash… (confirmed). Settings › General › Appearance. Settings › Voice ›
  How much to say: Briefly or Everything (up to about two minutes, then "The rest is on the screen."). Updates:
  releases only unless snapshots are chosen; a version let pass comes back the next day. *Checked:* tests (a
  fake MCP client saves, ticks and trashes a note, then is refused when turned off; full readings; the update
  timing), a note saved through `sidefolk mcp` into the dev app, UI snapshots of each new setting and the Trash.
  *Note:* no production release exists yet, so a snapshot copy left on the default now finds nothing to update
  to until 0.1.0 ships; choosing "Releases and snapshots" brings snapshots back.
- **Sleeping 3D companions:** Mochi and Spark sleep on their tummy facing you, chin on their paws, ears flopped,
  eyes closed; Ember and Kiko nod off sitting up (`doze`); Nimbo and Folio keep theirs. *Checked:* each one in
  the playground at the app's framing. *Not yet:* the 2D companions' sleep is unchanged.
- **Notebook looks and formatting (D53):** collection icons (30 symbols or any emoji) and 12 colours from Edit…
  (and when made), shown in the sidebar and the header; pinned notes first; notes formatted as you write
  (headings, bold, italic, strikethrough, code, links, bullets, numbers, checklists that tick on a click, quotes)
  from a formatting bar or shortcuts, stored as Markdown (`NoteMarks`), marks hidden except on the line being
  edited. *Checked:* NoteMarks and store tests, UI snapshots light and dark (a formatted, pinned note; the Edit
  collection sheet). *Not by hand:* typing in the editor (Return continuing a list, clicking a box, marks
  showing on the caret's line, the shortcuts): agents can't type into the native window. *Next:* the founder
  tries writing a note.
- **3D companions (D51):** Settings › Companion › Look chooses 3D (how Mochi and Spark now come) or 2D;
  Ember (a red fox), Kiko (a kid astronaut), Nimbo (a floating cloud, remodelled after the founder's sheet)
  and Folio (folded paper) join the gallery in 3D only. A three.js page in a transparent web view
  (`Companion3DStage`, `Resources/Companions3D`) under the 2D view plays every cue of the undrawn 2D rig
  (stand-in rigs for the 3D-only four), so states, idle life, clicks, petting, dragging and bubbles work as
  before, and the 2D effects and badges draw over it; its moves ask for more (zZz, hearts, notes, sparkles,
  "?", "!"). The chosen form shows at once (no 2D flash; 3D to 3D swaps inside the running page). Balanced and
  Lively add 3D moments (turning round, twirls, each one's trick); petting deepens into bliss; reactions to
  news, work done and errors come from one table by liveliness, and every move is announced (the hook for
  sounds later). Eyes ride the face surface; Spark's visor is smoked glass. Models from Meshy (sheets drawn
  with Codex image gen where there were none), rigged in Blender; sources, prompts, task ids and rig scripts
  in `companions-3d/`, and a skill to make more (`.claude/skills/sidefolk-3d-character`). *Checked:* all
  tests (incl. 2D/3D settings); every companion in the browser playground (feelings, moves, postures, tricks,
  petting, reactions); the dev app: each one on the desktop and animating, switches between forms and
  companions, a dance with notes, a reminder's "!" and count over the 3D Mochi, Settings' Look control and
  live preview. A 3D companion costs about 18% of a core (2D: 0.2%). *Not yet:* working props (laptop,
  notepad…) in 3D, VoiceOver and several screens with a 3D companion, a signed release. *Next:* the founder
  reviews the six on the desktop.
- **Approved 3D Mochi app icon (D29 amended):** the smiling white rabbit with navy ear tips and a
  turquoise scarf on midnight blue now supplies the ICNS and Xcode AppIcon. The committed master is an
  opaque, full-bleed square, prepared with the built-in image tool from the approved preview; only the
  macOS exports get the platform inset and rounded mask. `brand-assets.swift` rebuilds from that master,
  and the brand preview and asset guide are updated. *Checked:* exporter; opaque 2048/1024 sources;
  all ten icon dimensions, transparent corners, matching catalog exports and decoded ICNS representations;
  actual ICNS sizes at 16–256 px on light/dark backgrounds (`build/icon-qa/sizes.png`); release app built
  and signed with Apple Development, deep/strict signature verification passed, bundled ICNS matches the
  source and Info.plist names it. No runtime changes or live AI calls in verification. Nothing half done.
  *Next:* the next signed release/snapshot carries the icon to installed copies; this change has not been
  published. Local app: `build/Sidefolk.app`.
- **Conversations (D45):** every Ask answer opens on 8 lines with Show all and offers Reply in its own
  conversation, Copy and Open in Conversations; "new conversation", "start fresh", ⌘N and Clear all start fresh;
  Sidefolk's window › Conversations lists kept conversations with search and a transcript (steps included),
  replies after the 10-minute window, deletes one or all (also Settings › Privacy). Clear all now sits above the
  results (in German the header left the companion's name no room). *Checked:* ConversationsTests, UI snapshots
  in light, dark and German. *Not by hand:* ⌘N, the reply chip, a reply from the window with Stop.
- **Updates (D46):** a published copy looks for a newer release or snapshot on GitHub a minute after launch and
  daily, asks in a gentle bubble, the menu bar or Settings › General › Updates, and on Update checks the download
  (size, SHA-256, the running app's own Developer ID team and identifier, notarized), swaps itself in and reopens;
  a copy that can't replace itself gets the checked image in Downloads. release.sh stamps `SidefolkRelease`.
  *Checked:* tests with fake bundles, a real hdiutil image and a real ad hoc signature refused; live, the release
  list and the published 411 image (both checksums, mounted, requirement met, another team's refused); a dev app
  stamped as 404 found 411 by itself after 61 s. *Not yet:* a real swap, which needs the second release that
  carries the updater (RELEASE.md › Updates).
- **Using the internet (D47):** Settings › Privacy & Permissions: Ask each time / Ask once for each site
  (default) / Don't ask before reading, and the sites and services you allowed (Remove, Add). A site or built-in
  service allowed for good keeps working after Sidefolk read a page (before, every web use asked, every time); a
  read held to its site can't be redirected off it; a CPU or memory report never counts as network. *Checked:*
  InternetRuleTests (17), the redirect test, the Full-access exfiltration test unchanged, snapshots. *Not by hand.*
- **Your location (D48):** Settings › Privacy › Your location: off (default), the Mac's location (a town, from
  Location Services) or a town chosen by name. The AI hears the town, never coordinates; weather and reports with
  no place named use it; with none known Sidefolk asks which, with a button to the setting. New entitlement
  `com.apple.security.personal-information.location`. *Checked:* tests with a fake locator and geocoder, live
  Open-Meteo search, UI snapshots of six states. *Not yet:* the real Location Services prompt.
- **Reminders for a note or task (D49):** "Remind me" in the Notebook (an hour, this evening, tomorrow morning, any
  time), "add a task to call mom at 5", "remind me about the report task tomorrow at 9"; a bell and time on the
  item, the item on the reminder, Mark done and Open on the bubble; a task done or trashed ends its reminders,
  reopened or restored brings back the ones ahead. Migration `v3-reminder-links`. *Checked:* about 40 tests, the
  Notebook snapshot, a real dev app over its own socket (linked save, firing, Mark done).
- **One reading and chance on the desktop (D35, D44 amended):** "what's my CPU usage", "how full is my disk",
  "temperature in Fukuoka" answer once with no AI and nothing left running (`watch.read`); coins, dice and
  rock-paper-scissors are drawn in core (`companion.toss`) and played by the companion above itself, landing on
  the result, from words, the Play menu or the AI; Playtime keeps trivia and picks (1.1.0). "A joke about the
  weather every minute" no longer names a place called Joke. *Checked:* tests, the dev app (coin, 3 coins, 2 and
  7 dice, rock-paper-scissors), snapshots, the new moves for Mochi and Scout.
- **Instant answers from extensions (D50):** an author lists sentences ("time in {place:place}") that run a tool at
  once, without the AI, and can keep a tool from the model (`"ai": false`). Built-ins answer "what's 12*7", "15% of
  80", "convert 5 km to miles", "100 usd in eur" (asks once: it uses the internet), "time in Tokyo", "pick one: tea
  or coffee", "new uuid", "about this mac". Core first; two extensions → the AI; a tool that can't answer → the AI.
  Settings › Extensions › Details and the install preview list each one's sentences. *Checked:*
  ExtensionCommandTests (15), ExtensionCommandBuiltInTests (6, with the real programs), the dev app with no AI.
- **Extensions list (D39 amended):** one line per extension (its new `tagline`, translated for the built-ins; the
  full description under Details) with Details on a click, a search over names, tools
  and permissions (it names what matched), All / On / Off with counts, remembered; ⌘F, arrows, VoiceOver phrases.
  *Checked:* ExtensionListQueryTests with the 13 shipped built-ins, snapshots in light, dark and Arabic.
- **For the founder to read:** docs/research/licence.md (recommendation: FSL-1.1-ALv2 for the code, the brand kept
  apart, a CLA), docs/research/extension-ideas.md (70 ideas with tiers, sources and a top 15) and
  docs/research/extension-library-plan.md (a separate `sidefolk-extensions` repository, signed downloads, a
  signed index, Browse beside Installed; nine decisions at the top).
- **Dev tooling:** `scripts/dev.swift` commands reach only the debug app with the same `SIDEFOLK_HOME` (several
  ran side by side and answered each other's commands; one teammate's `ask:flip coin` reached an app without the
  local coin and cost one tiny Codex reply); `make dev` stops only its own checkout's app. *Checked:* a command for
  another home was ignored, one for its own home ran.
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
- **Built-ins as programs of their own (D39, amended 2026-10-28):** the founder read "Git needs Python"
  on 404. Every built-in is a Swift program (`extensions/<folder>/Sources` on `extensions/Kit`), built
  and signed with the app, run in the same sandbox; only Git needs something (git). Thirteen: Git, World
  Clock, System Vitals (+ about this Mac), Weather (+ sun and moon), Calculator, Currency (ECB), Playtime
  (chance, trivia with a score, rock-paper-scissors) and Images on; PDF Tools, QR Codes, Archives, Dev
  Toolbox and Feeds off, named to the model in one line each. New manifest permission `media` (the GPU
  and video decoder image code needs). A copy keeps its original's quarantine: Sidefolk quarantines what
  it writes, and Gatekeeper held every program at launch until the copies lost that mark. The app's own
  built-ins drop it altogether (a downloaded app marks every file inside it, as 404 in /Applications
  shows); a folder someone installs keeps its download's mark. *Checked:* a copy of the dev app with
  Chrome's mark on every extension file installed all thirteen, unmarked.
  *Checked:* every program in its sandbox by tests (live ECB, swift.org, Open-Meteo and a GitHub clone
  with `SIDEFOLK_LIVE_NETWORK=1`), all thirteen installed in the dev app, Settings › Extensions.
- **Ask panel as notifications (D5 amended):** every result a scroll away, newest first; two fingers
  sideways slide one off; "Clear all"; a fingertip-sized X; notices that need nothing fade after 20 s;
  a new word about talking replaces the last. *Checked:* dev app snapshots (`swipe:` drives the gesture).
- **Voice capture (2026-10-28):** 404 logged `mic_buffers: 0` on every press, 4 s held. The capture no
  longer points the engine's audio unit at the built-in microphone; it opens the default input, rebuilds
  once when nothing arrives within a second, logs opens and the first sound, and says when the
  microphone sent nothing. *Not yet checked with the real microphone* (the founder's next try).
- **Promises without action:** a reply that claims an action from a run that called no tool (gemma on
  Ollama: "I'll show you the temperature in Fukuoka") gets one more turn saying nothing happened
  (`UnbackedClaim`, English only). Reports read "evey 10s" as every 10 s, and the hint shows the rate
  really used (weather once a minute).
- **Play (D44):** tricks in plain words, Play in the companion's menu or by the AI (`companion.play`):
  dance, wave, bow, flip, hop, cheer, nod, giggle; a tickle makes it giggle; catch-me (20 s, best kept)
  and a one-minute breathing exercise with captions; Lively dances now and then. *Checked:* the moments
  rendered for every companion, the games in the dev app by snapshot (`play:`, `click`).
- **Extensions without limits (D39):** built-in Git (clone, status, pull, log over https), World
  Clock, System Vitals and Weather (all on), installed and updated with the app; per-call folders,
  `git` by name and per-tool timeouts in manifests; icons for every extension; Sidefolk drafts an
  extension when it lacks a capability (validated, test-run with no permissions, installed only from
  the preview); `skills/sidefolk-extension/SKILL.md` for developers; the catalog study in
  docs/research/extensions-catalog.md.
- **Fixes from the founder's use:** Open session brings Claude's desktop app forward (its Claude Code
  runs from a background-only bundle) or says why it can't; bubbles lost a gritty window shadow; an
  answer that ends with a question offers Reply; Settings › Agents shows each agent's own mark.
- **Lively companions (D43, merged 2026-10-27):** the companions have a life of their own on the
  shared Director: 17 moments as data (ear twitch, stretch, yawn, scratch, hop, wiggle, peek, glance,
  sneeze, double take; boop, pet, startle, cheer, land, spin, dizzy), fitted to each body so nothing
  leaves the window; sit and lie-down postures; an idle scheduler that holds still while the person
  types, skips its turn while the companion speaks and is sleepier at night; petting by stroking,
  throwing with a short flight. Settings › Companion › Liveliness: Minimal (today's companion),
  Balanced (default), Lively; Reduce Motion starts nothing on its own. Custom companions as data
  (`species.json` + SVG parts, strict, never run) from `<home>/companions/` and installed extensions,
  "Made by you" in Settings, `companions/template/` and Miso (a cat) as examples. The 3D spike was
  dropped. Choosing a custom companion shows it on the chooser's stage and names it as it came.
  *Checked:* every moment of every companion rendered inside its window (tests), release CPU runs and
  films (`scripts/lively-poc/`), docs/research/lively-companions.md, Settings › Companion snapshots
  with a custom companion in English and German; not yet a day in the real app, and new companion
  folders appear only after a restart.
- **Production review (2026-10-27):**
  - *Design (D40):* with no AI chosen, the Ask panel offers the Claude Code or Codex this Mac is signed
    in to (one click picks it and asks again); built-in calls read as sentences ("Clone … into
    ~/git/…"); each built-in shows a request to try; buttons wrap instead of being cut (`ButtonRow`);
    honest snapshot samples; Reduce Motion in the Ask panel. Weather now starts on (D39 addendum), and
    the built-ins' names, descriptions and titles come from the catalog (`BuiltInExtensionWords`).
  - *Hardening (D41):* six cross-feature end-to-end scenarios (`Tests/.../E2E`, a `World` harness),
    a fuzz of the new syntax, and fixes for: three crashes (one a crash loop from a huge repeat
    interval), Guard failing open when its settings couldn't be read, "until 6pm" repeating forever,
    monthly reminders losing their day, disk-full crashing the log, housekeeping only at launch (now
    daily), reports notifying in quiet mode, a clock set back silencing watchers, quit leaving CLI
    brains running. Nothing runs `xcrun` or the `/usr/bin` shims to find a program (no developer-tools
    dialog on a clean Mac); approval cards say what a call can do ("Uses the internet"). Idle 0.06% of
    a core, 25 MB; four 10 s reports 0.11%. `make app` builds in a staging bundle and swaps it in.
    docs/RELEASE.md is the release checklist.
  - *Agents (D42):* `skills/sidefolk/SKILL.md` installed by Connect beside the MCP entry (Claude Code and
    Codex, with backup, idempotent, never through a symlinked folder); Codex session hooks; new tools for
    other agents (`reminders_cancel`, `watch_report` for this Mac's metrics, `agenda_today`); descriptions
    written for other agents; "Copy Setup Instructions" for Cursor, VS Code and Zed. One tiny live call
    each through `codex` and `claude` with temp configs listed the tools and called `status`.
  - *Launch kit:* README for strangers, docs/RELEASE-NOTES.md for 0.1.0, docs/launch/ (descriptions,
    landing page, posts, demo script, press kit, reviewer FAQ, CHECKLIST.md, 35 screenshots),
    `scripts/launch-screenshots.swift`.
- **CI and releases on GitHub (2026-10-27):** `.github/workflows/ci.yml` builds, tests, reports
  untranslated strings and assembles the app on every push and pull request to `main`;
  `release.yml` publishes a snapshot (prerelease, signed when the secrets exist) or a Developer ID
  signed, notarized production release from a `v<version>` tag or Actions › Run workflow.
  `scripts/package.sh` makes the disk image alone. *Checked:* actionlint and shellcheck clean, the
  release plan in every case, the DMG from `package.sh`; CI green on GitHub (run 40420280161, about 8
  minutes: build, 1162 + 34 tests, translations, app). The Release workflow made its first snapshot,
  `v0.1.0-snapshot.400` (run 40480402125, about 10 minutes, ad hoc signed): the downloaded DMG matched its
  checksum, mounted, and held a valid 0.1.0 (400) app. The first signed snapshot (run 40502001451,
  build 403) imported the Developer ID secrets, passed the tests and signed the app (verified), then
  waited 39 minutes on Apple's notary service (submission d41ddcc9-5f3c-47fd-9a3b-d5b41379a2bb) until a
  network blip on the runner ended the wait, so nothing was published. `release.sh` now prints each
  phase and submission ID, asks Apple again after a blip, and waits up to 3 hours; the job's limit is
  210 minutes (checked first with a fake notarytool in six cases). The re-run, run 40510126126, made
  `v0.1.0-snapshot.404`, signed and notarized: 39 minutes, of which Apple took 29 for the app
  (submission 3107d33a-980f-46b3-aa6a-3a3821ae9db1) and 23 seconds for the DMG. The downloaded DMG
  matched its checksum; the DMG, app and helper are signed "Developer ID Application: Ghassen Bargougui
  (2XQJWQBD4W)" with a secure timestamp, the app with the hardened runtime and no get-task-allow;
  `stapler validate` passes for the DMG and app, and `spctl` accepts both as "Notarized Developer ID".
  Both workflows run on GitHub's `xcode-27` image:
  Xcode 26.6's Swift 6.3 crashed on valid code (two compiler crashes), after three fixes for it.
- **Tests:** 1195 (1161 core in 150 suites + 34 character). `make test` runs serially (about 50 s).
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

Release readiness review (2026-10-27): reviewed the release and launch checklists, repository
status, local signing identities, and GitHub releases and release runs. `main` was clean; no GitHub
release or release workflow run was listed, and this Mac has an Apple Development identity but no
Developer ID signing identity. No build or test was run for this review. Next: the founder chooses
the publisher and licence, sets up Developer ID, and agrees on the download and support details;
then run the signed, notarized release and test the downloaded DMG on a clean Mac.

## Next, as written at snapshot 466
1. The founder: try snapshot 466 (signed and notarized by run 40681936191; checked on the downloaded DMG:
   checksum, Developer ID and timestamps on the DMG, the app, its helper and all thirteen extension programs,
   hardened runtime, the location and microphone entitlements, the `SidefolkRelease` stamp, stapled tickets,
   Gatekeeper "Notarized Developer ID"). Install it by hand (411 has no updater); the next snapshot then proves
   the in-place update (RELEASE.md › Updates). Still waiting from 411: hold to talk with the real microphone.
2. The founder's decisions: the licence (docs/research/licence.md); which of the 70 extension ideas to build
   (docs/research/extension-ideas.md); the library plan's nine decisions (docs/research/extension-library-plan.md).
3. Then: build the approved extensions with instant commands where they fit; the library's phase 1; production
   v0.1.0 with curated release notes (snapshot notes are commit subjects, and the update window shows them).

