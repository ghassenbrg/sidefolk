# Decisions

Major choices, newest last. Each says what we decided, why, what else we considered and what it
implies. "Founding chat" = the ChatGPT brainstorm that seeded the project (docs/FOUNDING.md).

### D1 — Native Swift app instead of Tauri/web (2026-10-26)
**Decision:** Swift 6 (AppKit shell, SwiftUI views, Core Animation character), SwiftPM, macOS 15+.
**Why:** an always-visible companion must cost ~0% CPU idle; Core Animation animations run in the
render server, while the legacy WebKit overlay needed extensive work to get to a few percent.
Native panels give correct focus/Spaces/fullscreen behaviour, Keychain, notifications, login item.
**Alternatives:** Tauri + WebGL (legacy), Electron, SwiftUI-only animation (per-frame CPU).
**Implications:** no Windows/Linux; UI work happens in Swift.

### D2 — Vector character rig on Core Animation, not sprites or 3D (2026-10-26)
**Decision:** the approved character is rebuilt as layered vector shapes (gradients, shadows as
glow) with pose-to-pose spring transitions and morphing eyes.
**Why:** smooth state transitions instead of swapping GIFs, crisp at every size, reduced-motion
friendly, extension folks are data, near-zero idle CPU. AI image generation cannot produce
consistent animation frames; a Blender pipeline is slower to iterate.
**Implications:** the look approximates the soft-3D renders; a pre-rendered body is a later upgrade path.

### D3 — The robot keeps the name "Sidefolk"; Pip is the coral folk (2026-10-26)
**Why:** the founder's approved identity sheet labels the main character "Sidefolk" and Pip as the
Ideas & Notes folk. The legacy app (where Pip was the main character) was intentionally wiped.
The name is editable in Settings; onboarding does not ask for it.

### D4 — Plain-language understanding is local first; AI is for what needs reasoning (2026-10-26)
**Decision:** a deterministic intent parser understands reminders, notes, watches, quiet mode and
search in plain language ("remind me in 20 min to call mom") and completes them in milliseconds
without a model. The input shows a hint line saying what Enter will do and whether it uses AI.
**Why:** founding chat ("remind me at 5 → no LLM needed"), cost (users spend quota by accident),
speed (CLI brains take seconds to start), offline use. **Alternatives:** slash commands only
(too rigid), everything through the model (slow, costly).

### D5 — The Ask panel shows results, not a transcript (2026-10-26)
**Decision:** every request ends in a card (saved note, reminder, watch, answer, approval). Short
history is kept for follow-ups (10-minute thread window) but not displayed as a chat log.
**Why:** product review: a transcript makes Sidefolk "a chat app with a mascot".

