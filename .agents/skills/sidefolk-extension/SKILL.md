---
name: sidefolk-extension
description: Create, test, install and ship a Sidefolk extension end to end, inside this repository and the sidefolk-addons gallery - choosing its shape (tools, commands, watchers, a page in Home, a Today tile, switches and buttons, a palette, background work), the manifest and its validator rules, a Swift program on the Kit, unit and sandbox tests, a check in the debug app with snapshots, and shipping it to the gallery (addon.json, icon, translated words, build.py snapshots) or as a local folder. Use when asked to make a new Sidefolk extension, add a tool, command, watcher, page, tile, switch or palette to one, port another app's features into one ("replace Maccy with an extension"), or fix one the validator rejects. Not for companions (sidefolk-3d-character), themes (D58, `sidefolk theme new`), features that belong in the app itself (D38 built-in tools), or plain MCP servers.
---

# Sidefolk extension

An extension (D13) is a folder: `sidefolk-extension.json` plus a program that speaks MCP over stdin/stdout. Sidefolk
runs the program under `sandbox-exec` with a profile built from the manifest's permissions, shows those permissions in
plain words before install, and sends every tool call through `ToolExecutor` (Guard, approvals, audit). The program
never decides what it may do.

| Where | What |
|---|---|
| `docs/EXTENSIONS.md` | The author's reference: every key, the protocol, sandbox, commands, pages, palettes, limits. Read the sections you need. |
| `Sources/SidefolkCore/Extensions/` | `ExtensionManifest.swift` (strict decoding), `ManifestValidator.swift` (every rule below), `ExtensionCommandRules.swift`, `ExtensionPage.swift` (what a page may hold), `SandboxProfile.swift`, `PermissionSummary.swift` (the install sheet's lines), `ExtensionHost.swift` (lifecycle, pages, palettes), `ExtensionDrafts.swift` |
| `extensions/` | The four built-ins (world-clock, system-vitals, weather, calculator; `catalog.json`), the `Kit/`, and the Python sample `hello-folk` |
| `../sidefolk-addons/` (read its AGENTS.md) | The gallery (D55): `extensions/<name>/`, `Kit/` (a copy), `Tests/`, `scripts/build.py`, `check.sh`, `publish.sh` |
| `skills/sidefolk-extension/` | The public skill for outside developers, with Python, Node and sh templates (no pages) |
| This skill's `templates/swift/` | Water Tally: a Kit program with four tools, commands, a page with a Today tile, buttons, a switch, a chart and a watcher; `build.sh`; unit tests |

Copy what a working extension does before inventing. Closest examples: a page and switches, `keep-awake`; a palette
and background work, `clipboard`; a page with charts and many watchers, `system-vitals-plus`; folders named per call
and a program by name, `git`; the internet and a watcher that fires once per crossing, `currency` (all in
`../sidefolk-addons/extensions/`); commands, `extensions/calculator` and `world-clock`.

## 0. Is it an extension?

Yes when the job fits a sandbox: compute, read this Mac's own state (processes, memory, battery: what System Vitals+
reads needs no permission, D62), call a web API, work in a folder the person names, run a known program, keep a small
state, check something every few minutes, show a page, keep running (clipboard history, a power assertion).

No when it needs:
- other apps' content through Apple Events (Mail, Notes, Calendar): a built-in tool in the app (D38);
- an account, API key or token: extensions can't hold secrets (D39); a plain MCP server can (Settings › Extensions ›
  Add MCP Server, unsandboxed, at least medium risk);
- to know which app is in front, open apps or links: Launch Services stays closed (D63);
- to draw its own UI: pages are data Sidefolk draws (D62). A companion or a theme has its own path.

