# Sidefolk — Architecture

Native macOS app in Swift 6 (AppKit shell, SwiftUI views, Core Animation character), built with
Swift Package Manager and assembled into `Sidefolk.app` by `scripts/build-app.sh`.
Minimum macOS 15. One process for the app, one small helper binary (`sidefolk`) for the CLI and
the MCP bridge, and one process per running extension.

```
┌──────────────────────────── Sidefolk.app (SidefolkApp) ─────────────────────────────┐
│ AppKit shell: CompanionWindow · AskPanel · Bubbles · HomeWindow · Settings · StatusItem │
│ SidefolkCharacter: Rig (CALayers) · Pose · Choreographer · Folks                        │
│            ▲ CompanionPresenter (MainActor, @Observable) ◄── AppEvents                  │
├────────────┼────────────────────────── SidefolkCore ────────────────────────────────────┤
│  AgentRuntime ── Backends: Loop(Anthropic | OpenAI-compat) · ClaudeCode · Codex (CLI+MCP)│
│      │ ContextBuilder (budgeted)      ModelRouter (fast/smart)                           │
│  ToolExecutor ─► Guard (PermissionEngine + ApprovalBroker + Grants) ─► Tool registry     │
│      │                                     builtin tools · extension tools · MCP tools   │
│  ReminderScheduler · WatcherEngine · AttentionCenter · EventBus · ActivityLog           │
│  Stores (GRDB/SQLite): notebook · memories · reminders · watchers · exchanges ·         │
│                        activity · grants · extensions · agent runs                       │
│  ExtensionHost (sandbox-exec + MCP stdio client) · SkillLibrary · LocalAPIServer (socket)│
│  Secrets (Keychain) · Settings · Diagnostics (os.Logger + JSONL, redaction)              │
└──────────────────────────────────────────────────────────────────────────────────────────┘
        ▲ unix socket (0600, same uid)                     ▲ stdio (sandboxed)
  sidefolk mcp  ◄── Claude Code / Codex / any MCP client     extension processes
```

## Packages and targets (Package.swift)

| Target | Kind | Depends on | Contents |
|--------|------|-----------|----------|
| `SidefolkCore` | library | GRDB | Everything that is not UI. No AppKit. Fully unit tested. |
| `SidefolkCharacter` | library | — (AppKit, QuartzCore) | Character rig, poses, choreography, folks, icon rendering. |
| `SidefolkApp` | executable | Core, Character, KeyboardShortcuts | App delegate, windows, SwiftUI views, platform services. |
| `sidefolk` | executable | Core (protocol types only) | CLI: `sidefolk mcp` bridge, `sidefolk status`, `sidefolk ext validate`. |
| `sidefolk-render` | executable (dev) | Character | Renders every pose and folk to PNG contact sheets for visual review. |
| `SidefolkCoreTests` | tests | Core | Swift Testing. |

Executable product names avoid case clashes (`SidefolkApp` vs `sidefolk`); the build script
renames the app binary to `Sidefolk` inside the bundle and puts the CLI in `Contents/Helpers/`.
No SPM resource bundles are used for the app (they break `.app` signing); assets live in
`Resources/` and are copied by the build script. `ResourceLocator` finds them in the bundle or,
in development, in the repo (`SIDEFOLK_RESOURCES`).

## Data locations

| What | Where |
|------|-------|
| Database | `~/Library/Application Support/Sidefolk/sidefolk.sqlite` (WAL) |
| Extensions | `~/Library/Application Support/Sidefolk/Extensions/<id>/` |
| Skills | `~/Library/Application Support/Sidefolk/Skills/<name>/SKILL.md` |
| Socket | `~/Library/Application Support/Sidefolk/run/sidefolk.sock` (dir 0700, socket 0600) |
| Brain workdir | `~/Library/Application Support/Sidefolk/brain/` (empty cwd for CLI brains) |
| Logs | `~/Library/Logs/Sidefolk/sidefolk-YYYY-MM-DD.jsonl` (7 days) |
| Secrets | Keychain, service `app.sidefolk.secrets` |
| UI prefs | `UserDefaults` (`app.sidefolk`) |

`SIDEFOLK_HOME` overrides the Application Support folder (tests, dev, QA). Tests never touch real
user folders or agent configs.

## Core concepts and types (SidefolkCore)

