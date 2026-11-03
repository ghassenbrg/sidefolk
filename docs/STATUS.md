# Status

Updated 2026-11-03. What is true now, what is being worked on, what is missing, and how to check it. What was built
before, and how each piece was verified at the time, is in [HISTORY.md](HISTORY.md), newest first.

## Where Sidefolk is

Version **0.1.0**, not released: everything published is a snapshot (D62 amended, D65), and the version stays 0.1.0
until the founder releases it. The latest is **snapshot 867** (snapshot B: Playtime runs entirely from its pack and the app has no games, D98–D101), with the gallery published for it.

- **On the desktop:** the companion (Mochi or Spark built in, 3D or 2D; eight more from the gallery) stands on its
  light pool, which shows its state (working, waiting with a count, Focus, Quiet). Everything it says is the
  **Sidecard**: whispers, cards that fold into the count, Ask (⌘⇧Space or a click) with its understanding row, and
  permission slips for approvals (firm ones never take Return). Pins (live values) and the agents lane sit beside
  it, and extensions' **surfaces** (D99), always framed with their name: Playtime's eleven games and five puzzles among them.
- **Home:** Today, Calendar, Notebook (its own page, D134; with You and the Trash), On duty, History, extension pages arranged by the
  person, and the **Gallery** (companions, extensions, themes). The Say bar (⌘K) is in the toolbar.
- **Settings:** eight tabs with search: General, Companion, Attention (Open, Focus, Quiet, quiet hours), Brain (AI
  and voice), Trust (approval modes, Full access with an end), Connections (Claude Code, Codex, other MCP clients,
  the `sidefolk` command), Add-ons and Appearance (theme, light or dark, density).
- **The menu bar** is the Pocket, a popover with the state, the Open/Focus/Quiet dial, Needs you, Next up, Agents
  and Ask.
- **Themes dress the app only** (colours, faces, density, materials, the light): four, all built in (D92): Harbor
  (Lantern, the default), Paper Garden (warm paper and wood), Night Studio (indigo dusk) and Marshmallow (candy
  clouds); retired ones move to their successor. New themes start with the `sidefolk-theme` skill.
- **Without AI:** notes, reminders, watches, live values, the calendar, search and extension commands (games among them, with Playtime). With
  the AI the person picks (Claude Code, Codex, an API key, Ollama or LM Studio), everything else, through Guard.
- **For other agents:** `sidefolk mcp` and the skill Connect installs (D42, D52); session hooks tell the person when
  Claude Code or Codex needs them (D12 amended).
- **Ten languages** for everything people read, extensions included (D28, D76).

