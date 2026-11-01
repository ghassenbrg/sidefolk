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
- **Themes dress the app only** (colours, faces, density, materials, the light): built in are Harbor (Lantern, the
  default), Night Shift, Marshmallow and Field Notes; the gallery has Daylight, Night Studio and Paper Garden.
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

- **Docs cleanup** (branch `team/docs-cleanup` in both repositories, not merged): every doc, README and skill
  brought to the app as it is after D84; this file split into STATUS and HISTORY; finished plans removed.

- **What may interrupt you** (branch `team/interrupts`, not merged; D88): a level per source (Card, Whisper, Only in
  Today, Off) in Settings › Attention, applied before Focus and Quiet; "Fewer like this" and "Show these as whispers"
  in a card's ⋯ with Undo; Today's Kept for Today; "done today" counts only what changed something. Built, tested
  (`InterruptionsTests`, `InterruptionsCenterTests`, `DoneTodayTests`), snapshots read (`page-settings-attention-sources`,
  `page-today-kept`, light, dark, de, ar) and checked live (Claude Code at Only in Today, a `sidefolk hook` Stop: no
  desktop notice, Today's Kept for Today showed it). Not tried by hand: the ⋯ menu's two choices and their Undo (no
  click from the dev script; `interrupt:<key>:<level>` sets a level). Next: merge.

Nothing else is on a branch: every team branch is merged into main in both repositories.

## Next

1. **The founder plays the puzzles** (Garden Plots, Seesaw, Sudoku, Blossoms) and the games in snapshot 661.
2. **Miraya on a real TV:** live screen and sound with the three sound choices (only an emulator paired so far, D81).
3. **What D84 left out** (each needs something real first; AGENTS.md: no fake features): the evening wrap, the
   choice card for drops, the stack's arc animation, voice's level-reactive pool, answering cards from the keyboard
   outside Ask, Ask's "Open in History" header, the companions' own reactions, the Week view's "read only" note and
   "+1" overlaps, a watch's detail page (no check log or page versions are kept).
4. **Games not built** (D79): catching the companion in Which Cup? by clicking it, AI trivia packs, Connect Four,
   dragging a plot from the keyboard, a hint that plays its move, a daily board per level.
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
