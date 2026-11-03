# Status

Updated 2026-11-03. What is true now, what is being worked on, what is missing, and how to check it. What was built
before, and how each piece was verified at the time, is in [HISTORY.md](HISTORY.md), newest first.

## Where Sidefolk is

Version **0.1.0**, not released: everything published is a snapshot (D62 amended, D65), and the version stays 0.1.0
until the founder releases it. The latest released is **snapshot 1170**, on from snapshot 867 (snapshot B: Playtime runs entirely from its pack and the app has no games, D98–D101), with the gallery published for it.

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
- **Ask is a shortcut (D136):** results go seconds or minutes after they reached the person, eight requests at most, pins last until unpinned, and History keeps what a command answered.
- **The menu bar** is the Pocket, a popover with the state, the Open/Focus/Quiet dial, Needs you, Next up, Agents
  and Ask.
- **Themes dress the app only** (colours, faces, density, materials, the light): two built in (D130): Sidefolk (the default, from the
  app's icon) and Harbor (a painted harbor), and in the gallery Paper Garden (warm paper and wood), Night Studio (indigo dusk) and Marshmallow (candy
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
Toolbox, Feeds, Your Mac (System Vitals+), Clipboard, Keep Awake and Miraya. Themes Paper Garden, Night Studio and Marshmallow, once published (D130). Every add-on is in
snapshots. **Playtime 1.0.0-snapshot.11** needs Sidefolk snapshot 958, and a copy from before shows "Update Playtime" there (D101); **Miraya 1.0.0-snapshot.5** needs snapshot 827.

## In progress

- **Homepages for Miraya, Clipboard, Your Mac and Keep Awake (D170) — the general page abilities are in snapshot 1170; the four pages wait on add-ons `team/extension-homepages`, not published.** The founder's accepted designs, as native pages drawn from data: general page abilities here (`ExtensionPage+Compose`, `ExtensionPageCompose`, `Kit/PageCompose`), the pages in the add-ons. The handoff's id-routed `ExtensionPageExperiences.swift` stays out (D98). **Half done:** the four packs name the placeholder `minimum_sidefolk`, which becomes 1170 when they're built. **Next:** the packs to the gallery, on the coordinator's go. **Not verified, for the founder:** real mouse clicks and arrow keys, Copy (it would overwrite the real clipboard), VoiceOver by ear (`ax` doesn't reach into these pages), Increase Contrast and Reduce Transparency, a real TV, screen-recording permission and an app quitting under a session. **Result:** `sandbox/extension-homepage-implementation-handoff-2026-11-03/implementation/PARITY.md`, comparisons beside it. **Verify:** `SIDEFOLK_PAGE_DUMP=<dir> swift test --filter HomepageStatesTests` in the add-ons, then `SIDEFOLK_SNAPSHOT_PAGES=<dir> swift run SidefolkApp --ui-snapshots out --only page-file-<state>`.

- **Theme redesign (D130): in snapshot 1075,** Sidefolk the new default and Harbor a painted theme, with Paper Garden, Night Studio and Marshmallow still built in there.
  **The founder is checking on 1075:** real mouse clicks and drag, Delete and S on Next up, the New menu, VoiceOver by ear, Reduce Transparency, Increase Contrast, the tuned Mochi moving in the running app.
  **This branch, not published:** the three themes' move to the gallery, here and on `team/themes-two` in sidefolk-addons, on the founder's go of 2026-11-04. The add-ons name the placeholder minimum, so a signed build stops until Add-ons first sets the real snapshot (docs/RELEASE.md, D98): this app ships before the publish, and copies that still have them built in must not see them as Get. Whoever wears one gets it with no click while automatic add-on updates are on, at launch and after each add-on look (`fetchThemeThatMoved`, D70). **Not verified:** a real signed theme pack fetched that way, end to end.
  **Checked with synthetic clicks and keys:** ← → on a reminder in Your day, ⌘Z, a drag, the New menu opening, Next up's click, ↓, Delete and S. **Not pressed:** a real mouse and keyboard, a New menu item, a late reminder moved past now. **Known on Today:** the row with the keyboard shows no highlight (D130).
  The edge check flags petting and the flip with or without this change (older issue).

- **Sideflow (D110-D114, D125-D129): in the gallery as `sideflow-1.0.0-snapshot.2`, which needs snapshot 1137 (add-ons main 9b1ddc1), under Show snapshots.** HISTORY's top entry has what it is and how it was checked. **Known:** a tool line can slip in during a spoken local command (`runLocal` never sets busy); a job's notices show as the companion's; `TreeCompact` doesn't draw done or skipped, and a very long tree scales down until it's hard to read; an extension trying can write its own words into its own rows (T44). **Not verified, for the founder:** a real schedule over hours or with the Mac asleep, a live AI step and a real companion job end to end, the tree on a real card in Ask from a live AI turn, drag, keyboard and VoiceOver by hand, Arabic on the new screens. A voice line did play once, by mistake, in a check; nobody heard it to say how it sounds. **Verify:** `swift test --no-parallel` with `SIDEFOLK_ADDONS_REPO` at an add-ons checkout that has Sideflow; add-ons `swift test --filter Sideflow`.

- **Playtime's redesign (D145 to D148):** published in the gallery as Playtime 1.0.0-snapshot.11, on 2026-11-04, with a pause card in every game, practice boards and words that leave today's alone, and the concepts' Quick Paws machine and Surprise me dice. Result, what was checked and limitations: `sandbox/playtime-design-handoff-2026-11-03/implementation/RESULT.md`.
- **Dev ideas (`sandbox/sidefolk-dev-ideas.md`), for the founder to look at:** batches 1 to 6 are done (HISTORY's top entries). **For the founder:** [the notebook proposal](research/notebook-proposal.md) needs a choice; [the wake word's measurements](research/wake-word-prototype.md) recommend not building it yet, and a minute's microphone test at the Mac decides it; windows opening in another app's full-screen space were diagnosed, not proven, and wait on the founder's confirmation of the case. D115 keeps D49's return of a reminder when its task reopens, where the handover recommended it stay cancelled.
- **For the founder, from snapshot B (D101):** the reaction props the app still draws (D101's "Left for the founder"); in two-player rock, paper, scissors the reveal still says "You" and the companion's name with a winner's glow, as the old code did, against D96. Checks and what wasn't run: HISTORY's top entry. **Open, small:** with a surface panel open `snap` lists a 40×40 fully transparent `FloatingPanel` near the companion; not identified.
- **For other branches:** `Sources/SidefolkApp/Play/` and `Sources/SidefolkCore/Games/` are gone, so a branch from before snapshot B that touches them will conflict: its game changes go into Playtime in the add-ons instead.

- **Website:** `https://getsidefolk.com` serves the real site (Home, Extensions, Privacy, the test build) from the
  separate repository [sidefolk-site](https://github.com/ghassenbrg/sidefolk-site): `public/`, plain HTML and CSS,
  deployed on every push to its `main`. It lives apart because this repository's build number is the commit count of
  `main`, so site commits here would change it. Live since 2026-11-03, checked there: pages, images and font
  load, every address redirects to the HTTPS one. There is no download button until 0.1.0, only a link to the test
  builds. Its colours and Mochi are the new default theme's (D130), in snapshot 1075. Home shows the real Today page,
  light and dark, rendered from 1075's sources and captioned as sample data, and its sample cards use the app's wording
  (checked in the debug app and in source; the cards weren't seen on screen). Sideflow and Formatic are shown as in the
  gallery, each with how to find it: turn on Show snapshots in Get add-ons, needs snapshot 1137 (Sideflow) or 1170
  (Formatic). Those numbers are written by hand, so a new `minimum_sidefolk` for either means changing the site.
  **For the founder:** turn off Pages on this repository, which still publishes from a branch; the bundle ID `app.sidefolk.*` against this domain (launch [CHECKLIST](launch/CHECKLIST.md) row 3); the
  similar AI companion the domain research found.

- **Helper folks' art (D73 amended):** all ten paintings in `Sources/SidefolkCharacter/Art/folks/` are now generated transparent, not cut from a white sheet: same names, 384×384 and floor line, no loose notes or sparkles. Checked on magenta, dark and white, at the app's sizes against the old ones, and in `--ui-snapshots` (Today, the desktop floor); Scout, Pip, Byte and Guard are the site's art. `folk-family/<id>/<id>.png` were already clean. `Resources/Character/folks.png` still shows the vector folks from before D73. Next: the snapshot after the 2026-11-03 integration.

- **MCP and in-app tools (D156–D160, [the audit](research/mcp-tools-audit-2026-11-03.md)):** batch A is released in snapshot 958, B1 to B4 are in snapshot 1075 (HISTORY). The founder approved group B too (D160): B5 and B6 (the companion reading History and sessions) are in snapshot 1137, with an important reminder now holding its note against other agents, and B7 (`files.write`) comes last, with the founder's yes by name. **Next audit batch and the founder's open question:** the end of [the audit](research/mcp-tools-audit-2026-11-03.md). **Waiting:** Codex's tool timeout on `team/tools-a4`, until a live call measures its default (D156). **Not verified:** a real Claude Code or Codex session as the client; a real calendar; the History and sessions cards on screen, and a live model reading those lines.

- **Formatic, a file-conversion extension (D140–D143, D150–D152):** the host abilities it needs are here; its designed cards (D150) are in snapshot 1170.
  - **Here:** saving beside the file the person gave (D140), file drops with a menu and several files (D141), Open, Show and Undo on a saved file (D142), Finder's Send to Sidefolk (D151), sound under `media` (D143).
  - **Half done, local branches only:** the extension itself (add-ons `team/formatic`, for the gallery, now that snapshot 1170 carries D150), and the ring (D152: the founder's test passed, no go to build).
  - **Next:** Formatic to the gallery on the coordinator's go. The founder chose to wait for the design, and the site says "Coming soon" until it's there.
  - **Not verified:** Send to Sidefolk from a real Finder, including a cold launch: `NSPerformService` can't be aimed at a debug app while an installed copy runs. A real drag from Finder; Open, Show and Undo by real clicks. Checked by the suite and the debug app: every format through the real sandbox, a drop and a card choice by command. Drop menu titles can't be translated yet.

- **Noor, the extension (D105–D109, T43), not the companion of the same name (D121):** in the gallery since 2026-11-03 as `dev.sidefolk.prayer-times` `1.0.0-snapshot.1`, for snapshot 911 or newer, rebuilt at the founder's request to match its 20 approved boards. Snapshot add-ons are hidden until the person presses Show snapshots. The founder tests it next and comes back with findings.
  - **Checked:** two independent reviews pressed controls and walked a new person's journey; `pageInlay:` presses native controls through what their click runs; a real reminder at its minute; Ask's answers; a live place search; the signed pack installed from the live gallery, verified, and opened on first run. `NoorSceneTests` fails on any control the host would drop.
  - **Not verified:** VoiceOver and real mouse clicks by a person (this process has no Accessibility trust); typing in fields, open menus, the file panel and the consent question's buttons by hand; disable and enable pressed in Settings › Add-ons; the signed copy past first run; macOS notifications through a real permission prompt; real sleep and wake; Increase Contrast, Reduce Motion and Reduce Transparency.
  - **Known limits:** nothing is reminded while Sidefolk is quit or the Mac asleep unless macOS was asked to at quit (up to 20, within 7 days); the first question through `ask_noor` shows an approval card (network raises the floor), with Always; Noor's notices and Ask answers are Sidefolk's own surfaces, not the C01 board's richer ones; dial markers sit at real instants, unlike the boards' even spacing (the spec requires it). "Open Sidefolk's place settings" opens Trust's top, with Your location below it (`ExtensionPageModel`): a small fix for later.
  - **The founder's call, made:** AlAdhan publishes no terms we could find for caching or redistribution, and Noor caches its answers locally and credits it; Open-Meteo's free tier is non-commercial, which holds while Sidefolk is free. Published knowing that. Worth revisiting before any paid release.

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

- **Hide over full-screen apps (D138), what's left to check:** the companion's visit, the notification and a real click need a person there. Measured on a real full-screen space: with the setting off nothing changes, and with it on the companion's panel is gone over the full-screen app and back after leaving it.
- **A normal window opened over a full-screen app takes you to the desktop** (D137): it no longer lands inside that space, 3 of 3 with no click. A real click hasn't been measured. Test copies' companions and panels still show, sessions have to opt in to `SIDEFOLK_QUIET_WINDOWS=1`.
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