- `JSONValue` — dynamic JSON (tool inputs, schemas, configs).
- `Caller` — `.user`, `.agent(runID)`, `.routine(id)`, `.external(client)`, `.extension(id)`.
- `ToolSpec` — name, title, description, input schema, `risk`, `capabilities`, `category`,
  `mutates`. `Tool` — `spec`, `summary(input)` (plain language for approvals and Activity),
  `run(input, context) async throws -> ToolResult` (content for the model, optional result card,
  optional undo, `untrusted` flag).
- `ToolRegistry` — built-in tools + tools contributed by extensions/MCP servers; namespaced
  (`notes.create`, `ext.system-vitals.battery`). Model-facing names replace `.` with `_`.
- `Guard` — `PermissionEngine.evaluate(call, spec, caller, tainted) -> .allow | .ask(req) | .deny`;
  `ApprovalBroker` (actor) parks requests until the UI answers or a timeout denies;
  `GrantStore` persists "always allow" grants with scope (tool, folder, exact command, extension).
- `ToolExecutor` — the only path to run a tool: guard → (approval) → run with timeout → activity
  log → events. Every caller (agent loop, Claude Code brain via bridge, external MCP, slash
  command, routine) goes through it.
- `AgentRuntime` — handles a user turn: builds context (`ContextBuilder`, token budget), picks a
  model (`ModelRouter`), runs a backend, streams `AgentEvent`s, records an `AgentRun`.
  - `LoopBackend` drives `TurnModel` providers (`AnthropicModel`, `OpenAICompatibleModel`):
    request → tool calls → executor → results → repeat, max 10 steps / 120 s by default.
    `OpenAICompatibleModel` serves every `ProviderPreset` (see AI providers below).
  - `ClaudeCodeBackend` runs `claude -p --output-format stream-json --tools "" --strict-mcp-config
    --mcp-config <sidefolk bridge>` in the brain workdir with an isolated settings source; the
    brain can only call Sidefolk tools, which arrive over the socket tagged with a per-run token
    and go through the same executor.
  - `CodexBackend` runs `codex exec --json --ignore-user-config --ignore-rules --sandbox read-only
    --ephemeral`, every non-essential Codex feature off, and `-c mcp_servers.sidefolk…` pointing at
    the same bridge (SECURITY T7). Codex doesn't list its tools up front, so `CodexStream` watches
    the event stream and stops the run on anything but Sidefolk's tools.
  - `CLIBrain` holds what the two CLI brains share: binary vetting, the prompt-free probe, the
    environment allow-list, the one-message conversation, the per-run private folder.
  - `ScriptedModel` (tests only) replays canned turns.
- `ReminderScheduler` (actor) — one timer for the next due reminder (no polling), re-armed on
  change, wake, clock change; fires to `AttentionCenter`; recurrence; snooze; missed-on-launch
  summary; computes fallback system notifications when the app quits.
- `WatcherEngine` (actor) — runs `WatcherProbe`s: polling kinds share one scheduler loop keyed by
  next-check time; event kinds use DispatchSource (vnode/proc). Interval floors, exponential
  backoff on error, expiry, once/repeat, state persisted after every check.
- `AttentionCenter` (actor) — receives `AttentionRequest`s (level, source, title, body, actions),
  applies policy (quiet mode, fullscreen, away, grouping, re-nudge, rate limits) and emits
  presentation directives for the app. Pure policy core (`AttentionPolicy`) is unit tested.
- `EventBus` — typed broadcast (`AppEvent`) via `AsyncStream`s; UI subscribes on MainActor.
- `ExtensionHost` (actor) — discovers manifests, validates, computes sandbox profiles, spawns
  processes, speaks MCP (`initialize`, `tools/list`, `tools/call`) plus Sidefolk watcher methods
  (`sidefolk/watch.check`), enforces timeouts, isolates crashes, enable/disable/uninstall.
- `SkillLibrary` — reads skills, exposes an index to the context builder, `skills.load` tool.
- `MacApps/` (D38) — the Mac's own apps as built-in tools: `AppleEventsRunner` runs fixed JavaScript
  for Automation programs (`OsascriptRunner`: `/usr/bin/osascript` child, script on stdin, params as
  JSON); `AppleNotes` (an index of accounts, folders and notes cached 2 min, snippets, whole notes as
  Markdown via `NoteMarkdown`, removal into Recently Deleted); `AppleNotesLedger` (which notes are in
  the notebook, `kv` key `applenotes.copied`); `AppleReminders` (open reminders). Tools:
  `applenotes.list/read/copy/remove`, `applereminders.list`, capability `mac.apps`.