Where it will live:
- **Gallery** (Sidefolk's own, ids `dev.sidefolk.<name>`): `../sidefolk-addons/extensions/<name>/`, built and signed by
  `scripts/build.py`. `build.py` asserts the `dev.sidefolk.` prefix and `run.command == "bin/ext-<name>"`; there is no
  path for third-party packs yet.
- **Built-in** (ships inside the app, can't be removed): only for what everyone needs; D55 cut these to four. Ask the
  founder first.
- **Local** (one Mac, anyone's id like `com.example.thing`): a folder installed with Settings › Extensions › Install
  from Folder… (or dropped on the companion). No signing, no gallery, no updates but reinstalling.
- **Draft**: Sidefolk's own AI writes text-only drafts (`.py .js .mjs .cjs .sh .json .txt .md .csv`, at most 20 files,
  1 MB, id `local.<name>`, author "Sidefolk, for you") with `extensions.draft`, starts them once with every permission
  removed, and opens the install preview with `extensions.review` (`Resources/Skills/build-extension/SKILL.md`,
  `ExtensionDrafts.swift`, D39). You don't write drafts by hand; `swift scripts/dev.swift review:<name>` opens one.

## 1. Decide the shape, then the least reach

Write it down before any code: each feature, which part carries it, and what that part needs.

| Part | When | Manifest | Program (Kit) |
|---|---|---|---|
| Tool | Anything the AI or a person asks for | `tools.<name>` | `ext.tool(name, title, description, input:) { args in … }` |
| Command | A request with a clear shape answered at once, no AI, no tokens (D50) | `tools.<name>.commands`, `words` | (the tool) |
| Commands only | The AI gains nothing (a coin flip, a page's setting) | `"ai": false` plus at least one command | (the tool) |
| Watcher | "Tell me when…", checked every 5 min at the soonest; on a page it is a heads-up switch | `watchers.<name>` | `ext.watcher(name) { settings, state in Check(…) }` |
| Page | A feature someone looks at: a page in Home's sidebar under Extensions | `pages.<name>` | `ext.page(name) { args in Page(…) }` |
| Today tile | The page's summary on Today | `pages.<name>.widget: true` | (the page's `Summary`) |
| Switch, button | Act from the page: runs one of its own tools as the person, through Guard (D63) | the tool | `.toggle(…, tool:, input:)`, `.button(…, tool:, input:, style:)` |
| Ask button | Send a sentence to Ask, as if typed | none | `.ask(label, sentence)` |
| Palette | A list on a keyboard shortcut over any app (D63) | `palettes.<name>` | `ext.palette(name, query:, choose:)` |
| Background | Must watch all the time (each copy, a held assertion) | `"background": true` | `ext.background { … }` (await, never spin) |
| Nudge | Keep the person "active" for chat apps | `permissions.power` | `ext.send("sidefolk/nudge")` (Sidefolk honours one per 20 s) |

Permissions (`permissions`, all optional; nothing is the goal). Every name below is checked in
`ManifestValidator.checkPermissions` and opened by `SandboxProfile.swift`:
- none: reads its own folder, writes its data folder (`SIDEFOLK_DATA_DIR`, also `HOME` and `TMPDIR`), may read the
  process list and the I/O Registry (D62 notes this needs no permission);
- `network: true`: any host, the LAN and localhost too;
- `files.read` / `files.write`: fixed folders, absolute or `~/`, never `~`, `~/Library`, hidden or system folders,
  nor Sidefolk's own data; prefer **folders named per call**, `tools.<name>.paths: {"<param>": "read"|"write"}`
  (at most 4; Guard checks each against the person's shared folders, and that call runs in a process of its own);
- `exec`: absolute paths of real, root- or user-owned programs, or `git` by name (`ProgramResolver.known`). Shells,
  interpreters, `osascript`, `open`, `curl`… are flagged "can run anything" (`ExtensionPermissions.anythingRunners` in `PermissionSummary.swift`);
- `media`: the GPU and video decoders that Core Image and ImageIO need; `clipboard`: `com.apple.pasteboard.1`;
  `power`: `com.apple.PowerManagement.control` and nudges.

Risk per tool: `low` runs, `medium` asks once (Always allow possible), `high` asks every time. Missing means medium.
The floor is medium for every tool when the extension has `network`, any `files.write`, a `"write"` folder
parameter, a "can run anything" program, or `clipboard` (`ExtensionPermissions.raisesRiskFloor`, `PermissionSummary.swift`); a manifest can raise
a risk, never lower it. Mark read-only tools `"mutates": false`.

## 2. The manifest

Strict (`ExtensionManifest.swift`): an unknown key anywhere is an error, at most 64 KiB. Top level:

| Key | Meaning and rule (`ManifestValidator.checkIdentity` unless noted) |
|---|---|
| `id` | Required. `^[a-z0-9]+(\.[a-z0-9-]+)+$`, at most 64. Its last part names the tools (`ext.<last>.<tool>`) and should name the folder (another folder name is a warning; installed copies must match exactly). Stable forever. |
| `name` | Required. 1–60 characters of plain text. |
| `version` | Required. `^\d+\.\d+(\.\d+)?([-+][0-9A-Za-z.-]+)?$`. Gallery: the version it's heading for (`1.0.0`); `build.py` publishes `1.0.0-snapshot.<n>` until `addon.json` says `"released"` (D65). Never write `-snapshot.N` yourself. |
| `sidefolk` | `>=0.1`: refused if this copy is older (`satisfies`). Becomes the catalog's `minimum_sidefolk`. Sidefolk stays 0.1.0 until the founder ships it, so write `>=0.1` (D62 amended). |
| `description` | At most 300 characters; the install preview shows it whole, Settings under Details. |
| `tagline` | One line, 1–60 characters, under the name in Settings. |
| `folk` | `^[a-z0-9-]{1,32}$`; one of `pip byte seed melody scout tempo play guard nova brew` (`Sources/SidefolkCharacter/Folks.swift`). |
| `author` | At most 100 characters. Gallery: "Sidefolk". |
| `icon` | `icon.pdf` (one square page) or `icon.png` (64–1024 px square), at most 256 KiB, inside the folder; SVG refused (`ExtensionIcon`). |
| `run` | `{"command": "bin/ext-<name>"}` for a Kit program (a Mach-O file, executable, inside the folder), or `python3`/`node`/`sh` with the script as `args[0]` (`InterpreterResolver.supported`). At most 32 args. |
| `permissions` | Above. Keys: `network files exec media clipboard power`. |
| `tools.<name>` | `^[a-z0-9_]{1,64}$`, full name ≤ 64. `title` 1–80 plain text, `risk`, `category` (`notes memory time watch files web system agents extensions`), `mutates`, `paths`, `timeout` 1–300 s (30 default), `ai`, `commands`. At most 128 tools. |
| `words.<list>` | Word lists a slot can take (`{from:unit}`): at most 16 lists, 2,000 words. |
| `watchers.<name>` | `title` 1–60, `description` ≤ 300, `config.<key>`: `type` (`integer number string boolean`), `description`, `default` (must fit the type), `required`, `minimum` ≤ `maximum`. At most 32 watchers, 32 settings each. |
| `pages.<name>` | `title` 1–40, `symbol` an SF Symbol name (`^[a-z0-9]+(\.[a-z0-9]+)*$`), `refresh` 2–3600 s while open (5 default), `history` and `widget` (also read once a minute while Sidefolk runs; the install preview says so). At most 4 (`checkPages`). |
| `palettes.<name>` | `title` 1–40, `hotkey` like `shift+cmd+c` (cmd, ctrl or option, then one key), `placeholder` ≤ 60. At most 2 (`checkPalettes`). |
| `background` | `true`: starts with Sidefolk, no idle stop, back after a crash until 3 in 5 minutes turn it off. |

Commands (`ExtensionCommandRules.swift`, docs/EXTENSIONS.md › Answering without the AI): `{"say": [...], "input": {...}}`,
slots `{name}` (any words) or `{name:kind}` with kinds `text word number integer expression place url date list` or a
`words` list. A sentence needs a word of its own, can't start with a slot that takes any words, has at most 3 slots and
80 characters; no common replies ("yes", "thanks", "stop"); every sentence of a command has the same slots; at most 12
sentences a command, 8 commands a tool, 64 sentences an extension; `"ai": false` needs commands. English only (D28).
Without `input`, slots fill the arguments of the same name. Return an error (`Problem`) for input you don't understand:
the sentence then goes to the AI.

A real manifest with a page, a tile, commands and a watcher is `templates/swift/sidefolk-extension.json`. Others:
Keep Awake (background, `power`, a page with buttons and switches, `"ai": false` on `set_option`) and Clipboard
(`clipboard`, a palette on `shift+cmd+c`, a page), in `../sidefolk-addons/extensions/`.

## 3. The program on the Kit

`extensions/Kit/` (`Extension.swift`, `Page.swift`, `Schema.swift`, `System.swift`, `Language.swift`, `KitWords.swift`,
`Localized.swift`), copied unchanged to
`../sidefolk-addons/Kit/` (change it here first; `check.sh` warns when they differ). One `Extension(name:)`, register
handlers, then `await ext.serve()`; top-level code is on the main actor. The Kit answers `initialize`, `ping`,
`tools/list`, `tools/call`, `sidefolk/watch.check`, `sidefolk/page.render`, `sidefolk/palette.query` and
`sidefolk/palette.choose`, one JSON-RPC line each way; stdout carries nothing else (log to stderr).

- **Tools**: `Schema.object([...], required:)` with `Schema.string/integer/number/boolean/array/path`; every object
  refuses unknown keys, so bound everything. Read with `args.string/int/double/bool/strings/required`. Throw
  `Problem("…")` for what the person or model can fix: it becomes an `isError` result. Third-party descriptions never
  reach the model (D24); first-party ones (built-in and gallery, `ExtensionOrigin.firstParty`) do (D39, D55), so write
  them like prompts.
- **Watchers**: return `Check(triggered:, state:, summary:)`. Trigger on change, not level, keeping what you need in
  `state` (≤ 64 KB); `summary` ≤ 200 characters. A page shows each watcher as a heads-up switch that runs
  `watch.extension` as the person, every 5 minutes, in `repeat` mode (`Sources/SidefolkApp/Home/ExtensionPageModel.swift`).
- **Pages**: `Page(summary: Summary(title, detail:, tone:, symbol:), sections: [Section(title, [Block])])`. Blocks:
  `.gauge`, `.stat`, `.chart(id:…, series: [Series(key, label, value, display:)])`, `.bars`, `.facts`, `.note`, `.ask`,
  `.toggle`, `.button`; tones `good warn bad info neutral`. Sidefolk drops what doesn't fit (`ExtensionPage.parse`):
  a page over 128 KB fails; at most 16 sections, 24 blocks a section, 24 items a list, 4 series a chart; chart `id` and
  series `key` must match `^[a-z0-9_]{1,40}$` and stay stable (they name the kept history); a switch or button must
  name a tool of this extension (`^[a-z0-9_]{1,64}$`), its `input` ≤ 4 KB, and a switch adds `on`. Text is clipped
  (summary title 80, detail 240, labels 30–60, notes 400) and never reaches a model.
- **Language** (D76): Sidefolk sends `language` with every tool call, watcher check, page and palette request; the Kit
  keeps it (`Language.code`). Write every word people see as `L("English text", ["name": value])` (named `{name}`
  placeholders) or `L(one: "{count} app", other: "{count} apps", count: n)`, and numbers, sizes, durations and times
  with `Format` (`percent`, `bytes`, `duration`, `time` on 24 hours, `date`, `list`, `sentences`), never by hand. The
  words live in `strings/<language>.json` beside the manifest: `en.json` lists the English (`scripts/extension-strings.py
  sync <folder>` writes it from the `L(…)` calls), each other language translates `text` and the manifest's words people
  see (name, tagline, description, tool/watcher/page/palette titles, watcher descriptions, palette placeholder,
  `network_purpose`). `extension-strings.py check <folder>` says what's missing; `sidefolk ext validate` checks
  placeholders, plural forms and limits (half as long again as the manifest's). What a command or an `ask` button says
  stays English (Sidefolk understands typed requests in English). Don't put direction marks in text: Sidefolk strips
  them and keeps numbers, sizes and paths left to right itself when it lays out right to left. In-code tables work too
  (`Localized`, D75, as Playtime does). Tests: `Language.with("de", strings: folder) { … }`.
- **Palettes**: `query` returns `PaletteList([PaletteItem(id:, title:, detail:, kind:, pinned:, actions:)], note:)`
  (kinds `text link image file color code`, actions `plain pin delete`; at most 200 items, 10 s a call); `choose`
  gets the item id and `choose|plain|pin|delete` and returns `PaletteChoice(close:, paste:, message:)`. With `paste`,
  put the content on the clipboard first (needs `permissions.clipboard`); Sidefolk presses ⌘V once the person allowed
  Accessibility.
- **Background**: `ext.background { await … }` shares the main actor with requests (stdin is read off it).
- **Files**: `Paths.data` is the data folder (kept across updates, removed with the extension). `Paths.home` is the
  person's real home (HOME is the data folder in the sandbox). `run(program, args)` runs an `exec` program;
  `Web.json(url)` needs `network`.
- **Python, Node, sh** work too (`run.command` `python3`/`node`/`sh`; Python is the developer tools' 3.9 under `-I -B`),
  but every shipped extension is Swift so it needs nothing installed (D39 addendum). The protocol is the same: see
  `extensions/hello-folk/main.py` and `skills/sidefolk-extension/templates/`, and add `sidefolk/page.render` yourself.

## 4. Start from the template

```sh
cp -R .claude/skills/sidefolk-extension/templates/swift ~/scratch/<name>   # outside any repository
```

Then rename everywhere: the id (`com.example.water-tally`), `run.command` and the product `ext-<name>` (Package.swift,
`build.sh` reads the id), `Extension(name:)`, the test's `@testable import ext_<name>`. Replace Water Tally's logic,
keeping its split: pure logic in its own file (tested), the page in another, `main.swift` only wiring.

- **Local**: `./build.sh <sidefolk checkout> <out>` copies the Kit, builds release, and assembles `<out>/<name>/` with
  only the manifest, the icon and `bin/ext-<name>` (Install from Folder copies everything in a folder, so never install
  the source folder).
- **Gallery**: make `../sidefolk-addons/extensions/<name>/` with `sidefolk-extension.json`, `icon.pdf`, `addon.json`
  and `Sources/` (the template's `Sources/*.swift`), add `<name>` to `extensions` in that repo's `Package.swift`, and put
  its logic tests in `Tests/` (`@testable import ext_<name>`, see `Tests/ClipboardKeepAwakeTests.swift`).

## 5. Test

1. **Logic**: `swift test` (template, after `build.sh` copied `Kit/`), or in sidefolk-addons `swift test`.
2. **Protocol by hand**, from a scratch folder:
   ```sh
   cd "$(mktemp -d)" && printf '%s\n' \
     '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
     '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"log_water","arguments":{"glasses":2}}}' \
     '{"jsonrpc":"2.0","id":3,"method":"sidefolk/page.render","params":{"page":"water","language":"en"}}' \
     '{"jsonrpc":"2.0","id":4,"method":"sidefolk/watch.check","params":{"watcher":"behind","config":{"after_hour":6},"state":null}}' \
     | SIDEFOLK_DATA_DIR=$PWD <out>/<name>/bin/ext-<name>
   ```
3. **Validator and a start in the real sandbox** (`ExtensionValidator.validate`, then `.trial`, which installs a copy
   into a throwaway home):
   ```sh
   swift build --product sidefolk
   SIDEFOLK_HOME="$(mktemp -d)" .build/debug/sidefolk ext validate <out>/<name>
   ```
   It must end `Valid.` and "It started in its sandbox and offers N tools", with no `Warnings:`. Read the
   `Permissions:` lines and warnings as a stranger would: they are the install preview's lines
   (`PermissionSummary.forExtension`), and the preview adds "Pages in Home: …, read once a minute in the background"
   for `history`/`widget` (`ExtensionWords.pages`). Each line must be true and nothing the extension does may be
   missing from them. Note: the preview has no line for `background: true` or for palettes yet; the CLI prints
   "Keeps running while it's on" and "Palettes:". Gallery: `python3 scripts/build.py --unsigned` then
   `SIDEFOLK_APP=../sidefolk scripts/check.sh` validates every staged pack.
4. **Sandbox tests in the app** for a gallery extension: add a test to
   `Tests/SidefolkCoreTests/Extensions/ShippedExtensionSandboxTests.swift` (or `ExtensionPageTests.swift` for a page)
   gated on `ExtFixtures.hasAddons`: `HostEnv()`, `h.host.install(from: ExtFixtures.builtIn("<name>"))`,
   `h.call("ext.<name>.<tool>")`, `h.host.checkWatcher(…)`, `h.host.renderPage(extensionId:page:)`. They run against a
   built `../sidefolk-addons` (`swift build` there; `SIDEFOLK_ADDONS_REPO` moves it); `ExtFixtures.builtIns` copies each
   add-on's manifest, `icon.pdf` and program, so it needs an `icon.pdf`. `make test` (serial, D18).
5. **In the debug app**, with a fresh short home (the socket path must stay under 104 bytes):
   ```sh
   scripts/build-app.sh debug        # or make dev, which uses build/dev-home
   QA=$PWD/build/qa-$(date +%H%M); mkdir -p $QA
   SIDEFOLK_HOME=$QA build/Sidefolk-dev.app/Contents/MacOS/Sidefolk > $QA.log 2>&1 &
   SIDEFOLK_HOME=$QA swift scripts/dev.swift installFolder:<out>/<name>    # installs as if the preview was approved
   SIDEFOLK_HOME=$QA swift scripts/dev.swift page:<id>/<page>              # Home on the page
   SIDEFOLK_HOME=$QA swift scripts/dev.swift "ask:log 2 glasses of water"  # a command, or anything for the AI
   SIDEFOLK_HOME=$QA swift scripts/dev.swift palette:<id>/<palette>        # as if its shortcut were pressed
   SIDEFOLK_HOME=$QA swift scripts/dev.swift snap                          # PNGs in $QA/snapshots
   ```
   Read the PNGs (Home is the `NSWindow-…` one, Ask a `FloatingPanel-…`). A page re-reads every `refresh` seconds, so
   a change made from Ask shows on the next read. Logs: `$QA/Logs/` (category `extensions`); the profile:
   `$QA/Sandbox/<id>.sb`; its data: `$QA/ExtensionData/<id>/`. Stop only your app:
   `pkill -f "$PWD/build/Sidefolk-dev.app/Contents/MacOS/Sidefolk"` (teammates run theirs). No live model calls:
   test commands and pages, not the AI.

## 6. Ship it

**Local**: hand over `<out>/<name>/`; the person uses Settings › Extensions › Install from Folder… and reads the
preview. A new version is installed the same way; the sheet shows permissions gained and lost; changed tool
definitions are held until approved.

**Gallery** (`../sidefolk-addons`, never push or publish unless the founder asks):
- `addon.json` beside the manifest: `{ "category": "everyday" }` (or `files`, `developer`, `fun`: the shelf, D56).
  Add `"released": "1.0.0"` only when the founder releases that version (D65).
- `icon.pdf`: add a drawing function to `scripts/extension-icons.swift` (full-bleed, a folk's colours, 512 pt) and
  its entry in `icons`. The script writes `extensions/<name>/icon.pdf` in this repo, so for a gallery extension make
  that folder, run `swift scripts/extension-icons.swift --png /tmp/icons <name>`, look at the PNG, move the PDF to the
  add-on folder and remove the folder. Name only the icon you changed: a PDF records when it was written.
- Translated words: the extension's own `strings/` in all ten languages (step 3, Language): `build.py` packs it and
  puts the name, tagline and description per language in the catalog, so the gallery, the install sheet and every
  page speak the person's language. `ExtensionLanguagesTests` here wants every word in every language for Sidefolk's
  own. `BuiltInExtensionWords.swift` (the app's catalog) is the fallback for packs from before D76: keep it word for
  word with the manifest (`BuiltInExtensionWordsTests`), and add a new extension's words there too while older packs
  are around.
- `swift test`, `python3 scripts/build.py --unsigned`, `scripts/check.sh` there; `make test` here.
- `python3 scripts/build.py` (Developer ID) and `scripts/publish.sh` are the founder's. `build.py` numbers snapshots
  itself, keeps a published pack byte for byte, and stops when a released version's files changed. Never raise a
  version by hand to make a snapshot; never release a version yourself. To try a signed build in a debug app before
  publishing: `SIDEFOLK_ADDONS=<sidefolk-addons>/dist` (non-release copies only, `AddonCatalog.swift`).

## 7. Checklist

- [ ] It does what its words say; nothing on the page or in an answer is made up (no fake features).
- [ ] Every action goes through a tool, so `ToolExecutor` and Guard see it; pages, palettes and watchers only read
      and report. Switches and buttons call its own tools.
- [ ] The least permissions that work; each preview line and warning is true and complete; risks are honest.
- [ ] Titles and parameter names say what they do; inputs bounded; failures are `Problem`s that say what to do.
- [ ] Commands cover the common shapes, read right in the validator's "Answers without AI", and `"ai": false` is used
      where the AI gains nothing.
- [ ] Watchers trigger on change; the page's chart ids and series keys are stable.
- [ ] `sidefolk ext validate` says `Valid.` with no warning; logic tests pass; gallery: `check.sh`, sandbox tests,
      `make test`.
- [ ] Snapshots of the page (and palette, Ask answers) read and compared with what was meant, light and dark if the
      layout is new.
- [ ] Icon, tagline ≤ 60, description ≤ 300, author; gallery: `addon.json`, `BuiltInExtensionWords`, strings.
- [ ] Every word people see through `L` and `strings/`, complete in ten languages (`extension-strings.py check`);
      numbers, sizes and dates through `Format`; snapshots in German (long), Japanese and Arabic (right to left) read.
- [ ] `docs/STATUS.md` (what changed, how verified, the next step); a DECISIONS entry for any new kind of reach;
      `docs/EXTENSIONS.md` when the platform changed. Commit in a coherent milestone, no Co-Authored-By trailer.

## Newer features (D67, D68, D69, D74, D75, D76)

- **Games in the Play panel (D75, D79).** `games.<name>` in the manifest (`title`, `symbol`, `say` up to
  24 sentences, about two a language, `levels`, `ai`) and `ext.game(name, start:, move:, end:)` in the Kit
  (extensions/Kit/Game.swift, GameParts.swift): answer `start` with a session and a `Board`, each `Move` with the next
  board, within 2 s and 64 KB. Parts: prompt, answers (a tile's own `key`: Y, N, ?), board (`numpad`), score, result,
  timer, reveal, note, facts, button (a move, never a tool), choice, and `.play(...)`: pads (Sidefolk plays the
  sequence), cups (Sidefolk animates your swaps), reflex (Sidefolk times the press), meter, number, letters, keys (a
  keyboard per script, `letter` or `spell`), entry (a text field for input methods), sticks, lives. `afterMs` on a board
  is the companion thinking: Sidefolk waits, then sends `.next`. A board's `Cue` names a move, effect, prop, line key,
  sound and look from Sidefolk's fixed lists. Send the verdict in the board: Sidefolk shows the build-up first (the old
  score, words and keyboard, the cups down, the row flipping) and colours right/wrong/draw itself. Playtime
  (sidefolk-addons `extensions/playtime`: `Sources/GameKit` with `EventCues`, `Sources/Screens`, `Sources/Trivia`) is
  the example, eleven games; docs/EXTENSIONS.md › Games.
- **The person's language (D76 over D75).** One way: `strings/<language>.json` and `L("English {name}", [...])`,
  `L(one:other:count:)`, `Format`. The Kit's `Localized(language, tables)` (D75) is the lower layer `L` reads through
  (normalization: `zh-Hant` is `zh-Hans`, the nearest Sidefolk speaks; English fallback); use it directly only for a
  table that isn't the extension's words. Playtime's words, the engines' phrases included, are in its `strings/`.
- **A main switch where people are (D67).** An extension that is mostly on/off puts its switch on the page summary:
  `Summary("Awake until 18:00", detail: "25 min left", tone: .good, control: .toggle(...))` (extensions/Kit/Page.swift),
  with `"widget": true` on the page. Sidefolk shows it on the page, its Today tile and its sidebar row, runs the
  extension's own tool as the person through Guard, then reads the page again. Keep Awake is the example
  (sidefolk-addons `extensions/keep-awake/Sources/AwakePage.swift`). The tile and row use the last background read,
  so it needs `widget`.
- **Pages are the person's to arrange (D67).** They can hide a page (it stays in All Extensions), reorder it or take its
  tile off Today (`AppSettings.homePages`). Don't rely on a page being in the sidebar: put the quick action on the
  summary, and keep the page for choices and detail. Layout is automatic (`Home/ExtensionPageLayout.swift`): sections
  with gauges or stats, two or more cards, notes alone or buttons alone run across; others sit 2–3 to a row.
- **Pictures, previews and sections in palettes (D68).** A `PaletteItem` may name `image` (a PNG or JPEG the program
  wrote in its own data folder, `Paths.data`, named relative to it, e.g. `thumbs/<id>.png`), a `color` swatch and a
  `section` ("Pinned"). Make thumbnails once at about 256 px; Sidefolk reads them without following links, at most 4 MB
  per row (`Sources/SidefolkCore/Extensions/ExtensionDataFile.swift`). Answer `sidefolk/palette.preview` with a
  `PalettePreview` for the picked item in full; list actions `clear` / `clear_all` are asked twice. Maccy's keys
  (⌘1–9, ⌥↩, ⇧↩, ⌥P, ⌥⌫) are Sidefolk's (`PaletteKeys.swift`); the extension only sees the action. Clipboard
  (sidefolk-addons `extensions/clipboard`) is the example.
- **Page parts `choice`, `field`, `list` (D68)** run the extension's own tools as the person: a setting picked from a
  few values, a text setting, and rows with a picture and a button each.
- **Notices (`ext.on`, D68).** `ext.on("sidefolk/clipboard.source") { … }` hears what Sidefolk tells the program
  without a request; Sidefolk answers the clipboard source only with `permissions.clipboard`, once per copy.
- **Screen, UDP and a network purpose (D69).** `permissions.screen` records the screen and the Mac's sound
  (ScreenCaptureKit and the video encoder; every tool at least medium risk; macOS asks for Sidefolk, not the
  extension). `permissions.udp` (with `network`) lets it bind and receive UDP, e.g. for WebRTC.
  `permissions.network_purpose` ("to find TVs on your local network and stream to them") is shown after the network
  line, which always says "the internet included": the sandbox can't limit an extension to the local network, so
  never claim it. Linked frameworks ship in `lib/` (plain files, no symlinks), signed by the same team. A process
  started for one call (a file grant) gets `SIDEFOLK_ONE_CALL=1` and the Kit skips background work there. Miraya
  (sidefolk-addons `extensions/miraya`) is the example.
- **A page that reads like an app screen (D74).** For a feature with a main action and states (connect, share, play),
  lead the page with a `.hero(Hero(...))`: the state in a few words (`eyebrow`), a large title, a line, a `code` to
  compare, a picture, up to four live `facts`, and up to three `actions` drawn large. It replaces the summary banner on
  the page (the summary still feeds the tile and sidebar). Build the page per state, so each state is its own clear
  screen (Miraya: no TV, ready, pairing with the code, sharing with live numbers, paused, playing). Give every button
  its emphasis: `.primary` for the ONE thing to do (Sidefolk keeps only the first primary on a page filled), `.secondary`,
  `.destructive` (filled red when the page has no primary: "Stop sharing"), `.plain` for rarely needed ("Look again",
  "Forget"); `Action(..., detail:, disabled: true)` shows a step that can't run yet and says why.
- **Choosing visually (D74).** `.picker(label, style:, options, selected:, tool:, key:)` is a `choice` drawn as
  `.cards` (presets with a line each), `.tiles` (pictures: displays, windows, photos; up to 24) or `.rows` (devices or
  accounts with a `Badge` each and a small per-row `action`, up to 24). Picking runs your tool with the option's value
  under `key`. Tile pictures are files in `Paths.data` like list pictures: give each new picture a new name (Sidefolk
  caches by name) and delete old ones. Never let choosing reveal more buttons: pick inline, act with the hero's button.
- **Layout from the extension (D74).** `Section(..., place: .side)` puts a section in a column beside the main ones in a
  wide window (a device list, like an app's sidebar); `collapsed: true` folds it under its title (advanced settings,
  connection details). `.transport(Transport(...))` shows something playing: position, duration, round symbol buttons
  with play or pause as the primary. An older Sidefolk skips hero and transport and draws pickers as plain choices,
  so keep the summary meaningful (with its `control`) for those copies.
