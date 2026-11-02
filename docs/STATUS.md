# Status

Updated 2026-11-01. What is true now, what is being worked on, what is missing, and how to check it. What was built
before, and how each piece was verified at the time, is in [HISTORY.md](HISTORY.md), newest first.

## Where Sidefolk is

Version **0.1.0**, not released: everything published is a snapshot (D62 amended, D65), and the version stays 0.1.0
until the founder releases it. The latest is **snapshot 780** (2026-11-01, signed and notarized, on GitHub Releases),
with the Lantern revamp (D84), the games look and the four puzzles (D79 amended), and D86–D91 (safety, watch
history, interrupts, add-on updates, Ask lifetimes, backup). Main also carries the four themes (D92), the leftovers
and the CI fix, games v2 (D79 look v2, D93, D95, D96), Calendar v2 (D97) and the voice fix. Snapshot 780 fixes
the month grid taking clicks over its view controls (hidden buffer weeks now have bounded hit areas).

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
Folio, Iris, Nori, Purl and Rune; extensions World Clock, System Vitals, Weather and Calculator (on `team/ext-details`, also a
fresh Mac's seed packs, D98), Git, Currency, Playtime, Images, PDF Tools, QR Codes, Archives, Dev
Toolbox, Feeds, Your Mac (System Vitals+), Clipboard, Keep Awake and Miraya; the three themes. Every add-on is in
snapshots. **Playtime 1.0.0-snapshot.5** needs Sidefolk snapshot 661 (its puzzles; older copies keep the version
they have, D83); **Miraya 1.0.0-snapshot.4** needs snapshot 593 (`output_mute`, D81).

## In progress

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

## Next

1. **The founder plays the games v2** (the Game Center, two players, AI trivia) and the Calendar v2 in snapshot 780, including switching out of Month in the originally affected setup.
2. **Miraya on a real TV:** live screen and sound with the three sound choices (only an emulator paired so far, D81).
3. **What D84 left out** (it needs something real first; AGENTS.md: no fake features): the evening wrap.
4. **Games not built** (D79): Connect Four.
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
- Calendar input regression: `SIDEFOLK_RESOURCES=$PWD/Resources swift run SidefolkApp --ui-snapshots
  build/calendar-input --check-calendar-input --language en` uses an offscreen fixture to check that hidden
  month weeks cannot catch header clicks, and visible cells and view buttons still work (default Harbor theme).
- UI: `SIDEFOLK_RESOURCES=$PWD/Resources swift run SidefolkApp --ui-snapshots <dir>` (add `--language de|ar|ja`,
  `--theme <id>` or `--only <prefix>`, e.g. `window-home`, `window-settings`, `desktop`, `panel-pocket`,
  `design-system`, `a11y`), read in light and dark against [DESIGN.md](DESIGN.md).
- The running app: `make dev`, or a debug app on a fresh short `SIDEFOLK_HOME` (`build/qa-<name>`), driven with
  `swift scripts/dev.swift` (its header lists every command: `ask:`, `respond:`, `home:<place>`, `settings:<tab>`,
  `pocket`, `attention:focus:60`, `game:`, `drag:`, `snap`…).
- Characters: `swift run sidefolk-render out/`; 3D companions in `companions-3d/` (its README, `serve.py`).
