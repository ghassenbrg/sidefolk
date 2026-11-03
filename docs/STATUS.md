# Status

Updated 2026-11-03. What is true now, what is being worked on, what is missing, and how to check it. What was built
before, and how each piece was verified at the time, is in [HISTORY.md](HISTORY.md), newest first.

## Where Sidefolk is

Version **0.1.0**, not released: everything published is a snapshot (D62 amended, D65), and the version stays 0.1.0
until the founder releases it. The latest released is **snapshot 958**, on from snapshot 867 (snapshot B: Playtime runs entirely from its pack and the app has no games, D98–D101), with the gallery published for it.

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
- **Themes dress the app only** (colours, faces, density, materials, the light): five, all built in (D92, D130): Sidefolk (the default, from the
  app's icon), Harbor (a painted harbor), Paper Garden (warm paper and wood), Night Studio (indigo dusk) and Marshmallow (candy
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

- **Theme redesign (D130) — built on `team/themes-two`, not merged or released:** Sidefolk is the new default and Harbor a painted theme, on
  one calm design: a plain sidebar with art in its header, a selected row the theme draws, a rebuilt Today, rounded sheets
  with the theme's sky behind the toolbar. All ten languages. Verified: tests with the add-ons worktree, the release build, `sidefolk theme check`,
  snapshots in light, dark, Arabic and German and at the default window size (all five themes, light and dark), the move off the old id, arrow keys against a control, and synthetic clicks in a debug app: Your day's +, Add reminder, a drag in the day and ⌘Z.
  Paper Garden, Night Studio and Marshmallow stay built in for now; their move to the gallery is on `team/themes-two` (with `team/themes-two` in sidefolk-addons, unpublished), and the gallery must publish before an app without them ships.
  Mochi's brand images are redrawn in the newer design, and the live 3D Mochi is tuned toward them with the same model. Not verified, for the founder to
  check on the snapshot: real mouse clicks and drag, Delete and S on Next up, the New menu, VoiceOver by ear, Reduce Transparency, Increase Contrast, the tuned Mochi moving in the running app.
  The edge check flags petting and the flip with or without this change (older issue). Next: this split, `team/themes-default`, goes in the first snapshot; then the gallery move.


- **Sideflow (D110-D114, D125-D129), first landing `team/sideflow-host` on its way into the integration snapshot; add-on `team/sideflow` goes to the gallery right after that snapshot; second landing `team/sideflow-extras` (app and add-ons) waits.** A tree of cards in a page that takes the window, flows that reach every tool: D127 (MCP and shell, on a card every time), D128 (a job for the companion under their trust settings), D129 (hearing what happens, with titles for all), D126 (flat accent, the flow line keeps the gradient). What a flow fills in stays out of History (D127, T44), reviewed twice and found by running it for real; a reminder's title shows, the founder's choice. **First landing's next:** after the snapshot exists, `minimum_sidefolk` in `extensions/sideflow/addon.json`, a signed build with `--sidefolk-build N` from a clean worktree, the signed install in a fresh debug app, RELEASE? add-ons. **Second landing:** `voice.say`, `appearance.set`, a tree on Ask's card, the Activity tab; rebase, full suite, its own RELEASE?. Overlaps Ask (Formatic's D141). **After themes lands:** adopt `.fieldHint` for the three fields with a prompt (`ExtensionPageInputs.swift`, `ExtensionPageSteps.swift`, `ExtensionPageTree.swift`). **For the audit session:** `personWasAsked` must not be set for `.extension` calls, which also go through `ExternalFacade`. **Not verified, for the founder:** a real schedule over hours or with the Mac asleep, a live AI step and a real companion job end to end, a signed pack, drag, keyboard and VoiceOver by hand, Arabic on the new screens, voice heard aloud, the tidy page-click row (it needs a signed pack). **Verify:** `swift test --no-parallel` with `SIDEFOLK_ADDONS_REPO` at an add-ons checkout that has Sideflow; add-ons `swift test --filter Sideflow`.

- **Playtime's redesign (D145 to D148):** finished on add-ons branch `team/playtime-redesign`, not pushed. It waits for the founder's yes. It needs snapshot 958. Result, what was checked and limitations: `sandbox/playtime-design-handoff-2026-11-03/implementation/RESULT.md`.
- **Dev ideas (`sandbox/sidefolk-dev-ideas.md`), for the founder to look at:** batches 1 to 6 are done (HISTORY's top entries). **For the founder:** [the notebook proposal](research/notebook-proposal.md) needs a choice; [the wake word's measurements](research/wake-word-prototype.md) recommend not building it yet, and a minute's microphone test at the Mac decides it; windows opening in another app's full-screen space were diagnosed, not proven, and wait on the founder's confirmation of the case. D115 keeps D49's return of a reminder when its task reopens, where the handover recommended it stay cancelled.
- **For the founder, from snapshot B (D101):** the reaction props the app still draws (D101's "Left for the founder"); in two-player rock, paper, scissors the reveal still says "You" and the companion's name with a winner's glow, as the old code did, against D96. Checks and what wasn't run: HISTORY's top entry. **Open, small:** with a surface panel open `snap` lists a 40×40 fully transparent `FloatingPanel` near the companion; not identified.
- **For other branches:** `Sources/SidefolkApp/Play/` and `Sources/SidefolkCore/Games/` are gone, so a branch from before snapshot B that touches them will conflict: its game changes go into Playtime in the add-ons instead.

- **Website:** `https://getsidefolk.com` (registered at GoDaddy, verified on the founder's GitHub account, HTTPS
  enforced) serves a one-page placeholder with no download button, from the separate repository
  [sidefolk-site](https://github.com/ghassenbrg/sidefolk-site): `public/`, deployed on every push to its `main`. It
  lives apart because this repository's build number is the commit count of `main`, so site commits here would change
  it. Checked 2026-11-03: every address redirects to the HTTPS one, and the certificate covers `www`. **For the
  founder:** turn off Pages on this repository, which still publishes from a branch; the bundle ID `app.sidefolk.*`
  against this domain (launch [CHECKLIST](launch/CHECKLIST.md) row 3); the similar AI companion the domain research
  found. Next: the real page, from [LANDING-PAGE.md](launch/LANDING-PAGE.md).

- **Noor, the extension (D105–D109, T43), not the companion of the same name (D121):** an Islamic companion in the add-ons gallery (`extensions/prayer-times`, id `dev.sidefolk.prayer-times`, shown as Noor), rebuilt at the founder's request to match its 20 approved boards rather than resemble them. The host's abilities land first, through the coordinator; the add-on follows on the snapshot that has D109, with `minimum_sidefolk` set to that snapshot. Branch `team/noor` in sidefolk-addons until then.
  - **Checked:** an independent review pressed what it could and found dead controls, then fixed; `pageInlay:` presses native controls through what their click runs (Copy bearing and Copy result checked on the real clipboard, Allow opens Sidefolk's question, Import opens the review). `NoorSceneTests` fails on any control the host would drop.
  - **Not verified:** VoiceOver and real mouse clicks by a person (this process has no Accessibility trust: `pageKey` and `pageInlay` go through the handlers); the open file panel by hand; macOS notifications through a real permission prompt; a signed pack's install from the gallery until the add-on is released; real sleep and wake; Increase Contrast and Reduce Motion.
  - **Known limits:** nothing is reminded while Sidefolk is quit or the Mac asleep unless macOS was asked to at quit (up to 20, within 7 days); the first question through `ask_noor` shows an approval card (network raises the floor), with Always; Noor's notices and Ask answers are Sidefolk's own surfaces, not the C01 board's richer ones; dial markers sit at real instants, unlike the boards' even spacing (the spec requires it).
  - **Before the gallery:** AlAdhan's and Open-Meteo's terms for caching and redistribution, which RESEARCH left open.

- **MCP and in-app tools (D156–D160, [the audit](research/mcp-tools-audit-2026-11-03.md)):** batch A is released in snapshot 958 (HISTORY). The founder approved group B too (D160): B1 to B4 go in the next snapshot; B5 and B6 (`team/tools-b6`, the companion reading History and sessions) wait for one last fix and review, and B7 (`files.write`) comes last. **Waiting:** Codex's tool timeout on `team/tools-a4`, until a live call measures its default (D156). **Not verified:** a real Claude Code or Codex session as the client; a real calendar.

- **Formatic, a file-conversion extension (D140–D143, D150–D152):** the host abilities it needs are here; the extension and its designed cards aren't.
  - **Here:** saving beside the file the person gave (D140), file drops with a menu and several files (D141), Open, Show and Undo on a saved file (D142), Finder's Send to Sidefolk (D151). Sound under `media` is D143.
  - **Half done, local branches only:** the extension itself (add-ons `team/formatic`, in the gallery only after an app release carries these), its look (D150, `team/formatic-design` is the reference, after the themes work), the ring (D152: the founder's test passed, no go to build), and `team/sandbox-names` (failed its review once, fixed, needs another).
  - **Next:** another review of `team/sandbox-names`, then the extension to the gallery, then D150.
  - **Not verified:** the Service from a real Finder, including a cold launch; a real drag from Finder; Open, Show and Undo by real clicks. Checked by the suite and the debug app: every format through the real sandbox, a drop and a card choice by command. Drop menu titles can't be translated yet.

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

- **Hide over full-screen apps (D138) isn't proven on a real full-screen space:** the check is armed for an idle Mac. The companion's visit, the notification and a real click need a person there.
- **Normal windows still open inside another app's full-screen space** when no click asked for them (measured, D137): snapshot 916's change didn't cure it. A fix on `.fullScreenNone` is in progress. A real click hasn't been measured. Test copies' companions and panels still show, sessions have to opt in to `SIDEFOLK_QUIET_WINDOWS=1`, and in 916 macOS keeps a corner of a quiet window on screen.
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