### D6 — Memories fold into the Notebook as "About you" (2026-10-26)
**Decision:** no separate memory store. Durable facts/preferences are notes in a pinned profile
collection that is always offered to the model (within budget).
**Why:** users cannot tell a memory from a note; one visible, editable place builds trust.
**Alternatives:** separate memory table (founding chat's taxonomy), vector memory.

### D7 — No vector database in V1 (2026-10-26)
**Decision:** SQLite FTS5 (porter stemming, bm25) plus recency and collection scoping feed a
budgeted context package. **Why:** small personal corpora, explainable retrieval, no model needed
to index. Embeddings are a post-V1 option behind the same retrieval interface.

### D8 — Brains: Claude Code CLI, Anthropic API, OpenAI-compatible; one model + "Think harder" (2026-10-26)
**Decision:** the Claude Code CLI can be the brain using the user's subscription, launched with
`--tools ""` (no built-in tools), an isolated working folder and settings, and only Sidefolk tools
via the local MCP bridge, so every action still passes Guard. API backends share one tool loop.
Each provider has a main model and an optional "smart" model used by "Think harder".
**Why:** the founder has Claude Code; API keys are optional. The founding chat's automatic
multi-tier router is replaced by a simpler, explainable rule. Apple's on-device model was
`modelNotReady` on the dev machine, so it is post-V1.

### D9 — Folks are "on duty" markers, not cameos on every action (2026-10-26)
**Decision:** Tempo (reminder due within 15 min), Scout (watchers active) and Byte (agent session
or job running) sit beside the companion while their job is live, at most three, and never speak.
Guard appears as the badge on approval cards. In the Home window each domain uses its folk as
accent. **Why:** cameos on every action duplicate the robot's props and become noise.

### D10 — Presence modes (2026-10-26)
Always / Only when needed (a small peek until something needs you) / Menu bar only. The first
complaint about a desktop companion is "it's always there".

### D11 — Hotkey ⌘⇧Space (2026-10-26)
⌥Space (founding chat) is taken by Raycast/Alfred/ChatGPT on many machines.

### D12 — Agents can reach Sidefolk: MCP bridge, `sidefolk run`, Claude Code hooks (2026-10-26)
**Decision:** `sidefolk mcp` exposes notes, reminders, watches, notify and ask to any MCP client;
`sidefolk run -- <cmd>` runs a command and tells you when it ends (nobody knows PIDs); optional
Claude Code hooks (installed only on the user's click, with a backup) let the companion notice
when a session needs you or finished. **Why:** the founding chat's strongest differentiator
("watch this Codex session, tell me when it needs me") and the main daily use for the founder.

### D13 — Extensions are MCP-speaking executables with a Sidefolk manifest (2026-10-26)
**Decision:** an extension = folder + `sidefolk-extension.json` (permissions, tool risk, watchers,
folk) + an executable speaking MCP over stdio, run under a `sandbox-exec` profile generated from
its permissions. Plain MCP servers can be added too; they run unsandboxed, clearly labelled, and
their tools default to medium risk. **Why:** reuse the MCP ecosystem instead of inventing an RPC
protocol, yet keep manifests, permissions and failure isolation that the product requires.
**Alternatives:** MCP only (no permission model), in-process plugins (no isolation), JavaScript
runtime (heavy). `sandbox-exec` is deprecated but is what Claude Code and Codex use on macOS.

### D14 — Guard is deterministic and outside the model (2026-10-26)
Risk levels, caller trust, taint from untrusted content, folder grants, protected paths, exact-
command grants for shell, approvals answered only by the user. Founding chat's "the AI should
never decide its own permission" taken literally.

### D15 — No auto-update in V1 (2026-10-26)
Sparkle needs a signing identity, EdDSA keys and a hosted feed, none of which exist yet. Shipping a
"Check for updates" that cannot work would be a fake feature. Data migrations are versioned so a
later update path is safe.

### D16 — Agent integrations edit the config files directly, with confirmation and backup (2026-10-26)
**Decision:** connecting Claude Code / Codex edits `~/.claude.json`, `~/.claude/settings.json` and
`~/.codex/config.toml` directly (ordered JSON / TOML section edit, timestamped backup beside the file,
atomic replace, exact removal) instead of shelling out to `claude mcp add`. Only on the user's click,
after a dialog that lists every change and the backup path.
**Why:** predictable and testable, no CLI on PATH needed, same backup/removal semantics everywhere.

### D17 — Proprietary license until the founder decides (2026-10-26)
**Decision:** LICENSE reserves all rights. Dependencies (GRDB, KeyboardShortcuts) are MIT and listed in
THIRD_PARTY_NOTICES.md (bundled in the app). Choosing an open-source license later is a one-file change;
choosing one tonight would be irreversible for the founder.

### D18 — Test suite runs serially by default (2026-10-26)
**Decision:** `make test` and `release.sh` use `swift test --no-parallel` (~25 s). Under parallel
execution a few process-spawning integration tests occasionally fail because freshly written fixture
executables stall at launch under heavy contention; serial runs are reliable. Production spawning was
hardened anyway (spawn lock, close-on-exec pipes, ETXTBSY retry, probe retry).

### D19 — Extension watchers run through one "extension" probe kind (2026-10-26)
**Decision:** the watcher engine knows one generic kind that calls an extension's `sidefolk/watch.check`;
`watch.extension` (medium risk) starts them, validated against the manifest's config fields, never louder
than "attention". The agent sees available extension watchers in its context.

### D20 — The companion settles when nothing is happening (2026-10-26)
**Decision:** idle, listening and sleeping breathe for 20 s after any change, then hold still (blinks
continue); busy states keep moving. Loops are capped at ~24 fps, the body layer is rasterized, and
all loops pause while the window is hidden or covered.
**Why:** the performance review measured the endless breathing loop costing ~43% of a core in
WindowServer on a 120 Hz display (app CPU itself was 0.08%). Motion is information; constant motion
is noise and battery.

### D21 — Local addresses can be watched when the user asks (2026-10-26)
**Decision:** `watch.create` from the user's own request (`Caller.user`, untainted) may target
localhost, LAN and `.local` hosts ("tell me when localhost:3000 is up"). Agents, external clients,
extensions and tainted turns are still refused (SECURITY T11), with a message that says to ask
directly. **Why:** the developer persona's main watch target is a local server; the SSRF guard is
about model-built URLs, not the user's own words.

### D22 — Agents' questions are answered in the Ask panel; bubbles keep their buttons (2026-10-26)
**Decision:** Sidefolk's own agent (and external questions without options) asks inside the Ask panel,
where the user can pick an option or type an answer; `ask.user` accepts free-text answers. Bubbles
never lose their action buttons when they shrink, and questions never shrink. **Why:** the UX review
found unanswerable collapsed bubbles and a two-minute clarification ping-pong.

### D23 — `sidefolk run` tees stderr so failures can say what went wrong (2026-10-26)
**Decision:** the helper keeps stdin and stdout the caller's own, but passes stderr through a tee: a
pseudo-terminal with the caller's terminal settings and size when stderr is a terminal (so colours and
progress bars still work; output processing is off so bytes pass untouched), a pipe otherwise. Only on a
non-zero exit do the last three lines, cleaned of escape codes, go to the app. They are shown to the
user and never given to a model. **Why:** "npm test failed (exit 1)" is not actionable; the last
error line usually is. **Trade-off:** something the command leaves running in the background loses its
stderr when `sidefolk run` returns (it waits half a second for it).

### D24 — Extension tool descriptions never reach the model (2026-10-26)
**Decision:** the model sees an extension tool as a neutral line (its title, which extension, its risk)
and an input schema with free text removed, not the author's description. **Why:** a description is
text written by a third party and loaded into every run; tainting every run instead would make every
link and memory write ask for approval. Tool names and titles (60 characters at most) remain a small
residual channel (SECURITY T2).

### D25 — Reference-faithful production brand assets (2026-10-26)
**Decision:** use standalone transparent artwork reconstructed from the founder's Folk Family
reference for static logos and the macOS app icon. Reconstruct the flat wordmark as hand-authored
Bézier outlines following the reference, with navy/aqua fills and no generated text effects.
Export a complete ICNS/iconset and native 18 pt vector menu bar template; bundle production exports
and load them through `BrandAsset`. The menu template simplifies the companion's shell/visor/smile
for small sizes and lets macOS tint its alpha. The live vector rig remains as specified in D2.
**Why:** the identity must match the approved reference and work as real framework assets, rather
than mockups, a presentation sheet, or enlarged low-resolution crops. The deterministic
`make brand-assets` pipeline rebuilds each file from committed inputs without another model call.
**Source correction:** the reusable app-icon source is a flat, opaque square (2048/1024 px), with a
separate transparent artwork PNG. No bevel, raised tile, cast shadow or edge lighting is baked in.
Only derived legacy macOS ICNS/iconset representations get a flat inset rounded mask. An Xcode
asset catalog includes both the raw image sets and the macOS AppIcon set. The rendered-tile master
was rejected and removed.
**Wordmark correction:** reject the low-resolution contour trace. The canonical source is now
`Resources/Brand/masters/wordmark.svg`, drawn as 11 named, editable filled paths. SVG, PDF, PNG and
all logo lockups derive from that master. Color, navy and white SVGs have no embedded raster, font,
filters, transforms or clipping masks.

### D27 — Three companions to choose from; two are sprites; the robot's light colour is the only customisation (2026-10-26)
The default-appearance decision below is superseded by D29; all three choices remain available.
**Decision:** Settings › Companion offers the vector Sidefolk robot (default), Mochi and Spark, as
cards that show each one as drawn, switching live. Mochi and Spark are the founder's two earlier
characters (the legacy app's bunny "Pip" and robot "Spark"), drawn from 16 pose images each by a
`SpriteDirector` behind the same `CharacterView` contract as the robot's `Director` (state, gestures,
badges, alpha-based hit testing, anchor frame, the D20 settling rules). The bunny is offered as
**Mochi** because Pip is the coral folk in the Folk Family (D3); Spark keeps its name. A companion
named with a built-in default takes the new companion's name when switching; a name the user chose
stays. The robot's light (visor marks, ear pods, the marks drawn in that light) can be aqua, coral,
mint or light blue; nothing else is customisable.
**Why:** the founder wants a choice and a little personalisation. The two characters exist only as
pose renders, and rebuilding them as rigs would take weeks for a look the renders already have, so
sprites (crossfaded poses, alternating frames for busy states) are the honest way to offer them; the
robot stays a vector rig (D2). Sprites cost no more at rest: they settle to zero animations like the
rig. Customisation stops at a brand-palette light colour because every further knob (shell colours,
accessories, per-sprite tints) either breaks the approved identity or needs art that doesn't exist,
and each knob is a combination to keep working in every state. Pose files are measured rather than
assumed (PNG preferred over WebP, any pixel size, feet on the floor line, scale from the idle pose),
so redrawn art can replace the legacy cuts without code changes.
**Alternatives:** rigging Mochi and Spark as vectors (slow, would not look like the renders); one view
type per kind of companion (the app would juggle two); free colour pickers (off-brand); a tint for
the sprites' mint parts (the legacy recolouring; looks painted-on on 3D renders).
**Superseded by D30:** Mochi and Spark became live rigs on the robot's engine, the Folk Family joined
them, and the colour and an accessory became one style for every companion.
**Implications:** sprite companions have no effect marks or held props beyond what their poses show,
and no eye tracking (they lean toward the pointer instead). A new sprite companion is a folder of
the 16 poses plus a `CompanionChoice` case.

### D28 — Ten languages for everything people read; plain-language commands stay English (2026-10-26)
**Decision:** the interface, notices and messages ship in English, French, Spanish, German, Italian,
Portuguese (Brazil), Japanese, Korean, Chinese (Simplified) and Arabic. Sidefolk follows the Mac's
language and can be switched in Settings › General (it relaunches). Strings come from one String
Catalog (`make strings`, compiled into the app by `build-app.sh`). Text written for models (tool
results, prompts, tool descriptions) stays English. The local, no-AI understanding of typed requests
stays English in V1; with AI configured, requests work in any language, and the buttons (Save,
Remind me…, Watch) work in every language.
**Why:** a companion that lives on your desktop should speak your language; the founder asked for
it. A second rule-based parser per language would be a large, separate project (the English one is
fuzz-tested over 600k inputs), so it is deferred rather than done badly.
**Alternatives:** translate only the menus (half-translated apps feel broken); write parsers for two
languages now (high effort, uneven quality).

### D29 — Mochi becomes the brand mascot; the original robot remains a companion (2026-10-26)
**Decision:** adopt the founder's Mochi rabbit brand guide: white rabbit, navy ear tips and eyes,
mint/aqua scarf, unchanged wordmark and palette, rabbit family logos, blue app icon and a native
rabbit-ear/face/scarf menu template. Fresh settings and missing/unknown appearance values default
to Mochi. Explicit saved companion choices, custom names and robot accent colors are preserved.
The original `.sidefolk` vector robot and Spark stay selectable; the robot retains all four light
colors. Only the default and picker ordering change.
**Why:** the founder selected the rabbit as the main identity and explicitly asked to keep the
original robot. Brand identity and a person's chosen desktop appearance are distinct.
**Implementation:** all 16 existing Mochi poses receive a deterministic white/navy/scarf palette
grade from archived originals, preserving pose scale and alpha. Logos and icon portrait follow the
new guide and the founder’s close-up icon crop; monochrome and menu marks share hand-drawn native
vector geometry matching the close-up’s ears, paw, rays and separated scarf. Raw icon sources
have a simple blue-gradient square or transparent background; only separate macOS exports get a
geometric mask.

### D30 — Every companion is a live rig on one engine; thirteen to choose from; one style for all (2026-10-26)
**Decision:** Mochi, Spark and the ten folks are vector rigs on the robot's engine: `Director` drives
a `Figure` (the robot's own `RobotRig`, or a `SoftRig` built from a `Species` description), so every
companion has every state, gesture, prop, blink, gaze, the D20 settling, the frame cap, the occlusion
pause, reduced motion and silhouette hit testing. Mochi follows the brand mascot (white body, navy
bead eyes and ear tips, ears that droop, perk, trail and sway); Spark follows its concept render;
each folk is exactly twice its on-duty self with its personality at idle and its signature pieces
(glasses, headphones, cap, beret, bowler, sprout worn; magnifier, calendar, controller, shield,
brush, cup held at idle and put away when a state needs the hands). Settings › Companion is a
chooser: the chosen companion live with states to try, its name, colour and what it wears, over a
gallery of every companion with its role. Every companion takes the same `CharacterStyle`: a brand
colour (aqua, coral, mint, light blue) and an accessory (none, or a knitted scarf fitted to each
body); the colour paints what it wears and the robot's light and Spark's gear. Each companion keeps
its own style; the robot's saved light colour carries over. A folk that is the companion doesn't
stand beside itself on duty: its duty shows as the companion's badge (watching, busy) instead, and
it is not introduced as a newcomer.
**Why:** the founder asked for the new companions to work like the robot ("the main one we did and
it's well done"), and for every folk to be choosable with the same customisation. Pose pictures
could not hold props, follow the pointer, morph expressions or move ears, and the redrawn sprites
still read as stickers next to the rig. One engine with data-described bodies keeps thirteen
companions at one quality bar with one set of tests, and new ones are a `Species` away. The style
stops at a colour and a scarf: they suit every body and the brand (Mochi's scarf), while hats and
glasses clash with ears, fins, antennae and screens on some of them.
**Alternatives:** keep sprites for Mochi and Spark (D27; no props, no gaze, stiff); one rig class per
companion (thirteen copies of the same motion code); per-companion extras (later, if wanted).
**Implications:** the sprite engine, pose art and its scripts are gone. `CharacterSpecies.available`
gates what is offered. Folks' faces and accessories match the on-duty folks, which stay the
`FolkRig` drawings (shared through `FolkKit`).