- `LocalAPIServer` — unix socket JSON-lines server: `hello`, `tools/list`, `tools/call`,
  `status`; peer uid check; tokens map brain runs to `Caller.agent`.
- `Diagnostics` — `os.Logger` categories + JSONL file sink with `Redactor` (keys, tokens, long
  content trimmed); `DiagnosticsExporter` writes a zip without user content by default.

## Database schema (v1 migration)

```
collections(id TEXT PK, name, kind[inbox|project|topic|list], emoji, created_at, updated_at, archived_at)
items(id TEXT PK, collection_id FK, kind[note|idea|task|link], title, body, url, tags,
      status[open|done], due_at, source, created_at, updated_at, deleted_at)
items_fts(title, body, tags)  -- FTS5, external content = items, kept by triggers
memories(id TEXT PK, kind[fact|preference|person|project], content, collection_id, source,
         created_at, updated_at, last_used_at, expires_at)
memories_fts(content)
reminders(id TEXT PK, title, notes, fire_at, timezone, recurrence JSON, state[scheduled|fired|
          snoozed|done|cancelled], snoozed_until, last_fired_at, fired_count, level, action JSON,
          item_id, source, created_at, updated_at)
watchers(id TEXT PK, kind, title, config JSON, condition JSON, interval_s, state[active|paused|
         triggered|expired|error], mode[once|repeat], level, last_checked_at, next_check_at,
         last_state JSON, last_error, error_count, fire_count, expires_at, source, created_at, updated_at)
exchanges(id TEXT PK, thread_id, role[user|assistant|tool|event], content, meta JSON, created_at)
activity(id INTEGER PK, at, caller, tool, risk, decision[auto|allowed|always|denied|blocked|failed],
         summary, args_redacted JSON, outcome, error, run_id)
grants(id TEXT PK, tool, scope JSON, caller_kind, created_at, last_used_at)
folders(path TEXT PK, access[read|readwrite], created_at)
extensions(id TEXT PK, version, path, enabled, kind[sidefolk|mcp], granted JSON, installed_at, last_error)
agent_runs(id TEXT PK, thread_id, provider, model, started_at, ended_at, steps, input_tokens,
           output_tokens, outcome, error)
attention(id TEXT PK, level, source, title, body, actions JSON, state[pending|shown|acknowledged|
          expired], created_at, shown_at, acknowledged_at, renudged)
kv(key TEXT PK, value JSON)   -- domain settings that must live with the data; applenotes.copied (D38)
```

All timestamps are UTC seconds (REAL). IDs are ULID-like sortable strings.

## Concurrency model

Swift 6 strict concurrency. Core services are actors or `Sendable` final classes over GRDB's
`DatabasePool`. The app target uses MainActor by default for UI types. Events cross into the UI
through `EventBus` streams consumed by `@MainActor @Observable` presenters. No locks held across
`await`.

## Process, windows and focus

- Activation policy `.accessory` (no Dock icon). Opening Home/Settings switches to `.regular`
  while those windows are open so they are reachable with ⌘Tab.
- Companion: borderless `NSPanel` (non-activating), level `.floating`, collection behavior
  `.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle`; mouse events only on the
  character's hit shape.
- Ask panel: non-activating `NSPanel` that can become key so typing never steals app activation.
- Bubbles: child panels of the companion, positioned to stay on screen.

## AI providers

Settings › AI groups them by how the user pays (D26): a plan they already have, an API key, this
Mac, a custom endpoint, or no AI. Status comes from local reads only (`ClaudeBinary.status`,
`CodexBinary.status`, `LocalServers.probe`, the Keychain, `ModelCatalog.list`); "Test" is the one
action that sends a prompt.

| Provider | Auth | Notes |
|----------|------|-------|
| Claude Code | the user's `claude` login | Brain runs with `--tools ""` so only Sidefolk tools exist; isolated cwd and settings; no session persistence. |
| Codex | the user's `codex login` (ChatGPT plan) | `codex exec` isolated as in T7; Codex's default model unless one is picked from its bundled catalog; "Think harder" adds `model_reasoning_effort="high"`. |
| Anthropic API | API key (Keychain) | Messages API with tool use. |
| OpenAI-compatible | per preset | `ProviderPreset`: OpenAI, Google Gemini (its OpenAI-compatible endpoint), Mistral, Groq, xAI, DeepSeek, OpenRouter (key required, fixed address), Ollama (`/api/tags`), LM Studio (`/v1/models`), or a custom address with an optional key. |

