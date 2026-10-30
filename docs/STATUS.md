# Status

Updated: 2026-10-30. Version 0.1.0. Latest: the add-on gallery (D55): Ember, Kiko, Nimbo, Folio and nine
extensions moved to github.com/ghassenbrg/sidefolk-addons, signed packs Sidefolk downloads on demand (not
published yet: the founder runs scripts/publish.sh there). 1374 core and 34 character tests pass, serially.
Before that: the founder's list after snapshot 478: other agents change and
delete notes, with Settings › Privacy › Other agents choosing what they may do; Empty Trash; Light, Dark or Same
as Mac; spoken replies briefly or in full; releases only by default, offered again daily (D52); 3D companions
that really sleep; a notebook with collection icons, emoji and colours, pinned notes and notes formatted as you
write (D53); and a brainstorm on companions made by people and a gallery to get them
(docs/research/companion-marketplace.md). 1367 core and 34 character tests pass. Before that: 3D companions
(D51) and snapshot 478, published, signed and notarized.

## Done and verified
- **Iris, Nori, Purl and Rune in 3D (D61):** four gallery companions from the founder's sheets, add-ons in
  `sidefolk-addons/companions/` (built and signed, not published). Iris, Purl and Rune were modelled again after
  a first pass that missed their sheets; Nori kept its model and lost the glossy strip over its glasses. Rig kit:
  `regutter()` (no pale seam cracks) and `mark()` (a part mask the material reads as `part`); the playground's
  `sheet.js turnaround()` saves front, ¾, side and back to compare with a sheet. *Checked:* turnarounds and the
  16-cue sheets of all four against their sheets in the playground; the dev app (all four animate, Rune waves);
  `make test`. *Not yet:* the founder's review; Iris's arms pull a little yellow from the body's sides when raised;
  the stand-ins were resized to the new models but not looked at in the app; the app's side (cases, stand-ins,
  role lines, strings, tests) is in the working tree, interleaved with the 2D work (D59), and goes in with it. *Next:*
  the founder reviews, then
  `scripts/publish.sh` in sidefolk-addons; the app offers them once a release knows their cases.
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
- **Themes, steps 1–3 built; the Home rework planned (D57, D58):** the reasons are in `docs/research/themes.md`, the
  build plan in `docs/research/themes-plan.md`, the seven boards locally in `sandbox/theme-sandbox/`. Built in:
  Harbor (default), Night Shift, Marshmallow, Field Notes; gallery: Daylight, Night Studio, Paper Garden. Step 1:
  `ThemeTokens` (SidefolkCore) and `ThemeStore` behind every `Theme` name. Step 2: Home › Activity rows open in
  place (what, who, the decision in words, the outcome, the arguments, the rule in Settings). Step 3: links to
  conversations. An Activity row shows "Asked in" and the conversation, found through its run
  (`ExchangeStore.conversations(ofRuns:)`, no new column); a note shows "Saved in" and "Changed in" links under its
  date (`items.run_id`, migration `v5-item-run`, written by `notes.save` and `profile.remember`; changes from
  `notes.update`/`notes.trash` rows that ran); each opens the conversation (`AppServices.openConversation`). The
  sample data gets a conversation that saved "Karim's new address" (new snapshot `window-home-notebook-connected`).
  *Checked:* ConversationLinksTests through the real agent loop and tools (a mutation check proves the "ran" filter
  matters); UI snapshots rendered in a clean worktree before and after each step and compared on every channel: the
  differences are the intended ones plus relative times and capture flakes (a window caught as active, a title line,
  a pressed button); the full suite in a clean worktree. *Found:* `--ui-snapshots` shows raw English keys because it
  runs without the compiled catalog (plan B13). Harbor's `inkFaint` is 2.95:1 on white and white on the light danger
  fill 4.27:1 (plan step 8). *Next:* plan step 4: Today and its decision queue (B1, B2), with Guard approvals in
  Home and `ApprovalRequest.expiresAt`.
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

## In progress
Nothing.

Release readiness review (2026-10-27): reviewed the release and launch checklists, repository
status, local signing identities, and GitHub releases and release runs. `main` was clean; no GitHub
release or release workflow run was listed, and this Mac has an Apple Development identity but no
Developer ID signing identity. No build or test was run for this review. Next: the founder chooses
the publisher and licence, sets up Developer ID, and agrees on the download and support details;
then run the signed, notarized release and test the downloaded DMG on a clean Mac.

## Known issues / not yet verified
- **New this round, not yet tried by hand:** the Location Services prompt and Apple naming the town; an update's
  swap and reopen (needs the second release carrying the updater); ⌘N and the reply chip; the Conversations
  window's reply with Stop; the companion coming out of hiding for a coin and Reduce Motion in the running app;
  the Now page's reminder rows showing their item (built, below the fold in every snapshot).
- **Using the internet (D47):** Feeds and Git still ask after outside content (Guard would need their address
  parameters); "Always" is never offered after outside content, so a built-in service is allowed from a clean
  turn's card or in Settings. A site you allowed can receive what a steered model puts in a page's path.
- **Not yet tried by hand with the real thing:** the microphone (its permission prompt, hold to talk,
  AirPods), Apple Notes on a real library after the -1728 fix, "clone … under ~/git" with a real AI,
  the menu bar's Approvals submenu and orange Full access icon, a live ElevenLabs voice, "Answer with
  Claude Code" from the no-AI card, Connect adding the skill and Codex's hook trust dialog, a first
  launch on a clean Mac without the developer tools (every built-in but Git should work there now),
  a two-finger swipe on a real trackpad, catch-me with a real mouse, macOS 15 and 26.
- **Built-ins' limits:** QR Codes needs an Apple GPU (a virtual machine's isn't opened); Currency covers
  the ECB's 30 currencies (no TND, AED…); the promise check reads English replies only.
- **Release blockers that need the founder** (docs/launch/CHECKLIST.md, docs/RELEASE.md): a licence,
  Developer ID and notarization, the name and domain, a privacy policy and support contact, Open-Meteo's
  terms if Sidefolk is paid, Anthropic's (and OpenAI's) approval of their logos.
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
- **Signing:** the Developer ID certificate and notary credentials live only in GitHub's secrets, so
  the Release workflow signs and notarizes; local builds are signed with the "Apple Development"
  identity or ad hoc. Apple took 29 minutes over the first accepted app; later ones should be quicker.

## Next
1. The founder: try snapshot 466 (signed and notarized by run 40681936191; checked on the downloaded DMG:
   checksum, Developer ID and timestamps on the DMG, the app, its helper and all thirteen extension programs,
   hardened runtime, the location and microphone entitlements, the `SidefolkRelease` stamp, stapled tickets,
   Gatekeeper "Notarized Developer ID"). Install it by hand (411 has no updater); the next snapshot then proves
   the in-place update (RELEASE.md › Updates). Still waiting from 411: hold to talk with the real microphone.
2. The founder's decisions: the licence (docs/research/licence.md); which of the 70 extension ideas to build
   (docs/research/extension-ideas.md); the library plan's nine decisions (docs/research/extension-library-plan.md).
3. Then: build the approved extensions with instant commands where they fit; the library's phase 1; production
   v0.1.0 with curated release notes (snapshot notes are commit subjects, and the update window shows them).

## Design next (from the 2026-10-26 pass)
1. A hand-drawn Mochi pose for the About window and onboarding (Mochi waving with the folks around,
   on a transparent background) would replace the family art where the companion speaks.
2. Check the hero and wordmark with each companion and in each accent colour by hand.