**The add-on gallery** (github.com/ghassenbrg/sidefolk-addons, release `gallery`): companions Ember, Kiko, Nimbo,
Folio, Iris, Nori, Purl, Rune and Piko (a robot cat in Spark's colours, 3D only, no `CompanionChoice`: worn by name, D77,
snapshot 1 needs Sidefolk snapshot 779; its pipeline isn't in this repository) and Noor (a baby moth, 3D only, worn by name, D121, snapshot 1 needs snapshot 779); extensions World Clock, System Vitals, Weather and Calculator (on `team/ext-move`, also a
fresh Mac's seed packs, D98), Git, Currency, Playtime, Images, PDF Tools, QR Codes, Archives, Dev
Toolbox, Feeds, Your Mac (System Vitals+), Clipboard, Keep Awake and Miraya. Themes are the app's own (D92). Every add-on is in
snapshots. **Playtime 1.0.0-snapshot.9** needs Sidefolk snapshot 867, and a copy from before shows "Update Playtime" there (D101); **Miraya 1.0.0-snapshot.5** needs snapshot 827.

## In progress

- **Dev ideas (`sandbox/sidefolk-dev-ideas.md`), for the founder to look at:** batches 1 to 6 are done (HISTORY's top entries). **For the founder:** [the notebook proposal](research/notebook-proposal.md) needs a choice; [the wake word's measurements](research/wake-word-prototype.md) recommend not building it yet, and a minute's microphone test at the Mac decides it; windows opening in another app's full-screen space were diagnosed, not proven, and wait on the founder's confirmation of the case. D115 keeps D49's return of a reminder when its task reopens, where the handover recommended it stay cancelled.
- **For the founder, from snapshot B (D101):** the reaction props the app still draws (D101's "Left for the founder"); in two-player rock, paper, scissors the reveal still says "You" and the companion's name with a winner's glow, as the old code did, against D96. Checks and what wasn't run: HISTORY's top entry. **Open, small:** with a surface panel open `snap` lists a 40×40 fully transparent `FloatingPanel` near the companion; not identified.
- **For other branches:** `Sources/SidefolkApp/Play/` and `Sources/SidefolkCore/Games/` are gone, so a branch from before snapshot B that touches them will conflict: its game changes go into Playtime in the add-ons instead.

- **Noor, the extension (D105–D109, T43), not the companion of the same name (D121):** an Islamic companion in the add-ons gallery (`extensions/prayer-times`, id `dev.sidefolk.prayer-times`, shown as Noor), rebuilt at the founder's request to match its 20 approved boards rather than resemble them. The host's abilities land first, through the coordinator; the add-on follows on the snapshot that has D109, with `minimum_sidefolk` set to that snapshot. Branch `team/noor` in sidefolk-addons until then.
  - **Checked:** an independent review pressed what it could and found dead controls, then fixed; `pageInlay:` presses native controls through what their click runs (Copy bearing and Copy result checked on the real clipboard, Allow opens Sidefolk's question, Import opens the review). `NoorSceneTests` fails on any control the host would drop.
  - **Not verified:** VoiceOver and real mouse clicks by a person (this process has no Accessibility trust: `pageKey` and `pageInlay` go through the handlers); the open file panel by hand; macOS notifications through a real permission prompt; a signed pack's install from the gallery until the add-on is released; real sleep and wake; Increase Contrast and Reduce Motion.
  - **Known limits:** nothing is reminded while Sidefolk is quit or the Mac asleep unless macOS was asked to at quit (up to 20, within 7 days); the first question through `ask_noor` shows an approval card (network raises the floor), with Always; Noor's notices and Ask answers are Sidefolk's own surfaces, not the C01 board's richer ones; dial markers sit at real instants, unlike the boards' even spacing (the spec requires it).
  - **Before the gallery:** AlAdhan's and Open-Meteo's terms for caching and redistribution, which RESEARCH left open.

## Next

1. **The founder plays the games v2** (the Game Center, two players, AI trivia) and the Calendar v2 in snapshot 780, including switching out of Month in the originally affected setup.
2. **Miraya on a real TV:** live screen and sound with the three sound choices (only an emulator paired so far, D81).
3. **What D84 left out** (it needs something real first; AGENTS.md: no fake features): the evening wrap.
4. **The relook** (`sandbox/games-relook`): now a Playtime update alone. **Games not built** (D79): Connect Four.
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

- **A web watch on a sign-in page that answers 200** watches the sign-in page: "any change" and `contains` can't tell (D135). A page with no text at all, and words never seen, now say so.
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
- **Built-ins' limits:** QR Codes needs an Apple GPU; Currency covers the ECB's 30 currencies; a folder with more than 20,000 items can't be watched.
- **Languages:** the `sidefolk` command line, `StatusSnapshot.sentence`, bridge protocol errors, manifest checks
  (`ManifestValidator`, `ValidationReport.text`) and `ExtensionError`/`MCPError` details stay English on purpose.
  Stored collection names ("Inbox", "About you") stay English and are shown through
  `NotebookCollections.shownName`. KeyboardShortcuts' recorder has no Arabic of its own.
- **Cost:** while the mouse moves, the global mouse monitor and the eyes that follow it cost about 1–5% CPU in
  bursts. Measurements at rest and with a game open are in D84 (phase 5), D99 and D101.
- **Residual trust gaps** (SECURITY.md): code running as the person can name its own ancestor or a known terminal as
  a session's host; extension tool names and titles (60 characters) reach the model.
- **Signing:** the Developer ID certificate and notary credentials live only in GitHub's secrets, so the Release
  workflow signs and notarizes; local builds use the Apple Development identity or ad hoc.

## How to verify

- `swift build`, then `make test` (Swift Testing, serially). The extensions' sandbox tests run the gallery's
  extensions from `../sidefolk-addons`, or `SIDEFOLK_ADDONS_REPO=<a clean add-ons checkout>`: an add-ons checkout
  behind main fails the gallery and words tests.
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