Keys live in the Keychain, one account per preset (`ProviderPreset.keyAccount`), each bound to its
host (`ProviderKeys`); a key saved before presets existed still works for the host it was saved for.
Model lists come from the provider (`GET /models`, free) and Gemini's "models/…" ids are used without
the prefix; the first suggestion the provider actually offers becomes the default, and each
provider keeps its own model when the user switches (`ProviderSettings.switchProvider`).

Each provider has a main model and an optional smart one for "Think harder" (D8).

## Voice (D34)

Push-to-talk in, one short spoken line out. Everything that can be tested without audio hardware is in
core; the app holds the audio and speech frameworks.

- **Core** (`Sources/SidefolkCore/Voice/`): `VoiceSettings` (in `AppSettings.voice`); `VoicePolicy`
  (which transcripts are sent, when a reply is spoken, muted or handed to VoiceOver); `SpokenLine`
  (the one breath said for an answer, a card or a list: no URLs, paths or code); `Sentences` and
  `SentenceBuffer` (NLTokenizer); `SpeechOutput`, the protocol every voice engine implements (text in,
  `VoiceAudio` pieces out); `SpeechPlayer`, the playback queue over an `AudioSink` (sentence by
  sentence, instant `stop()`, levels for the mouth); `ElevenLabs` (voices, models, streamed PCM).
- **App** (`Sources/SidefolkApp/Voice/`): `VoiceController` runs a turn: the talk key or a held
  companion → `MicrophoneCapture` (AVAudioEngine tap, built-in microphone preferred, rebuilt on
  hardware changes) → a `SpeechRecognizer` (`AnalyzerRecognizer` on macOS 26+, `BasicRecognizer`
  before) whose partial words fill the Ask box → release → `AskModel.submit(spoken:)`, the normal
  pipeline. Replies come back through `VoiceController.reply`, which applies `VoicePolicy` and plays
  through `AudioPlayer` (an `AudioSink`) with `AppleVoice` or `ElevenLabsVoice`. The companion's pose
  follows `CompanionMood.hearing`/`transcribing`, its mouth the player's levels.
- **Dev paths** (debug builds): `SidefolkApp --voice-transcribe <audio file>` runs a file through the
  same recognizer and conversion as the microphone and prints what releasing would send;
  `--voice-say "<answer>" <out.caf>` writes the spoken line to a file through the real queue;
  `--voice-install <language>` downloads a language's model; `swift scripts/dev.swift voice:file:<path>`
  plays a file into a running debug app as if the talk key were held.

## Extension protocol (summary; full guide in docs/EXTENSIONS.md)

Folder with `sidefolk-extension.json`:
```json
{ "id": "dev.sidefolk.system-vitals", "name": "System Vitals", "version": "1.0.0",
  "sidefolk": ">=0.1", "folk": "byte", "description": "...",
  "run": { "command": "python3", "args": ["main.py"] },
  "permissions": { "network": false, "files": { "read": [], "write": [] }, "exec": ["/usr/bin/pmset"] },
  "tools": { "battery": { "risk": "low", "category": "system" } },
  "watchers": { "battery_low": { "title": "Battery low", "config": { ... } } } }
```
The process speaks MCP over stdio. Tool metadata (risk/category) comes from the manifest; tools
not described there default to `medium`. Watchers are checked with `sidefolk/watch.check`
`{watcher, config, state}` → `{triggered, state, summary}`. The host runs the process under
`sandbox-exec` with a profile derived from `permissions` (deny network unless granted, writes only
to its data dir unless granted, exec allow-list). MCP servers added by command run unsandboxed and
are labelled so; their tools are medium risk until the user grants more.

## Build and release

- `make dev` / `scripts/run.sh` — debug build, assemble `build/Sidefolk-dev.app`, launch with
  `SIDEFOLK_HOME` pointing at `build/dev-home`.
- `make test` — `swift test`.
- `make app` — release build, `build/Sidefolk.app`, ad-hoc signed.
- `scripts/release.sh` — sign with Developer ID (hardened runtime, entitlements), DMG, notarize,
  staple. Fails clearly when `SIDEFOLK_SIGN_IDENTITY` / `SIDEFOLK_NOTARY_PROFILE` are missing.
