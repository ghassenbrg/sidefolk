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
*Amended by D51 and D59:* companions also come in 3D (three.js), and their 2D forms are painted.
**Decision:** the approved character is rebuilt as layered vector shapes (gradients, shadows as
glow) with pose-to-pose spring transitions and morphing eyes.
**Why:** smooth state transitions instead of swapping GIFs, crisp at every size, reduced-motion
friendly, extension folks are data, near-zero idle CPU. AI image generation cannot produce
consistent animation frames; a Blender pipeline is slower to iterate.
**Implications:** the look approximates the soft-3D renders; a pre-rendered body is a later upgrade path.

### D3 — The robot keeps the name "Sidefolk"; Pip is the coral folk (2026-10-26)
*Superseded by D56:* the robot is retired as a companion.
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
*Amended by D45 and D84:* Ask is now the Sidecard's largest size; kept conversations are in History.
**Decision:** every request ends in a card (saved note, reminder, watch, answer, approval). Short
history is kept for follow-ups (10-minute thread window) but not displayed as a chat log.
**Why:** product review: a transcript makes Sidefolk "a chat app with a mascot".
**Amended 2026-10-27:** the cards behave like notifications, not like a two-card window: all of them
(the last 40 entries) stay reachable by scrolling, newest first; two fingers sideways slide one away,
"Clear all" empties them, and notices that need nothing ("Undone", a word about talking) fade after
20 seconds unless the pointer is on the panel. *Why:* the founder lost older results with no way to
see or clear them, and the per-card X was too small to hit.
**Amended 2026-10-28 (D45):** an answer can be read in full, followed up in its own conversation and found again
in Home › Conversations; the panel itself still shows results, not a transcript.

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
`modelNotReady` on the dev machine, so it is post-V1. D26 adds Codex and provider presets.

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
**Amended (2026-11-01):** "needs you" is only a real prompt (a permission, a question). Claude Code's "waiting for
your input" means finished. A finished session is a gentle notice, never in Needs you: one per session, replaced by the
next and withdrawn when the session works again. The founder's long session, resumed by its own background
teammates, stopped dozens of times and each stop sat in Needs you with an Open button and nothing to answer.

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
*Superseded by D46 and D70:* Sidefolk updates itself from GitHub Releases.
Sparkle needs a signing identity, EdDSA keys and a hosted feed, none of which exist yet. Shipping a
"Check for updates" that cannot work would be a fake feature. Data migrations are versioned so a
later update path is safe.
**Replaced 2026-10-28 by D46:** releases are now signed, notarized and checksummed, which is all an updater needs.

### D16 — Agent integrations edit the config files directly, with confirmation and backup (2026-10-26)
**Decision:** connecting Claude Code / Codex edits `~/.claude.json`, `~/.claude/settings.json` and
`~/.codex/config.toml` directly (ordered JSON / TOML section edit, timestamped backup beside the file,
atomic replace, exact removal) instead of shelling out to `claude mcp add`. Only on the user's click,
after a dialog that lists every change and the backup path.
**Why:** predictable and testable, no CLI on PATH needed, same backup/removal semantics everywhere.
*Amended by D86:* only the copy on the person's own data folder edits these files; any other `SIDEFOLK_HOME`
edits stand-ins inside itself.

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
*Amended by D84:* questions are Sidecard cards and permission slips; firm ones never take Return.
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

### D26 — Every main provider, chosen by how you pay; Codex isolated like Claude Code (2026-10-26)
**Decision:** add Codex (`codex exec`) as a brain on the user's ChatGPT plan, beside Claude Code,
and keep one OpenAI-compatible transport with presets: OpenAI, Google Gemini (its OpenAI-compatible
endpoint), Mistral, Groq, xAI, DeepSeek, OpenRouter, Ollama, LM Studio and a custom address. Each
preset knows its address, whether a key is needed, where to get one, and how to list models; its
key has its own Keychain account bound to its host. Settings › AI groups the choices by how you pay
(a plan you already have, an API key, this Mac, your own server, no AI), shows each one's state
(found, signed in, key saved, running) and the exact next step (a link, or a command to copy), and
opens the chosen one's setup in place. Model lists come from the provider; the first suggested
model it actually offers becomes the default. Each provider keeps its own model when you switch.
"Test" sends one tiny real request through the same path as a question.
**Why:** the founder pays for ChatGPT and uses Codex, and wants setup easy for everyone. Presets
remove the base-URL guesswork that caused the Gemini bug ("models/…" ids, array-wrapped errors)
without a second transport. Model names go stale, so suggestions are checked against the
provider's own list rather than hard-coded as the only choice. A free `/models` lookup isn't a test:
only a real request proves a question will work.
**Why the CLIs are isolated this way:** a subscription CLI is a general coding agent with a shell,
file edits, a browser and plugins, running as the user; Sidefolk's brain must only act through
Sidefolk's tools so Guard sees every action (D14). Claude Code reports its tools at start, so the
run is checked there. Codex doesn't, so every Codex feature that's on by default is switched off
except the plumbing the brain needs (later features included), its config, rules and folder
instructions are ignored, it runs read-only with approvals off in a private folder, and the event
stream is watched: anything that isn't a message or a Sidefolk tool call stops the run, and what
the switches should have prevented also disables the backend until restart (SECURITY T7).
**Alternatives:** Codex through its app-server protocol (more surface, same tools to switch off);
a separate `CODEX_HOME` (loses the user's sign-in); one Keychain account for every
OpenAI-compatible service (each switch would need the key again); hard-coded model lists.
**Implications:** Codex adds the user's own global `AGENTS.md` and keeps `apply_patch` offered to
its own models; neither can act (read-only sandbox, approvals off, events watched) but they're
documented residuals. New Codex versions are probed (flags and feature names) before use.

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
*Superseded by D56* for the robot, which is no longer a companion.
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

*Amended 2026-10-29 (approved 3D app icon):* the founder approved the smiling Mochi portrait
with navy ear tips and a turquoise scarf on midnight blue. `masters/mochi-app-icon.png` is its
opaque, full-bleed square master, prepared from the approved preview with the built-in image tool
to remove the white surround and rounded tile. `brand-assets.swift` derives the square sources
and the legacy macOS mask/iconset/ICNS from it; the transparent logo mark remains a separate asset.
The icon's 3D character lighting is intentional; no tile rim, bevel or shadow is baked into the source.

### D30 — Every companion is a live rig on one engine; thirteen to choose from; one style for all (2026-10-26)
*Amended by D54 and D56:* the folks are helpers only and the robot is retired; D51 and D55 changed the list.
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

### D31 — The wordmark is built from strokes and calibrated against the founder's lettering (2026-10-26)
**Decision:** the "Sidefolk" wordmark matches `Resources/Brand/reference/wordmark-reference.png`.
`scripts/wordmark.swift` constructs every letter as the lettering is drawn: round-capped strokes of one
stem weight, rings for the d and o, a round dot for the i, two lighter rays; the S and e are a main
stroke plus a same-width stroke that branches off tangentially and rejoins it, which gives the counters
round ends and the curves their weight without seams. Core Graphics outlines and merges the strokes
into one path per letter; the numbers were calibrated by fitting the construction's coverage to the
reference (S 97.8 %, other letters 96–98 %, the rays 92 % because they are thin and the reference is
soft). `--check` writes the overlay and difference (`Resources/Brand/wordmark-fit.png`). Every
wordmark and logo export is regenerated from this master.
**Why:** the founder found the previous hand-authored outlines wrong ("the S is weird") and an earlier
trace wobbly. Building from strokes keeps the shapes geometric and consistent (all stems one weight),
and measuring against the reference makes "like this" checkable instead of a matter of taste.
**Alternatives:** tracing the reference (wobbly, inherits its blur); hand-drawn Bézier outlines (what
drifted); a variable-width brush stroke for the S (smooth, but its fit was worse and its counters came
out pointed); unioning untangent turn arcs (round counters, but small notches where edges crossed).

### D32 — The menu bar shows a reduced Mochi glyph, not the shrunk monochrome mark (2026-10-26)
**Decision:** the 18 pt template is its own drawing (`MochiMenuGlyph`): a 1.5 pt outline of Mochi's
head and ears, the ear tips filled (the brand's navy tips), two wide-set eyes and the nose, with the
eyes and nose on whole pixels at 2x. One alpha shape, `isTemplate`, so macOS tints it on any bar. The
large monochrome mark (rays, paw, scarf) stays for lockups and print, where its detail reads.
**Why:** the founder found the old template "not the best": shrinking the full mark to 18 pt put
rays, a paw, a scarf and an outline in 36 pixels, which read as noise beside system glyphs. Six
candidates were drawn at real size beside wifi, battery and search on light and dark bars, at 1x and
2x (`Resources/Brand/menu-bar-candidates.png`). Solid silhouettes were bolder than every system glyph
and merged the ears; a plain outline read as any bunny; adding the scarf crowded the 1x pixels. The
filled ear tips plus the nose are the two details that say Mochi at this size, and the outline matches
the weight of the symbols around it.

### D33 — Where the brand appears in the app, and in which variant (2026-10-26)
**Decision:** the full-colour art is the hero and appears where it has room; the lettering keeps its
two colours on every surface. Specifically:
- **Home sidebar:** the wordmark alone at 30 pt (navy "Side" + aqua "folk" on light, the new
  `wordmark-reversed` with white "Side" on dark); clicking it opens About. It replaces a 30 pt cropped
  portrait beside 17 pt lettering, which read as a sticker.
- **Now:** a greeting card on a quiet aqua-to-blue wash with *your* companion, drawn by its rig in its
  style at 176 pt, and an "Ask <name>…" button. The mascot is shown where it is large, not shrunk.
- **About window** (app menu, menu bar menu, sidebar wordmark): the family art and the wordmark,
  version, tagline, notices. It replaces the standard panel, which could only show the icon.
- **First hello bubble:** the family art (`family-color`), as the bubble's code always meant.
- **Ask panel:** the companion's face in a small disc beside its name, so you see who you're asking.
- **Empty pages:** your companion with its notepad in an empty collection; folks where their job is
  the subject (Scout for search, Seed for About you, Guard for Activity, Brew for Trash).
- **Menu bar:** the monochrome glyph (D32). **Settings:** no brand header; macOS Settings windows
  carry their identity in the toolbar, and About is a click away.
Single-colour wordmarks and lockups (navy, white) stay for print and partners; the app never shows
all-white or all-navy lettering, because the aqua "folk" is half of the name's look. Wordmarks load
from the vector PDF exports, so they stay sharp at any size without a 4096 px bitmap in memory.
**Why:** the founder found the logo "a little bit small" and asked for the companion, the folks and
the logo to be used to make the app warmer. Each placement is where the art has room to be itself;
small places get one clear element (lettering, a face) instead of a reduced composition.

### D34 — Voice: hold to talk, recognized on this Mac, answered in one short line (2026-10-26)
**Decision:** Phase 1 of docs/research/voice-feasibility.md, with its suggested defaults.
- **Talk key: hold the Ask shortcut.** A tap still opens and closes the Ask panel; held for 0.3 s it
  talks, and releasing sends. Settings › Voice can give talking a shortcut of its own instead (no
  default), which opens the microphone the moment it goes down. Pressing and holding the companion
  (0.35 s) also talks. *Why:* one shortcut to learn, voice is a way of asking, and a second global
  shortcut is a second clash nobody can detect (MACOS-NOTES). The price is the hold: the microphone
  opens 0.3 s after the press, and a three-key chord is held while talking; people who mind either
  give talking its own shortcut. The companion's ears go up when the microphone is really on.
- **Off by default.** Nothing asks for the microphone until the person turns voice input on and
  holds the key. The microphone is open only while the key is held (the orange dot is honest), it
  is the input chosen in System Settings › Sound, and the capture is rebuilt when the audio hardware
  changes or sends nothing for a second. (Preferring the Mac's own microphone kept AirPods out of
  call quality, but pointing the engine's audio unit at it by hand left build 404 with no audio at all.) Audio is never stored; the words join history as text, marked spoken.
- **Recognition on this Mac.** SpeechAnalyzer with SpeechTranscriber on macOS 26+, DictationTranscriber
  for languages it lacks (Arabic, here), the language's model downloaded by macOS with progress
  (Settings › Voice, or the first press); on macOS 15 the older recognizer forced on device, labelled
  "basic". It listens in the app's language unless one is pinned; the locale is picked by Sidefolk
  (installed first, the Mac's region, then the language's home), because Apple's own equivalence
  mapped "en" to en-ZA. Measured on the dev Mac (macOS 27.0.1): SpeechAnalyzer needs no
  speech-recognition permission (only the microphone's), the last words arrive 0.02–0.06 s after
  release, 45 locales are offered, and French's model downloaded in 16 s.
- **Release sends** through the normal Ask pipeline: local parser or AI, same cards, approvals and
  Undo. An empty or one-filler transcript ("um") sends nothing: a sad face, "I didn't catch that",
  and the words left in the box to fix.
- **Spoken replies:** Off, Only when I spoke (default) or Always; one short line, always shown in the
  panel too (with a muted speaker when it stayed silent). Silent in quiet mode, while another app
  records, when the person typed since asking; with VoiceOver on, the line goes to VoiceOver instead.
  The talk key, a click on the companion and Esc stop the audio at once, drop the queue and cancel
  the run of a spoken request still working, so no stale answer turns up.
- **The line for an AI answer is its first sentence**, made speakable (links become their site, paths
  their last name, code goes; nothing left → "It's on the screen."), cut at a pause past 24 words;
  a list says how many and the first. A spoken request adds one paragraph to the prompt asking for a
  first sentence that stands alone. *Why not a separate spoken field in the answer format:* every
  brain would have to follow it, CLI brains included, whose output Sidefolk doesn't parse; a field a
  model forgets or mangles leaks into the card; it costs tokens on every answer. The first sentence
  works with every brain and is already what the persona asks to lead with.
- **Engines behind one `SpeechOutput` protocol** (text in, audio out in pieces) and one playback
  queue (`SpeechPlayer`: sentence splitting, the next sentence made while one plays, instant stop).
  Apple: AVSpeechSynthesizer written into Sidefolk's own player (so its loudness drives the mouth),
  the best enhanced or premium voice installed, else the one macOS uses for the language, with a
  button to System Settings where better voices are downloaded. ElevenLabs: the person's key in the
  Keychain, bound to api.elevenlabs.io, streamed 24 kHz PCM, never redirected, models tried in order
  (Eleven v4 Turbo, Flash v2.5, Multilingual v2), a plain statement of what is sent, and "Test voice"
  saying it costs about 50 characters. Each line's voice follows the line's own language.
- **Kokoro is left out.** FluidAudio 0.17.7 builds cleanly in this package and its legacy Kokoro
  runtime ran offline (83 MB model, 71 ms for 2.4 s of speech), but it fails the bar: the English
  text-to-phoneme model and lexicon always go to ~/.cache/fluidaudio, whatever folder is given, so
  they can't live under the Sidefolk home or be deleted with it; the recommended v3 runtime aborted
  the whole process on macOS 27.0.1 (an MPSGraph assertion), and in-process that takes the companion
  down; English only. Revisit when FluidAudio lets the phonemizer's folder be chosen, in a helper process.
- **The body:** a `hearing` state (both ears up, eyes wide, the waves) driven by the same code that
  opens the microphone, thinking while the last words settle, the error face for a miss, and a
  talking mouth on every companion (`Figure.talk`): an "o" whose height follows the playback level
  (about 20 updates a second, quantized), each a short ease; nothing repeats, so it stops with the audio.
**Alternatives:** a dedicated talk shortcut by default (a second clash, no default anyone agrees on);
a spoken field in the answer format (above); Kokoro (above); cloud transcription (no reason to send
voices off the Mac for short commands); wake word and always-on listening (the study's "do not build").
**Implications:** the microphone usage string and the hardened runtime's audio-input entitlement;
the speech-recognition usage string for macOS 15; microphone permission resets with ad-hoc builds,
so testers need the Apple Development or Developer ID signature.
**Amended (2026-11-01, the founder heard nothing in Japanese):** "while another app records" means an app recording
(a call, a voice memo, a screen recording with sound), not macOS's own background listeners. Siri's voice trigger
(corespeechd, in /System/Library) runs the microphone whenever any audio plays, to hear past it; counting it muted
every reply while music, a video or a game's sounds played. The founder's session had played Playtime with sounds
on, and the game sounds' engine never stopped, so every reply after it was muted, in any language, with Apple's
voice or ElevenLabs, until the relaunch; it now lets the hardware go 3 s after its last sound. Programs in
/System/Library outside an app bundle don't count; apps (Apple's too), avconferenced (FaceTime's calls) and anything
unknown still do. Every spoken-reply decision is logged at info level without the words (`voice` › `reply speak`,
`reply muted` with `why` and who has the microphone, `reply saying` with the engine, the voice that really speaks and
its language and the output, then `reply played`, `cut off`, `made no audio` or `failed`), so the next report reads
from the log. A refused ElevenLabs model is remembered per language, and a full answer keeps its own ？！؟.

### D35 — Reports: a value told every few seconds or minutes, live and in place; reminders down to a minute (2026-10-26)
**Decision:** a watcher can be a *report* (`Watcher.Mode.report`): at every check it tells the current value
instead of waiting for a change. `watch.report` reads a system metric (CPU, memory, battery, free disk,
network: Mach host statistics, IOKit power sources, the volume's resource values and the routing table's
64-bit counters, no shell), the weather somewhere, or one value on a page or API (JSON path, simple
selector or pattern); `watch.command` with `report=true` shows a command's last output line.
- **Floors, never refusals:** metrics 5 s, command output 10 s, weather and web 60 s (HostThrottle still
  allows one request a minute per host). They are written in the tool descriptions so models pick valid
  values; a faster request is raised, and both the card ("Every 5 s is the fastest for this; I'll check
  every 5 s.") and the model's result say so. The system prompt tells every brain never to refuse for
  frequency.
- **An end:** a report stops after an hour when it reads more often than once a minute, after a day
  otherwise, unless the person gave an end ("until 6pm", "for an hour") or said "until I stop it". The card
  says when it stops; the end itself is a gentle notice with Keep going. Other agents' watchers still end
  within a day (T4), and `watch.report` is not offered to them at all.
- **Presentation:** a small pill per report above the on-duty folks ("CPU 23%", "Fukuoka 18 °C"), not the
  folk holding the value: a number with its name must be readable at a glance, several can stack (at most
  four live at once), and updating text moves nothing in the rig (no pose, no breathing restarted, D20). A
  "Live" section on Now shows the value large with Pause and Stop. While the companion is hidden the newest
  value sits beside the menu bar icon. A notification only when asked for ("notify me"), or when the
  companion is hidden and the report is slower than once a minute; one identifier per report, so the new
  value replaces the old one. "Stop telling me the CPU" and "stop the Fukuoka temperature" work without AI.
- **Built-in weather (Open-Meteo):** free, no key, no account. Without it "temperature in Fukuoka every
  minute" needs a model to geocode, read coordinates out of a JSON reply and build a forecast URL: two
  dependent requests that small models get wrong, a turn tainted by reading web content, and nothing at all
  without AI. Built in, the local parser handles it, the place is looked up once and remembered, and only
  numbers we format come back, so the result stays trusted. Units follow the Mac's region.
- **Budget:** values travel as `AppEvent.watchReading`, not `.dataChanged(.watchers)`: a reading every few
  seconds reloads no list and reads no database; it reaches the database only with the routine saves (at
  most every 5 minutes). The engine's one timer sleeps with a tolerance of a tenth of the wait, checks due
  within half a second share a wake-up, and no timer runs when nothing is live. Measured in a release build
  on the dev Mac (macOS 27, Apple silicon; companion shown, folks and pointer-following off so the mouse
  adds no noise), 330 s after a 30 s settle, process CPU time from `ps` and `top -pid` every 5 s: idle with
  no report 0.036 % of one core (0.12 s), with a CPU report every 10 s 0.042 % (0.14 s, 33 readings, so
  about 0.6 ms each); `top` showed 0.0 % in 62 of 67 samples and 0.1 % in the rest, the same as without the
  report. The database got one routine save in those 5 minutes.
- **Reminders:** `Recurrence.Frequency.minutely` (a minute is the finest step; seconds are raised to a
  minute and the answer says so; a value every few seconds is a report). The parser reads "every 30
  minutes", "every half hour" and "until 6pm"/"until friday" after a repeat. A frequent reminder's notice
  replaces its previous one and offers "Stop repeating".
**Why:** the founder asked for "the temperature in Fukuoka every 1 minute", "the CPU every 10 seconds" and
reminders more often than daily, and Sidefolk refused all three: watchers were change detectors with
floors of 5 min (pages) and 1 min (commands), and recurrence stopped at hours.
**Alternatives:** lowering the change-detector floors (still silent when nothing changes, and a page every
10 s is abusive); a bubble per reading (a bubble every 10 s is spam, and each is a database row); the folk
holding the value (illegible at folk size, and it would animate the rig); only a generic web value for the
weather (fragile and impossible without AI).

*Amended 2026-10-28 (one reading):* a value asked for once is one reading, not a report. `watch.read` runs the probe
once on a watcher that is never added: nothing keeps running and nothing is saved; CPU and network are measured
over a fresh half second. The parser answers plain questions with no interval this way, without AI ("what's my CPU
usage", "how full is my disk", "temperature in Fukuoka", "what's the weather": the person's place, or the "Which
place?" card); words about repeats or later leave it alone. A place named without "in" must sit right before the
weather word, so "a joke about the weather every minute" names no place. *Why:* the founder saw "what's my CPU?"
start a report and stop it, because no tool read a value once.

### D36 — Reasoning effort per model slot, only where accepted; services shown by their own logos (2026-10-26)
**Decision:** each provider's everyday and "Think harder" model has its own reasoning effort, stored
in `ProviderSettings.effort`/`smartEffort` and remembered per provider with its models. "Default"
sends nothing. `EffortSupport` lists the levels a provider and model take, and it is both what
Settings offers and the only thing ever sent: Claude Code's `--effort` levels as its `--help` lists
them (a full model id also limited to what that model takes); Codex's levels per model from its
bundled catalog (`codex debug models --bundled`, read in the probe), sent as `-c
model_reasoning_effort`; the Anthropic API's `output_config.effort` (Opus 4.5 low–high, 4.6 adds
max, 4.7 and later all five; Sonnet/Haiku 4.5 and older none); `reasoning_effort` for OpenAI, Gemini,
Mistral, Groq and xAI by documented model family; OpenRouter's `reasoning.effort` for any model but
its routers. Ollama, LM Studio, DeepSeek and custom servers get no control. A saved level the
current model doesn't take shows as Default and isn't sent, but is kept. Thinking itself keeps each
model's default (Anthropic: no `thinking` field). Extra high and Max raise the API loop's output
allowance to 16k, as "Think harder" does. "Think harder" on Codex starts at High, which it always
sent.
Services show their own logo as vector PDFs (see the logo addendum below, which replaced the first
choice of Simple Icons, black-only marks and monograms). Credits and trademark note in
`Resources/Brand/third-party/README.md`.
**Why:** the founder runs Codex at different efforts per model (gpt-6-luna at extra high, gpt-6.1-sol
at high) and asked for logos so the services are recognisable. Offering a level a model rejects
would turn a setting into a failed request; offering nothing where support is unknown is honest.
**Alternatives:** one effort for both slots (can't express the founder's setup); every level for
every provider (requests that fail); Codex's "ultra" (it delegates to sub-agents, which the isolated
brain switches off, D26); enabling Anthropic thinking explicitly (changes models whose default is
off); Sidefolk drawing its own logos for OpenAI, Groq and xAI (imitations of trademarks).
**Implications:** the per-family tables go stale as providers ship models; a model Sidefolk can't
place shows no control until the table learns it. The CLIs tell Sidefolk themselves, so they stay
current. Logos load from resources: dev builds see them with `SIDEFOLK_RESOURCES`.
**Addendum, logos (2026-10-26):** the founder wanted every brand's real, recognisable mark, and Simple
Icons has none for OpenAI, Codex, Groq or xAI (and draws Claude Code as the terminal mascot, not Claude).
So the logos now come from LobeHub Icons (`@lobehub/icons-static-svg` 1.101.0, MIT, kept as downloaded):
Claude's starburst for Claude Code and for the Anthropic API row (it sells Claude models, and
Anthropic's letter A would read as another service), OpenAI's knot, Codex's own cloud-and-prompt mark,
Gemini's gradient sparkle, DeepSeek's whale, Mistral's stripes, Ollama's llama, and LM Studio, Groq, xAI
and OpenRouter in black or white (OpenRouter's own Ink and Cloud). Marks the owner draws in colour keep
every colour. Marks that are black or white by design are templates tinted pure black or white, not
the navy ink, which would be a recolouring. All sit on a neutral plate (`Theme.logoPlate`), so the old
objection to colour logos, that they clash with the folk-colour tiles, is gone with the tiles. The
script now writes the PDFs itself: CoreSVG bends arcs written with run-together flags, drops opacity
on `currentColor`, and a PDF context drops a gradient's alpha (Gemini). MIT covers LobeHub's drawings,
not the owners' trademarks; the README records each brand's rules and what isn't verified (Anthropic
says use is limited to what it permits; OpenAI's and xAI's pages couldn't be read).

### D37 — Approval modes, and no task left waiting on a question (2026-10-26)
*Amended by D185: Full access asks for nothing but a skill's text, after outside content too, and works in any unprotected folder of the home; Auto, after outside content, runs what can't carry data out. Invariants 1 and 2 below, and the Full access alternative on the folder list, are as D185 says.*
**Decision:** Settings › Privacy & Permissions starts with how much Sidefolk asks before its own agent
acts, one choice with a line each:
- **Ask every time** (was "Cautious"): every medium and high action asks; "Always allow" is ignored.
- **Ask once per kind** (was "Standard", still the default): as before, grants honoured.
- **Auto:** medium-risk actions in a clean turn run without a card. High risk, and anything in a turn
  that read outside content (a web page, file, the clipboard, a drop, an extension's or MCP server's
  output: the T2 taint), ask exactly as before.
- **Full access:** everything runs without a card except, in a tainted turn, what could carry data out
  (list below). It is turned on only through a sheet that says what it means; the menu bar's
  "Full access…" opens that sheet in Settings.

And "If I don't answer", for the cards Sidefolk's own agent waits on: **keep waiting** (a day at most,
then the task stops), **skip that step and continue after N minutes** (the default, 10 minutes), or
**stop the task after N minutes** (2, 5, 10, 30 or 60).

**Invariants, in every mode** (`ModeMatrixTests`, `UnansweredTests`, `PolicyStorageTests`):
1. *Off stays off, protected stays protected.* Capabilities switched off and forbidden locations
   (T10) are denied before the mode is looked at. The folder list is *where* Sidefolk may work, not
   *how often* it asks: a folder outside it still gets its card in every mode (other agents and
   extensions are refused, as before).
2. *Prompt injection still needs the person.* Auto changes nothing in a tainted turn. In Full access a
   tainted turn still asks before any call that could carry what it read, or anything in the context,
   off the Mac or into later moments (`PermissionEngine.couldCarryOut`), each for a reason:
   - network or another app at an address the person didn't type: the address is where a model-built
     request carries data (T2, T11). An address the person typed runs, as it already did;
   - running a program (`shell`): a command can send anything anywhere (T9). Command watchers are
     refused outright in tainted turns anyway;
   - changing files (`files.write`): a granted folder may sync (iCloud Drive, Dropbox), and a move can
     put a private file into one (T21);
   - extension and MCP tools: they receive model-built input and may have network or run unsandboxed
     (T13, T16); the same goes for extension watchers;
   - clipboard and memory writes: pastejacking (T12) and persistent injection (T3) into later clean
     turns, where Auto and Full access would then act without asking.
   Instructions to read in full (a new skill) ask in every mode, clean turns too: they steer later
   runs (T3). What Full access does let a tainted turn do without a card is what keeps data on the Mac
   and inside Sidefolk: reading the clipboard, a skill to the Trash (undoable), and the low-risk
   actions that ran anyway.
3. *Other agents and extensions keep their own rules.* Modes only ever loosen Guard for Sidefolk's own
   agent (`Caller.agent`): runs the person started from the Ask panel, answering their own words.
   Other agents (external MCP clients) are the confused-deputy threat (T4): a hostile repo can steer
   them, their names are self-chosen, and the person's choice is about their own requests. So in every
   mode their low-risk calls run, everything else asks every time with no "Always", one card at a time,
   two minutes and then no. Extensions and routines as callers keep "Ask once per kind" rules too.
   "Ask every time" applies to every caller: asking more is always safe. Extension *tools* called by
   Sidefolk's own agent follow its mode, with the tainted-turn rule above.
4. *Everything is in Activity.* Every call is logged with its decision: new chips say **Auto**,
   **Full access** (done without asking) and **Skipped**. Activity now offers the same Undo the Ask
   panel does (15 minutes; `UndoCenter.undoableRows`). Deleting goes to the Trash; that is in the
   tools, so no mode can change it.
5. *Nothing is silent.* An action a mode answered for the person shows in the Ask panel as "done
   without asking", in a bubble when the panel is hidden, and in Activity. The mode itself is always
   visible: a chip in the Ask panel header (filled red for Full access), an Approvals submenu in the
   menu bar, whose icon turns orange in Full access with "Full access is on · Turn Off" first in its
   menu, and a banner at the top of Now.

**Never stalling:** a card Sidefolk's own agent waits on follows the setting; every other card still
waits two minutes and counts as no (T1). When the wait runs out on "skip", the model reads "Skipped:
the user didn't answer in time, so this step was skipped and nothing was done. Carry on…" and the run
goes on; on "stop" (and at the end of a day of "keep waiting") the run is cancelled and ends with "I
stopped: you didn't answer in time." Time spent waiting for the person doesn't count against the
run's own two minutes (`BrainToolbox.deadline(from:)`: the deadline moves by every wait and can't pass
while a card is open), for the API loop and both CLI brains; the CLIs' own tool-call timeouts are set
just above a day (Codex `tool_timeout_sec`, Claude Code's per-server `timeout`) so they never give up
first. A skipped or stopped step waits in Now › Needs you (and the menu bar's Now list) with the
question its card asked, word for word, and **Run it now**: that click answers that question (same
tool, arguments and words, `ApprovalRequest.asksTheSame`); Guard still checks everything else, and a
new question shows as a normal card. Steps are kept in memory, 20 at most for a day; after a restart
they are only in Activity, whose redacted arguments can't run again. No card anywhere waits forever.

**Long jobs that read private data (Apple Notes, D38):** reading a note taints the turn, so before
this every later batch asked again (a 214-note library meant about eight cards). Now, in a tainted turn,
a card for a step that can't carry anything off the Mac (`couldCarryOut` is false: no network or other
app at an untyped address, no command, file change, extension, clipboard or memory write, nothing to
read in full, not high risk) offers **Allow for this request** where "Always allow" would be: that tool
then runs without a card until Sidefolk's run ends (`RequestAllowances`, cleared with the run's cards).
Not in "Ask every time", never for other agents. For the Notes tools that gives, by mode:
- *Ask every time:* every step asks, as chosen.
- *Ask once per kind:* the first list in a clean turn asks (and may be "Always"); after it, listing,
  reading and copying ask once each with "Allow for this request": about three cards per request
  instead of one per batch.
- *Auto:* list, read and copy are medium, so a clean turn runs them; once a note has been read they ask
  like above (a note's text is outside content, which Auto never lets steer an action).
- *Full access:* list, read and copy also run in a tainted turn: what they move goes from Notes to the
  AI and into the notebook, all on the Mac, and nothing reaches a server or another app.
- *Every mode:* `applenotes.remove` asks every time, high risk with every note listed in full: it is
  destructive in another app, and the place an instruction hidden in a note would aim.
A "planned job" approved once ("Copy 214 notes into these collections") was the alternative. It would
need Guard to know each note's folder when it decides (Guard only sees a call's arguments) and to hold
the model to the plan across later calls: a tool-specific state machine inside Guard. "Allow for this
request" is general, comes from a real card the person read, ends with the run (10 steps, 25 calls),
and exists only where nothing can leave the Mac. The cost is in the residual risks below.

**Why:** the founder wants to choose how much Sidefolk asks, like Claude Code and Codex, and never to
come back after an hour to a task stuck on a question (before, a card waited two minutes and the run's
own deadline had passed by then anyway). Modes are about how often to ask; the boundaries that make
asking meaningful (capabilities, protected places, folders, taint, other agents) stay where they were,
so the worst a mode can do is act on the person's own request without checking with them.

**Alternatives:** a "just do it this time" for a whole request, chosen in the Ask panel before it
runs (not built: a second, less visible way to loosen Guard, easy to trigger by habit with a modifier
on Return, and decided before Sidefolk knows whether the turn will read outside content; the chip and
the menu switch are one click and stay in view, and "Allow for this request" covers one tool after a
real card); Full access widening the folder list (no: "where" is a separate, standing
decision); detecting "away" from idle time or a locked screen (a fixed wait is predictable, and
someone can be away without locking); saving skipped steps in the database (they hold model-built
arguments, which Activity deliberately keeps redacted).

**Implications:** `GuardPolicy` (`guard.policy` in SQLite, never UserDefaults, so `defaults write`
can't turn on Full access, T8) gains `unanswered`; the old `standard`/`cautious` load as the new names,
an unknown mode reads as the default and never as more access, and each field (and each capability) is
read on its own so one unknown value can't turn switched-off capabilities back on. SECURITY T1, T2, T9
and §5 note the exceptions.

**Residual risks:**
- Full access runs model-written commands (command watchers, extension programs), opens links in
  other apps' schemes (a Shortcut, `ssh://`) and moves files to the Trash in clean turns without the
  person reading the exact text first: a model *mistake*, not only an injection, acts at once. The
  sheet says so; Activity, Undo and the Trash are the way back.
- Same-uid code can still write the policy in the database and turn on Full access (out of scope,
  SECURITY §1); the planned HMAC over Guard's rows (T19, P1) now covers the policy too.
- A clean turn is only as clean as taint tracking. What reaches the context without setting it can
  steer Auto and Full access with no card: extension tool names and titles (60 characters), notes the
  person saved from elsewhere as their own, text they paste into the request itself.
- In clean turns Auto and Full access fetch and open model-built addresses without a card, so a
  misbehaving model can send context (About you, notes) to a server of its choosing.
- "Run it now" acts on arguments chosen when the step was asked, up to a day earlier; they are shown
  word for word, but files or pages may have changed since.
- After "Allow for this request", and in Full access, an instruction hidden in a note can steer the
  rest of the run to read other notes (their text goes to the AI provider, which T21 accepts by design)
  or copy notes into other collections, with no card. Nothing reaches a server or another app, copies
  carry `app:notes` and are never offered to the model as the person's own, and removing still asks.
- A long wait keeps the run, its CLI brain process and the Ask panel's busy state alive for as long as
  the setting says (a day with "keep waiting"); Stop ends it.
- The CLIs' longer tool-call timeouts are set from their documented options and checked in tests of
  the invocation, not in a live run (no quota spent).

### D38 — The Mac's own apps through built-in tools on Apple Events, Apple Notes first (2026-10-26)
**What failed:** the founder asked Sidefolk to "check my Apple Notes and move them, well organized, into
our notebook". The model could open an app (`open.app`) but not read one, and nothing said so: the system
prompt only told it to act through its tools "rather than explaining how they could do it". It opened Notes,
the one tool that sounded related, and asked him to export his notes by hand.
**Decision:**
- Sidefolk reaches the Mac's own apps through **built-in tools** that send **Apple Events** from fixed
  JavaScript for Automation programs, run by `/usr/bin/osascript` as a child process (`AppleEventsRunner`,
  `OsascriptRunner`, `Sources/SidefolkCore/MacApps/`). The model never writes script: typed tool inputs reach
  a program only as one JSON value, ASCII-escaped, so no input can end the literal and become code.
- Apple Notes: `applenotes.list` (accounts and folders with counts, then a page of at most 50 notes: short
  id, title, folder, modified date, the start of the text; `folder`, `query`, `not_copied`, `offset`),
  `applenotes.read` (at most 5 whole notes as Markdown, attachments named, never read), `applenotes.copy`
  (at most 50 notes, each into the collection the model chose: the text as written, an italic line saying
  where it came from, the tag `apple-notes`, Notes' own dates, source `app:notes`; a ledger in `kv` remembers
  what is copied), `applenotes.remove` (moves notes to Notes' Recently Deleted). Apple Reminders:
  `applereminders.list` (open reminders, read only).
- Guard: capability `mac.apps` (a switch in Settings › Privacy & Permissions). Reading and copying are
  medium: the card says what is read and where ("Read the titles, folders and dates of up to 50 notes in
  “Recipes” in Apple Notes", "Copy 25 notes from Apple Notes into “Cooking”, “Travel”"), labelled "Reads
  private data" when the call only reads. Results are untrusted, so the turn is tainted and every later
  medium call asks (T2). Removing is high risk, asked every time, never "always", and lists every note by
  title; it is refused before any card unless the note was copied, and at run time unless its copy is in
  the notebook, whole (no attachments left behind, not cut) and unchanged since, and its account has a
  Recently Deleted folder. Copy is the default; the tool description and the prompt say "move" or "delete"
  must come from the person. None of these tools is offered to other agents.
- Permission: `NSAppleEventsUsageDescription` and the hardened-runtime entitlement
  `com.apple.security.automation.apple-events`. macOS asks once per app the first time the person approves a
  read. A refusal comes back to the model as instructions to relay and to the person as a card whose
  "Open System Settings" button opens Privacy & Security › Automation (only that page; `PrivacyPane`).
- How the model learns what it can reach: the offered tools and their descriptions (`open.app` now says it
  only shows the app), and a "What you can reach" section in the system prompt built from the offered tools:
  which of the Mac's own apps it can use and how, that nothing else on the Mac is reachable unless a tool
  does it, to say so in one sentence and offer what it can do (an extension or MCP server could add it), and
  not to send the person off to export or paste things by hand unless they ask how. Guard's refusals
  (switched off, refused by macOS) are worded for it to relay.
- Big libraries go in batches: pages and copies of at most 50, every copy result saying where the job stands
  ("Progress: 75 of 214 notes in Apple Notes are in the notebook; 139 to go"), `not_copied` to pick up where
  the last request stopped. One request never holds the whole library.
**Why built-in, compared with the alternatives:**
- *A bundled extension:* extensions run under `sandbox-exec`, whose profile denies Apple Events (SECURITY §3);
  their tool descriptions never reach the model (D24), so it couldn't learn what they do; and opening the
  sandbox to Apple Events would let an extension drive any app as Sidefolk.
- *Delegating to a connected agent (Claude Code, Codex):* their brains run with Sidefolk's tools only (T7).
  Handing one a shell for `osascript` means model-written scripts Guard can't summarise, a CLI and its quota
  as a requirement, and the agent's own words as the only record of what was read.
- *MCP servers:* the right path for the long tail (Mail, Things, Bear), added by the person, unsandboxed and
  medium by default (T16). But they are third-party code that can't ship as a default, and Guard sees an
  opaque tool. Notes is a first-party, everyday target that deserves typed tools with exact approval text.
- *`NSAppleScript` in the app:* Apple Events block until the app, or the person at macOS's prompt, answers,
  and `NSAppleScript` belongs on the main thread. A child process has a deadline and dies as a group; the
  script goes over stdin and nothing personal goes in argv.
- *EventKit for Reminders and Calendar:* the native framework, and the only one that expands repeating
  events. Reading open reminders fits the Apple Events pattern (one permission flow, one recovery path), so
  it is here; Calendar doesn't (repeating events come back once, big calendars are slow), so calendar
  awareness stays EventKit work (PRODUCT §13).
**Implications:** Sidefolk now asks for Automation (SECURITY T22, T25). Children it starts (approved command
watchers, MCP servers the person added) inherit its TCC grants, Automation included (T9, T16 residuals).
Notes' Recently Deleted folder is recognised by name, in English and in Notes' own word for the Mac's language
(read from NotesShared's strings); where it isn't found, removing is refused. The scripts are checked against
the apps' scripting dictionaries and a stand-in object model that the real scripts run against through
osascript, never against real notes: the founder's manual test is the first run on a real library.

### D39 — Extensions without limits: built-in extensions, folders named per call, icons, and drafts the AI writes for the person (2026-10-26)
**What failed:** the founder typed "please clone this repository under ~/git" and Sidefolk said it lacked
the capability. It was right: no tool runs git or writes outside the file tools' moves and renames; the
`shell` capability only covers command watchers (T9), never a one-off command; and "What you can reach"
(D38) told the model to say so and point at Settings › Extensions. Making it "just work" through an
existing tool wasn't possible, and a general "run this command" tool would have been the wrong fix (below).
**Decision:**
- **Built-in extensions.** Sidefolk ships extensions in `extensions/`, listed in `extensions/catalog.json`
  with whether each starts on (`BundledExtensions`). Bundled, on: Git (clone a public https repository,
  status, pull fast-forward only, log), World Clock (time anywhere, conversions; no permissions), System
  Vitals, and Weather (Open-Meteo; the place asked about leaves the Mac; on since 2026-10-27, below). **No core tier:**
  anything fundamental is a built-in tool (D38), and an addition the person can't switch off is one they
  can't refuse. Built-ins are installed like any extension, can be switched off but not removed, and are
  reinstalled whenever the app's copy differs from the installed one (update or damage), keeping whether
  the person had it on; an update that asks for more is installed off, with a notice. A copy someone
  installed by hand with the same id stays until the app brings a strictly newer version, then it is
  replaced, with a notice. One that can't run on this Mac (no git) is listed in Settings with the reason.
  Their tool descriptions and full schemas reach the model: first-party text inside the signed app, so
  D24's reason (a stranger's words in every run) doesn't apply. Everything else keeps D24.
- **Folders named per call** (`tools.<name>.paths: {"<parameter>": "read" | "write"}`). Guard treats the
  parameter like a file tool's path (shared folders, the folder card for Sidefolk's agent, protected
  places refused); `ToolContext.folders` carries what Guard allowed, the tool re-checks the canonical path
  at run time and hands it to the extension, and the call runs in a process of its own whose sandbox adds
  just those paths and ends with the call. Fixed `files.*` folders stay, for extensions that need one.
- **Programs by name**: `"exec": ["git"]` resolves git in the developer folder `xcode-select` points at,
  the Command Line Tools, Xcode or Homebrew (never `/usr/bin`'s xcrun shim, never by running xcrun), pins
  it with its https helper, opens its installation read-only, and passes `SIDEFOLK_EXEC_GIT`. Not "can
  run anything": in the sandbox it can start only its helpers. Per-tool `timeout` (≤ 300 s) for clones.
- **Icons**: manifest `icon`, a square PNG (64–1024 px) or one-page square PDF of at most 256 KiB, checked
  as an image only (header and size, page count and box) at install and every load, pinned with the other
  files, drawn from the locked copy. SVG is refused (XML that can reference files and addresses). Default:
  a tile in the folk's colour with the initial. Shown in Settings, on the install sheet, on approval cards
  ("From the Git extension") and on result cards.
- **The builder.** `extensions.draft`, `extensions.review` and `extensions.read_draft`, used by the
  bundled `build-extension` skill: the AI proposes the extension in plain words and waits for a yes, writes
  a text-only draft into `ExtensionDrafts/local.<name>/` (Sidefolk sets the id and author; no binaries,
  links, executable bits or icon), which is validated like an install and started once with **every
  permission removed** so the AI can fix it before anyone is asked; then `extensions.review` opens the
  normal install preview, in a window of its own ("written by Sidefolk for you", Show Files; a sheet over
  Settings would stay hidden while the app isn't active, and the Ask panel never activates it). Only the
  person's click installs it. The tools refuse other agents, routines and extensions, and any request that
  read outside content (as command watchers do, T9). The "What you can reach" section offers to build one
  when the tool is offered. Installed drafts are origin `draft`, "Written for you", and follow D24.
- **For developers and companies**: `skills/sidefolk-extension/SKILL.md` (Claude Code and Codex, with
  Python, Node and sh templates); publishing (signed packages, a directory, trust levels, updates,
  revocation) is proposed in docs/research/extensions-catalog.md, not built.
**Why, compared with the alternatives:**
- *A generic "run this command" built-in tool* (shell, high risk, verbatim card): it would have cloned the
  repository today, but with the person's full rights and Sidefolk's TCC grants (T9's residual), with
  model-written command lines nobody can summarise, and it would make every later capability a shell
  command instead of a typed, sandboxed, reviewable tool. Git as an extension is narrower: https only, one
  folder per call, no credentials, no hooks.
- *Git as a built-in tool* (like Apple Notes, D38): D38 went built-in because the sandbox denies Apple
  Events. Git runs fine sandboxed (verified: clone, status, pull, log), so it should prove the extension
  path instead of bypassing it.
- *A fixed `files.write` folder for Git*: guessing `~/git` or `~/code` is wrong for most people, and it
  would keep that folder open whenever the extension runs. Per-call folders reuse the folder grants the
  person already manages, and the sandbox opens nothing between calls.
- *Generic file writes for drafts* (a `files.write`-style tool): drafts live under Sidefolk's own data,
  which file tools must never touch (T10); and a dedicated tool can enforce text-only, the id prefix, the
  author, validation and the trial in one place. *Installing from an approval card* instead of the install
  sheet: one more permission UI to keep honest; the sheet already shows permissions, warnings, the
  sandbox, update diffs, and arms after 800 ms.
- *Trusting an AI-written draft's descriptions*: the draft is the model's own words from a clean turn, but
  they would persist into every later run (T3); skills written by the agent aren't trusted either. Titles
  and parameter names carry enough.
- *Locking a core extension on*: see above.
**Implications:** SECURITY T27 (AI-written extension code; per-call folders) and §5 ("no AI-generated
executable code" now reads "none runs outside a sandbox without an install the person approved"). A
freshly installed extension's tools are offered from the person's next request (tools are fixed per run).
Built-in descriptions now reach the model, so they are reviewed like prompts. Extensions still can't hold
secrets, choose hosts, or reach Unix sockets; the catalog lists those as the next platform pieces.

**Addendum (2026-10-27):** Weather starts on. The design review found weather the most common first
question, and D35's weather reports already send the place asked about to Open-Meteo by default, so
keeping the extension off protected nothing and left the question unanswered. An install where the
person switched Weather off keeps it off.

**Addendum (2026-10-28): the built-ins are programs of their own, and there are thirteen.** The founder
installed Sidefolk and read "Git needs Python": every built-in was a Python script, and a Mac without
Apple's Command Line Tools has no Python. Each is now a small Swift program (`extensions/<folder>/Sources`,
on `extensions/Kit`), built with the app and signed inside it, run under the same sandbox as any extension;
Git needs only git. Nine new ones: Calculator, Currency (the ECB's file, a rate watcher), Playtime and
Images start on; PDF Tools, QR Codes, Archives, Dev Toolbox and Feeds ship off. *Why on and off:* every tool
of an enabled extension reaches the model with each request (tokens on every run), so only everyday ones
start on; the others reach the model as one line each ("switched off in Settings: PDF Tools (…)"), so it can
suggest switching one on. A new manifest permission, `media`, opens the GPU and the video decoder that
Core Image and ImageIO need on Apple silicon (two IOKit user clients and one service, measured), named on
the install sheet. The Python sample (hello-folk) stays in the repository for developers and no longer
ships. *Alternatives:* bundling a Python runtime (tens of MB, a second toolchain to sign and notarize);
one multi-tool program for every built-in (each folder pins its own files, so it would be copied thirteen
times); `/usr/bin/curl` or `osascript` for the network parts ("can run anything"). *Quarantine:* Sidefolk
quarantines every file it writes (`LSFileQuarantineEnabled`), and a downloaded app's files all carry the
download's mark, so Gatekeeper stopped each copied program at launch. A built-in's copy drops the mark (its
files are sealed in the signed, notarized app Gatekeeper already let run, and the install checks the copy
against them); any other install keeps its original's mark for Gatekeeper to judge.

*Amended 2026-10-28 (Settings › Extensions):* thirteen built-ins with every row open read as a wall of permissions.
Each extension, server, draft and skill is now one line (name, what it does, its switch), and a click, Space or
Return opens its details; a row whose tools changed opens by itself. Under "Installed" (so a "Browse" catalog can
sit beside it later; none is shown), a search reads names, descriptions, tool titles and names, what each may do,
the request to try, authors, ids and server commands, ignoring case, accents and width. "No access to…" lines are
not searched, so "internet" finds what can reach it. When a row's own line doesn't show the match, it names what
matched. All / On / Off count what matches the typed words and are remembered per person; drafts and skills,
neither on nor off, are listed under All. The logic is `ExtensionListQuery` in core, tested against the shipped
built-ins. Under each name is a `tagline`, a new manifest field of one line (at most 60 characters; the built-ins'
are translated), and the full description opens with Details; an extension without one shows its description's
first sentence. *Why:* the founder found every description cut off with "…" in the list.

### D40 — With no AI chosen, the Ask panel offers the plan this Mac is signed in to (2026-10-27)
**Decision:** when a request needs AI and the provider is "No AI", the "That needs AI" card probes the
subscription CLIs the way Settings › AI does (`ClaudeBinary.status`, `CodexBinary.status`: version, help
and Codex's login, never a prompt) and offers **Answer with Claude Code** / **Answer with Codex**. One
click chooses that provider (`switchProvider`, the same change Settings makes), turns the card into a line
saying which AI answers from now on and where to change it, and sends the request again with what was
dropped with it (still untrusted). Only plans are offered: Codex signed in with an API key bills that key,
so it stays a Settings choice, and API-key and local providers are never chosen from the panel. Without a
plan, "Set up AI…" leads the card. Built-in extensions show one request to try under each in Settings ›
Extensions (`BuiltInExamples`, app-side and translated: built-ins are first-party and only the AI reads
the words); the button fills the Ask panel and nothing is sent until Return. Their calls read as
sentences on approval cards and in Activity (`BuiltInToolSummary`: "Clone https://… into ~/git/x"), built
only from the exact arguments and only for the app's own copy (origin bundled); any other extension's
card keeps its title and the arguments as they are (T1).
**Why:** the primary persona (PRODUCT §3) has Claude Code or Codex, yet a fresh install answered their
first question with "That needs AI, which isn't set up" and "Save as task" as the main button; Settings ›
AI is where they'd never look at that moment, and PRODUCT §5 says AI setup is offered when first needed.
**Alternatives:** choosing a found CLI at launch (a silent change of where requests go); an onboarding
step (skipped by many, and too early: the need isn't there yet); offering API-key providers too (a
surprise bill, and a key to type).

### D41 — Hardening for 0.1.0: fail closed, bound what comes in, tidy up while running, swap the app (2026-10-27)
**What the release review found** (quality, performance and security pass over D34–D39 together, with
end-to-end scenarios in `Tests/SidefolkCoreTests/E2E`): crashes from numbers (the hint line on a typed long
number; another agent's giant repeat interval, which crashed at every launch), Guard falling back to a default
policy with nothing switched off, steps refused by Stop missing from Activity, a typed "every 30 minutes until 6pm"
repeating forever (the local path dropped the end its hint promised), reports notifying in quiet mode, tool
recoveries never reaching the model, a clock set back silencing every watcher, housekeeping only at launch, a log
writer that crashed on a full disk, and `make app` deleting the bundle a running copy was using.
**Decision:**
- *Fail closed.* When Guard can't read the person's settings, or the caller is gone, nothing runs and the refusal
  is in Activity. Settings change through `PermissionStore.updatePolicy` (one transaction), never by saving a
  default over a failed read. `withTimeout` never starts work for a cancelled caller (SECURITY T29).
- *Bound what comes in.* Numbers from text, agents, extensions' schemas, stored rows and the network are bounded
  before any `Int` conversion; a repeat is every 1000 units at most (`Recurrence.maxInterval`), enforced in the
  schema, the initializer and again in `RecurrenceMath` for rows already stored. The parser's contract (D4) is kept
  by a seeded fuzz of D35's syntax (`NewSyntaxFuzzTests`): a repeat's end or span it can't hold goes to the AI.
- *Tidy up while running.* As a login item Sidefolk runs for weeks, so retention can't wait for a launch:
  `DailyChore` runs housekeeping once a day (history, Activity, AI runs, finished jobs, sessions, Trash), logs prune
  when the day changes and stop at 16 MB a day, the WAL is truncated to 4 MB after checkpoints, drafts are 20 at
  most and interrupted ones are cleared.
- *Say it the same way twice.* A tool's `recovery` is part of what the model reads; a memory report counts RAM in
  binary units for the model as on the pill; a report's notification follows quiet mode
  (`WatchReading.notifies`); a clock set back clamps every watcher's next check to what it could have been.
- *Quit stops runs.* Quitting cancels requests in flight, so a CLI brain's process group gets SIGTERM instead of
  finishing a turn on the person's quota.
- *Nothing runs to find a program.* `xcrun`, `xcode-select` and the `/usr/bin` shims offer to install Apple's
  developer tools on a Mac without them, so Python is read from the developer folder's link like git
  (`ProgramResolver.developerFolders`), and a built-in that needs Python, Git or Node this Mac lacks says so
  plainly, with how to get it.
- *Card labels are true.* A medium card names the call's `ApprovalRequest.Effect` (uses the internet, reads
  files…), worked out from what Sidefolk lets the call do, never from an extension's own word.
- *Build beside, then swap.* `scripts/build-app.sh` assembles and signs in a staging bundle and swaps it in; the
  replaced bundle stays until `lsof` says nothing runs from it (docs/RELEASE.md).
**Measured** (release-optimized build of this commit, macOS 27, Apple silicon, isolated `SIDEFOLK_HOME`, companion
shown, folks and pointer-following off, 300 s windows after a 30 s settle, `ps` CPU time and `top -pid` every 10 s,
other builds running on the Mac, load average 4–5; built with `-DDEBUG` only so it wouldn't take the talk
shortcut from the founder's running copy, which adds two notification observers and nothing that runs): the
socket answers 0.61 s after launch the first time (built-in extensions installed in the same second) and 0.22 s
after; idle, 0.19 s of CPU in 300 s (0.06 % of one core; D35 measured 0.036 %), `top` 0.0 % in all 30 samples,
25 MB footprint, 3–4 threads; with four reports every 10 s (CPU, memory, network, battery: 120 readings), 0.34 s
(0.11 %, about 2.8 ms a reading with its pill), `top` 0.0–0.1 %, 26–27 MB, 7 threads. `top` showed no idle
wake-ups in either window; `powermetrics` needs root and wasn't run.
**Why:** a public 0.1.0 meets inputs nobody on the team typed, Macs that never restart, and disks that fill. A crash
loop or a setting silently undone costs more trust than any feature earns.
**Alternatives:** clamping huge numbers instead of refusing them (a reminder every 9e18 days is a mistake to
report, not to guess); a background vacuum of the database (more disk I/O than the rows are worth; FTS and
`secure_delete` already keep deleted notes off the disk); building the app into a versioned folder and pointing a
symlink at it (macOS resolves a bundle through its path, and Finder and Launch Services dislike linked bundles).

### D42 — Other agents drive Sidefolk: a skill installed by Connect, the tools they were missing, Codex hooks (2026-10-27)
**Decision:** what someone asks Codex or Claude Code about Sidefolk works from that agent, within T4.
*Amended by D86:* Connect installs the skill and hooks into the person's agents only from the copy on
their own data folder; any other `SIDEFOLK_HOME` writes stand-ins inside itself.
- **Tools other agents were missing**, each safe under T4 and run through `ExternalToolGateway` (Guard,
  audit, quotas): `reminders.cancel` for the reminders that agent set (`ReminderTools.canManage`: another
  agent's or the user's read as not found), `watch.report` for this Mac's metrics only (cpu, memory,
  battery, disk, network: nothing leaves the Mac, so "show the CPU every 10 s" works; web values and the
  weather stay off), and `agenda.today`, "what's on my plate today" in one read (today's reminders, open
  tasks, watches running), which asks like every read of the user's data. A fast report of another agent's
  stops within the hour like anyone's (before, its one-day cap replaced the hour).
- **Their own words.** `ExternalToolPolicy.externalSpec` gives other agents descriptions and schemas that
  say what they can do: `notes.save` without `collection_kind` and with "other agents can't create
  collections", `level` without critical, `watch.create` saying local addresses and unshared folders are
  refused, `watch.report` with only `source: metric`. Before, they read Sidefolk's own agent's
  descriptions, tried what Guard refused, and lost the way out: a refusal's recovery line never reaches a
  model, so the collection refusal now says it in its message. "my shopping list" finds a list called
  "Shopping" (`NotebookCollections.resolve`). `notify.user` says when a notice was held, so a caller
  doesn't send it again louder. The MCP `initialize` instructions say what Sidefolk is for.
- **The skill:** `skills/sidefolk/SKILL.md` (Agent Skills format: `name`, `description`, Markdown) says what
  Sidefolk is, which tool for which request with examples, approvals, limits, and what not to do (spam,
  quiet mode, secrets in notes, instructions for other AIs). The app ships it as
  `Resources/AgentSkills/sidefolk` (not `Resources/Skills`, which Sidefolk's own AI reads).
- **Connect installs it** beside the MCP entry: `~/.claude/skills/sidefolk/SKILL.md` and
  `~/.codex/skills/sidefolk/SKILL.md` (`$CLAUDE_CONFIG_DIR/skills`, `$CODEX_HOME/skills`). Checked on this
  Mac, read only: Claude Code 2.1 reads user skills from its config folder's `skills`; Codex 0.160 reads
  `$CODEX_HOME/skills` and `~/.agents/skills` (a throwaway `HOME`/`CODEX_HOME` with a probe skill in each,
  through `codex debug prompt-input`), and its own skill-creator documents `$CODEX_HOME/skills`. The card
  lists the change, the confirmation shows it with the backup, a line under the front matter marks the file
  as Sidefolk's, an older copy of ours shows as outdated, Disconnect removes only a marked file and its
  folder when nothing else is in it, and installing twice changes nothing. A file that differs from ours is
  backed up first; a link in the skill's place (people link skills from their checkouts) is left alone and
  the card says why.
- **Codex session updates:** Codex 0.160 has hooks (feature `hooks`, stable, on), in `$CODEX_HOME/hooks.json`
  with Claude Code's format and payload. Connect adds UserPromptSubmit, PreToolUse, PermissionRequest
  (Codex has no Notification; this is when a session waits for an approval), Stop and SessionEnd, running
  `sidefolk hook <Event> --agent codex` with a 3 s limit (Codex clamps SessionEnd to 3 s and warns about
  more), behind the same checkbox, confirmation and backup as Claude Code's; a hooks.json left empty goes.
  Codex lists new hooks as untrusted and asks the person to trust them in its own UI; Sidefolk never writes
  Codex's trust hashes. Verified with a throwaway `codex app-server` (`hooks/list`): all five load, untrusted.
  Codex's legacy `notify` was not used: it is one command, often already taken (the founder's runs Codex
  Computer Use).
- **Other MCP apps:** "Copy Setup Instructions" puts the command, a snippet for Cursor, VS Code and Zed, and
  the skill's folder on the clipboard. Sidefolk edits nothing for them. The text stays English, like the
  `sidefolk` command's output.
**Why:** the founder wants to give orders from Codex ("remind me in 20 minutes…") as from the Ask panel. The
MCP server already existed, but agents didn't know when to use it, read descriptions that promised what
they couldn't do, couldn't undo a reminder they set, couldn't show the CPU, and needed two approval cards
for "what's on my plate".
**Alternatives:** *a generic "command" tool or web reports for other agents*: T4 says no (their sandbox would
gain Sidefolk's network and grants). *Letting other agents create collections*: a hostile repo could add
"URGENT" projects beside the user's own (T3). *Writing the skill into Claude Code with `claude mcp`/plugins*:
a plugin is heavier, and D16's direct, backed-up edit is predictable and testable. *Only `~/.agents/skills`
for Codex*: it works, but Codex documents `$CODEX_HOME/skills` and Sidefolk already honours `CODEX_HOME`.
*Codex `notify`*: see above. *Trusting the hooks for the person*: that is Codex's own review, not ours.
**Implications:** SECURITY T4 (the new tools) and T28 (what Sidefolk installs into other agents).
`AgentIntegration` gains `claudeSkill`, `codexSkill`, `codexHooks`; `IntegrationLocations` gains the skills
folders and Codex's hooks file. `SessionTracker` treats `PermissionRequest` as "needs you". Live checks:
`SIDEFOLK_LIVE_CODEX=1` / `SIDEFOLK_LIVE_CLAUDE=1` run `LiveAgentsTests` (each CLI, with only this test's
Sidefolk configured, lists the tools and calls `status`).

### D43 — Companions with a life of their own; custom companions as data (2026-10-27)
**Decision:** the shared `Director` plays **moments** (one-shot bits of life written as data:
tracks on identity layers plus face and gaze beats, fitted to each body so nothing leaves the
window), **postures** (sit, then lie down) and **reactions** (boop, pet, drop, throw, startle on
news, cheer when done), chosen by an idle scheduler that holds still while the person types, skips
its turn while the companion speaks, and is sleepier at night. A **Liveliness** setting: Minimal
(today's companion, D20 unchanged), Balanced (the default: a moment every 28–65 s) and Lively (every
10–26 s, more kinds, eyes on the pointer across the screen); at every level the loops settle 20 s
after anything happens. Reduce Motion starts nothing on its own. **Custom companions** are a folder
with `species.json` and SVG parts, read strictly as data (never code), checked to draw inside the
window in every state, loaded from `companions/` in the Sidefolk home and from installed extensions,
listed under "Made by you".
**Why:** the founder found the companions doll-like; life comes from small self-initiated moments,
attention, weight and time, all of which fit the vector engine at near-zero idle cost: the companion's
own process stays near 0.05% of a core at every level, WindowServer pays only while something moves
(about 0.5% of a core on average in Balanced, 1.2% in Lively; docs/research/lively-companions.md).
Data companions reuse the `Species` path D30 made, without a code path or a sandbox.
**Alternatives:** constant idle loops (D20's measured cost); Rive/Lottie (an art pipeline and a
runtime, and they lose props and data species); **3D** in SceneKit/RealityKit, tried as a spike and
dropped (a GPU frame for every moving frame, a cost even when hidden, and a modelling pipeline we
don't have); walking across the screen (later); sound (designed with voice, opt-in, later).
**Implications:** `AppSettings.liveliness` (default Balanced) and `customCompanion`; Settings ›
Companion gains Liveliness and "Made by you"; the companion window answers clicks, strokes and throws;
`sidefolk-render --live`, `--antics` and `--check-companion` review it.

### D44 — Playing with the companion: tricks, a tickle, catch-me and a breath (2026-10-28)
**Decision:** the companion does tricks when asked (dance, wave, bow, flip, hop, cheer, nod, giggle, or a
trick of its choosing), giggles when stroked again soon after a pet, and plays two small games: **catch-me**
(for 20 seconds it hops about near its spot, faster as it goes, and each click catches it; the best score is
kept) and **breathe with me** (five slow breaths, in four seconds, hold one, out six, the body breathing along
and one line of text above it). They are asked for in plain words ("dance!", "do a trick", "let's play catch",
"help me relax", no AI), from Play in the companion's menu, or by the AI through `companion.play`, which only
publishes `AppEvent.companion` for the app to play, so the AI can cheer with the person (a right trivia answer)
or offer a break. Lively mode also breaks into a short dance on its own now and then (rare, never at night).
**Why:** the founder wants the companion to be relaxing and funny to play with, not only useful: a few minutes'
break, a laugh. Tricks are data like the other moments (D43), so they cost nothing at rest; the games use the
window and the moments the engine already has. A tool rather than an app-only path keeps every action, the
person's own words included, going through the executor and its audit.
**Alternatives:** a mini-game window (a second UI to design and keep up; play with the companion itself is the
point); games as an extension (sandboxed programs can't move or animate the companion); sound (opt-in, later).
**Implications:** `CharacterAntic` gains wave, dance, bow, nod, giggle and breathe (one breath lasts 11 s, the
only moment over four); `IntentParser.play`; Play submenu; `CompanionPlayer` and its caption panel, which
never takes a click; dev commands `play:<act>` and `click`.


*Amended 2026-10-28 (chance on the desktop):* coins, dice and rock-paper-scissors are the companion's.
`companion.toss` draws them in core with the system's random generator and tells the model and the person the same
real result; the app plays a move (`flick`, `roll`, `pump`) and draws the objects in code above the companion,
landing on the result, with the result as a caption (Reduce Motion shows it at once; VoiceOver hears the result).
The rock-paper-scissors score is kept in the database. Plain words ("flip a coin", "roll 2d6+1", "rock paper
scissors", then "rock") and the Play menu reach it without AI. Playtime keeps trivia and random picks only (1.1.0),
so the model has one way to do each. *Why:* the founder wanted these shown, not written, and instant.

### D45 — Conversations you can come back to, start fresh, or forget (2026-10-28)
*Amended by D84:* Conversations and Activity are one place, History.
**Decision:** *amends D5.* The panel stays the quick place: a long answer opens on 8 lines with Show all (measured,
so nothing hides); every answer offers Reply (the main button when it asks something), Save, Think harder, Copy
and Open in Conversations; Reply continues that answer's own conversation however long ago, and a chip above the
input says which. *Starting fresh:* plain words without AI ("new conversation", "start fresh", "start over", "new
chat", "new topic", "forget this conversation", "change the subject"), ⌘N, and "New conversation" in the hint row
while one is open; the panel keeps what it shows. Clear all also starts fresh. *Home › Conversations:* each
conversation is named by its first request and searchable; the transcript shows the person's words, the replies
as the panel renders them, each run's Activity steps as quiet lines (with why one wasn't done) and failures as
notes; a reply field continues it even after the 10-minute window; delete one or all, each confirmed (delete all is
also in Settings › Privacy); continuing one makes it current for the panel too. *Runtime:* a request naming a
thread continues it while its history is kept; otherwise the 10-minute window applies. Deleting stops the thread's
runs, then removes its history and the "last sent" preview; Activity and run records stay as the audit trail.
**Why:** the founder wanted to clear history or start fresh, read a long reply in full, reply to it and switch
conversations, without Sidefolk turning into a chat app. Clear all starts fresh because a follow-up shouldn't lean
on answers the person just cleared; "New conversation" keeps the screen because it is about what the AI remembers.
**Alternatives:** a chat window as the main surface (D5's "chat app with a mascot"); deleting history from words
(too easy to say by accident: nothing is deleted from words).

### D46 — Sidefolk updates itself from GitHub Releases, asking first (2026-10-28)
**Decision:** *replaces D15.* A published copy (Info.plist `SidefolkRelease`, stamped by release.sh) reads this
repository's GitHub Releases a minute after launch (unless it looked within the hour) and once a day while "Check
for updates automatically" is on (default), plus "Check for Updates…" in the menu bar and Settings › General ›
Updates. Snapshots look at releases and snapshots by default, releases at releases only; versions sort as semver.
A version found by itself comes up once in three days as a gentle bubble (Update / Later / Skip This Version),
which waits through quiet mode. Update downloads `Sidefolk-<release>.dmg`, checks its size and SHA-256 against the
release's `.sha256` and GitHub's digest, mounts it hidden, checks the app inside (bundle id, the release it names,
newer, signed with the running app's own Developer ID team and identifier, notarized), stages it beside the app,
checks the copy again, removes its download mark, swaps the two in one rename, quits and reopens. A copy that can't
replace itself (built locally, not Developer ID, translocated, read-only, folder not writable) gets the checked
image in Downloads; Sidefolk never asks for admin rights. The request carries only Sidefolk's version.
**Why:** the founder asked for update checks that ask first. Sparkle needs an EdDSA private key in CI secrets and
a framework; releases already carry what trust needs (Developer ID, notarization, checksums), and a stolen GitHub
account alone can't ship code (SECURITY T31).
**Implications:** release.sh stamps the release and refuses an app whose stamp doesn't match the DMG; snapshot
notes list commit subjects since the previous release; RELEASE.md › Updates says how to prove the swap (it needs
the second release that carries the updater) and that `Version.swift` must be raised after a production release.

### D47 — Using the internet without a card every time (2026-10-28)
**Decision:** Settings › Privacy & Permissions › "Using the internet", for Sidefolk's own agent only: **Ask each
time** (no grants, no "Always", and Auto or Full access never answer for it), **Ask once for each site** (default),
**Don't ask before reading** (before outside content, any public page and the built-in services go without a card,
logged as "Web setting"; after it, the built-in services and the sites you allowed do). After outside content was
read, a grant from a clean turn or from Settings still holds where nothing the model writes reaches anyone new:
reading a page on a site allowed for good (the exact site, `www.` aside, never with a `?` or `#` part (audit F1),
never redirected off the site), and a call whose destination Sidefolk's code fixes (the weather report to
Open-Meteo; Weather and Currency, only the app's own copies, their programs' addresses checked by a test).
"Always" is still never offered after outside content; new sites, `?` addresses, watchers, opening links, and
other people's network extensions and MCP servers keep their rules. A CPU or memory report never counts as
network. Sites are added and removed in Settings, and the card names the site "Always" covers.
**Why:** the founder found every web use asked, every time: once a run read outside content (a page, any extension
result, a follow-up in a conversation that read one), Guard ignored every grant, even in Full access.
**Alternatives:** honouring any grant after outside content (reopens exfiltration through a model-written URL);
trusting a manifest's word about its hosts (the sandbox can't hold a program to them). *Residual:* a site you
allowed can receive what a steered model puts in a page's path; with "Don't ask before reading" a steered place
name can reach Open-Meteo. Feeds and Git still ask after outside content.

### D48 — Sidefolk knows where the person is, when they choose (2026-10-28)
**Decision:** Settings › Privacy › Your location: **Off** (default) / **Use my Mac's location** (Location Services
at a city's accuracy, significant changes, named by Apple's geocoder; macOS asks once, only from that choice) /
**A place I choose** (Open-Meteo geocoding by name). The AI's "# Now" gets one line: town, region and country (and
the time there when a chosen place keeps another clock), never coordinates; with none known it is told to ask.
Weather with no place named is the person's own, sent to Open-Meteo by its coordinates (rounded to 0.01°, kept
only for that); with none known, the parser and `watch.report` ask "Which place?" with a button to the setting
rather than guess. A position is named again only after a move of 5 km or a day, at most every 10 minutes;
switching source clears the place, revoking the permission forgets it, logs never say where, diagnostics drop it.
No announcement when the place changes. A report keeps the place it was made with.
**Why:** the founder: "be aware of the location and where we are, what time, so things are easier". Nothing about
where the person is leaves the Mac until they choose.
**Implications:** `com.apple.security.personal-information.location` (hardened runtime) and usage strings in
Info.plist; the Weather extension reads "Town, Country" places (1.2.0); SECURITY T30.

### D49 — A reminder can belong to a note or task (2026-10-28)
**Decision:** `reminders.item_id` (already in v1) is now real: "Remind me" on any Notebook item (in an hour, this
evening, tomorrow morning, pick a time), `reminders.create(item:)`, `notes.save` / `notes.update(remind:)`, "add a
task to call mom at 5", and "remind me about the report task…" when exactly one task fits. The reminder follows its
item: a task done or an item trashed ends the waiting reminders (a one-off becomes done, a series stops) and
records why (`ended_with_item`); opening the task again or restoring the item brings back the ones still ahead; the
person's own cancel is final; deleting an item for good cancels its reminders (a trigger, migration
`v3-reminder-links`); a rename carries reminders that share the item's title. The scheduler settles links on every
`.notebook` event and checks the item again inside `fire`, so no reminder fires for a task done a moment ago. The
bubble offers Mark done (the task), 10 min and Open; notifications get a matching category.
**Why:** the founder asked whether a reminder can be linked to a task or note.
**Alternatives:** hooks in every write path (the Notebook, the tools, Undo and other agents change items
differently; settling on `.notebook` events catches them all). A task with a repeat stays a plain task, since one
"done" would end the whole series. Another agent's linked reminder needs its own title and learns the item only by
kind and id (T4).

### D50 — Extensions answer what needs no thinking, without the AI (2026-10-28)
**Decision:** a tool's manifest may list `commands`: whole sentences (`say`) with typed slots (text, word, number,
integer, expression, place, url, date, list, or the extension's own `words` lists) and the `input` they fill;
`"ai": false` keeps a tool from the model altogether (no tokens). The local parser tries the commands of switched-on
extensions after every core intent; a sentence two extensions claim goes to the AI; the hint names the extension
("World Clock · Look up the time in Tokyo · no AI"). A command runs through Guard as `Caller.command`, treated as
Sidefolk's agent in a clean turn: it computes without a card, but a network, folder or risky tool asks (an "Always
allow" counts for the AI and commands alike), the approval mode and "Using the internet" apply, and an address the
person typed counts as typed. A one-line answer is the card's title and the panel stays open. A tool that reports it
can't answer hands the sentence to the AI; with something dropped on the panel, the AI gets it. The built-ins answer
sums, units, currencies, days until a date, the time somewhere, numbers and picks, UUIDs and timestamps, QR codes and
About this Mac.
**Why:** the founder: a coin flip or a small sum shouldn't wait seconds for an AI, and authors should decide what is
automatic and what is smart, for an ecosystem others build on.
**Rules:** a sentence needs a word of its own (a lone expression aside), never starts with a slot that takes any
words, never has two touching; at most 3 slots and 80 characters a sentence, 12 sentences a command, 8 commands a
tool, 64 an extension; no common replies ("yes", "thanks", "stop"…); slots are checked again after matching;
`ManifestValidator` names each mistake. SECURITY T32. Not given commands: text transforms and checksums (the parser
tidies what is typed, so a hash would be of the wrong text) and trivia (its answers need the question in the AI's
conversation). Command sentences are English, like the core parser.
**Alternatives:** routing everything through the AI (slow, costs quota); letting an extension see every sentence and
decide (it would read everything people type); a regular expression in the manifest (too easy to write one that
captures anything).

### D51 — Companions in 3D: Mochi and Spark either way; Ember, Kiko, Nimbo and Folio in 3D (2026-10-30)
**Decision:** Settings › Companion › Look offers **3D** or **2D** for Mochi and Spark (3D is how they
come); **Ember** (a red fox), **Kiko** (a kid astronaut), **Nimbo** (a floating cloud) and **Folio** (a
folded-paper wish, added the same day after the founder's sheet) join the gallery in 3D only; the robot and the Folks stay 2D. A 3D companion is a three.js page (r180, vendored, offline)
in a transparent `WKWebView` served from `Resources/Companions3D` over a private `companion3d://` scheme,
laid over the companion's soft rig, which still runs undrawn: the `Director`, Life, states, gestures,
postures, antics, petting, dragging, hit testing and bubble anchors are unchanged, and every cue
(`CharacterView.onCue`) is replayed in 3D. The 3D-only companions run on stand-in rigs shaped like their
3D silhouettes. The 3D characters are Meshy models (from sheets drawn with Codex image gen where there
were none) rigged in Blender, with an engine of their own: layered poses, springs for ears, antennae,
tails and follow-through, 3D eyes with shader lids and a painted face decal (light on Spark's visor).
The 3D box is 30% larger than the 2D rig's at the same Size. A 3D companion's colour and scarf are fixed
as designed, so those controls show only in 2D; Settings shows a 3D companion live, and its still is a
render.
**Why:** the founder wants movie-like companions that really sit, lie, sleep, bow and wave, which a
flat vector rig can't do; and asked for the 2D Mochi to stay as the lighter choice.
**Cost:** measured with `top` on the debug app, a 3D companion costs about 18% of a core while shown
(about 4% in Sidefolk hosting the web view, 14% across WebKit's page and GPU processes) plus WindowServer
compositing; the same Mochi in 2D, 0.2%. It draws 15 frames a second while it only breathes and glances,
30 while it moves, at 1.5× pixels, with a 512 px shadow map redrawn every other frame; nothing while the
window is hidden. That is why 2D stays one click away. 23 MB of models and runtime in the app.
**Alternatives:** SceneKit/RealityKit (D43's spike: another modelling pipeline, and the same GPU frames);
pre-rendered sprite sheets (no live gaze, speech or follow-through, and very large); Meshy's mocap
presets (a humanoid rig without ears, tails, antennae or a face, fighting the chibi proportions).
**Implications:** `CompanionChoice.ember/kiko/nimbo/folio`, `CompanionDimension`, `AppSettings.dimensions`
(`dimension(for:)`); `CharacterLook.threeD`, `CharacterSpecies.has3D/only3D`, stand-in species;
`Companion3DStage`; `companion:<id>:2d|3d` in scripts/dev.swift; sources and pipeline in `companions-3d/`.
The 2D view's effects and badges stay drawn over the 3D character (only the 2D body hides), and
the 3D moves ask it for more (`CharacterView.flash`: zZz while asleep, hearts while petted, notes
when dancing or humming, sparkles, "?", "!"); hearts and notes are new effects.
Liveliness reaches the page: Balanced and Lively add moments only a 3D body can have (turning
round, twirls, each character's trick), and one table (`REACTIONS` in the engine) sizes the
reactions to news, work done, errors and petting by level; every move is announced as the hook
for sound effects later. Not shown in 3D yet: working props (laptop, notepad…); a 3D
companion's still is one pose.
D43's "3D, dropped" is superseded for these five companions.

*Amended 2026-11-01 (team/leftovers):* in Sidefolk's window (`frame('sidefolk')`) a hop's rise and the stretch before
and after it ease into the room above the body (`roomAbove()`: its modelled top, standing, against the frame's top),
after `hopScale`, so a tall companion hops less instead of leaving the window: Mochi's ears, Kiko's hair, Ember and
Spark reached the top on hop, jump and flip (the playground's `edges()` and the debug app's snaps). Arms raised over the
head (Kiko's cheer) still reach it. The playground's other framings are unchanged.

### D52 — Other agents change and delete notes; appearance, how much is said, releases by default (2026-10-30)
**Decision:** *amends D42 and D46.* Claude Code, Codex and other MCP clients may change a note (`notes.update`:
text, collection that exists, done, tags, reminder) and move it to the Trash (`notes.trash`) by id, without a
card by default; only the person empties the Trash, now also all at once (Home › Trash › Empty Trash…, confirmed).
Settings › Privacy › Other agents sets three groups to Allow, Ask each time or Off: saving (notes, their own
reminders and watches; default Allow), changing and deleting notes (default Allow) and reading notes, reminders
and today's plan (default Ask each time). Off hides the tools and refuses a call with words that name the setting.
Settings › General › Appearance: Same as Mac, Light or Dark for every window. Settings › Voice › How much to say:
Briefly (D34's one breath) or Everything (the whole answer, still without links, paths or code, up to about two
minutes, then "The rest is on the screen."). Updates look for releases only unless the person chooses snapshots,
whatever build runs, and a version the person let pass comes up again the next day instead of after three.
**Why:** the founder asked an agent to delete notes and was told it couldn't, on purpose; agents are how they
work, and a note in the Trash is restorable, so the default can trust them while Settings lets anyone tighten it.
Reads stay asking by default: they are what a hostile repo would want (T4). The rest was asked for directly.
**Alternatives:** *per-client permissions* (names are self-chosen and unverified, T4); *deleting for good from
agents* (nothing to undo); *"Always allow" offered on the read card* (one click by accident opens the notebook;
a setting is a deliberate choice).
**Implications:** `AgentAccess` in `AppSettings.agentAccess`; `ExternalToolPolicy` groups (`always`, `saving`,
`reading`, `changing`) and `permission(_:access:)`; `ExternalToolGateway(access:)` reads it at every call;
the agent skill and MCP instructions say so (installed copies update on the next Connect, as for any skill
change); `AppSettings.appearance`, `VoiceSettings.length`, `UpdateSettings.effectiveChannel`,
`UpdateChecker.askAgainAfter` 20 h; `NotebookStore.emptyTrash`.

### D53 — A notebook that feels like yours: looks for collections, pinned notes, formatted text (2026-10-30)
**Decision:** a collection gets an icon (one of 30 symbols, or any emoji) and a colour (12, stored by name), from
Edit… in its menu or when it is made; the sidebar and its header show them, and the Inbox can have a look too
(About you keeps its own). A note can be pinned to the top of its collection (pinning isn't an edit). A note's text
is formatted as you write: headings, bold, italic, strikethrough, inline code, links, bulleted, numbered and
checklists (the box ticks on a click), quotes, from a formatting bar or the usual shortcuts (⌘B, ⌘I, ⇧⌘X, ⌘K,
⇧⌘L, ⇧⌘7, ⇧⌘8); Return carries a list on and an empty item ends it. The text stays a small Markdown (`NoteMarks`):
its marks hide except on the line being edited, and the list shows each note's first line without them.
**Why:** the founder wants the notebook to look and feel like theirs and to write notes the way Apple Notes allows.
Markdown keeps every other reader working unchanged: search, agents (which may now write it, and are told so),
export, the Apple Notes import (which already wrote Markdown) and older versions.
**Alternatives:** *rich text stored as RTF or HTML* (search, agents and export would each need a converter, and
an agent's plain text would arrive unformatted); *a WebView editor* (another runtime in the Home window); *showing
the Markdown as typed* (what people asked to get away from).
**Implications:** migration `v4-notebook-look` (`collections.symbol`, `collections.color`, `items.pinned_at`; the
Inbox's and About you's unused emoji cleared); `NotebookStore.setLook`, `setPinned`; items list pinned first;
`NoteBodyEditor` (TextKit 1: hidden marks are null glyphs, boxes and bullets drawn by the layout manager);
`CollectionLook`; the UI snapshots show a formatted, pinned note and the Edit collection sheet.

### D54 — Companions have profile pictures; folks are helpers only (2026-10-30)
**Decision:** each 3D companion has a profile picture: head and shoulders on its own colour, round, drawn with Codex
image gen from its 3D render and sheet (prompts in `companions-3d/references/prompts.json`, sources in
`references/avatars/`, the app's 256 px crops in `Resources/Companions3D/avatars/`). The Ask panel's header and
Home › Conversations (beside each reply, with the companion's name) show it; a 2D or custom companion shows its
drawn face on a disc instead (`CompanionArt.avatar`). Settings' gallery and Home's Now keep the full-body stills.
The Folk Family are no longer offered as the companion: they stay the helpers beside it; settings that chose one
move to Mochi, keeping a name the person gave it.
**Why:** the founder found the full-body renders unreadable at avatar size and wanted a real profile picture in
conversations; and saw no need for folks as companions now that there are six designed ones.
**Implications:** `CompanionChoice.isFolk`, `AppSettings.choose` ignores folks; `CompanionArt.offered` leaves them
out. Supersedes the part of D30 that offered folks as companions.
**Amended (2026-10-30, the founder):** a companion has one profile picture for both its looks. Its 2D look shows the
same picture as its 3D self, unless a picture was made for the 2D look (`avatars/<id>-2d.png` beside the 3D one);
only a companion with no picture at all (a custom one) shows its drawn face on a disc.

### D55 — The add-on gallery: Ember, Kiko, Nimbo, Folio and nine extensions download on demand (2026-10-30)
*Amended by D84:* the Gallery is in Home, not Settings; D61 added Iris, Nori, Purl and Rune, D62–D69 more extensions.
**Decision:** Sidefolk keeps built in only what it needs: Mochi and Spark (3D and 2D), the robot, the folks (helpers,
D54), and four extensions (World Clock, Calculator, System Vitals, Weather). Everything else is an **add-on** in
the public repository `ghassenbrg/sidefolk-addons`: the companions Ember, Kiko, Nimbo and Folio, and the extensions
Git, Currency, Playtime, Images, PDF Tools, QR Codes, Archives, Dev Toolbox and Feeds. One repository holds every
add-on, Sidefolk's own and later anyone else's, each with its author; Sidefolk's own carry a seal ("Made by
Sidefolk", ids under `dev.sidefolk.`).
- **Packs.** `scripts/build.py` there wraps each add-on as a bundle, `<name>.sidefolkaddon/Contents/{Info.plist,
  Resources/…}`, signed as a whole with Sidefolk's Developer ID (codesign seals every file; extension programs are
  signed on their own too, with the hardened runtime), and zipped. The catalog is a pack of its own
  (`dev.sidefolk.addons.catalog`: `catalog.json` and previews). `scripts/publish.sh` uploads them to the
  `gallery` release, packs first and the catalog last.
- **What Sidefolk checks** (`AddonStore`): the catalog's and every pack's signature, strictly, against a Developer
  ID Application certificate of the team the app's Info.plist names (`SidefolkAddonsTeam`) and the exact
  identifier asked for; a pack's size and SHA-256 against the (signed) catalog, and its Info.plist's id and version;
  a companion's files are exactly its four (`characters/<name>.js`, `assets/<name>.glb`, `portraits/`, `avatars/`).
  Entries that are malformed or need a newer Sidefolk or 3D engine are left out. Downloads come only from
  `github.com` and GitHub's file hosts, as updates do (T31); the last good catalog stays for offline use.
- **A published version is never rebuilt.** A catalog is used for 30 minutes, so a pack replaced under the same
  name (a new signature alone changes its bytes) would no longer match the digest a copy holds. `build.py` keeps
  the release's pack of every version already published and stops when an add-on's files changed without a new
  version (each entry records a `source` digest); `publish.sh` skips packs already there. And when a pack doesn't
  arrive as its entry says, Sidefolk fetches the catalog again and, if the entry changed, the pack once more.
- **Companions** download when picked in Settings › Companion (dashed cards with the seal and the size), install
  into `<home>/Addons/Companions/<name>/`, and the 3D page reads them beside the app's own; Control-click removes
  one (the one in use gives way to Mochi). A companion chosen before it moved, or whose files went missing, is
  fetched again by itself at launch; Mochi stands in meanwhile.
- **Extensions** are listed in Settings › Extensions › Gallery (beside Installed). Get downloads and checks the
  pack, then opens the usual install preview; installed, they are origin `official`: first-party like a built-in
  (their descriptions, translated words and services count, D39 and D47), but the person's to remove, and updated
  from the gallery (Update), never by themselves. Built-ins an earlier version installed and this one doesn't ship
  stay installed and become `official` (`ExtensionHost.adopt`).
- **The AI** hears of Sidefolk's own extensions that aren't added, one line each, so it can say "Currency would do
  that; add it in Settings › Extensions › Gallery" (only official entries: their words are Sidefolk's).
**Why:** the founder wants companions and extensions outside the app so nobody carries what they don't use, a
place to browse and add them, and one repository for official and community add-ons. The DMG loses about 20 MB
(the four companions' models and pictures, and nine programs). *Signing with the Developer ID* rather than a new
Ed25519 key (docs/research/companion-marketplace.md): it needs no second secret, matches how updates are trusted
(D46, T31), and codesign already seals whole folders; a stolen GitHub account alone can't publish a pack that
passes. *Extensions keep the install preview* because one can act for the person; a companion only draws.
*Alternatives:* two repositories (sidefolk-companions, sidefolk-extensions) share everything but the folder;
a catalog JSON on raw.githubusercontent.com without a signature (anyone with the account could change it);
community 3D characters now (their character files are code: they wait for the data-only format, step 1 of the
brainstorm).
**Implications:** `AddonCatalog`, `AddonSource`, `AddonStore`, `AddonCodeCheck`, `ExtensionOrigin.official`
(`firstParty`), `ExtensionHost.adopt`, `SidefolkPaths.addons`, `ContextSources.inGallery`; app: `AddonGalleryModel`,
`GalleryExtensionsView`, `GalleryCompanionCard`, `CompanionAddons`, `Companion3DStage.has/file`; Info.plist
`SidefolkAddons` and `SidefolkAddonsTeam`; `SIDEFOLK_ADDONS=<folder>` points a non-release copy at a local build.
Tests of the moved extensions stay here and run against a built sidefolk-addons checkout beside this one
(`SIDEFOLK_ADDONS_REPO`), skipped without one; their pure logic tests moved there. SECURITY T33. Supersedes D51's
"Ember, Kiko, Nimbo and Folio … join the gallery" as built-ins, and D39's list of built-ins.
**Amended (2026-10-30, the founder asked how updates reach people):** a gallery companion on this Mac updates by
itself to the catalog's newer version (`AddonStore.updateCompanions`: a look 90 s after launch, then every six
hours), since a companion only draws; the one on the desktop swaps to it in place (a fresh 3D page takes over once
it has drawn: `CompanionWindowController.reload3D`). Extensions still wait for **Update** in the gallery: one can act
for the person. A version a copy can't run (`minimum_sidefolk`, `engine`) is left out of its catalog, so that copy
keeps what it has. Launch's `tidy()` now removes only what earlier runs left, so a companion coming back by itself
at launch is no longer cut off mid-download.

### D56 — The original robot is retired; the gallery gets shelves and search; other ways to add stay in sight (2026-10-30)
**Decision:**
- **The robot.** The original Sidefolk robot is no longer a companion: its vector rig (`RobotRig`, D2) is gone and
  `CharacterSpecies.sidefolk` with it; Mochi draws by default. `CompanionChoice.sidefolk` stays only so older
  settings read: one that chose it moves to Mochi, keeping a name the person gave it, and the robot's default name
  ("Sidefolk") now follows whichever companion is chosen.
- **Gallery shelves and search.** Each gallery extension names a shelf in the catalog (`category`: everyday, files,
  developer, fun; `addon.json` beside the manifest in sidefolk-addons); one this copy doesn't know shows under Other,
  and a malformed one drops the entry. Settings › Extensions › Gallery has its own search (name, tagline,
  description, author and shelf, ignoring case and accents) and a segmented row of shelves with counts; the list
  is grouped by shelf. A catalog fetched more than 30 minutes ago is fetched again when the gallery opens.
- **Other ways to add.** Install from Folder… and Add MCP Server… sit at the top of Settings › Extensions, beside
  the Installed / Gallery switch, on both pages; the samples stay under Added by you.
**Why:** the founder no longer wants the robot as a companion; asked for search and categories in the gallery;
and found the other ways to add an extension hidden at the bottom of the page.
**Implications:** `CompanionChoice.isRetired` (folks and the robot); `AddonCategory`, `AddonEntry.category/shelf/
matches`; `AddonStore.freshFor` 30 minutes. Supersedes D2 and D3's robot as a companion (the brand stays Mochi,
D29) and D27's robot choice.

### D57 — Your calendar on Today, read-only and off until you turn it on (2026-10-30)
*Amended by D97:* once the person allows changes, the Calendar adds, moves and deletes events through `calendar.create`,
`.update` and `.delete`, never events with other people invited.
**Decision:** Today's day line, Glance and the morning brief show calendar events beside reminders, read with
EventKit and never written. Nothing is read until the person turns it on, from the day line ("Show your
calendar") or Settings › Privacy › Calendar, which asks macOS for access. The AI sees events only through a new
`calendar.today` tool with effect `readsPrivateData`, checked by the Guard like any other tool; when it's off,
nothing is read.
**Why:** the redesigned Today is the shape of your day (D58), and a day without its meetings is half a day. Decided
by Claude at the founder's request (docs/research/themes.md section 5).
**Alternatives:** reminders only (the day line misleads); reading the calendar for the AI by default (private data
leaving without a choice).
**Implications:** built in step 6 of docs/research/themes-plan.md. `AppSettings.showCalendar` (off);
`CalendarReader` and `PlatformBridge.calendarEvents` (Core), `MacCalendar` (EventKit, full access, asked only from
the person's choice); `Capability.calendar` and `calendar.today`, which `AgentRuntime` offers only while the calendar
is shown; the morning brief lists events and reminders in time order. Info.plist's
`NSCalendarsFullAccessUsageDescription`, the hardened runtime's calendars entitlement, SECURITY T34. Glance's
events come with Glance (plan step 7).

### D58 — Themes: a theme is data, the app owns the layouts (2026-10-30)
*Narrowed by D84:* themes dress the app (colours, faces, density, materials); each place has one layout.
**Decision:**
- **What a theme is.** A theme is a `theme.json`, plus optional PNGs, that sets colour roles in light and dark,
  the heading face (system, rounded or serif), density, radii, motion, the sidebar material, the companion's nook
  and art. It also picks one of the app's own layouts ("recipes") for navigation, Today, Activity and the editor.
  It never carries code or wording.
- **The shared Home.** It's the same in every theme:
  - Now becomes Today, a decision queue answered from the keyboard;
  - the one bar (⌘K, and the Ask panel), which shows what it understood before ⏎;
  - the day line, watch tiles, agents at work, the companion's nook and Glance;
  - Activity rows that open in place;
  - notes that show where they came from, with stored links to conversations.
- **Approvals.** Another app's approval never takes ⏎ in any theme (the rule at `AppCoordinator.swift:562`).
- **Built in:** Harbor (the default and today's design), Night Shift, Marshmallow and Field Notes.
- **In the gallery:** Daylight, Night Studio and Paper Garden, as signed packs.
- **Community themes** install from a folder or file once they pass the validator, labelled as not reviewed, with
  their images re-encoded.

**Why:** the founder wants themes that serve different people, and wants anyone to be able to make one. Shared
recipes make each new theme only data. The reasons are in docs/research/themes.md and the build plan in
docs/research/themes-plan.md; the boards are local in `sandbox/theme-sandbox/`. The founder chose the built-in set from Claude's recommendation.

**Alternatives:**
- Colour-only themes (every theme the same layout, which is what the first brainstorm produced).
- Themes that bring their own views (code from strangers in the app).
- Renaming Activity to Journal (confused with the Notebook).

**Implications:** Step 1 is built:
- `ThemeTokens` (SidefolkCore) holds Harbor's values.
- `ThemeStore` (an observable `Mutex`, readable from any thread) turns tokens into SwiftUI colours, metrics and
  fonts.
- `Theme`'s names read the store, so call sites are unchanged.
- The brand palette and the logo plates (D36) stay fixed.
- All 232 UI snapshots are pixel-identical before and after.

The rest follows the plan's order.

Links between things (step 3) are stored, not guessed. An Activity row reaches its conversation through its run,
which every reply records in `meta.runId`, so no new column is needed. A note has `items.run_id` (migration
`v5-item-run`), written by `notes.save` and `profile.remember`. "Changed in" comes from `notes.update` and
`notes.trash` rows that name the note and ran. A deleted conversation links to nothing.

Step 4 renamed Now to Today in what people read (the sidebar, the menu bar, the Ask panel; code keeps `now`). Guard's
waiting questions join Today's queue, soonest deadline first, with `ApprovalRequest.expiresAt` set by the broker.
Keys answer only the queue row that has the keyboard, never a window-wide Return, and
`ApprovalRequest.mayApproveFromKeys` (Core) is the one rule for the queue and the Ask panel's card.

Step 5's one bar searches with `SidefolkRuntime.find` and sends words only through the Ask panel's path
(`AppServices.ask`: Return as today, ⌘Return asks the AI even what is understood without it, ⌥Return saves a note),
so nothing new can run a tool. The Ask panel keeps its own input (voice, drops, replies) and gains the same results.

Step 7 completes the Desk recipe. A page watch keeps its last change (`PageChange`, 2 KB) in its state for Today's
tile; agents at work show your companion's own run, sessions with their last call to Sidefolk, commands and sessions
finished in the last hour; the companion's nook sits in Home's sidebar. Glance is the Ask panel's idle state, not a
separate panel: one click on the companion opens it, with what needs you (answered there as on Today), the next
two things in your day, who's working and the way to Today.

Step 8 made a theme a file. `theme.json` (format 1) is read by `ThemeCheck`: an error (a missing id, a built-in's
id, text under 4.5:1, an image outside the folder, not a PNG or over 2 MB or 2048 px) stops it; anything else is
fixed on the way in and said (a missing colour is Harbor's, a value is clamped, an unknown layout is the one that
exists). Installing copies it into `<home>/Themes/<id>/` and decodes and writes every image again, so only pixels
are kept. A folder chosen in Settings, or made by "Start a Theme…" / `sidefolk theme new`, is followed: each save is
checked and, if usable, installed and painted within a second; if not, the last good theme stays and Settings lists
the problems. Harbor changed in three colours so it passes its own check: faint ink, a new `link` role for the
accent as text, and the danger red.

### D59 — Every companion also comes in 2D: painted cut-out parts on the vector rig, a real 2D look (2026-10-30)
**Decision:** all ten companions (Mochi, Spark and the gallery's Ember, Kiko, Nimbo, Folio, Iris, Nori, Purl, Rune) can
be shown in 2D or 3D (Settings › Companion › Look; 3D is how they come). The 2D look is set by one style target,
`companions-2d/references/lineup-2d.webp` (Codex image gen from the 3D portraits): a 2D cartoon, not a flat copy of the
3D models. Nine are **painted cut-out rigs**, as 2D animated series rig them: Codex image gen paints each character's
parts on a magenta sheet (blank-faced head, body, arms, ears, tail, feet), `companions-2d/parts/cut.py` keys and cuts
them, and the vector rig (D30) moves them: the head turns and tilts, ears and tails sway, arms raise for props, feet
splay; the eyes, mouth, nose and cheeks stay drawn live on top, so blinks, gaze, every expression and talking work as
before. Each part's vector outline, measured off the target in canvas units, places the painting, takes clicks and
anchors bubbles. Mochi keeps a flat vector drawing in the same look (the founder approved it). The engine gained
`Painted`/`Painting` (`Species.painted`), the flat look (`Shading.flat`, `Flat`) for vector parts, cartoon eyes with a
coloured iris and two catchlights, tails, hovering, a single lens eye, outward arms, shaped feet, and per-species eye,
mouth and cheek sizes. The gallery companions' 2D rigs and paintings are built into the app (760 KB of 256-colour PNGs
for nine); their packs still download when picked, and in 3D they keep running on their stand-in rigs. Nori comes
wearing the shared scarf in mint. The folks and custom companions keep the soft look.
**Why:** the founder wants each official character to have its own 2D form, light on the Mac, and found the old 2D
Mochi and Spark out of date. They asked that 2D not try to look 3D, stay smooth and alive, and match the style target;
hand-drawn vector parts fell well short of it ("they look very ugly"), and the founder pointed at image generation.
Painted parts give the target's quality, and keeping the rig keeps everything a single picture can't do.
**Alternatives:** vector-only parts (D30's way; far from the target's finish); a single painted image per pose or sprite
sheets (no gaze, props, morphing faces or follow-through, D30); shipping the 2D rigs as data in gallery packs (D43's
format can't say tails, hovering, single eyes or paintings yet, and packs would need a new file rule).
**Implications:** `SidefolkCharacter` has resources (`Art/<companion>/<part>.png`, found through `Bundle.module` in the
app's Resources); `CharacterSpecies.only3D` became `inGallery`; `CharacterLook.threeD` no longer forces gallery
companions into 3D; `CompanionChoice.dimensions` is `[.threeD, .twoD]` for all ten; `standardStyle` dresses Nori.
`sidefolk-render` compares every companion with its cut-out target (`overlay-<id>.png`). Asleep and lying down, a soft companion
is no longer squashed (a painted body would distort): it sinks onto its feet, which stay planted and come forward,
its head droops forward and aside (`Pose.headTilt`, `headDrop`; a body without a head leans and sinks as a whole),
its arms hang in front, its eyes close in plain ink over a small round mouth, and asleep its head nods with each
slow breath (until the loops settle, D20). How a 2D companion is made:
`companions-2d/README.md`.

### D60 — 3D companions added from a folder on this Mac; likeness faces (2026-10-30)
**Decision:**
- **Adding one.** A 3D companion made the gallery's way (`companions-3d/`) can be added without being published:
  Settings › Companion › Made by you › Add from Folder…. The folder must hold an `addon.json` (as the gallery's
  add-ons write it: `name`, `companion`, optionally `tagline`, `author`, `version`, `engine`, `body`) and exactly
  `characters/<id>.js`, `assets/<id>.glb`, `portraits/<id>.png` and `avatars/<id>.png`: no links, nothing else,
  each under a size limit and of its kind (glTF binary, PNG). An id that is one of Sidefolk's companions, or one
  the gallery installed here, is refused. Before anything is copied an alert says the character file runs as code
  in the 3D view and isn't from the gallery; once the person agrees it lands in `<home>/Addons/Companions/<id>/`
  beside the gallery's, its `addon.json` marked `fromFolder`, and it becomes the companion.
- **Wearing one.** `AppSettings.localCompanion` names it, worn instead of `companion` like a custom companion
  (D43); choosing any other companion clears it, and its name gives way like a built-in's. Under it runs the
  undrawn stand-in rig of a gallery companion of the same build (`body`: biped Kiko's, floating Nimbo's, card
  Folio's). Control-click removes one; the one in use gives way to the companion chosen before it.
- **The 3D page** takes only its own files: a Content Security Policy allows scripts, images and fetches from the
  `companion3d:` scheme alone, so a character file can't reach the network.
- **Likeness faces.** A face that is a person's, in the model's own texture, isn't drawn by the engine: the ink
  face gained `layout.lids` (painted lids close over the model's own eyes for blinks, squints and sleep),
  `layout.mouth.lips` (an opening mouth parts the model's own lips, with `colors.teeth`) and `layout.brow: false`;
  without `layout.eye` no 3D eyes are built.

**Why:** the founder made companions of themselves and Kana from their own sheets and wants them only on their
Mac, never in a repository or the gallery, yet working like the others; and asked that the faces look exactly
like the sheets, which drawn cartoon eyes and mouths can't.

**Alternatives:**
- A `CompanionChoice` case each (private names in the app's code, and a release for every new one).
- Unsigned packs through the gallery's install (the gallery's guarantee is its signature).
- 3D companions as data only (the character file holds shaders, moves and poses).

**Implications:** `InstalledCompanion.tagline/body/fromFolder`, `CompanionBody`, `AddonStore.readLocalCompanion`
and `install(companionFolder:)`; `CharacterLook.character3D`; `Companion3DStage` keyed by a character's name;
`CompanionArt.locals`. Debug: `swift scripts/dev.swift addCompanion:<folder>` and `companion:local:<id>`.

### D61 — Iris, Nori, Purl and Rune in 3D, made to their sheets (2026-10-30)
**Decision:** four more gallery companions (D55), from the founder's sheets: Iris (a toy camera whose one lens is
its eye; blinking shuts a brown lens cap), Nori (a tuxedo cat in glasses and a mint scarf), Purl (a stitched linen
ragdoll) and Rune (a pocket stone golem whose amber gem glows while it listens). Each is an add-on in
`sidefolk-addons/companions/<id>/` and a `CompanionChoice` case. The first models of Iris, Purl and Rune missed
their sheets and were made again: the bar is the sheet's turnaround, checked side by side with
`sheet.js turnaround()` before anything else.
- **Design images**: whatever the prompt puts on a face, Meshy sculpts (Iris's brow and smile came out in relief);
  and it rounds shapes off unless told what not to make (Rune's blocky head became a dome until the prompt said
  "NOT a dome, NOT a mushroom"; Purl's head was lopsided until it said "perfectly symmetric").
- **Textures**: Meshy packs its islands edge to edge, so a shrunk texture cracks pale along every seam;
  `rigkit.regutter()` repacks them with a margin and bakes the colour again (as light: a metallic material bakes
  black as diffuse). Colours are set by zone in the material, keeping only part of Meshy's shading, so its specks,
  crumples and copied patches go.
- **Parts colour can't find**: the rig marks them in the AO colour's green channel (`rigkit.mark()`), read by the
  material as `part` (Nori's black frames on charcoal fur).

**Why:** the first pass was rigged and wired but looked unlike the sheets (sculpted brows, a dome for a block, a
lopsided head, pale cracks, glossy fur over the glasses); the founder's bar is that a companion looks like its
sheet.

**Implications:** Iris's eye ignores the lower lid (`uLid.z`), so smiles don't cover the lens; Purl's arm weights
are everything past the body's sides, as the mitten tips curl off the arm's line. Raw models stay on Meshy (task
ids in `prompts.json`).

**Review, after the founder saw Nori move (2026-10-30):** stills are not enough; every move is now filmed from the
front and the side (`sheet.js filmstrip()`) and the surface checked close up (`closeups()`). That found a tail
weighted by distance to its bones' endless lines, which ran on through the back of the head (a flip pulled a
sheet of skin from behind an ear: `rigkit.seg_dist()` measures to the segment), feet that dragged the tail's root
along the floor, and colours Meshy put where the sheet has none (cream round the nape, torn paw and tail-tip edges),
which the material now paints by place. The texture probes read colour one gamma too bright (`lum` 0.46 there is
0.18 in the material): the materials' shading is normalised to the material's own values, so Purl's weave and
Rune's mottling are no longer flattened by their clamps. Faces: painted layers can be matte (`paintRoughness`;
glossier paint turns dark strokes grey on felt), a cat's mouth is a ω (`mouth.cat`), and `twinkle: false` drops the
idle twinkle cross the sheets don't have. Purl's linen is a procedural plain weave that fades below a pixel;
Rune's granite has a speckle from a high pass of the pile map. The same films of Iris, Purl and Rune found one
more: Iris has no neck, so looking round wrung the camera like a towel; `turnWhole` gives that share of the head's
and chest's yaw to the whole body.

### D62 — Extensions add pages: a page in Home, a tile on Today, heads-ups as switches; System Vitals+ first (2026-10-31)
**Decision:** an extension can add a whole feature, not only tools. `pages.<name>` in the manifest puts a page in
Home's sidebar (under Extensions), with an optional tile on Today (`widget`). The extension answers
`sidefolk/page.render {page, language}` with what is true (a summary and sections of parts: gauge, stat, chart, bars,
facts, note, ask); Sidefolk draws it with its own components, so a page follows the theme, dark mode and right to
left, and can't look like an approval card. Charts send only the value now: Sidefolk keeps their past
(`ExtensionPageHistory`, 15 minutes of every value then a day at one a minute), so extensions need no storage and a
chart isn't empty when it opens. Pages with `history` or `widget` are read once a minute while Sidefolk runs, which the
install preview says. Under each page the extension's watchers are switches (heads-ups): on, `watch.extension` runs
through the executor as the person, in repeat mode every five minutes, and the companion tells them. An `ask` part is
a button that sends a sentence to Ask, so it reaches the extension's commands or the AI through Guard like anything
typed. The gallery's `minimum_sidefolk` comes from each manifest's `sidefolk`. *Amended 2026-10-31:* Sidefolk
was to become 0.2.0 with pages, but the founder keeps snapshots on 0.1.0 until 0.1.0 ships, so it stays 0.1.0 and
extensions with pages ask `>=0.1`. A 0.1.0 snapshot from before pages lists them in the gallery and refuses to
install them (an unknown `pages` key) rather than skipping them; snapshots are for trying, so that is accepted.
- **Not tools, like watchers:** a page read is not a tool call, so a page open for an hour doesn't write 1,200
  Activity rows. It runs in the same sandbox as the extension's tools and can change nothing; what it says is shown
  only on its page and never reaches a model. Anything that acts goes through a tool (an `ask` button, a heads-up).
- **System Vitals+** (`dev.sidefolk.system-vitals-plus`, gallery, shelf Everyday) is the first: the whole Mac in plain
  words. Processor and graphics, memory and its pressure, apps grouped by app (a browser's helpers are the browser),
  disks, battery health against new, heat, network; a verdict on top with what to do; charts; eight tools with
  instant commands ("how's my Mac", "what's slowing my Mac"); seven watchers (working hard, an app using a lot, memory
  tight, hot, disk low, battery low, battery worn). Everything is read in the process (Mach, sysctl, the I/O Registry,
  each process's own counters): no internet, no files, no programs. System Vitals stays, small and built in.

**Why:** the founder wanted extensions that add whole features (screens, commands, ways to ask, the companion
speaking up), and a 360° view of the Mac that anyone understands. Extensions could only add tools and watchers.

**Alternatives:** a web view the extension draws in (any look, but it can imitate Sidefolk's own cards, ignores
themes, and needs its own sandbox story); history kept by each extension (every author writes the same store, and
it stops when the process idles); page reads as tool calls (an audit row every few seconds).

**Implications:** found while building it: an extension in the sandbox can list every process and read its CPU
time, memory and path (`proc_pid_rusage`, `proc_pidpath`), and read the I/O Registry, with no permission naming
it. System Vitals+ uses exactly that, so the install preview says nothing about it. Worth a SECURITY note and maybe
a permission of its own before third-party extensions are common. Page text is English only for now (`language` is
passed for extensions that want it); a Mac's fan speeds and temperatures need the SMC, which the sandbox closes, so
heat is macOS's own thermal state.

### D63 — Extensions that keep running and act: background, palettes, clipboard and power, switches; Clipboard and Keep Awake (2026-10-31)
**Decision:** extensions can now be features that run all the time and act for the person, with each new reach
named at install:
- **`background: true`**: the program runs while the extension is on (no idle stop, back after a crash, the crash
  limit still turns it off). The Kit reads stdin off the main actor so `ext.background { }` runs between requests.
- **`permissions.clipboard`** opens `com.apple.pasteboard.1`; **`permissions.power`** opens
  `com.apple.PowerManagement.control`. One Mach service each, nothing else. Clipboard tools are medium risk at least.
- **Palettes**: a list on a keyboard shortcut in a non-activating panel (the app in front keeps focus), filled by
  `sidefolk/palette.query`, acted on by `sidefolk/palette.choose` (`choose`, `plain`, `pin`, `delete`). When the
  extension says `paste`, Sidefolk presses ⌘V. The shortcut is changed on the extension's page.
- **Switches and buttons** on pages run the extension's own tools as the person, through Guard.
- **Nudges**: `sidefolk/nudge`, honoured only for `permissions.power` and at most every 20 seconds: Sidefolk posts a
  pointer move of nothing. Pasting and nudging need Accessibility for Sidefolk; the page asks for it.
- **Clipboard** (gallery): history of text with formatting, links, pictures, files, code and colours, ⇧⌘C (Maccy's
  shortcut, so muscle memory carries over), pins, plain-text paste, search, answers ("what did I copy"), pause and
  clear. Better than its model: copies marked concealed or transient (password managers) are never kept; anything
  that looks like a key, token or card number is masked, kept only in memory and forgotten after two minutes; Ask
  can find "the address I copied yesterday" and save it to notes.
- **Keep Awake** (gallery): a macOS power assertion (what `caffeinate` uses) for minutes, hours, until a time, while
  an app is open, or until stopped; the screen kept on or not; "keep me active" for chat apps by nudges, only while
  the person is idle 45 s, about once a minute with jitter; lets go on battery or under 15%; tells when it ends by
  itself. Better than a mouse jiggler: nothing moves on screen, it never fights the person's own pointer, and it ends.

**Why:** the founder wanted to drop Maccy and Mouse Jiggler for Sidefolk extensions that do more.

**Found while building it:** `IOPMAssertionDeclareUserActivity` doesn't reset the idle time apps read
(`HIDIdleTime`, `CGEventSource`), measured on macOS 27; a zero-distance mouse event does, but only from a process
with Accessibility, so Sidefolk posts it, not the sandboxed extension. Launch Services (`com.apple.coreservices.
launchservicesd`) would tell an extension which app is in front, but also lets it open apps and links (a way out of
the sandbox for what it read), so it stays closed: Clipboard knows a copy's app only when the app names itself on
the clipboard, and Keep Awake finds open apps from the process list.

**Alternatives:** Sidefolk building these in (they are what extensions are for, and others can now build the
like); a jiggler that really moves the pointer (visible, fights the person); palette results through tool calls
(an audit row per keystroke); keeping secrets on disk briefly (a crash would leave them).

### D64 — A theme arranges the app's own pieces: Today as blocks in rows and columns (2026-10-31)
*Superseded by D84:* themes no longer arrange Today; the layout keys still decode, and only `layout.icons` is read.
**Decision:** a theme no longer picks one of a few fixed screens ("recipes"). Today is rows of columns of **blocks**,
each one of the app's own pieces in one of its styles, and a theme's `layout` says where each goes and how it looks:
- **Blocks and styles:** header (line, large, console, page), queue (rows, cards, stack, index), day (rail, list,
  compact, stickers, ruled), watching (tiles, list, signals, badges, margin), agents (rows, card, steps, helpers),
  recent (rows), notes (cards, chips), art (tile), companion (stage, sticker). A column has a width (its share) and
  may be drawn on a sheet of paper (`page`); columns sit side by side while each gets its least width, else stack.
- **Around Today:** navigation (sidebar, rail with a status bar, pills, ribbons), where the nook sits (top, foot, or
  none when the layout gives the companion a block), Activity (table, log, diary) and the editor (rich, or Markdown
  with tabs, references and an outline).
- **Presets** are layouts written the same way: desk (Harbor), board (Daylight, Night Studio, Paper Garden), console
  (Night Shift), stage (Marshmallow), planner (Field Notes). A theme names one and changes what it likes.
- **Rules the check keeps:** only what the app draws is accepted (anything else is left out or replaced, and said);
  what needs you always has a place (a queue, or a stage that speaks it); a block appears once; at most 8 rows and 4
  columns. `extension:` blocks are reserved for extensions and refused for now.
- **Data behind the boards:** recent values of live reports (a sparkline, memory only), each agent's last calls to
  Sidefolk, reminders done today, the newest notes, and the one bar's plan (`IntentPlan`: the action, its parts, the
  tool and its risk, from the same parse that runs it).
- **Where themes come from:** Harbor in code; Night Shift, Marshmallow and Field Notes in the app's
  `Resources/Themes`; Daylight, Night Studio and Paper Garden as signed packs in the add-on gallery (D55, kind
  `theme`), installed through the same check with images re-encoded. Only Sidefolk's Resources and signed gallery
  may use ids under `dev.sidefolk.`.

**Why:** the founder asked for themes as faithful as their boards, content and components included, and for a
flexible UI where a theme decides where things go and how, with extensions joining later, not a fixed Home in
different skins. Blocks keep every action going through the same models and `ToolExecutor`; a theme still carries no
code and no words.

**Alternatives:** whole-screen recipes per theme (step 9's first plan: each new arrangement needed new code and
couldn't be mixed); themes shipping their own views (code from strangers).

**Implications:** first committed as D62 (0fb13ff0), renumbered: D62 and D63 were taken by the extensions work.
`docs/research/themes-fidelity.md` lists each board's elements against the app. Older copies of Sidefolk skip the
gallery's theme entries (entries decode one by one). Not built: chips you can edit with Tab in the one bar, a progress
bar for runs (no run reports progress yet), and blocks from extensions.

### D65 — Extensions have snapshots until they're released, as Sidefolk does (2026-10-31)
**Decision:** a gallery extension is in snapshots until the founder releases it. Its manifest names the version it's
heading for (`1.0.0`), and sidefolk-addons' `build.py` publishes it as `1.0.0-snapshot.<n>`: n rises each time its
files change, and the published pack stays while they don't. Writing `"released": "1.0.0"` in its `addon.json`
releases it: the next build publishes plain `1.0.0`. From then on 1.0.0 is fixed (files changed means raise the
version, as before), and the next version (`1.1.0`) starts its own snapshots. All twelve extensions began at
`1.0.0-snapshot.1`, including those already published as 1.1.0 or 1.2.0. Companions and themes too (amended below).

**Why:** the founder treats extensions like the app, which is still in 0.1.0 snapshots: no extension is released
yet, so it shouldn't need a new version number for every change while it's being made.

**Implications:** Sidefolk needs no change: `ReleaseVersion` already reads `1.0.0-snapshot.3`, orders snapshots by
number and a release above them, and offers each as an update; 0.1.0-snapshot.489 does too. The pack's manifest
carries the snapshot version, so what's installed compares with the gallery. A copy that installed currency 1.1.0,
dev-toolbox 1.1.0, git 1.1.0, playtime 1.2.0 or qr-codes 1.1.0 keeps it and isn't offered the 1.0.0 snapshots
(they're lower), until it removes and reinstalls it. *Superseded by D80:* such a copy is offered the gallery's version.

**Amended (2026-10-31): every add-on, and the gallery follows Settings › Updates.** Companions and themes are
snapshots until released too, by the same `"released"` in their `addon.json`; all eight companions and three themes
went out as `1.0.0-snapshot.1`, and a theme's packed `theme.json` carries that version (Sidefolk compares an
installed theme's own file with the gallery). The gallery follows the person's choice in Settings › Updates, as
Sidefolk's own updates do (`UpdateChannel.includes`, the founder's call): on Releases (the default, D52) it shows,
offers to update, and updates companions by themselves to, released versions only, and the AI hears only of those;
on Releases and snapshots, snapshots as well. One catalog serves both: the app filters (`AddonCatalog.offered`).
While a gallery list hides snapshots it says so, with **Show Snapshots**, which turns on snapshots in Settings ›
Updates (Sidefolk's own included, as the note says): on the default, nothing is released yet, and an empty gallery
would look broken. An add-on already installed stays and runs whatever its version; on Releases it waits for its
release. A copy that installed a companion or theme as plain 1.0.0 keeps it, as with the extensions above.

**Amended (2026-10-31): a release stays beside the next version's snapshots.** Otherwise the first add-on released
and then changed would vanish from Releases: the catalog listed one version per id, so `1.1.0-snapshot.1` replaced
`1.0.0` and publish.sh deleted its pack. `build.py` now keeps an add-on's latest release, its pack byte for byte,
listed first, while its next version is in snapshots, and stops if the snapshots aren't of a higher version.
`AddonCatalog` keeps every version of an id (one per version) and picks per choice: `entry(_:on:)`,
`companion(_:on:)` and `offered(on:)` give the newest version the channel takes, so Releases gets the release and
snapshots the snapshot. A pack fetched again stays the same kind (a release isn't swapped for a snapshot). A chosen
companion that comes back by itself is the release on Releases, or the newest when none is released. Copies from
before this read the first entry of an id, which is the release.

### D66 — A Calendar of everything with a time, and a time is typed or picked (2026-10-31)
*Amended by D97:* Day, Week, a scrolling Month, Year and Agenda, in the calendars' own colours, with the Mac's events
changeable through Guard.
**Decision:** Home gets a Calendar page (⌘5, under Today in the sidebar, last in the rail, pills and ribbons so ⌘1–4
keep their places): a month, a week (an hour grid placed by the clock, overlaps side by side, an all-day row) or a list
of 14 days. It shows pending reminders, a repeating one at every time it will fire (`ReminderScheduler.occurrences`,
capped per reminder), the notes and tasks those reminders belong to (D49), what was done or told on past days, and the
Mac calendar's events while they're shown (D57, read-only). Every change goes through Today's paths: moving is
`moveReminder` (with ⌘Z), adding is `reminders.create` through `ToolExecutor`, editing, ticking, snoozing and opening are
NowModel's. Wherever a time is set, `WhenField` keeps typing first with a picker beside it (⌘↓; a month, a time, quick
times); picking writes an ISO date and time on the person's clock, which the existing `WhenParser` reads in every
language, and the reading is said back under the field ("Tomorrow, 9:00"). Places that only had a picker (the
Notebook's reminder sheet, Ask's Pick…) gained the field.

**Why:** the founder asked for one screen with everything that has a due date, and for the classic date and time
picker beside typing, for people who prefer to click. Reusing the scheduler, models and executor means the Calendar
can't show or do anything the rest of the app wouldn't.

**Alternatives:** writing to the Mac calendar (D57 keeps it read-only); a due date of its own on notes
(`NotebookItem.dueAt` exists but nothing sets it; reminders carry a note's time); localized words in the field (the
parser reads English and ISO, and a second parser would disagree with the one that sets the reminder).

**Implications:** found on the way: `WhenParser` read an ISO date's year in the person's calendar (a Buddhist or
Japanese calendar put "2026-11-03" centuries away, the Notebook's ISO times too); ISO years are now Gregorian. Your day
(`DayLine` in Core) now starts every chip at its time instead of sliding it left inside the line, keeps an hour after
the last thing and labels hours so none touch; `WrapRow` puts a row's button under its words in a narrow column.

### D67 — Extension pages fill the window and are the person's to arrange; a main switch where people are; Your Mac; icons simple or colourful (2026-10-31)
*Amended by D84:* the All Extensions page is gone; pages put out of the sidebar are one menu row.
**Decision:**
- **Layout:** an extension page lays out by what it holds: numbers, several cards, notes alone or buttons alone run
  across; other sections sit 2–3 to a row; cards share their row's size. Rich pages grow to 1320 pt, centred; pages of
  switches stay 860 pt.
- **Arranging:** Home's Extensions group folds; its pages are dragged or moved, hidden from the sidebar (they stay in
  All Extensions) or have their tile taken off Today (`AppSettings.homePages`, so it follows `SIDEFOLK_HOME`). **All
  Extensions** (`.page("/")`) lists every page with its state, main switch and where it shows. Rails show the arranged
  pages; pills show them as icons; ribbons one All Extensions ribbon.
- **Main switch:** a page summary may carry the extension's main switch or button (`summary.control`, Kit
  `Summary(control:)`), shown on the page, its Today tile and its sidebar row, and run as the person through Guard.
  An on/off feature uses that with `widget` rather than relying on a page; Keep Awake does.
- **Your Mac:** System Vitals+ is named Your Mac (same id, its own icon). While Sidefolk's own Your Mac is on,
  Sidefolk's own System Vitals rests (`ExtensionOverlap`): its tools and commands aren't registered, it offers no new
  heads-ups, Settings says why, and it comes back by itself. Only between first-party extensions.
- **Icons:** themes say `layout.icons: simple | colorful` (Marshmallow colourful); Settings › General › Icons in Home
  overrides. Colourful draws the places as white glyphs on rounded tiles and extension pages with their own icon.
  `ExtensionBadge` is the one extension icon everywhere: continuous corners (22.5%), a hairline, a soft shadow from 24 pt.

**Why:** the founder found Your Mac using half a wide window, asked how to manage many extension pages and why Keep
Awake couldn't be turned on from Home, found the "+" didn't say System Vitals+ was the bigger one, and asked for real,
rounded icons as an option.

**Alternatives:** a manifest `quick` control (a second place for state the page reports); a manifest `includes` key
(any extension could silence another); turning System Vitals off at install (saved state, a surprise on removal); a
theme token or a setting alone for icons (one side couldn't choose); separate icon code per screen (drift).

### D68 — Clipboard replaces Maccy: pictures, a preview, Maccy's keys and settings; palettes and pages grow for any extension (2026-10-31)
**Decision:** palette items may name a picture: a PNG or JPEG the extension wrote in its own data folder, named
relative to it. Sidefolk reads it without following links (`ExtensionDataFile`: the opened file must be inside that
folder, one link, at most 4 MB for a row and 25 MB for a preview) and only draws it. A palette may offer
`sidefolk/palette.preview` (the picked item in full beside the list) and list actions (`clear`, `clear_all`, asked
twice); items may carry `color` and `section` and an `alternate` action. Maccy's keys work beside Sidefolk's (⌘1–9,
⌥↩, ⇧↩, ⌥P, ⌥⌫). A palette opens at the top, the pointer or the middle, or under the menu bar icon from its menu.
Pages get `choice`, `field` and `list` parts, run as the person through Guard. With the clipboard permission an
extension may ask which app was in front for the copy just made (`sidefolk/clipboard.source`), answered once per
clipboard change. Clipboard uses it all: pictures and screenshots with thumbnails made once, formatting in files,
duplicates by digest, 100–5,000 copies, three orders, pins top or bottom, four ways to search, ignore apps, patterns
and types, skip the next copy, paste or only copy. D63's protections stay (concealed copies never kept, secrets masked
in memory and forgotten after two minutes).

**Why:** the founder wanted to uninstall Maccy; Clipboard had no pictures, no preview and almost no settings.

**Alternatives:** pictures inlined in replies (megabytes per keystroke for 200 rows); Sidefolk making Quick Look
thumbnails of paths an extension names (it would read any file an extension points at); Launch Services for the
source app (it also opens apps and links, D63); pushing every app switch to the extension (it would learn the
person's app use); settings as manifest keys (older 0.1.0 snapshots refuse unknown keys).

**Not built:** Maccy's random letter per pin, app icons in rows, highlighted matches, the latest copy in the menu bar
title, clearing on quit.

### D69 — Extensions that record the screen and stream on the network; Miraya as an extension (2026-10-31)
**Decision:** three permissions, each named with caution at install:
- **`permissions.screen`** opens ScreenCaptureKit (`com.apple.replayd`, `com.apple.windowserver.active`) and the video
  encoder (`com.apple.coremedia.videoencoder`). It raises every tool to medium risk at least, and with the network the
  sheet warns that what's on screen could be sent elsewhere. macOS attributes the recording to Sidefolk, so the grant in
  Screen Recording is Sidefolk's and this permission is the gate between extensions.
- **`permissions.udp`** (only with `network`) allows binding and receiving UDP, which WebRTC needs.
- **`permissions.network_purpose`** (only with `network`; one line starting "to" or "for", ≤ 120 characters) is added
  after the network line, never instead of it: "Can use the network, the internet included. It says it uses it to …".
A process started for one call runs no background work (`SIDEFOLK_ONE_CALL`). Gallery extensions may ship linked
frameworks in `lib/`, signed by the same team. **Miraya** (gallery, Everyday, named and drawn as Miraya's own app) is
Miraya's Mac side in the sandbox for its unchanged Android TV app: TVs found by name, pairing by a six-digit code,
mirroring a display, a window or an area preset with sound over WebRTC, five quality presets, a file or HTTPS link
played on the TV, a page, a Today tile, tools with instant commands and two heads-ups. A file to play is cloned into
its data folder by the call's own process (the per-call file grant) and deleted on stop.

**Why:** the founder wants Miraya without installing its Mac app. Measured on macOS 27: ScreenCaptureKit hangs without
the two services; VideoToolbox encodes nothing without the encoder; `network` alone refuses a UDP bind; the sandbox
can't be limited to the local network (only `*` or `localhost` compile), so the sheet says "the internet included"
even though Miraya only talks to the LAN (the founder noticed "uses the internet" and asked that it not mislead);
macOS 27 adds Sidefolk to Screen Recording switched off instead of asking, and Miraya says where to turn it on.

**Alternatives:** Sidefolk capturing for extensions behind a host API (keeps the grant usable only through Sidefolk;
a frame and audio pipe across processes, maybe later); an unsandboxed helper (outside the model); a `localNetwork`
permission (untrue: the sandbox can't enforce it); a fixed `files.read: ~/Movies`; the older media-over-TLS path
instead of WebRTC (the TV app and Miraya's tests favour WebRTC).

**Not built:** sound on the TV only (CoreAudio's `audiohald` stays closed), a drawn capture area (needs a picker
Sidefolk draws), keeping the Mac awake while sharing, a Stop button on the Today tile. Pairings live in a 0600 file in
its data folder (the sandbox has no Keychain). SECURITY T36.

### D70 — Sidefolk and its add-ons update on separate choices; Sidefolk may install itself at a calm moment (2026-10-31)
**Decision:** *amends D46 and D55.* Settings › General › Updates holds two independent choices, and "Versions to
offer" (D65) applies to both.
- **New versions of Sidefolk:** Don't check / Tell me (the default; D46 as it was) / Install automatically
  (`UpdateSettings.app`, `AppUpdateMode`). Automatic uses the same looks and channel, and downloads and checks
  exactly as Update does (`UpdateInstaller.prepare`: size, both checksums, bundle id, release, Developer ID of the
  same team, notarization, the staged copy checked again), out of sight. The checked copy then waits beside the app
  for a calm moment, `InstallMoment.decide`: never while a request to the AI runs, an approval card waits, voice is
  on, the Ask panel is open or a `sidefolk run` job is going; and only once the person has been away five minutes
  (no input). A ready copy is looked at every 30 s; quitting puts it in place without reopening
  (`UpdateInstaller.installAtQuit`), so the next launch is the new version. The new copy says "Updated to Sidefolk …"
  once, with What's New (its release page), from a mark written just before the swap
  (`UpdateState.installedByItself`). A copy that can't replace itself (D46's cases), and any failure on the way,
  falls back to telling, with Skip This Version; a version that failed isn't tried by itself again until relaunch.
  The window, the menu bar and Settings show it ready with Restart Now.
- **Update add-ons automatically** (`UpdateSettings.addons`, on by default): companions, themes and extensions from
  the gallery, looked at 90 s after launch, every six hours and a few seconds after the switch or the channel changes
  (`AddonUpdater`, `AddonUpdateController`). Companions and themes install by themselves (a companion only draws, a
  theme is data, both checked as the gallery checks them). An extension installed from the gallery (origin
  `official`) installs by itself **only if its update widens nothing** (`AddonUpdateRule`,
  `ExtensionUpdateDiff.widens`): no permission it didn't have, judged on `ExtensionPermissions` itself (a new flag,
  file path, program, or folders read→write) rather than on the sheet's wording; no tool riskier than before (a new
  one above its riskiest tool, or one it had, raised); no `background`. Otherwise it waits for review, whatever the
  switch says: Settings › Updates lists it with Review…, which fetches it and opens the install sheet ("New
  permission: …"), and one gentle heads-up comes per version. An extension that was off updates and stays off.
  With the switch off nothing installs by itself: Settings says how many updates wait (Update All, which follows the
  same rule), the gallery keeps Update for extensions and themes, and a companion with a newer version gets an
  update mark on its card and "Update … to …" on Control-click.
- Settings from before this decode as they were: `automatic: false` is Don't check, `true` Tell me; `automatic` is
  still written for older snapshots. What happened is in the log (`"cat":"updates"`, `"cat":"addons"`), and the last
  add-ons updated by themselves are named in Settings › Updates. Activity stays the record of tool calls.

**Why:** the founder wants to choose separately: add-ons updating by themselves but not the app, or the opposite.
*Add-ons on by default* because companions already updated by themselves (D55) and turning that off for everyone
would be a step back; extensions join them only within what the person already agreed to, so the default costs no
consent, and every pack is signed by Sidefolk's Developer ID and checked as before (T33). *Sidefolk stays on Tell me*
because installing restarts the companion, Sidefolk is in snapshots whose notes the person may want to read first
(D52), and D46 promised to ask. *A calm moment rather than a schedule* because the person's work is in the app (a
conversation, an approval, a dictation); away for five minutes is the longest wait that still lands within a day for
most people, and the quit catches the rest.

**Alternatives:** one switch for both (the founder asked for two); installing at the next launch instead of at quit
(the staged copy is tidied at launch, and a launch is when people want the app at once); judging "widens" by the
sheet's lines (a narrowing adds "No access to your files or the internet", a new network reason adds a line);
silent extension updates whenever signed by Sidefolk (the permission is the person's, not the signer's); updates
in Activity (it is the audit of tool calls; an update is not one).

**Implications:** `UpdateSettings.app/addons`, `InstallMoment`, `UpdateChecker.markInstalling/takeInstalled`,
`UpdateInstaller.installAtQuit` (`BundleSwap.relaunch` takes no app to open), `UpdateModel.Phase.ready`,
`ExtensionUpdateDiff` (own file: `riskierTools`, `widensPermissions`, `startsInBackground`, `widens`),
`ExtensionPermissions.widens`, `AddonUpdater`, `AddonUpdateRule`, app `AddonUpdateController` (replaces
`keepCompanionAddonsUpdated`), `AppServices.companionsUpdated`, `AppCoordinator.installSignals`; dev commands
`update:ready`, `update:updated`, `addons:review|waiting|clear`, `scroll:<0…1>`. RELEASE.md › Updates.

**Amended (2026-10-31): "Check for Updates…" checks the add-ons too.** It fetches the gallery's list again rather than
the one kept for half an hour, then looks as the timed check does (installs what may install by itself, lists what
waits). Miraya was published minutes after the founder's copy had kept the list, and nothing could make it look sooner.

*Amended by D89:* waiting updates are shown wherever add-ons appear (the Gallery's Updates, an extension's page,
Settings › Add-ons, Home's sidebar, Today, the Pocket) with Update all, and a whisper after a day.

### D71 — Install sheets and approval cards that are honest without being scary: trust first, tone by source, guards beside each permission (2026-10-31)
**Decision:** the same facts for every extension, said as loudly as where it comes from calls for.
- **Where it comes from, first** (`InstallSource`, a row under the title): *From the Sidefolk gallery · Signed by
  Sidefolk and checked before install* (D55's signature and digest checks), *From a folder on this Mac · Not checked
  by Sidefolk: install it only if you trust who made it*, *Written by Sidefolk for you · Sidefolk's AI wrote it at your
  request, and nobody else has read its code*.
- **Tone by source, never facts** (`InstallReview.tone`): the risky combinations (`PermissionSummary.warnings`, words
  unchanged) are a red box headed *Read this before installing*, above the permissions, for anything but code Sidefolk
  signed as its own; for a gallery extension with Sidefolk's id (`AddonEntry.isOfficial`) the same sentences sit in a
  calm *Good to know* box after the list. A draft stays strong: nobody read the code.
- **What guards each permission, beside it** (`PermissionSummary.Line.note`), only where the code enforces it: a
  folder named per call is one the person shared or allows on a card, opened by the sandbox for that request
  (`ExtensionTool.run`, `PermissionEngine`; extensions and other agents can't ask); recording needs Sidefolk switched
  on in Screen & System Audio Recording, *and that switch covers every extension that records* (T36); a program
  Sidefolk found may start only its own helpers. *Can't use the internet* is listed when files are and the network
  isn't. The network line gets no note: nothing keeps it to the LAN (D69).
- **After you install** (`InstallReview.next`): it runs in a sandbox limited to the list; a background extension
  *keeps running and can use all of this by itself, without asking each time* (D63: no card covers that); Guard asks
  before the AI or another agent uses its tools as often as the person chose, or, when every tool is below the floor,
  that they can't reach the internet or change files (`ExtensionRisk`); network with UDP: macOS may ask about Local
  Network; turn off or remove in Settings › Extensions.
- **Progressive:** what it adds (tools, commands, pages) folds under *It adds*.
- **Updates** (`InstallReview.Update`): one asking for more is a box of its own, *This update asks for more*, with
  each *New permission:* in bold, amber for Sidefolk's own and red otherwise; one that doesn't says *No new
  permissions*; removed ones are listed.
- **Approval cards** (the founder's Full-access "mirror my screen to the living room TV"): Guard's decision is
  unchanged (after outside content, Full access never answers a call that could carry it out, T2, T12, T21). The card
  now says an extension call's arguments in words (`ArgumentWords`: `tv: “living room”`, hidden characters gone, long
  values clipped, full paths as ~/…) with the exact request under *Exact request*; and why it asks
  (`ApprovalReason`): what the run read first (`TaintSource`, kept by `BrainToolbox` from the first untrusted result:
  an extension by name, a web page, a file, or "outside content"), what this call could do with it (from its effect),
  and, in Full access or Auto (medium risk), that the mode never decides this after outside content. Calm when
  Sidefolk's own extension acts on Sidefolk's own extension's answer, red otherwise. Another app's request (evaluated
  as tainted to ask each time, T4) says so instead of claiming something was read. "Always allow" stays not offered.

**Why:** the founder, installing his own Miraya, was scared by two red warnings and unsure what install grants. People
must know what an extension can do, and Sidefolk's own signed extensions shouldn't read like malware, nor unknown
folders like Sidefolk's. Severity follows what Sidefolk can vouch for (who wrote and signed the code), and each claim
names a guard the code enforces. Every claim was checked in the code: per-call grants (`ExtensionTool`,
`PermissionEngine`), the risk floor (`ExtensionRisk`), page buttons running as the person (no card), background work
without cards, macOS attributing recording to Sidefolk (T36).

**Alternatives:** dropping the combinations for official extensions (hides a real capability); "records only when you
start sharing" (Miraya's behaviour, not something Sidefolk enforces: its background process could); a per-call
mode-aware sentence on the sheet (the mode can change after install); a Miraya-specific sentence in the app for its
cards (couples the app to a gallery add-on; arguments in words serve every extension).

**Implications:** `InstallSource`, `InstallReview`, `PermissionSummary.Line.note`, `AddonEntry.isOfficial(id:)`,
`ArgumentWords`, `TaintSource`, `ApprovalReason`, `ApprovalRequest.input/taintedBy/mode/firstParty`,
`ToolOutcome.source`, `ToolExecutor.execute(taintedBy:)`; app: `ExtensionInstallPreview.review`, `InstallReviewParts`,
`ApprovalReasonLine`, `ExactRequest`; snapshots `sheet-install-gallery|unknown|update`, `desktop-ask-outside`.
A future community shelf in the gallery gets the strong tone (only `dev.sidefolk.` ids are calm). MCP servers keep
their own add sheet, already "only add servers you trust". SECURITY T1, T13, T33.

### D72 — A TV the person paired is their own destination: no card for it after outside content in Auto and Full access (2026-10-31)
**Decision:** amends D37, D47 and D69. A tool of Sidefolk's own extensions (origin `bundled` or `official`) may declare
`"reach": "paired"`, with `"device"` naming the parameter that names the device (none: the device in use now). For
Sidefolk's own agent, after the run read outside content, in Auto or Full access, Sidefolk asks the running program
`sidefolk/paired.check` with only those words, before Guard decides. When it names a device the person paired,
Sidefolk binds the call to that device's id (the parameter becomes the id) and Guard answers it: Full access always,
Auto unless high risk (Activity: a **Paired device** chip in the mode's colour, its details naming the mode). "Ask every time" and
"Ask once per kind" ask as before; a clean turn, typed commands, other callers, and anything not confirmed (not
paired, no answer within 5 s, someone else's extension, a copy installed from a folder) are unchanged. A call that
also carries a link the person didn't type, a file outside a folder the person allowed in a card for that very call, a
program, a file change or text to read in full keeps its card. Miraya declares it on share_screen and play_on_tv (the
`tv` parameter) and on stop, pause, resume, seek and tv_volume (the TV in use; nothing playing reaches no device, and
stopping gives a TV nothing). Its check finds the TV exactly as the call does and names it only when it's in its trust
store; a paired TV now comes before any other device the same words fit, including when no TV is named; a call bound
to an id reaches only that pairing; and the connection still demands the pinned certificate before the token or any
picture is sent.

**Why:** the founder: "mirror my screen to the living room TV" in Full access still showed a card, because the run had
first read Miraya's TV list (names come from the network), and D37 never lets Full access hand input to an extension
after outside content. A TV the person paired (six digits compared on both screens, Allow on the TV, its key pinned)
is their own destination, like an address they typed: an injected instruction can at most put the screen on the
person's own TV. A new TV still asks.

**Alternatives:** reading `tvs.json` in Miraya's data folder through the safe reader (Sidefolk would have to repeat
Miraya's name matching, which depends on what Bonjour shows now, and own its file format; asking the program that will
make the connection keeps one lookup, and binding the call closes the gap between the check and the call); trusting
any extension's declaration (the sandbox can't hold a program to it, D47); honouring the extension's "Always allow"
after outside content in "Ask once per kind" (D47's rule would allow it, but the founder asked about Full access and
Auto; it can follow); passing the whole call to the check (the program would hear arguments before Guard decided).

**Implications:** `NetworkReach.paired(device:)`, `Tool.confirmReach`, `ExtensionTool.PairedDevice`, `PairedAnswer`,
`ActivityEntry.Decision.fullAccessPaired`/`autoModePaired`, manifest keys `reach` and `device` (an older Sidefolk
refuses the manifest, as with D69's permissions), the Kit's `ext.paired`. *Residual:* in Auto and Full access an
injected instruction can show the screen, a window or a video the person allowed on their own paired TV, or stop,
pause or seek it there. If an official program lied about pairing it could stream anywhere anyway (it records the
screen and has the network), so its word adds no reach. SECURITY T2, T21, T36; EXTENSIONS › A device the person paired.

### D73 — The helper folks follow the approved redesign (2026-10-31)
**Decision:** the ten on-duty helper folks use paintings cut from the founder-approved reference in
`folk-family/redesign-2026-10-31/`. Their existing helper roles, accessibility labels, placement, and
whole-body entrance, exit and breathing remain. The vector drawing is retained as a fallback and for
the resource-free plain version; the selectable companions are unchanged.
**Why:** the founder approved the new silhouettes and asked for the current helpers to match them.
*Amended 2026-11-03:* the paintings are no longer cut from that white sheet, which left white patches under their
feet and around small props. All ten are generated transparent from the start, with the reference as their likeness,
and they stay the same size in the same canvas with the same floor line. The founder's rule: never generate on a
background and cut it out afterwards. The loose marks (notes, sparkles, steam) are gone, since that's where leftovers hid.

### D74 — Extension pages read like app screens: a hero, one primary action, choices as pictures, cards and rows; Miraya rebuilt on them (2026-10-31)
**Decision:** pages get what a well-organised app screen needs, for any extension, still drawn by Sidefolk from data
(D62):
- **`hero`**: what the page is about now (an eyebrow with the state, a large title, a line, a large `code` to compare, a
  picture from the data folder, a spinner, up to four live facts, up to three actions drawn large). First on the page,
  it takes the summary banner's place there; the summary still makes the Today tile and sidebar row.
- **Emphasis**: one primary button a page. `ExtensionPage.parse` keeps the first primary in reading order (the summary's
  control first when the banner shows it) and turns later ones `secondary`. Primary is filled and larger; destructive is
  filled red when nothing on the page is primary; new `plain` is quiet accent text; any button may be `disabled` with a
  `detail` saying why.
- **`choice` styles**: `cards` (2–6 presets with a line each), `tiles` (1–24 pictures: displays, windows) and `rows`
  (1–24 devices or accounts with a badge and a small action each), plus `key` (where the value goes) and `disabled`.
- **`transport`** for something playing (position, duration, state, up to five round symbol buttons).
- **Sections** may go in a side column at the start edge in a wide window (`place: side`) and fold under their title
  (`collapsed`). The rules of what goes where moved to SidefolkCore (`ExtensionPage+Layout.swift`), tested there.
- **Miraya** is rebuilt on them, a page per state like its Mac app: no TV (Look again and an address field), ready (the
  hero names what goes where with Start sharing; TVs as rows, paired, new or off, the one chosen ticked; what to share as
  a screen, a window or part of a screen, each a picture; quality as five cards; sound a switch; more settings and
  playing a link folded), pairing (the code large, Codes match the primary), waiting for Allow, connecting, sharing
  (what's shared, its picture, fps, delay and size, Pause and a red Stop), paused (Resume primary), a video (a
  transport). Stills come from ScreenCaptureKit inside the sandbox (`SCScreenshotManager`, 480 × 300 JPEGs in its data
  folder) only while the page is open, at most every 20 seconds, never while sharing, and only when macOS already lets
  Sidefolk record (`CGPreflightScreenCaptureAccess`: picking Window or sharing is what asks). The summary's control is
  Start sharing, or Stop, on the Today tile and the sidebar row: D69's "Stop on the tile" is built.

**Why:** the founder found Miraya's page confusing: every button looked the same, nothing was highlighted, it read like
text, and "Show windows" only revealed more buttons. Miraya's own Mac app shows the bar: a TV list with states, a
visual choice of what to share, quality as cards, one prominent Start or Stop. He asked that extensions be able to do
this well, for any feature, not by special-casing Miraya.

**Alternatives:** a web view or custom drawing per extension (D62: it could imitate Sidefolk's approval cards and ignore
themes); Miraya drawn by Sidefolk itself (not extensible, and Miraya is an extension); a `layout` key naming fixed page
templates (too rigid: a hero, pictures and a side column cover the screens we know and combine); letting extensions mark
several primaries (the founder's complaint is exactly that nothing stands out); a new part type for each choice look
(older copies would drop them; a `style` on `choice` degrades to a plain choice).

**Implications:** older 0.1.0 snapshots skip `hero` and `transport` and draw styled choices plainly, so pages keep a
meaningful summary with its control; manifests still ask `"sidefolk": ">=0.1"` (the version stays 0.1.0). `set_option`
in Miraya also takes `kind`, `display`, `window` and `area` (the page's picks, kept in `choices.json` as optional keys
so an older file still reads); no new tool and no manifest change. Window stills show any app's window inside Sidefolk's
own Home, as they would in Miraya's app; they stay in Miraya's data folder, round before last deleted, removed with it.
**Not built:** a drawn capture area, seeking by dragging the transport's bar, a volume slider, app icons on window tiles.

### D75 — Games beside the companion: the Play panel, a game channel, companion cues; trivia without AI; the four redesigned (2026-10-31)
*Amended by D79:* ten more games, one trivia, and Playtime's words in `strings/`. *Amended by D99:* an extension may now draw
pictures and play sounds of its own from its pack, in a surface; the game channel stays until snapshot B (D101). *Amended by
D100: pack pictures, settings and a History row are general abilities now.*
**Decision:** games are played in a **Play panel** beside the companion, drawn by Sidefolk from data, with the companion
as the opponent next to it (the approved plan, phase 1):
- **`games` in the manifest** (`title`, `symbol`, `say`, `levels`, `ai`): `say` sentences follow the command rules
  (whole sentences, no slots) and open the game without the AI; every game is in the companion's Play menu and in the
  core tool **`games.open`** (low risk; it only shows a panel), whose description lists them for the AI. The panel takes
  the keyboard when the person opened it and waits for a click when the AI did.
- **The game channel, not tool calls:** `sidefolk/game.start {game, level, language, options}` → `{session, board}`,
  `sidefolk/game.move {game, session, move}` → `{board}`, `sidefolk/game.end {game, session, reason}`. A move is small
  and typed (`answer`, `cell`, `button`, `choice`, `timeout`, …) and sent only when the board on screen offered it,
  only for the one game open, at most 20 a second; an answer later than 2 s or over 64 KB ends the game ("Playtime
  didn't answer"). One Activity row per game, written when it ends ("Played Trivia with Playtime · You 7 · Mochi 6").
  Options are `tone`, `sneaky` and the companion's name, nothing else about the person.
- **Board parts, game-only:** `prompt`, `answers` (2–4 tiles, states, the companion's pick with its face, Sidefolk's
  own pictures for hands), `board` (up to 8 × 8), `score` (pills, round pips, a streak, the companion's sealed pick),
  `result`, `timer` (Sidefolk keeps time and sends `timeout`), `reveal` (coin, dice, hands), `note`, `facts`, `button`
  (a move, never a tool; one primary), `choice` (cards or segments). Unknown parts are skipped. Text is cleaned and
  clipped as on pages and never reaches a model.
- **Companion cues (a new, narrow reach):** a board may carry one cue, every value from a fixed list (`GameCue`): a
  move (mapped to moments and states every 2D and 3D companion has), an effect and a prop (drawn above it in code),
  a **line key** for which Sidefolk says one of its own lines in the person's language and the chosen tone, a sound
  and where to look. Moves 0.8 s apart (a newer one replaces one waiting), a line every 2 s, four sounds a second,
  only while the panel shows that game. A cue never moves the window, opens a bubble, takes focus or says the game's
  words. This amends D44's "extensions can't animate the companion": a game names a mood, it never drives the rig.
- **Suspense and meaning (the founder's rules):** nothing gives a result away before its reveal ends: the panel
  first shows a build-up (`GameSuspense`: the hands pumping sealed, the pick pressed beside the sealed card) and the
  verdict a beat after (colours, score, words, the cue, sounds, VoiceOver); the Ask panel's card, its spoken line and
  the AI's reply after a toss wait until it lands. One colour per meaning (`GameVerdict`): the person's win is the
  theme's success green, a loss (the companion's win included) a calm sand tone (`GameColors.lost`), never the danger
  red, a draw neutral ink; always with a symbol (✓, ✕, =, a crown). Selections use the theme's accent.
- **Sidefolk's own game on the same path:** rock, paper, scissors as a best of three (`HandsMatch`): the companion's
  hand is drawn with the system's generator when each round begins, sealed before the person picks and never read
  from it; now and then a bluff ("I'm going rock…"). A hand alone ("rock") is still a quick throw on the desktop.
- **Coin, dice and hands redesigned (D44 stays):** a 48-pt coin with the companion's own face on heads, flicked
  150 pt and wobbling to rest, called or not ("flip a coin, I call tails", Play › Flip a Coin › Call Heads); dice
  thrown onto a felt tray, d6 tumbling in 3D, other dice as their real shapes; hands that meet and act on each other;
  the result as a chip under the objects with an Again pill (the only click the layer takes, never during catch-me);
  the companion reacts (a call right or wrong, a natural 20 or 1, doubles, snake eyes).
- **Settings › Companion › Games:** "When it wins" gentle, cheeky (the default) or competitive; game sounds, off by
  default, with a speaker button per game (sounds are made in code, follow Quiet, a fullscreen app and macOS's
  interface-sounds setting). Lines are spoken only for someone who hears every reply (Settings › Voice) with the
  game's sound on. Sneaky is a setting passed to games (off), shown when a game offers it.
- **Playtime** (still 1.0.0, in snapshots; first planned as 2.0) plays trivia in the panel with no AI: a topic, 5, 10 or endless questions, relaxed or 15 s each,
  the companion's sealed pick (right as often as it knows the question: by difficulty, its favourite and weak
  topics, the level), "Ask Mochi" once a round (unsure in a weak topic, it can fade the right one), a fact after
  each answer, an end card with a new best, records in its data folder, and a page in Home. Its words come in all ten
  languages from tables chosen by the `language` Sidefolk passes (the Kit's new `Localized`). The `trivia` tool stays
  for chat and voice. The rules are pure engines under `Sources/GameKit`'s protocols, so the new games and the 400
  questions per language drop in.

**Why:** the founder approved the games plan: today's games were things you read, trivia cost a model call per answer,
and the companion barely played. Founder's answers: all ten games, cheeky by default as a setting, sounds off with
a speaker per game, Sneaky off, one extension, lines spoken only with spoken replies, coin/dice/hands in core, and
every official extension in all ten languages. Trying it, he found the result shown before the animation, red used
for draws and wins, and the companion seeming to mirror rock; these rules come from that.

**Alternatives:** moves as tool calls (an Activity row and Guard per click); a web view per game (could imitate
Sidefolk's cards, ignores themes); extension text spoken by the companion (an extension could make it say anything);
modelling props per companion (twelve companions); shipping sound files (synthesized ones cost nothing to bundle).

**Implications:** a 0.1.0 snapshot from before games refuses Playtime's games snapshots at install (an unknown `games` key), as with
pages (D62); accepted for snapshots. New companion moves (sulk, shrug, tease, ready and the short accents) borrow the
nearest existing moment until each is made and filmed for every 3D companion (built: the amendment below); trivia's questions stay the 52 English
ones until the content packs land (`TriviaPack`). **Not built:** the `pads`, `shuffle`, `reflex`, `meter`, `number`,
`letters` and `keys` parts (phase 2–3), Sneaky's switch in Settings, a tail on the panel.

**Amended (2026-11-01), the reaction moves, built:** the game moves that borrowed a near one are each the companion's
own now. In 3D, shared in `engine/moves.js` for every companion (Mochi and Spark in the app, the gallery's eight on
the same engine): **sulk** (a huff, then the shoulder turned on you, head away rather than down, ears drooping, a
glance back), **shrug** (shoulders up, paws out and open, head tipped), **tease** (a paw by the cheek, a lean with a
short wink, a waggle of the hips), **ready** (a crouch, paws up in front and apart, two bounces), and the accents
**waveQuick**, **hopQuick**, **spinQuick**, **bowQuick** (0.55–1 s, eyes open for the next beat); **wince** and
**gasp** play the engine's `wince` and `surprised`. Each lasts 0.6–1.6 s and comes back to rest by itself. A move may
carry a `still` version that the engine plays instead under Reduce Motion (`liveliness: 'still'`): the face and a
small turn of the head, nothing that travels. In 2D the same ten are new `CharacterAntic` cases drawn from the rig's
parts (`Antics`), with the moods each body already draws (a wink is the one-eye `wince`); a 2D spin narrows twice
rather than turning edge-on. `CueDirector.moment` maps each `GameCue.Move` to its own antic; `sulk` is no longer the
`error` state. Every move was filmed for every 3D companion from the front, 40° and the side, and tuned from the
films: big heads turn rather than droop in a sulk, long arms stay apart in ready, the wink is short because a one-eyed
body (Iris) reads a long one as shut, the accents keep their eyes open. No character file changed, so the gallery's
companions need no new version: they get the moves with the app. The playground gained `reel()` (several moves at
several angles in one picture) and `edges({ only })`; the debug app `cue:<move>`.

**Amended by D101 (2026-11-03):** the Play panel, the game channel, the Play menu's games and the desktop toss are gone from the app; an extension's screens are surfaces (D99). Cues live on only as `CompanionCue`'s fixed lists on a surface's reaction, with no words.

### D76 — Extensions speak the person's language: `strings/` beside the manifest, `language` with every request (2026-10-31)
*Amended by D100: commands are translated too (`commands`, `parts`, `choices`, `carry` in `strings/`), and settings, entries, drop actions and the AI's purpose.*
**Decision:** every extension can show all its words in Sidefolk's ten languages, and Sidefolk's own do.
- **What the manifest shows people** (name, tagline, description, tool, watcher, page and palette titles, watcher
  descriptions, a palette's placeholder, `network_purpose`) is translated in `strings/<language>.json` beside the
  manifest, one file per language, never in the manifest itself. `ManifestValidator` reads the folder
  (`ExtensionStrings`): file names only the ten languages, strict keys, each field only where the manifest has one, plain
  text within the manifest's limit or half as long again (languages run longer than English), `en.json` holding only
  `text`. `ExtensionHost` shows the person's language (`Configuration.language`, the app's translation), the closest the
  extension has (`pt` finds `pt-BR`, `zh-CN` `zh-Hans`, `zh-Hant` nothing), then, for Sidefolk's own copies from before
  this, the app's catalog (`BuiltInExtensionWords`), then the manifest: in Settings, Home, palettes, heads-ups, tool
  titles everywhere (the AI's included), the install sheet (`ValidationReport.shownWords`, `shownPermissions`) and
  update diffs (both sides worded alike). What is granted never changes with the language.
- **The gallery** carries the same per language: `build.py` copies name, tagline and description from `strings/` into
  each catalog entry's `localized` (`AddonWords`, read leniently: a bad field or language is left out, never the entry).
- **What the program says**: `MCPClient` adds `language` to every `tools/call` and `sidefolk/` request of a Sidefolk
  extension (`page.render` had it, D62); a plain MCP server gets requests unchanged. The program keeps its sentences
  under `text` in the same files, keyed by their English, `en.json` listing every one; named placeholders kept, CLDR
  plural forms per language. The Kit reads them (`Language.swift`: `L`, `L(one:other:count:)`, `Format` for numbers,
  sizes, durations, 24-hour times, dates, lists and sentence joining, `Language.with` for tests), carries its own few
  sentences in ten languages (`KitWords`), and looks plain words up through `Localized` (D75's helper, the same file).
  `scripts/extension-strings.py` keeps `en.json` in step with the `L(…)` calls and lists what each language lacks.
- **Right to left**: extension text stays stripped of direction marks (T13). Sidefolk adds its own when drawing in
  Arabic (`BidiText`, `Text(ext:)` on pages, tiles and palettes): a value of numbers and signs alone is isolated left to
  right ("3024 × 1964" read reversed before), and so are paths, addresses and number runs inside an Arabic sentence.
- **Page details** (switches, choices, rows, the summary) are clipped at 240 characters instead of 160, so a German
  sentence fits (an older Sidefolk still clips at 160).
- Every official extension but Playtime (rebuilt on team/play, which localizes itself with D75's tables) speaks all ten:
  World Clock, Calculator, Weather and System Vitals in the app; Your Mac, Clipboard, Keep Awake, Miraya, Git, Currency,
  Images, PDF Tools, QR Codes, Archives, Dev Toolbox and Feeds in the gallery. Miraya's sources copied from its Mac app
  (`Miraya/`) stay as they are: what they say passes through `Said.shown` on its way to the person.

**Why:** the founder asked that extensions, Sidefolk's own first, work in every language Sidefolk speaks; pages, answers
and the install sheet were English (D62's "English only for now"), and only a few manifest words were translated, in
the app's catalog, which no one else's extension can use. *Files beside the manifest rather than a `localized` key*
because 0.1.0 snapshots refuse a manifest with a key they don't know (T13) and ignore a folder they don't read, so a pack
with translations still installs on them. *Text keyed by its English* so the code reads as English, a missing
translation shows English, and `en.json` can be written from the code. *Named placeholders and CLDR plurals* because
word order and counts differ (Arabic has six forms). *Sidefolk draws the direction*, not the extension: it knows the
layout, and direction marks stay a way to disguise text.

**Alternatives:** a `localized` object in the manifest (older copies refuse it); tables compiled into each program
(D75's `Localized`: fine for a few words, but invisible to the validator and the gallery, and a third party writing
Python would need its own; both work, and `L` uses `Localized` underneath); translating tool descriptions from
`tools/list` (they are pinned at install: a language change would hold every tool); letting extensions send isolates
(the same characters that reorder a name); the install sheet trusting `BuiltInExtensionWords` alone (only Sidefolk's own,
and only the app's copy of them).

**Implications:** `ExtensionStrings`, `ExtensionShownWords`, `ValidationReport.strings/shownWords/shownPermissions`,
`ExtensionHost.Configuration.language`, `MCPClient(language:)`, `AddonEntry.localized`/`AddonWords`, `BidiText`, app
`Text(ext:)`; Kit `Language.swift`, `KitWords.swift`, `Localized.swift`; `scripts/extension-strings.py`; build-app.sh and
build.py copy `strings/`; tests `ExtensionStringsTests`, `BidiTextTests`, `ExtensionLanguagesTests` (every official
extension, every key, every language), add-ons `LanguagesTests`. An extension's English output changed where Foundation
now formats it ("1 hr, 30 min", "51 GB"). `BuiltInExtensionWords` can go once no installed pack predates `strings/`.
Commands and `ask` sentences stay English (GLOSSARY rule 1), except a sentence that only opens a game (D79). `zh-Hant`
reads `zh-Hans` in both layers since D79.
**Amended (2026-11-01), values keep their own direction:** the Kit's `L` wraps each value it fills in in a first-strong
isolate (FSI … PDI, invisible). An Arabic sentence that begins with a name in Latin letters ("{name} counts… {n}
left.") took its direction from the name and read left to right; the isolate is skipped when the paragraph's direction
is found, so the sentence reads right to left and the name keeps its own order, in every language. Sidefolk keeps only
these isolates, and only in pairs, in what it shows (`ExtensionText.shown`: page and board text, `ExtensionPage.text`,
`GameBoard.longText`; an unpaired one is dropped, so it can't reach past its value); everything else that reorders
text (overrides, embeddings, LRI, RLI, marks) is still removed, and nothing passed on keeps them (tool results, names,
the validator's checks, what reaches a model: `clean`, `untrusted`, `UntrustedText`). `BidiText`'s runs nest inside
an isolate rather than crossing it, and clipping counts only what shows. The Kit chose isolating at the source over
the app guessing where a value starts and ends, which it can't know. `L` is for words people read, never a file name or
an argument; older packs keep their words without isolates.

### D77 — The companion chooser: every companion of yours in one grid, visible actions, and a gallery to browse (2026-10-31)
*Amended by D84:* the chooser's Gallery page moved to Home's Gallery.
**Decision:** *amends D43, D55, D56 and D60 for companions.* Settings › Companion has two pages at the top, outside the
scroll, as Settings › Extensions has: **Yours** and **Gallery**.
- **Yours, in one place.** Every companion the person can wear now is in one grid under the live stage
  (`CompanionLibrary.owned`): Sidefolk's own first, then everything else by name, wherever it came from. Each tile is its
  still in the look it is worn in, a small 3D or 2D chip on the picture, its name, and one quiet line saying where it
  came from (*Built in*, *From the gallery*, *Made by you*, *From a folder*). The one worn is the accent tile; under the
  stage's name a line says where it came from, with its version and maker when known. A click wears one, at once on the
  desktop, as before. The "Made by you" group and its rows are gone.
- **Visible actions.** Each tile has a "…" button, and the same menu on Control-click and in VoiceOver's actions
  (`CompanionLibrary.actions`): *Wear* (unless worn), *Update to …* (a gallery companion with a newer version, while
  add-ons wait to be updated by hand, D70; the tile keeps its update mark too), *Show in Finder* (made by you, or added
  from a folder), and *Remove…*, *Move to Trash…* for one made from data (the person's own work goes to the Trash,
  never deleted). Where Remove can't be, the menu says why in its place, disabled: *Comes with Sidefolk: can't be
  removed*, *Comes with an extension: remove the extension instead*. Removing asks first and says what goes and whether
  it can come back (the gallery still has it, or may not; a folder's copy goes but the folder isn't touched; the Trash
  can give it back), and who takes the place of the one worn (`CompanionLibrary.replacement`: Mochi for a gallery
  companion, the one chosen before for one worn by name or made from data). "To remove one, Control-click it" is gone.
  There is no Edit: nothing in Sidefolk edits a companion.
- **Add your own, where you look.** After the companions, an *Add Your Own* tile opens the two ways with a line each: a
  3D companion from a folder (D60; Choose Folder…, then the same warning that its character file runs as code, D71), and
  a 2D companion (D43): Open Companions Folder makes and opens `<home>/companions/`; what is saved there shows up when
  Sidefolk comes back to the front. Beside it a *Get More* tile says how many the gallery has that aren't here and opens
  Gallery.
- **The gallery as a browser.** Gallery has a search (name, line, description and maker, and Sidefolk's own lines in
  the person's language), filters shown only when they tell something apart (3D/2D when some come in 2D and some don't;
  *Made by* Anyone/Sidefolk/Others when both are there; *Hide yours*), and an order: Name, Smallest, and Newest when the
  catalog dates its entries (`CompanionBrowse`). Cards say the size and looks, or *On this Mac*, with one button: Get,
  the download's progress in place, Wear, Update, or *Wearing*. Pictures are read and scaled off the main thread as
  cards come into sight and kept (`GalleryPicture`), so hundreds cost only what is on screen. A card opens its details:
  the picture large, maker, version, size, looks, description, *From the Sidefolk gallery · Signed by Sidefolk and
  checked before install*, and Get or Get and Wear. Get only downloads; Get and Wear also wears it. Snapshots follow
  Settings › Updates as before, with Show Snapshots when they are hidden.
- **Gallery companions worn by name.** A gallery companion this copy has no `CompanionChoice` for is worn as one from a
  folder is (`AppSettings.localCompanion`), standing on the rig its body names: the catalog may give `body` (D60's) and
  `published` (a date, for Newest); both are optional and checked. Installing one keeps its tagline and body
  (`InstalledCompanion`), never replaces the person's own companion of that name added from a folder, and never takes a
  retired character's name. Sidefolk-signed packs only, as before (D55, T33): nothing about trust changes.
- **Shared with the extensions gallery:** only what a gallery page shows instead of its list (`GalleryStatus`: no
  gallery, snapshots hidden, looking, not reached) and the "as last seen" line (`GalleryLastSeen`).

**Why:** the founder found two lists (on this Mac, then the gallery's) that won't scale to hundreds, his own companions
in another place, so it took him a while to see how to add one and what he could choose, and no way to delete one until
he noticed "Control-click". One grid makes the person's own companions first-class; a visible "…" puts every action in
sight, each said with its consequence; Add Your Own sits where the person looks; and a separate Gallery page with search
and filters keeps the grid about what you have. *A page beside Yours rather than a sheet* because Settings › Extensions
already works that way (one way to learn both), Presence and Behavior stay on Yours, and a page scrolls through hundreds
in the full height of the window. *Click wears, the menu does the rest* because wearing is what people come for and is
undone with another click, while Remove is destructive and must be asked. *Get only downloads* from a card, so a click
in a grid of hundreds doesn't change the desktop; the details have Get and Wear.

**Alternatives:** the gallery as a sheet over Settings (narrower than the window, and modal over a long browse); a
master-detail beside the grid (the window is 640 points wide); badges as icons only (ambiguous, the founder's problem
was not seeing); a size filter (the gallery's companions are 2 to 4 MB; Smallest orders instead); Popular (no download
counts exist); delete outright for made-by-you (their own work: the Trash gives it back).

**Implications:** Core: `OwnedCompanion`, `CompanionAction`, `CompanionRemoval`, `CompanionKeep`, `CompanionLibrary`,
`CompanionBrowse`, `AddonEntry.wearable/looks/published/body`, `AddonStore.install(companion:)` guards; app:
`CompanionChooserModel` (`SettingsModel.chooser`), `CompanionGrid`, `CompanionMenuItems`, `AddCompanionOptions`,
`CompanionWords`, `CompanionRemovalWords`, `CompanionPageHeader`, `CompanionGalleryView`, `CompanionGalleryDetail`,
`GalleryPicture`, `GalleryStatus`, `GalleryLastSeen`, `CompanionArt.still` and `locals` (gallery companions worn by
name too), `AddonGalleryModel.remove(companion:wearing:)`, `readInstalled`, `companionError`; snapshots
`page-settings-companion-yours|gallery[-search|-filters|-none|-downloading]`, `sheet-companion-detail-*`, `-add`,
`-menus`, `-remove` (sixty sample companions, `SampleCompanions`); debug `chooser:…` (scripts/dev.swift). For
sidefolk-addons: `build.py` may write `published` (and `body` for a companion this app has no case for) into the catalog.

### D78 — Colour meaning: red only for errors and real risk, amber for waiting, green for good outcomes (2026-10-31)
*Amended 2026-11-01 (`team/theme-skill`):* the theme check holds every role drawn as text to 4.5:1 where it is drawn (success on every surface, and each chip's words on its own soft fill: link, danger, warning, success), and the soft fills to their status's hue or grey (a purple `dangerSoft` read as news). The built-ins and the gallery's themes were darkened along their own hues to pass; Night Studio's and Marshmallow's dark soft fills moved to red and amber. The new rules are errors for a theme made or added from a folder (`sidefolk theme check`, Load from folder) and warnings for a copy Sidefolk already keeps or one from its own gallery (`ThemeCheck.check(folder:strict:)`), so a theme that passed when it was added isn't taken away before its update; sidefolk-addons' `check.sh` holds the gallery to the strict check.
**Decision:** every status colour means one thing, in every screen and theme (ARCHITECTURE › Colour meaning):
- **danger/red:** an error, a failure, a destructive action, or real risk to the person's data or privacy. Nothing else.
- **warning/amber:** needs a look or is waiting (late reminders, what waits on you, a countdown running out, a step
  the rules stopped, Full access in Activity). New theme roles `warning`, `warningSoft` and `onWarning`, readable as
  text (4.5:1) like `danger`; Harbor's is the brand sun, deepened in light (#8A5800).
- **success/green:** done, healthy, allowed, won, a settled good state. Not "busy": working and watching are neutral.
- **news/accent:** something new to look at, like an unread dot: a page that changed is news, not an error.
- **neutral ink:** information, off, paused, "no", nothing happened, a draw.
- The now line on every time line is the accent: a time marker, not an alarm.
- Folk colours are identity, never status, and never the only signal; every status colour comes with a word or icon.
- Core's `StatusTone` holds the mapping (Activity decisions, risk, watches, agent sessions, late reminders, an
  extension's tones), tested; the app paints it with `Theme.color`/`Theme.soft`/`ChipTone(_:)`.
- The theme check refuses a theme whose danger doesn't look red, warning amber or success green (hue and saturation,
  in both appearances). A theme without the warning roles gets Harbor's amber, which reads on any surface.

**Why:** the founder: "Colours have meanings. When it's a draw it shows me red, which gives the impression I lost, and
when I win something is red too." The audit found red for late reminders, a page that changed, "needs you", the now
line, a denied or skipped step, a removed line in a page's change, a stopped run and "Not available"; green for
"working" and low risk; the accent for "Allowed"; and a folk's colour as a status. Amber had no theme role (the brand
sun, unreadable as text), so a theme couldn't say "waiting" at all.

**Alternatives:** keeping red for "needs you" counts, as Mail's unread badge does (the founder asked for meanings over
convention); a separate "late" or "changed" token (warning and the accent already say them); hue rules as warnings only
(a theme mapping success to red would mislead every screen).

**Implications:** the install sheet's tones (D71) and Full access's red chip and orange menu bar icon (D37) stay. The
games' verdicts come from `GameVerdict` (D79); Play's folk colour is red, so it marks only the panel's icon, never a
win or a draw. Community themes made before this get Harbor's amber and a warning naming the
roles; gallery themes pass as they are.

### D79 — Games, phases 2 and 3: the ten new games in the Play panel, their parts, one trivia, one way to speak (2026-10-31)
*Amended by D99:* "a game never sends a picture" holds for the Play panel's boards only; a scene draws from the extension's pack.
*Amended by D100: `say`'s exception for games goes with any extension's commands in `strings/`.*

**Decision:** *amends D75 and D76.* All ten approved games are played in the Play panel from Playtime, on the engines written for them, with
no AI: Tic-tac-toe, Copy Me, Quick Paws, Which Cup?, Higher or Lower (both ways), Guess My Animal, Balloon Words, Last
Stick, Memory Pairs and Daily Word, beside trivia.
- **New board parts, drawn, timed and fed by Sidefolk** (`GameBoardParts`): `pads` (Sidefolk plays the sequence: each
  pad lit with its note and the companion's short move, then takes presses), `cups` (the gem shown, the game's swaps
  animated, a pick after), `reflex` (Sidefolk shows the signal and times the press from the key's own timestamp; an
  early press says "Too soon!" at once), `meter`, `number` (with a digit pad and the guesses so far), `letters` (rows
  that flip, or slots), `keys` (a keyboard per script, letter by letter or spelling a word; Korean jamo drawn as the
  syllables they make), `entry` (a text field, for input methods: Chinese idioms, an animal's name), `sticks`, `lives`;
  a tile's own key cap (Y, N, ?) and a number-pad grid. Each value is checked and capped (64 steps, 40 swaps, 8 × 24
  tiles, 120 characters), every move only for a part on the board.
- **The companion's turn is the game's, the clock Sidefolk's:** a board's `after_ms` (0.1–6 s) has Sidefolk wait
  (the companion thinking, two cards left up) and ask for the next board with `{next: true}`; nothing else is taken
  meanwhile. The engines' `think(ms)` becomes that wait.
- **No verdict before its build-up, for every game** (`GameSuspense`): besides a reveal and a judged answer, a board
  that scores a point, draws a winning line, lifts the cups, times a reflex, judges a guess, turns a card with a
  reaction or shows the end card comes after a beat with the previous score, words, keyboard and lives, the cups down
  and the pick pressed; a Daily Word row flips tile by tile before its keys, cue and card. Colours stay GameVerdict's:
  letters right in success green with ●, elsewhere yellow with ◐, absent faded; a missed key the calm loss tone, struck
  through; the thermometer cold blue to warm orange, never red.
- **Fairness:** every chance is `Games.Random.fresh()` in play (seeded in tests), and what the companion hides is drawn
  before the person moves: the gem's cup with the shuffle, the reflex time with the round, the number at the start,
  trivia's pick with the question; tested to be the same whatever the person does.
- **One event table:** the engines' `Games.Event` becomes the companion's reaction through `EventCues` (the weightiest
  event first: an ended match before a point, a point before a turn); a screen only adds its own props (balloons held,
  a magnifier, the gem). Records in Playtime's folder: tallies and bests, the last ten games, Daily Word's day, streak
  and Today tile (the page's summary, `widget`), what it learned about animals (per language, capped), Last Stick's
  lesson after three losses.
- **One trivia:** phase 1's round (set-up, pace, levels, records, Home) is kept, with the engines' 400 questions in all
  ten languages as one `TriviaPack` per language and the Quiz engine's idea folded in: each companion has its own
  strong and weak topics, drawn from its name. The Quiz engine is gone. The bank has no "Did you know?" lines, so none
  shows.
- **One way to speak (D76 over D75):** Playtime's words and the engines' phrases are its `strings/<language>.json`,
  read with `L()`; `Localized` is the layer `L` reads through. `zh-Hant` is `zh-Hans` in both layers (the nearest
  language Sidefolk speaks); numbers through `Format`; placeholders named. A game's title is translated in `strings/`
  (`games.<name>.title`), and a game's `say` holds up to 24 sentences so each opens in all ten languages (an exception to
  D76's "commands stay English", only for a sentence that just opens a game).

**Why:** the founder approved all ten games; phase 1 built the platform and left these parts and games to come.
**Alternatives:** a timer in the extension for the companion's turn (stdin can't keep time, and it would hold a process
awake); keeping both trivia engines; a romaji/jamo input of Sidefolk's own instead of the input method for idioms.
**Amended (2026-11-01):** some parts are drawn with built-in pictures (`Sources/SidefolkApp/Play/Art`: cup, gem,
balloon, trophy, made for Sidefolk), picked from the part's data; a board still never carries an image.
**Amended (2026-11-01), the games look:** the founder wanted the games to look and feel like real games (two direction
boards). The Play panel (400 pt) is drawn as one: a header in the game's colour (back to the menu, its icon on a tile,
title, whose game it is, speaker, ✕), "You vs <companion>" with both faces (the Mac account's picture read once from the
local directory through Collaboration, else a smiling stand-in; never in snapshots) and the score or round pips, the
game's illustrated scene behind the board (dimmed in dark mode, the arcade dark in both), the companion in it saying the
prompt in a speech bubble (whole, never cut: standing on the table's back edge with a soft shadow for cups, pads,
sticks and the Boop button, small beside its bubble over a bigger board, fitted by height or width so a tall Spark or a
wide Ember shows entire; its 2D poses follow the cue's move, a 3D one shows its still; always the person's own
companion), the eyebrow as a round chip, chunky toy buttons and tiles, a hint pill, and an end card that stands in for
the board and holds the level for the next game (who won in words, the trophy with rays and confetti for the person's
win, Play again beside a "Back to games" square). The panel stays under about 720 pt for a 13" screen: a board taller
than its room (540 pt) scrolls inside it; none does in English, German, Arabic or Japanese. The panel's home is a **menu**
(the Play menu's All Games…, a game's back button): game cards in their colours with icon and tagline, "Play against
<companion>" then "Puzzles" (`GameLook.solo`), "Resume" on a game put away, and Wins, Streak and Played counted from
Sidefolk's own Activity rows (`GameStats`; each `games.play` row now records `result` win, loss or draw).
- **Fixed keys, checked:** the manifest's `games.<name>.look` (`GameLook`: cups, dance, arcade, sticks, quiz, grid,
  numbers, animals, balloons, cards, hands, words; the validator names a wrong one) and `tagline` (60 characters,
  translated as `games.<name>.tagline`); a pad's `art` (wave, hop, spin, bow, wave_both; an unknown one keeps the shape).
  Pictures for SF Symbols a board already names (Memory Pairs' faces, trivia's topics) are Sidefolk's own mapping.
- **What is drawn where:** `GameStyle.of(look)` (Play/GameLooks.swift) holds each look's colours, scene and icon;
  `GameArt` (Play/GameArt.swift) the pictures; Play/GameStage.swift the companion and its bubble; Play/PlayMenu.swift the
  menu. A look's colour is identity only (D78): verdicts keep GameVerdict's colours, primary buttons the app's accent.
- **Restraint and motion (the founder, on review):** like a game, not a busy one. The scene sits softly behind the
  board (the room blurred and lowered in contrast in the picture itself, the table the props stand on left sharp; dimmed
  further in dark mode), one focal point a screen, effects only for a win or a new best. The companion is still art
  only (its portrait or 2D pose stills, never a live 3D view in the panel) and hops once (300 ms) when a board arrives;
  nothing loops: the confetti's and a reveal's clocks stop once they land, the trophy's rays open once and stay. Swapped
  cups slide along the table, one passing in front of the other (lower and larger), never through it. Measured in a
  debug app: the app's process at about 3.7 % CPU with the panel closed (the desktop companion), about 4–4.5 % with a
  game, the menu or an end card sitting idle in it.
- **The art budget:** about 0.8 MB of the 6–8 MB allowed, in one warm, glossy, toy-like style made with Codex image
  generation: 11 scenes (HEIC, 768 × 1024, 29–67 KB; the table a prop stands on is the scene's own bottom), 12 menu
  icons, 5 pad moves, 12 card faces, 10 topics, the Boop button, a bulb, a card back and a magnifier (WebP with alpha),
  beside the earlier cup, gem, balloon and trophy. The companion is never generated.
- **A new game's look:** a `GameLook` case (and `solo` for a puzzle), its row in `GameStyle.of`, `game-bg-<look>.heic`
  and `game-icon-<look>.webp` in Play/Art with their `GameArt` cases, then `"look"` in the manifest.
- **Implications:** a Sidefolk from before this refuses a Playtime naming looks and taglines (unknown manifest keys,
  T13), as with earlier snapshots; a pad's `art` is ignored by older copies.
**Amended (2026-11-01), the puzzles:** the founder asked for four logic puzzles in the spirit of the ones LinkedIn
offers; they are built on the classic public genres with Sidefolk's own names, pieces, words and look, nothing of
LinkedIn's (names, colours, layouts or pieces: no sun and moon, no crowns). **Garden Plots** (Shikaku: rectangles over
numbers, as many squares as the number), **Seesaw** (Takuzu: hearts and stars balanced in every line, never three
alike, `=` and `×` between cells), **Sudoku** (6 × 6 with 2 × 3 boxes on Easy and Fair, 9 × 9 on Hard) and **Blossoms**
(one-star Star Battle: one flower per row, column and bed, none touching). Played alone, under "Puzzles".
- **Engines in Playtime** (`Sources/Games/Puzzles`): each generator keeps only a board its own step-by-step solver
  finishes with the level's techniques (Easy the plain rules, Fair one more, Hard a short chain), so the solution is
  unique and a hint is always the next forced move with its reason, from wherever the person is (a wrong mark first,
  to take back). Uniqueness is checked again in tests by plain backtracking; the worst board takes about 60 ms in
  release. One daily board per puzzle and date at Fair, the same for everyone (seeded by puzzle and day; a fingerprint
  test guards it), kept as far as played; after it, "Play another" deals practice boards at the level picked. Records:
  a best time per level only without hints, the daily streak, the practice tally (`PuzzleRecord`, read leniently),
  Home rows, Last games ("Solved in 3:12") and the puzzles' live streaks on the Today tile.
- **One new part, `puzzle`** (GamePuzzle.swift, checked and capped: 2–10 a side, two-character numbers, notes 1–9,
  twelve regions, 200 edges, 100 plots), with moves `{area}` (a rectangle dragged) and `{place}` (a number or a note),
  offered only by a puzzle that takes them; Sidefolk draws the cells, beds with heavier lines, Sudoku's boxes, `=`/`×`
  discs, plots (dashed while dragged), the digit pad with a Notes switch (N) and the clock, which counts on in the panel
  from the time the board says (once a second, nothing else moves). A rule broken is the calm loss tone with a !, never
  red; a hint lights what it rests on in the sun's colour and shows its move faintly in an accent ring. A puzzle is the
  same picture in every language: laid out left to right in Arabic too, arrows moving as they point.
- **Room:** a puzzle has no "You vs" bar; its clock and Notes switch share the eyebrow's row; cells are sized so a 9 × 9
  Sudoku with its pad, Hint, Undo and Start over is about 630 pt tall (the panel's 720 pt rule). The solve settles on a
  still, locked board for the beat before the end card ("Solved!", the time, hints, best and streak), the companion
  celebrating then, with a line only for a new best; a hint is a nod, a broken rule a thoughtful look.
- **Looks:** `plots` (soil brown, a vegetable garden), `seesaw` (plum, a playground at golden hour), `sudoku` (slate
  blue, a reading desk), `blossoms` (coral, a flower garden), with four scenes and four icons made in the games' style
  (Codex image generation; the rooms softened in the picture). The game pieces are the existing heart, star and flower
  faces.
- **Not built:** dragging a plot from the keyboard (arrows and Return clear or plant one cell), a hint that plays its
  move by itself, a daily board per level.
**Implications:** older Playtime boards still open (unknown parts are skipped); a snapshot from before games still refuses
Playtime's `games`. New companion moves still borrow the nearest moment (D75). **Not built:** catching the companion by
clicking it in Which Cup? (a "Check its paw" button does it), AI trivia packs (phase 3 extra), Connect Four.
**Amended (2026-11-01), the games' items (the founder's plan, D14 and D15):** what the puzzles and Which Cup? left out.
- **Catching the companion:** a board button may say `"companion": true`; Sidefolk then draws no button and the
  companion in the scene is it (`GameBoard.companionButton`, `CatchableFigure`): a small badge with the button's symbol
  on its shoulder, the pointing hand, the button's words as the tooltip and for VoiceOver, its key (C) still pressing
  it. Which Cup? on Sneaky says so in the companion's words ("Think I'm hiding it? Click me."), checks once a round (then
  the companion isn't clickable: "Nothing in my paw! It's under a cup."), during the shuffle or before the lift; a board
  of the same round carries the shuffle on rather than starting it again (`PartsState.shuffled`). A Sidefolk from
  before this draws the button as before, so its "Click me" would be untrue there: Playtime's `minimum_sidefolk` must
  name the snapshot that ships this.
- **Garden Plots from the keyboard:** the arrows move the cursor; Space or Return starts a plot there, the arrows
  stretch it in the pointer's dashed preview, Return (or Space) plants it (on one square: a click there, clearing a plot
  or planting a one-square one), Esc lets it go and only then doesn't close the panel. The hint row says which.
- **A daily board per level:** Easy, Fair and Hard each have a board of the day, the same for everyone (seeded by
  puzzle, level and day; Fair keeps its earlier seed so that day's board didn't change; each level fingerprinted),
  kept as far as played per level. A puzzle opens on today's board at the level asked for, else the level last
  picked, else Fair; once that one is solved, practice at it. The end card names the boards still open today ("Today's
  Easy and Hard boards are still waiting."), and a level picked there opens its board of the day while it's open;
  "Play another" is practice. One streak: a day counts when any of its boards is solved. Home rows list today's
  boards solved with their times and how many are left; the Today tile counts the puzzles' boards solved today ("3 of
  12"). An older record's one daily board reads as Fair's (`PuzzleRecord.days`), its kept board too.
- **A hint that plays its move:** after a hint, the Hint button becomes "Do it" (H again) and plays the hinted move;
  it was counted as a hint when asked, so a best time stays out of reach.
- **The menu is a destination:** "show me the games", "what games do you have", "let's play", "I want to play
  something", "games", "play" and their likes in the ten languages (`IntentParser.gamesMenuSentences`, whole
  sentences, after Sidefolk's own and before a game's) open the Play panel's menu without AI; `games.open` without a
  game (or `"game": "menu"`) opens it for the AI, whose description says to do that rather than list the games in
  words, and answers with the games' names. "play trivia" still opens the game, "play this on the TV" stays Miraya's.
  `AppCoordinator.openPlayMenu(focus:)` is the one way to open it (`EventBus.gamesMenu`), for Ask's Play tab and the
  Pocket too.
- **Back always works:** the back arrow is shown on every game and never refused (`PlayBack`): at the start, mid-move,
  during a build-up, while the companion thinks, on the end card or after the game stopped, it puts the game away (to
  resume from the menu for ten minutes) and shows the menu at once; ⌘[ does the same, and ⌫ too where no part types
  with it (a word, a number, Sudoku's digits, a text field). It "sometimes didn't work" for two reasons, both fixed:
  the scene's picture fills the space behind the board, and over a short board (cups, rock, paper, scissors) it
  overflowed upward under the header, hidden by `clipped` but still taking the clicks, so back, the speaker and ✕ were
  dead there (the scene and table pictures no longer take clicks); and SwiftUI's views don't take the first mouse, so a
  click on the panel while it wasn't key only made it key. The Play panel now acts on that first click
  (`FloatingPanel.firstClickActs`), without activating Sidefolk, so the person's app stays in front. Checked in a debug
  app on ten games' states (a start, a shuffle, a build-up, the companion thinking, a word half typed, a reveal), eight
  of them as the first click on a panel that wasn't key.
- **Fixes:** Korean Daily Word rows keep every tile in its column, a syllable's pad drawn behind its jamo, so played,
  typed and empty rows are one width; Last Stick's taken sticks go entirely once none is left (the faded one stayed
  through the build-up before the end card); an end card's "3 – 2" (the person's, then the companion's) is isolated in
  the layout's direction, so in Arabic the person's number is on the "You" side of the bar whichever way the text runs
  ("7 / 10" stays left to right).

**Amended (2026-11-01), the games look v2 (`team/games-look-v2`):** the founder's "Imagine Skin" concepts (34, light and
dark, every game and the menu) set the direction, warmer and more illustrated, not a spec; read beside the app as it
was and the reviewed reward card. Adopted, adjusted where the rules say so:
- **One panel over one scene:** the game's scene now fills the whole panel, header included, and **dark mode is the same
  place at night** (14 night paintings of the day scenes, made from them with Codex image generation so the table a
  prop stands on is cut from the same rows; the arcade is night already), not the day dimmed. The header is a card of
  the panel's own surface over the scene (back, icon tile, title, whose game it is, speaker, ✕): the game's colour
  stays on its icon tile and the menu card, so the words read the same in every game.
- **Cards on the games' own surfaces** (`GamePaint`): the theme's raised card with a pale blue hairline by day and a
  moonlit navy one at night, a cool inset for the score's halves, a blue lip under raised tiles and buttons. "You vs"
  is one card with bigger faces (36 pt), a bigger score and still sparks at the VS; the round chip is bigger; the hint
  is a card whose first keys are in ink; the companion beside its bubble is 70 pt (56 over a puzzle, keyboard,
  letters or answers, for room). Trivia's topic cards each wear a pastel of the beds' palette.
- **A level chip is never red** (the concepts' red "Fair" is not taken): `GameStyle.levelChip` is the game's colour,
  or a neighbour where that colour is red or pink (Which Cup? and Quick Paws blue, Memory Pairs violet, Blossoms leaf
  green, Higher or Lower sky blue).
- **The menu** keeps its order and keys; each card puts the picture tile beside the title and tagline (three short
  lines in German, never cut), so more games show at once; the two groups get tinted heading bands (the companion's
  face, a puzzle piece); Wins, Streak and Played share one card. `GameArtTile`, `GameCard` and `GameSectionHeader`
  (Play/GameCards.swift) and `GameStyle.of(look)` are the one source for a game's picture and colours, for Playtime's
  page in Home too.
- **The reward card is the reviewed one** (the founder's flatter revision, ported): the result as one unit (an award mark
  beside the score: Sidefolk's trophy for the person's win, the verdict's symbol otherwise, on a soft tile of its
  colour), who won in words, the game's line, a small new-best chip, facts, flat actions with "Back to games", the
  level for the next game. The confetti and the trophy's rays are gone; the card springs in once. When the actions'
  words don't fit one row, the first takes its own (Higher or Lower's "Play again" was cut to "Pla…" beside "Switch:
  Mochi guesses").
- **Puzzles in a frame:** a pale blue frame around the board, Sudoku's boxes in its blue; Garden Plots is soil in a
  wooden frame with white numbers; the clock, the level and Sudoku's Notes switch sit side by side (a German level
  ran under the switch); Blossoms' beds are rounded tiles with a 3 pt gutter and the bed lines in it (ported
  from the same revision). Seesaw keeps its heart and star: the revision's blue crescent and sun are LinkedIn Tango's
  pieces, which this decision rules out ("no sun and moon"), and the concepts kept hearts and stars; switching is the
  founder's call (a `crescent` and `sun` symbol in Core, Playtime sending them, and its `minimum_sidefolk`).
- **Not taken:** a person's face invented for "You" (real data only: the Mac account's picture or the stand-in), the
  companion drawn big in every header, a Rock, Paper, Scissors screen redone as Playtime's look, decorative leaves
  and petals around boards (one focal point a screen). Higher or Lower keeps the thermometer (its cards in the concept
  are another game); Memory Pairs keeps its raspberry backs.
- **Art:** 14 night scenes (HEIC 768 × 1024, 19–51 KB) and two icons in the set's style (Guess My Animal a puppy,
  Seesaw a heart and a star on a toy seesaw; WebP); the folder is about 1.5 MB (`GameArtFilesTests` holds every look
  to a day and night scene of the same frame, an icon, and the budget).
- **Room and motion:** every board stays under 720 pt in English, German, Arabic and Japanese (the tallest, German
  trivia's set-up, about 715). Nothing new moves: the sparks are still, the scenes are pictures; the cups still pass in
  front of each other. Measured in a debug app: about 2–3 % CPU with the menu, a game or a puzzle with its clock idle
  in the panel, as with it closed.

**Amended by D101 (2026-11-03):** every game, its look, words, art and sounds, and the panel's layout now live in Playtime's pack (`Sources/Stage`), so an app update can't change them. The rule that matters stays, in the program and its tests: no result before the build-up, never red for a loss or mistake (D78), under about 720 pt, no live 3D. What 'as they are' couldn't hold is D101's accepted differences.

### D80 — A copy from before the renumbering gets the gallery's version (2026-10-31)
**Decision:** *amends D65.* An installed add-on from the gallery (an extension, companion or theme) is offered the
gallery's version on the person's channel when that version is newer, as before, or when the installed version is a
release the gallery doesn't list, nor any release above it (`AddonCatalog.offers(_:over:on:)`). Those are the copies
from before D65 numbered everything `1.0.0-snapshot.<n>`: playtime 1.2.0, git, currency, dev-toolbox and qr-codes
1.1.0, archives, feeds, images and pdf 1.0.0, companions at plain 1.0.0. They update like any other version (by
themselves when nothing new is asked, D70, else after a look), on Releases only to a release.

**Why:** the founder's Mac kept Playtime 1.2.0 and never got the games in `1.0.0-snapshot.2`, nor this week's
translations for eight more extensions: each looked newer than the gallery. D65 had accepted "remove and reinstall";
nobody would know to.

**Alternatives:** raising every add-on above 1.2.0 (the founder keeps them at 1.0.0 until released); a one-time
migration at launch (the rule is the same and also covers a copy restored from a backup).

**Implications:** a release the gallery publishes stays listed (D65 amended), so its copies are never offered a lower
snapshot. A waiting update is dropped once its version is installed (`AddonUpdateController.dropSettled`), not when
the installed one is higher. A copy of Sidefolk before this still needs the remove and reinstall.

### D81 — Responsive extension pages and a host-owned temporary audio mute (2026-10-31)
**Decision:** extension pages may end their side and main columns with `place: bottom`; this section and the ones after
it span the page, while a narrow window keeps the original order. A collapsible section may summarize its current
setting with `detail`. Miraya uses these parts for the approved responsive layout, with focused discovery, pairing and
live-sharing states. It retains presets for a screen region, rather than promising a freehand crop.

Miraya's sound choices are Mac only, TV only and Mac and TV. TV only temporarily mutes the Mac's default output,
including other apps, as Miraya's Mac app does; it does not use the microphone. `permissions.output_mute` separately
discloses this capability and widens an update, so installation requires review. The sandboxed extension sends an
ordered request to Sidefolk and reports TV-only only after confirmation. Sidefolk owns a helper outside the extension's
process tree; EOF on its pipe restores the previous mute state after the host exits, and stopping or crashing the
extension releases its lease. Only one extension holds it. Device changes and unsupported mute are reported; a person
unmuting the device is respected. The SDK delivers notices while a serialized tool request is waiting, so the host can
answer without deadlocking a long request. Validation trials cannot mute the person's output.

**Why:** the founder approved screens that adapt within Home and asked for the original Miraya app's three sound
choices. An extension-owned helper is unsafe here: Sidefolk deliberately kills an extension's complete process tree
on stop, crash or watchdog. The host-owned helper keeps that boundary and the recovery path separate.

**Verification:** fake-device and helper-process tests cover ownership, changes, timeouts and recovery. On the Mac's
actual default output, the helper muted and restored the original state both normally and after its parent was killed.
An isolated Android TV emulator confirmed pairing. Live screen and sound playback on a physical TV remains to be checked.

### D83 — An add-on version can need a Sidefolk snapshot, and an add-on Sidefolk can't read yet says to update (2026-11-01)
**Decision:** *amends D55 and D65.* A gallery entry's `minimum_sidefolk` may name a snapshot (`0.1.0-snapshot.593`):
copies of Sidefolk then compare their own published snapshot (`SidefolkVersion.running`, from the `SidefolkRelease`
stamp; a build on this Mac counts as its plain version) and leave the version out until they're that snapshot or later.
A plain minimum (`0.1.0`) still counts every 0.1.0 snapshot as 0.1.0. The gallery sets it in an extension's
`addon.json` (`build.py`), not its manifest, because a copy before this would refuse a manifest's
`"sidefolk": ">=0.1.0-snapshot.593"` (the validator now reads that form too). When an extension can't be installed only
because of keys this copy doesn't know or its `sidefolk` minimum (`ValidationReport.needsNewerSidefolk`), the sheet
says "This version needs a newer Sidefolk. Choose Check for Updates… in Sidefolk's menu, then try again." with the
validator's words folded in the detail.

**Why:** the founder's Mac on snapshot 590 was offered Miraya `1.0.0-snapshot.4`, which needs 593's `output_mute`, and
the Update button showed "That folder isn't a Sidefolk extension … permissions.output_mute isn't a known key". D75 and
D81 had accepted that refusal for snapshots; it reads as broken.

**Alternatives:** raising Sidefolk's version for each such snapshot (the founder keeps 0.1.0 until release); holding
the add-on back until everyone updates (no way to know).

**Implications:** copies before this snapshot still see such versions and get the old error; from this snapshot on
they don't. Miraya's `addon.json` names 593.


### D84 — The Lantern revamp: one calm look, themes that dress, one layout per place; phase 1, the foundations (2026-11-01)
*Amended by D130:* a new default theme, a theme-drawn selected row, a header in the sidebar and a rebuilt Today.
*Amended by D87 and D88:* a watch has its own page in Home and On duty's rows a bar of its checks (D87); each source has its own level in Settings › Attention (D88).
**Decision:** *narrows D58 and D64; builds on D71, D74, D77 and D78.* The founder approved the revamp design (a local
design folder: brief, three directions, the design system, screens to design, an audit, 250 mockups) and chose:
1. **Lantern is the direction:** native macOS surfaces, neutral, so the companion and its light are the warm things on
   screen; state as light (a pool at the companion's feet: aqua while it works, amber when something waits, dim in
   Focus); one surface family on the desktop, the Sidecard (whisper, card, Ask, stack); one deep aqua action colour
   that reads with its label in light and dark (#0B7783 / #3CD6DB; the pale brand aqua under navy read as disabled).
   Field Journal and Playroom may come back as themes on Lantern.
2. **Themes dress the app only:** colours, the display face, density, materials, radii, the light pool's colours and
   the nook's art. Each place has **one excellent layout**; a theme no longer arranges Today or picks navigation,
   Activity or editor layouts (narrows D64; the layout keys and presets stay readable until phase 3 retires them, so
   existing themes keep working).
3. **Firm cards never take Return:** another app's approval, agents' questions and anything after outside content need
   ⌘Return or a click (D58's rule, widened).
4. **Merges:** Conversations and Activity become History; AI and Voice become Brain; Trash moves into the Notebook.
5. **The Gallery moves into Home** and leaves Settings.
6. **Focus is a half circle, Quiet a moon,** everywhere (`Theme.Symbol`).
7. **Full access may have an end time** ("for 1 hour", "until tonight").
8. **Companion names stay in Latin letters in Arabic** (Mochi, not موتشي), direction-isolated.
9. **Only what exists is shown** (AGENTS.md: no fake features). Content the app doesn't keep yet (which facts went
   into an answer, a watched page's last two versions, a log of each watch's checks) is left out of the screens, or
   stored where that is cheap and safe, decided per screen.

**Phases:** 1 foundations (this), 2 the desktop (light pool, Sidecard, stack, permission slip, pins, agents lane), 3
Home (Today, the Say bar and ⌘K, On duty, History with Undo, You, Calendar's Agenda, the Gallery in Home), 4 Settings
and the rest (8 tabs with search, Attention, Brain, Trust, the menu bar Pocket, onboarding, updates, install sheets),
5 polish (Reduce Motion, Transparency and Contrast versions, German and Arabic on real systems, the companions' own
reactions). Each ships in snapshots behind the same tests; the version stays 0.1.0.

**Phase 1, built:** Harbor is Lantern (ink, surfaces, the action colour, status colours, every text pair ≥ 4.5:1 on
every surface, the action colour ≥ 3:1 on a card). New optional theme roles `well` (fields, chips, the search, a
segmented track), `glow` and `waitGlow` (light, never text): a theme without them keeps its `surfaceSunken` for wells
and Harbor's lights, with no warning, so Night Shift, Marshmallow, Field Notes and the gallery's Daylight, Night Studio
and Paper Garden pass as they are. Type: the theme's face dresses titles, the greeting, state words and numbers; what
is read, the companion's words included, is the system face (D58 had the companion's words in the theme face).
Eyebrows are sentence case. Sizes, depth (e0–e3), glass, motion tokens and the folk accents are Lantern's. Shared
components (docs/DESIGN.md): buttons with sizes, hover, press and working states; chips with their tone's ink; what-it-
touches chips; the segmented picker (every segmented Picker but the companion stage's, which falls back to a menu by
measuring AppKit's control); list rows; status badges, counts, state tiles, pins and folk avatars; fields and the
search as wells; the Say bar's shell, key hints and the understanding row; the Sidecard surface with its tail, the
whisper, card, slip strip and stack; the light pool and shoulder badge. A design-system sheet in the UI snapshots is
the reference. An approval's risk tag became a sentence-case chip.

**Phase 2, built (the desktop):** the companion stands on its light (`DesktopLight`: idle, working, waiting with
a count, alert while a card is out, failed, Quiet) with the count on its outer shoulder, VoiceOver hearing the state.
The bubbles are the Sidecard: a gentle notice is a whisper (6 s, a line runs out the time, it waits under the pointer
and grows into a card when clicked, Undo on it when an agent's change can be undone); an attention notice is a card
(who it is from, at most three answers, the rest in ⋯) that folds into the count after 30 s, and the companion calms
down; hovering the count fans what waits, clicking it or the companion opens Ask on top of them; the last held card
answered says "All clear" once. Ask is the Sidecard's largest size beside the companion with its tail to the head:
the Say field, an understanding row from the same parse that runs the words (`Understanding`: a sentence, chips, "On
this Mac, no AI" or the AI; ↩, ⌘↩, ⌥↩), Glance as its resting state, each request one card with its words inside.
The approval is a permission slip (`slipTone`: calm for the person's own words and Sidefolk's own extensions, firm for
another app, an unchecked extension or after outside content; only a calm slip of normal risk from the person's words
takes Return, everything else ⌘Return or a click); a slip arriving while Ask is closed stands alone above the head.
Pins and the agents lane (`AgentLane`: a face per working or waiting Claude Code or Codex session) are kept small at
the founder's request during the phase: the companion's corner is no bigger than before (281 × 159 pt at the medium
size in 3D, with three folks, two pins and two agents), pins show their number, agents a face with a status dot,
details only in a tip on hover, and the extras fade and shrink while the person types in a window under them or passes
the pointer through (the senses the companion's life already reads, no permission). With phase 4 merged, Focus
dims the light to grey with its half circle on the shoulder (or, in grey, how many wait, the whispers it holds
included) and Quiet puts the light out with a moon; when either ends, what was held comes back as phase 4's one card
("While you were focused", and the same card with Quiet's words; `HeldSummary.quiet`), signed "Mochi · Focus ended".
The morning brief is a card with its day as rows; toss captions are whispers. Today's Needs you shows approvals as the
same permission slip (`ApprovalCard` is retired; a slip ignores answers for its first 0.8 s rather than looking
disabled). An agent session's notice names the agent and its project ("Claude Code · sidefolk"). *Not built:* the
evening wrap, the drop choice card, the stack's arc animation, the level-reactive pool for voice, keyboard answering of
cards outside Ask. The Play panel stays as it was (games are another teammate's).

**Phase 3, built (Home):** one layout in every theme. The sidebar (232) holds the companion live in its nook (its
portrait in the desktop's pose on its `LightPool`, a state chip, one line), the five places (Today ⌘1, Calendar ⌘2,
Notebook ⌘3, On duty ⌘4, History ⌘5), the Notebook (You, the Inbox and collections in tinted squircles, the Trash last as
a filter), the person's extension pages arranged by dragging (pages put out of the sidebar are one menu row; All
Extensions is gone) with "Get add-ons", and Quiet at the foot (the menu bar's Quiet; Focus comes with phase 4's
Attention). The toolbar has the place's title and line, the Say bar in the centre (⌘K, `SayBarField(size: .home)`) whose
panel says in plain words what Return will do, its parts as chips and whether AI is used, from the same `IntentPlan` that
runs the words, with ↩ / ⌘↩ / ⌥↩ as buttons and what the words find under it. **Today:** a greeting with the Mac's first
name and one deterministic sentence (`DayBrief`), three counts (need you, on duty, done today), the day as a line, then
Needs you (three cards, the rest folded into one line with Show all; held in one card while Quiet is on; all clear says so
with what's next) beside On duty at a glance (watch and live-value tiles, agents at work, extension tiles), and what was
captured today; a first day keeps the day and offers three starts that fill the Say bar. **On duty** (new): every watch,
live value, repeating reminder and routine, agent session, command and extension working in the background (a page whose
main switch is on), grouped by folk with state and Pause, Resume or Stop through the existing calls (`OnDuty` counts what
runs, paused ones are listed but not counted). **History**: Activity, the kept conversations, what Sidefolk told the
person (attention items) and other agents' sessions as one timeline (`HistoryTimeline`) by the hour, a plain sentence
per row with an outcome chip (said no and skipped are calm), Undo where Activity's undo still exists, the exact record
folded in each row, conversations opening in place with their reply field, sessions as receipts of their calls; filters,
a span and search. **You**: the About-you facts as a profile with where each came from, Edit (in place) and Forget (the
Notebook's Trash with its Undo); facts another agent suggested wait at the top, out of answers, with Keep (new: re-tags
the fact as the person's, `ProfileFacts.keep`). When a fact was last used isn't kept, so it isn't shown. **Calendar**: the
Agenda (two weeks as a list, today's now line, a repeating reminder once a day with how many more) comes first, then Week
and Month. **The Gallery** is in Home on Settings' own models (companions with big pictures and the browser's filters,
extensions with their passport: what they can touch once added, else that the install preview says it, who signed them,
amber when Sidefolk didn't check them; themes); Settings' Companion and Extensions tabs lose their Gallery page for a way
to it. **Retired** (one layout per place): the theme layouts' rail, pills, ribbons and status bar, the Today blocks
(console, planner, board, stage), the Activity table/log/diary styles and the Markdown editor with tabs; the keys still
decode, so themes keep working, and `ThemeCheck` still reads them. A reminder's Activity line reads its time as a date,
not ISO. Not done: the permission slip on Today's cards (phase 2's `ApprovalCard`), the Week view's "read only" note and
"+1" overlaps, a watch's detail page (A9: no check log or page versions are kept), Focus in the sidebar's pill. *(The
Week view's two were built later, team/leftovers: a "+N" in a column's last place when an overlap needs more columns
than fit at 34 points each, which opens the day, `CalendarGrid.fit`; and a line under a week with the Mac calendar's
events saying they are read only here.)*

**Why:** the founder found the app inconsistent: nothing showed how much something mattered, the main button read as
disabled, the desktop's five surfaces looked like five designs, and safety screens spoke engineer. One look, one layout
per place and one component set keep the product learnable and let extensions place parts predictably; themes still
serve different people through how things look.

**Alternatives:** Field Journal (paper and ink: slower, hard with glass and 3D companions) or Playroom (bright, toy-like:
tiring, fights extension pages and themes) as the base; themes that keep arranging Today (D64: every arrangement needs
its own care and extensions can't count on a place); a new `canvas` role (the page already is `surfaceSunken`); new
roles required (every existing theme would warn).

**Phase 4, built (Settings and the rest):** Settings is a sidebar window (920 × 700, at least 760 × 480) with a search
and eight tabs: General (a waiting version on top, start, updates, words for times, the welcome), Companion (D77's
chooser restyled; its Sounds moved to Attention), Attention, Brain (AI and Voice), Trust (was Privacy & Permissions),
Connections (was Agents), Add-ons (was Extensions; "Get Add-ons" opens the old gallery page until Home has it) and
Appearance (theme, light or dark, density, Home's icons). Every setting kept a home; the old tab names still open
the right tab (`SettingsTab.privacy` is Trust, and so on), and every "Settings › AI/Privacy/Extensions…" sentence
points at the new tab. **Search** reads `SettingKey`, one catalog of every row and group with its tab, section,
title and detail (`SettingsRow(_ key:)` takes its words from it, so the page and search can't disagree); matching is
`SettingsSearch` in Core (each word starts a word of the title, detail or section, accents and case ignored, titles
first; CJK matched anywhere), results grouped by the tab with the best match, the match marked, switches and short
choices usable in place, ↑↓ and Return or a click to jump: the tab opens, scrolls to the row, and the row glows.
**Attention** is built on Attention's own rules: Open, Focus and Quiet with an end ("for 1 hour", "until 18:00",
"until tomorrow morning", "until I turn it off"). Focus is new and real: whispers wait and come back as one "While
you were focused" card when it ends; cards that need an answer still come (`AttentionEnvironment.focus`,
`AppSettings.focusUntil`). Quiet hours every night (off until turned on; choosing Open or Focus inside them sets the
rest of that night aside), what a full-screen app does (Quiet as before, Focus, or nothing), sounds, notifications
and the morning brief. A timer looks again when an end or a quiet-hours edge passes. The per-source "what may
interrupt you" table of the mockups was left out: no source has its own level to set. *(D88 built it.)* **Full access may end**
(`GuardPolicy.fullAccessEnds`, `beforeFullAccess`, `choose(_:fullAccessEnds:)`): Guard reads the policy through
`current(at:)`, so past its end Full access is the mode it replaced even if no timer fired (the Mac asleep, Sidefolk
quit); the sheet offers in 1 hour, tonight at 22:00 (while more than an hour away) or when turned off, and its button
is the primary, not red. **Trust** leads with Guard and the four modes as cards, each with what it does to one
example step. **Appearance › Density** (`AppSettings.density`) overrides the theme's spacing. **The menu bar Pocket**
replaces the long menu: a popover with the companion and its state, the Open/Focus/Quiet dial with its end, Full
access with Turn Off, a waiting version, Needs you, Next up, Agents and an Ask field; a right-click (or ⋯) has Open
Sidefolk, Settings, palettes, Hide/Show Companion, Check for Updates… (or Update to …), About and Quit. The icon's
corner says the state (amber dot, half circle, moon), fades while the companion is hidden, and stays orange in Full
access. **Install sheets** are a two-step passport (who made it, then what it can touch), D71's words and tones
unchanged, Install armed only on the second step. The update window and About are on Lantern. Onboarding stays on the
desktop (D4) and its bubbles are phase 2's; its "Connect…" now opens Settings › Connections, where each file that
changes is listed, instead of connecting at once.

**Phase 5, built (polish):** the whole app walked as a person would in the debug app (onboarding, a reminder typed
and fired, its card, fold and stack, another app's approval, Focus and Quiet with their one card, every place of Home
with ⌘K, every Settings tab and search, the Pocket, an extension installed from a folder, the Gallery, a game from
Playtime), then fixed: the Calendar asked Home's window for more height than it had and pushed the whole window under
its toolbar; Today's reminder card lost Done (its main answer was sorted out) and cards keep their answers at the
trailing end, as in Ask; a card replacing a shorter one is measured again (it was cut at the top); onboarding's lines
never fold or make an "All clear"; the Say field's ring had flat bars beside its round ends; empty On duty and You
had two primaries; History and Today name another app's notice by the app and show the companion's face for its own
words; opening a tab clears an old search; "In 10 min" for the snooze; buttons in sentence case; Trust says History,
not Activity. What a "While you were…" card told is settled in the store (a notice as told, a question as shown in
Needs you), so it never comes back after a restart or counts twice. `ThemeCheck` reads only `layout.icons` (and a
preset's icons); the other layout keys still decode, unread and unsaid, and a new theme writes only its icons. Every
`.roundedBorder` field is on Lantern's well (`.lanternField()`, `WhenField(boxed:)`). Pins at rest show their number
and unit (`PinValue.atRest`: "17.2 GB", the rest in the tip). Reduce Transparency draws every glass solid;
Increase Contrast makes `Theme.line` a control's border through the high-contrast appearances, and fills without a
border (wells, the segmented track, the Pocket's cards, Today's cards) get one (`.contrastEdge`); snapshots stand in
for both with `\.solidSurfaces` (`a11y-*`). VoiceOver hears a card or whisper arrive. Home's nook keeps a still light:
its breath redrew the whole window every frame (Home open: 4.1% CPU against 1.4% before the revamp; now 1.5%; the
desktop at rest 1.4% both). *Not done:* the mockups' per-source "what may interrupt you" table (no source has a level
of its own), Ask's "Open in History" header, the companions' own reactions, the evening wrap and drop card.

**Desktop polish, built (2026-11-01, branch `team/desktop-polish`):** what phase 2 left, each on a real path.
- *Cards answer from the keyboard outside Ask:* a global shortcut (⌃⌥Space unless changed in Settings › General,
  "Answer cards from the keyboard") is registered only while a card, a slip or held cards wait, and is off when
  macOS (input sources use ⌃⌥Space on many Macs) or Ask's or talk's shortcut has the same keys. It hands the
  keyboard to the slip standing alone, else the card in front (a whisper grows first), else the held cards fanned
  with the newest chosen. ↩ presses the answer in focus only on the person's own cards (`AttentionItem.takesReturn`:
  reminders, commands, the brief, Sidefolk's own words); everything else needs ⌘↩ and says so; ⎋ puts a held card
  back (closes the companion's own); ←/→ and Tab move between answers (⋯ is one stop, its menu opens);
  ↑/↓ bring the other held cards to the front; answering moves to the next held card. A key line on the card says
  what the keys do. A held-down Return answers one card, keys wait half a second after a card changes, and the
  keyboard goes back when the person clicks elsewhere. The logic is `CardKeys` (core, tested).
- *Ask's header:* Ask, Today and Play tabs under the name (Today: Needs you and Next up, with its count; Play opens
  the Play panel in Ask's place); "Just now · Open in History" for the open AI conversation. The field stays on
  both tabs; typing or a new result shows Ask; Ask opens on Today when nothing is in the conversation and something
  waits or comes up. Glance left Ask's resting state for the Today tab.
- *The drop card:* a dropped file, folder, link or text shows four choices in a 2×2 card in Ask, each with one line
  of what it does (`DropChoices`): file or folder Save to notebook, Watch it, Ask about it, Open with… (the apps
  macOS offers); link Save link, Watch page, Ask, Play on TV when Miraya's tool is there and the link is an https
  video (`ext.miraya.play_on_tv`, through Guard as its sentence runs it), else Remind me; text Save as note,
  Remind me, Ask, Copy. Return does the first; typing still asks about the item, as before.
- *Motion:* held cards come out of the shoulder count along a short arc and fold back into it; a card that folds
  drops into the count as a small copy of itself (a window of its own for half a second). While the microphone
  listens the light swells with the voice (`VoiceLevel`: twelve reads a second, eight steps, only a change reaches the
  screen). None of it with Reduce Motion or Increase Contrast's ring, nothing at rest: idle CPU measured side by side
  with origin/main (top, 12 × 5 s, two pins and two agents, a busy Mac): 2.14% against 2.09%.
- *VoiceOver:* the companion's corner is one "Sidefolk companion" group: the companion (name, state, press to talk),
  what it says above its head (the card, held cards or slip; pressing gives it the keyboard), the count, the pins top
  to bottom (value, how live, their menu), the agents' faces, the folks, each pressable as a click is. The card's
  window is named. `swift scripts/dev.swift ax` writes the tree; SwiftUI's own parts appear only to a connected
  assistive app, so the Sidecard's inside is checked in code and snapshots.

**Implications:** phases 2–4 build on `docs/DESIGN.md`'s tokens and components. Not done in phase 1: the 16 text
fields still on `.roundedBorder`, the theme-only Today blocks' capitals (console, planner), the macOS switch's tint in
snapshots (AppKit draws it grey in an inactive app). `glow`/`waitGlow`/`well` are written by `sidefolk theme new`.

### D85 — A companion added from a folder may bring a 2D form, painted, beside its 3D one (2026-10-31)
**Decision:** *amends D43 and D60.* A 3D companion added from a folder (D60) may carry a `2d/` folder: `species.json`
in the custom companion format (D43) with its `parts/*.svg` and, new, `paint/*.png`. When it does, it comes in both
looks like a gallery companion (Settings › Companion › Look, 3D first; the choice is kept per companion,
`AppSettings.dimensions["local.<name>"]`), and in 2D it is drawn from that data on the soft rig, its paintings fitted
over its outlines as the gallery's 2D forms are (D59). The format gained, all optional so every file that loaded still
does:
- `paint`: `head`, `torso`, `armL`/`armR`, `footL`/`footR` (arms and feet in pairs), each `{image, nudge?, grow?,
  widen?}` like `Species.painted`; PNGs of at most 2048 px a side and 4 MiB, eight at most.
- `body.look` `"flat"` (the 2D cartoon of D59: one fill, one hard shade, an outline, `body.line`) or `"soft"`.
- `face.screen` `{center, size, radius}`: a dark screen whose eyes and mouth are light (Spark's), in `face.glow`
  and `face.mouthGlow` instead of the style colour; `face.ink`, `face.iris`, `face.eyeSize`, `face.mouthSize`.
The `2d/` tree is checked like the rest of the folder (names, kinds, sizes, nothing else in it), and its data is loaded
and drawn in every state before the companion is added: one whose 2D form doesn't load isn't added. Nothing in it runs;
it is data, as D43's always was.

**Why:** the founder wanted a private companion in 2D as well as 3D, kept out of the repositories like its 3D files
(D60). The gallery's 2D forms are Swift rigs and paintings built into the app (D59), which can't hold a private one;
D43's data couldn't say paintings, a screen face or eye colours, so a robot with a black visor would have had dark ink
eyes on black. Extending the data keeps one 2D engine and one format, and makes "Made by you" companions better too.

**Alternatives:** a Swift rig on a local branch that is never pushed (fragile, and private code beside the app's);
shipping 2D rigs as data in gallery packs (later, on this format); a separate 2D companion in "Made by you" (two
entries for one character, and no Look switch).

**Implications:** `SpeciesFile` (`paint`, `body.look/line`, `face.screen/glow/mouthGlow/ink/iris/eyeSize/mouthSize`),
`CompanionBody` and `Species(custom)`; `Species.painted(image:)` and `Painted(image:over:)`; `SoftFace.glow`,
`mouthGlow`; `AddonStore.checkLocalFiles` allows `2d/`, `InstalledCompanion.twoD`; `OwnedCompanion.looks` for a folder
companion; `AppSettings.dimension(forLocal:)`; `CompanionArt.localForm`, the Look switch and stills for it;
`docs/research/lively-companions.md` documents the keys.

### D86 — Only the copy on the person's own data folder changes their agents' configs (2026-11-01)
**Decision:** *amends D16 and D42.* `IntegrationLocations.forApp(paths:)` gives the app the real `~/.claude.json`,
`~/.claude/settings.json`, `~/.claude/skills`, `~/.codex/config.toml`, `~/.codex/hooks.json` and
`~/.codex/skills` (honouring `CLAUDE_CONFIG_DIR` and `CODEX_HOME`) only when `SidefolkPaths.isDefaultHome`,
and `commandLineTool(paths:)` gives it `~/.local/bin/sidefolk` on the same condition. A copy on any other
data folder (`SIDEFOLK_HOME`: `make dev`, agents' QA runs, a release build pointed elsewhere) gets stand-ins
in `<home>/agent-configs/`: `claude/` and `codex/` laid out as `CLAUDE_CONFIG_DIR` and `CODEX_HOME` folders
(whatever the environment says, since an agent's shell can name the real ones), and `.local/bin/sidefolk`.
At launch `prepareStandIns` starts them as this Mac's agents are (an empty `.claude.json` and the folders
where the real ones exist; it only checks that they exist), so Connect, its dialog, backups and
Disconnect work in a dev copy exactly as for the person, on files nobody else reads. The helper's
environment carries `SIDEFOLK_HOME` whenever the folder isn't the default one, not only in debug builds.
**Why:** on 2026-10-26 a QA run (home `build/qv1` in an agent worktree) clicked Connect. The locations
were the real ones, so the founder's Claude Code and Codex were pointed at `<worktree>/build/qv1/bin/sidefolk`;
the worktree was deleted, and both failed on every start ("ENOENT … bin/sidefolk"), hooks included.
AGENTS.md already said dev runs must not touch agent configs, but nothing enforced it. The fix was first
written on 2026-10-27 (as a "D44" on a branch that never reached main, whose number main has since used for
companion play) and is ported here onto today's code.
**Alternatives:** *refusing Connect unless an opt-in variable is set*: safe, but Connect could no longer
be tried in a dev copy, and the opt-in is one `export` away from the same accident. *Honouring
`CLAUDE_CONFIG_DIR`/`CODEX_HOME` in dev copies*: an agent's own shell may set them to the real folders.
*Keying on `#if DEBUG`*: a release build on a QA folder would still write the real files.
**Implications:** `SidefolkPaths.isDefaultHome` and `agentConfigs`; the command link's dialog names the
stand-in's place in dev copies. To try a dev copy's Connect with a real agent, run that agent with
`CLAUDE_CONFIG_DIR=<home>/agent-configs/claude` or `CODEX_HOME=<home>/agent-configs/codex`.
`IntegrationLocationsTests` checks a non-default folder never resolves to the real paths, even when the
environment names them, and that installing and removing all six connections there leaves every byte of
the person's folders as it was.
*Amended the same day (team/leftovers):* Connections' cards name where the copy really writes
(`IntegrationLocations.shownPlaces`, `IntegrationStatus.places`): the stand-ins in a dev or QA copy, the folders
`CLAUDE_CONFIG_DIR` and `CODEX_HOME` name otherwise. The command's dialog in such a copy names its stand-in and gives
`export PATH="<home>/agent-configs/.local/bin:$PATH" SIDEFOLK_HOME="<home>"` instead of a line for `~/.zshrc`. Snapshot
`page-settings-connections-dev-copy`.

### D87 — A watch keeps its history: every check, the latest change's two versions, and its own page in Home (2026-11-01)
**Decision:** *amends D84 (a watch's detail page, left out for want of a history) and D58 (the page change kept for
Today's tile).* Every watch that isn't a live value (D35) keeps a record of its checks and, for a page or a file, the text
it compared, and has its own page in Home.
- **The check log** (`watch_checks`, migration `v6-watch-history`): each check is unchanged, changed (with the notice's
  words), failed (with the reason, the same words as `lastError`) or paused, with how long it took. Checks in a row that
  found the same thing are one row with a count and their first and last times, so a watch looking every 30 s writes a
  row only when the outcome changes; a run that only grew reaches the database with the watcher's routine saves (every
  5 minutes, `WatcherEngine.routineSaveInterval`) and on quit (`flushHistory`), and readers ask the engine, which has it
  as it stands. Waiting for a busy site or the network (`ProbeError.deferred`, `.offline`) isn't a check. Reports keep
  no log: they read every few seconds and keep their own line of values in memory (D58).
- **Versions** (`watch_versions`): the extracted text the probe compared, never the HTML: a page's readable lines
  (`PageText`), a plain text file's lines (`FileText`: an allow list of text kinds, 512 KB at most, UTF-8, read only on
  the first look and when the file changed, invisible and bidirectional controls removed, SECURITY T2). The first look
  is kept, then each change with what it was before (`ComparedText`); only the newest two stay, each cut at 32,000
  characters on a line, and the same text twice is kept once. A file that isn't text keeps none: its size and time are
  what it compares.
- **Kept small:** checks older than 30 days go at the daily tidy (`SidefolkRuntime.housekeeping`), and at most 500 rows
  per watch whatever their age. The two versions stay while the watch does (the newer is what the next change is
  compared with). Both tables reference `watchers` with a cascade, so stopping a watch deletes its history; "Your
  data" exports both (`watchChecks`, `watchVersions`) and "Delete all data" empties both. Nothing leaves the Mac.
- **The watch's page** (`HomeSelection.watch`, `WatchDetailView`), opened from On duty's rows, Today's watch tiles (the
  popover they had is gone) and a changed-watch card on Today ("See what changed", a link, so the card keeps its three
  buttons): what it watches, how often, Scout, since when and until when; Check now (the one primary while it watches)
  or Resume (when it doesn't), Pause and Stop watching (confirmed: its history goes with it), through the same
  `AppServices` calls On duty uses; "What changed" for page and file watches, inline or side by side (`LineDiff`: every
  line that differs, in reading order, two lines of context, at most 600 lines), in the text's own direction; and the
  timeline of runs under a bar of the last 48 checks. A page watch from before this shows the changed lines D58 kept.
- **On duty's bars:** each watch row has its last 24 checks as ticks (`CheckTicks`), with their counts in words for
  VoiceOver; "Watching" is no longer a chip there (the bar says it), other states still are.
- **Colours (D78, `StatusTone.check`):** a change is news (the accent), a failed check amber; red stays for a watch that
  stopped (`StatusTone.watch(.error)`). In "What changed", removed lines are struck through in muted ink and added ones
  sit on the news tint, marked − and +.
- **For agents:** `watch.list` adds ", last changed 2 h ago" to each watch that changed, with the notice's words in
  brackets only for kinds whose summary is made from the watch's own settings (`url_change`, `site_status`,
  `file_changes`, `file_appears`); a folder's new file names, a program's or an extension's words are outside content
  (T2), so for those only the time is said. No tool's input schema changed, so MCP clients see the same tools.

**Why:** the founder: a watch only kept its latest state, so the app couldn't say when it last changed, what changed,
or that it had been failing all night; D84 left the watch page and On duty's bars out rather than fake them. A run-length
log keeps a month of a 30-second watch in a few rows, and keeping the compared text (not the page) is what makes "what
changed" possible at a size that doesn't matter (two versions of 32,000 characters, 50 watches at most).

**Alternatives:** a row per check (2,880 a day for one file watch, and a write every 30 s against the routine-save rule);
keeping the fetched HTML (big, and not what was compared); a diff stored at change time instead of the two versions (no
side-by-side view, and nothing to compare the next change with for files); reading a file's text at every check (it
compares size and time; reading only on a change costs nothing while nothing changes); putting the change summary in
`watch.list` for every kind (it would make the list outside content whenever a folder watch fired).

**Implications:** `WatchCheck`, `WatchVersion`, `WatchHistoryStore`, `WatchHistoryLimits` (Storage); `ProbeResult.compared`,
`FileText`, `LineDiff`, `WatcherEngine+History` (`note`, `keep`, `checks(for:)`, `recentTicks`, `versions(for:)`,
`lastChanges`, `flushHistory`); `StatusTone.check`; `DataPorter`; the app's `WatchDetailModel`, `WatchDetailView`,
`WatchChecks.swift` (`CheckTicks`, `CheckRow`, `CheckWords`), `WatchChangeView.swift`; `NowModel.ticks` and
`openWatch`; `WatchTile` and `ChangeLines` removed; `swift scripts/dev.swift home:watch[:<id>[:check|:sidebyside]]`;
snapshots `window-home-watch*`.

### D88 — What may interrupt you: a ceiling per source, Only in Today, and "done today" counts only what was done (2026-11-01)
**Decision:** *amends D84 (phase 4 left the per-source table out) and D12.* Every notice now has a **source** with a
level the person sets in Settings › Attention › What may interrupt you: reminders, watches (all, and one watch set
apart), commands (`sidefolk run`), each agent by its client name (Claude Code, Codex, then any other app that called
Sidefolk or started a session), each extension whose watches report, games (the companion's lines while playing) and
the companion itself (its AI's notices, routines, folk introductions, "All clear"). The levels are **Card** (may step
forward), **Whisper** (gentle; if it needs an answer it folds into the stack when it fades), **Only in Today** (never on
the desktop: kept in Today, `AttentionItem.State.kept`) and **Off** (History only). Reminders offer no Off; games only
Whisper or Off. A notice gets the **lower of its own level and its source's ceiling, then Focus or Quiet**
(`Interruptions.route`, applied first in `AttentionCenter.consider`, so a held notice is judged again when it comes
back). **Never turned down:** a question (`refKind "ask"`) and an agent session that needs the person (its approval in
its own window); Guard's approvals never go through the attention center at all. The most specific level the person set
wins (a watch, then its extension, then all watches); unset levels are the source's default, which is the behaviour
before D88, and a default clears the stored value. Stored as `AppSettings.interruptions` (`{"agent:codex": "today",
"watch:<id>": "whisper"}`); settings from before decode to the defaults and unknown keys or levels are skipped. To tell
agents apart, a session's notices are `session:<agent>:<id>` (from before: no agent, so no ceiling), and an extension's
watch posts as `extension:<id>` (`Watcher.noticeSource`; the card still reads as Scout's watch). A card's ⋯ menu has
**Show these as whispers** (a card from a source at Card) and **Fewer like this** (Only in Today), for its most specific
source; the card goes as a whisper would, and a whisper says what changed with **Undo**. `notify.user` tells the agent
when its notice was kept in Today or turned off, so it doesn't resend it. Today shows kept news under **Kept for Today**
(who · when, its answers, Dismiss) and kept notices that need an answer in Needs you; the desktop count, the stack and
the Pocket leave them out.

**"Done today"** (`DayBrief.doneCount`, the one definition) counts reminders and tasks finished today, notes, ideas,
tasks and links saved today, and today's other calls that changed something (`ToolSpec.mutates`), refused, failed and
skipped ones left out. Reads (searches, lists, another agent's `status`) never count, and the calls whose result the
stores already count (`notes.save`, `reminders.complete`, `notes.update` to done) aren't counted twice.

**Why:** levels came only from each event's kind, so the person could quiet everything (Focus, Quiet) but not one
chatty agent; the founder's sessions finishing many times an hour were the case. A ceiling keeps each poster's own
judgement (a failure stays louder than a success) while letting the person cap it, and Only in Today keeps the news
without the interruption. Questions and approvals stay out of it so nothing waits unseen. "Done today" counted every
call that didn't fail, so Codex checking `status` made the day look busy.

**Alternatives:** a level per event kind (too many rows; the person thinks in who, not what); Off for reminders (the
person's own words at their own time; Only in Today is the quietest); storing the source's agent in a new column (a
migration for what the source string can say); counting done from History's rows (they mix reads and changes).

**Implications:** `Interruptions`, `InterruptSource`, `InterruptLevel` (Core/Attention); `AttentionEnvironment.
interruptions`, `AttentionCenter.kept()`, `AttentionStore.kept()`; `SidecardItemCard.fewer`, `SidecardModel.
lowerSource`, `AppCoordinator.lowerSource/undoLevel`; `InterruptionsGroup` in Settings › Attention and
`SettingKey.interruptions`; `NowModel.kept` and Today's Kept for Today; `CueDirector.linesShown`; the debug command
`interrupt:<source key>:<level>`. Tests: `InterruptionsTests`, `InterruptionsCenterTests` (every level against every
ceiling, then Open, Focus and Quiet), `DoneTodayTests`.

*Amended by D89:* the table gains **Add-on updates** (`addonUpdates`, key "addons"), Whisper by default: the whisper
after updates waited a day and the heads-up about an update to look at.

### D89 — Add-on updates in sight wherever add-ons appear, with Update all (2026-11-01)
**Decision:** *amends D70.* Updates that wait for the person (the switch off, or an extension update that would do more)
are shown where add-ons are, from one list (`UpdateModel.addonPending`, kept by `AddonUpdateController`):
- **Home's Gallery** leads with **Updates** and a count: one row per add-on (companions, extensions, themes) with
  Update, Review… for one that would do more, its progress while it installs, Updated or Try again, and **Update all**.
- **An extension's page** has a calm "Update available" strip with **What's new** (the install sheet, which says what
  the version changes, D71) and Update; **Settings › Add-ons** rows say "New version x" with Update beside their switch,
  and a card offers Update all; **Home's sidebar** marks a page's row with an accent dot and counts updates on Get
  add-ons; **Today** has one compact row (count, names, Update all, Show), the **Pocket** one row in Needs you.
- **Update all** installs every waiting update that asks for nothing new, one at a time, by D70's own rule
  (`AddonUpdater.updateAll`, the path a timed look with the switch on takes too). One that would let an extension do
  more stays listed with Review…, which opens its install sheet; one that fails keeps its old copy, says why and has
  Try again, and the rest go on. It ends with a summary ("3 updated, 1 needs your review"). A single Update does the
  same for one, and opens the sheet at once when the version asks for more. A version needing a newer Sidefolk is never
  offered (the catalog leaves it out, D83).
- **One whisper** ("2 add-ons have updates", Update all and Show) once updates have waited a day with the switch off
  (`AddonUpdateNudge`); then nothing more about them, only about a later one after its own day. Its source is
  **Add-on updates** in D88's table (`InterruptSource.addonUpdates`, key "addons", Whisper by default), which also
  covers D70's heads-up about an update to look at.

**Why:** the founder: "If I don't go there on purpose, I'll never notice." Updates lived in Settings › General and on
gallery cards only. The App Store and Google Play put an Updates list with Update all where apps are, and say so once.

**Alternatives:** a card per update on Today (a pile; the founder asked for one row); release notes in the catalog
for What's new (the gallery publishes none; the install sheet already says what a version changes, honestly);
installing widening updates with Update all (they need the person's look, D70); nudging with the switch on
(updates then install by themselves; the review heads-up stays per version, D70).

**Implications:** Core `AddonUpdater.update(_:)`, `updateAll(_:step:)`, `AddonUpdateStep`, `AddonUpdateOutcome`,
`AddonUpdateReport.failed/summary`, `AddonUpdateNudge`; `AddonStore.updateCompanions` went (the updater installs
companions). App: `UpdateModel.addonSteps/addonSummary/addonRecent/addonPending/addonInstallable/addonRows`,
`AddonUpdateActions.update/showAddonUpdates`, `Updates/AddonUpdateViews.swift`, the whisper's kind `addon-updates`;
dev commands `addons:updates|nudge|auto:off|get:<id>|check|updateAll`; snapshots `window-home-gallery-updates`,
`window-home-today-updates`, `page-extension-clipboard-update`, `page-settings-addons-updates`,
`panel-pocket-addon-updates`. Tests: `AddonUpdateAllTests`.

*Amended the same day (team/leftovers):* the Gallery's Updates shows under every filter and while searching, only the
updates that filter or search shows, and its Update all updates those (`AddonUpdateActions.update(_ entries:)`). An
update that Update all left for review, then reviewed and installed, says Updated. Checked live: a signed local gallery
whose QA Net 1.1.0 asks for the network; Update all updated QA Notes and left QA Net with Review…, whose install sheet
said "New permission: Can use the internet" and installed 1.1.0 on Update (dev commands `addons:review:<id>`,
`installSheet:continue|install`). Snapshots `page-home-gallery-updates-extensions`, `page-home-gallery-updates-search`.

### D90 — Ask tidies itself by each result's weight; agents' sessions in one folder are one line (2026-11-01)
**Decision:** *amends D5 and D84.* Results in Ask go by themselves, each by its weight (`ResultLifetime`):
- **Quick** (a value read now, a lookup, a calculation, chance, a notice): about two minutes after it was first seen
  in Ask, so opening Ask again five minutes later finds it gone. Not seen yet, it waits for its look.
- **Normal** (an answer, something made: a note saved, a reminder set; an error with nothing to retry): half an hour,
  or the day: the next day's first look starts clean.
- **Needs you** (an approval, a question, a failure with Retry): until dealt with or cleared.
A request goes when all its results are past their time; a small Pin on it keeps it; Clear all stays. Nothing goes
while the pointer is on Ask or Ask has the keyboard (Ask opening tidies first); what goes fades, and a quiet line,
"Older answers are in History", links there: everything is still in History. The ten-minute reset that emptied Ask
now only starts a new conversation. Ask's "Working" list is gone (the agents' faces, On duty and the Pocket show
who works), and sessions of one agent in one folder in the same state (subagents, a second terminal) are one face,
row or line with how many (`AgentSessionGroup`): "Claude Code in sidefolk · 3".

**Why:** the founder: people ask and go without clearing, and an old battery level was still there ten minutes later;
the same session three times read as noise.

**Alternatives:** one fixed time for everything (a question waiting would vanish); clearing on every open (an answer
read a minute ago would be gone); keeping them and collapsing old ones (still a list to scroll).

**Implications:** `AskEntry.seenAt`, `.weight`; `AskModel.opened`, `tidy`, `pinnedRequests`, `tidied`; the panel
looks every 15 s only while open. `AgentChip.count`, `Glance.sessions` as groups.

### D91 — Back up everything to one file, restore it on another Mac or after starting fresh (2026-11-01)
**Decision:** Settings › Trust › Your data (and the app menu) gains **Back up everything…** and **Restore from a
backup…**; onboarding's first bubble offers "Restoring from another Mac?".
- **The file** (`Sidefolk Backup <date>.sidefolkbackup`, a zip, 0600): `manifest.json` (format 1, app version and
  snapshot, when, which Mac, the database's migrations, counts, every other file's SHA-256), `data/` (the database copied
  with `VACUUM INTO`, never the live file; ExtensionData, ExtensionDrafts, Skills, companions made as data), `review/`
  (extensions installed from a folder or written for the person, companions added from a folder, themes of their own)
  and, only when chosen, `keys.json`. Gallery add-ons are only named (id, version, on or off): a restore fetches them
  from the gallery again, signatures checked (D55); their signed files are never copied. Left out: logs, caches,
  downloads, the sandbox profiles, chart history, and Claude Code's and Codex's configs (connect again, D86).
- **Keys** only with "Include my keys, protected by a password": the providers' keys with their host bindings and the
  MCP servers' secrets, sealed with AES-GCM under a key from PBKDF2-SHA256 (600,000 rounds, random salt). Sidefolk
  doesn't keep the password; a wrong one is refused in the restore sheet before anything changes; left empty, the
  restore goes without the keys.
- **Restore** opens and checks first (`BackupReader`): no entry may leave the folder (`zipinfo` before unpacking), no
  links, exactly the files the manifest lists with their digests, a format and migrations this copy knows (a newer
  Sidefolk's backup is refused, saying to update; an older database migrates when it opens). The sheet shows what it
  holds ("1,240 notes · 32 reminders…", made on, which Mac, which Sidefolk). **Replace only:** the backup is staged
  beside the data, Sidefolk relaunches, and the swap happens before the database opens (`BackupRestore.applyAtLaunch`);
  what was there goes to `Restore-undo-<date>`, and **Undo restore** puts it back for 7 days. A swap that fails half
  way is rolled back. History says "Restored from a backup made on …" (or that it was undone).
- **After the relaunch** (`RestoreFollowUp`): the gallery's extensions, companions and themes are installed again in the
  background, each with its switch as it was, with progress in Your data and a whisper at the end naming what isn't
  back; built-ins get their switch back; the person's themes are checked again as any theme from a folder. Extensions
  from a folder and companions from a folder are listed with **Review…**: the install sheet, or D60's question. MCP
  servers come back switched off (their command runs with the person's permissions). Keys saved before the relaunch
  replace those with the same names; Undo restore doesn't take them back.
  *Amended the same day (team/leftovers):* the values they replace are kept for Undo restore, sealed (AES-GCM) in the
  undo folder under a random key kept in the Keychain (`BackupRestore.saveKeys`, `BackupKeys.keepBefore`), so Undo
  restore puts the old keys back and deletes those the backup added; the sealing key goes with the undo copy (and
  when it expires). A restore that fails at launch puts the keys back too.
- **The app's conveniences** (amended the same day): `preferences.json` carries what the app keeps in its defaults
  rather than its database, from an allow list (`BackupPreferences`): Home's and Settings' window frames, the
  companion's place on each display, the person's keyboard shortcuts, where each palette opens, the extension list's
  filter, Catch Me's best and which folks were introduced; plain values only, any other name ignored. A restore sets
  them at launch and keeps what they replaced for Undo restore. Not carried: the language chosen in Settings (it would
  take another relaunch) and macOS's own keys. There is no "last tab" to carry: Home opens on Today, Settings on General.

**Why:** the founder: export here, import on a new Mac; or export, reinstall fresh, import. One file, honest about what
it can't carry (agents' configs, keys without a password), and a restore that can be taken back.

**Alternatives:** *Merge* (left out): notes, reminders and settings made apart can't be matched without guessing, ids
collide, and a half-merged notebook is worse than either; Replace with Undo is safe and simple. *A hot copy of the
database file* (torn by WAL; `VACUUM INTO` is consistent while running). *Copying the gallery's signed packs* (a backup
would carry code past the gallery's checks; fetching again checks it). *Keys in the clear*, or in the Keychain's own
export (another Mac's Keychain can't open it; a password the person chooses can). *Swapping while running* (open
database handles, running extensions).

**Implications:** Core `Backup/`: `BackupManifest`, `BackupWriter`, `BackupReader`/`OpenedBackup`, `BackupKeys`,
`BackupRestore`, `RestoreFollowUp`; `AppDatabase.migrationIdentifiers`. App: `RestoreModel`, `AppCoordinator+Backup`
(`resumeRestore` at launch), `BackupSettings.swift` (`BackupRows`, `BackupSheet`, `RestoreSheet`), `SettingKey.backUp`
and `.restore`, the menu's Back Up Everything… and Restore from a Backup…; dev commands `backup:`, `restoreFile:`,
`restoreConfirm`, `restoreNow:`, `undoRestore`; snapshots `sheet-backup`, `sheet-backup-keys`, `sheet-restore`,
`page-settings-trust-restored`. Tests: `BackupTests`. SECURITY T19.


### D92 — Four themes, each its own atmosphere, all built in; retired themes move to their successor (2026-11-01)
*Amended by D130:* Sidefolk is the default and Harbor a painted theme of its own, the only two built in; the others moved to the gallery.
**Decision:** *narrows D58's set and D64's gallery themes; builds on D84 and D78.* Now that a theme only dresses the
app (D84), seven themes were mostly the same few atmospheres. Sidefolk keeps four, each one nobody would mistake for
another, and ships all four in the app:
- **Harbor** (code): Lantern itself, neutral graphite and paper, the deep aqua action colour. The default.
- **Paper Garden** (`dev.sidefolk.theme.paper-garden`, 2.0.0): the paper family in one: Field Notes' and Paper
  Garden's warm paper, sage and editorial serif, with the finish of Tea House (made with the `sidefolk-theme` skill,
  never published): a hinoki-wood sidebar, a washi grain, light through a paper screen with bamboo shadows on every
  page and behind the companion's card, a full set of roles.
- **Night Studio** (`dev.sidefolk.theme.night-studio`, 2.0.0): the evening one: Night Studio's indigo glass over a dusk
  landscape and mint for good news, with Night Shift's crisper corners for long sessions beside agents.
- **Marshmallow** (`dev.sidefolk.theme.marshmallow`, 2.0.0): the playful one, kept because nothing else is: candy
  colours over its cotton-candy clouds, now a page wash and nook art instead of a portrait stage; a raspberry accent
  that reads as a button (the pink read as an error and as disabled).
Dropped: **Daylight** (white cards and an azure accent: Harbor's light look with a sky; Harbor covers it), **Field
Notes** and **Tea House** (into Paper Garden), **Night Shift** (into Night Studio; Harbor's dark covers a neutral dark,
and Appearance › Density covers compact).

**Where they live:** all four in the app's `Resources/Themes` (2.7 MB with their art, about what the three built-ins
took before: Marshmallow's two portrait stages became four small crops). The gallery has no themes for now. Every
survivor is the successor of a theme someone may wear offline, and a successor must be there at launch without a
download; Paper Garden and Night Studio keep their gallery ids, so an installed gallery copy is simply shadowed by the
built-in (`ThemeLibrary.all`). The gallery stays open for a future theme whose atmosphere none of these has.

**Mapping** (`ThemeSuccession`, at launch before the first paint, unless a theme folder is followed):
Field Notes → Paper Garden and Night Shift → Night Studio (their files are gone: the setting moves, a whisper says
"Field Notes is now Paper Garden, its successor." once; Night Shift's people get compact spacing unless they chose a
density); Daylight → Harbor (a gallery theme: where it is still installed it stays and stays usable, D65, and one
whisper offers "Use Harbor"; `AppSettings.themeSuccessorsOffered` keeps that to once; where it is gone, the setting
moves to Harbor with the whisper). sidefolk-addons drops `themes/`, so `publish.sh` removes their packs.

**Why:** the founder: "keep only the necessary themes; if some serve the same concept or atmosphere, make them one".
Fewer, finished themes are easier to keep right on every screen (each was re-checked with the D78 amendment and
snapshots in light, dark and Arabic) and easier to choose from.

**Alternatives:** keep the gallery for the art-heavy two (a person on Field Notes or Night Shift would need a download
at launch, or fall to Harbor); merge Daylight into Harbor (a sky behind the default changes everyone's look); keep
Night Shift for developers (with one layout per place, what was left of it was a dark palette and compact spacing,
both already a setting away).

**Implications:** `ThemeLibrary.builtInOrder`, `Sources/SidefolkCore/Themes/ThemeSuccession.swift` and its tests,
`AppCoordinator+Themes` (`succeedRetiredTheme`, `announceSuccession`, "Use …"), `Resources/Themes/{paper-garden,
night-studio,marshmallow}`; the `sidefolk-theme` skill names the four as what a new theme must differ from.

### D93 — The Game Center: Playtime's page drawn by Sidefolk from records; games steered in the person's own words (2026-11-01)
*Superseded in part by D100: every piece of it can now be an extension's own (D100's table); it stays until snapshot B.*
**Decision:** *amends D62, D74, D75, D76 and D79.* A game extension's page in Home is a **Game Center** Sidefolk owns,
and the common things people say about games work without AI in the ten languages.
- **A native page, fed by records, not more page parts.** The first page of an extension that declares `games`
  (`ExtensionPageInfo.gameCenter`) is drawn by `GameCenterView` instead of from parts. Its answer to `page.render`
  keeps its `summary` (the Today tile and sidebar row, unchanged) and adds **`games`**: `records` (per game, by its
  manifest name or a tally under it: `played`, `won`, `lost`, `drawn`, `streak`, `best_streak`, `best` in its own words,
  `today` {`text`, `done`, `streak`} for a daily) and `recent` (the last games: `game`, `at`, `outcome` won/lost/draw/
  solved, `text`). Numbers and short text only, read leniently and capped (`GameCenterRecords`: 64 games, 20 recent,
  80/60 characters, cleaned like page text); an older Sidefolk ignores the key. Sections a page still sends are drawn
  under the center with the usual parts. The Kit has `Page(summary:games:)` and `GameRecords`.
- **What it shows** (`GameCenter` in core, tested): a hero in the Play panel's art (the playroom, by night in dark
  mode) with the companion and one big action: Continue the game put away, else Play today's daily not done, else
  Surprise me (a random game), and All games (the Play menu); Wins, Solved, Best streak, Played; **Today**, each
  daily with its state, a tick when done and its days in a row; every game as a card in its group (Play against
  <companion>, Puzzles; the menu's rule, `GameLook.solo`, so a new group is a new case), with its art, tagline, best,
  record, when it was last played (Activity), Play, a Level menu and Resume when put away; the last games with their
  verdict in D78's colours and symbols; **badges** earned only from those numbers (first win, ten and fifty wins, three
  and five in a row, every game played, ten puzzles, a week of dailies, every daily today), the rest shown with how far
  there is to go; and **game settings** in one place: when it wins, sounds (every game's speaker follows), Sneaky
  (now also in Settings › Companion › Games), and a level per game. A game an extension says nothing about (Sidefolk's
  own best of three, an older extension's) is counted from Activity's `games.play` rows. The cards use the look v2's
  shared parts (`GameArtTile`, `GameSectionHeader`, `.gameCard()`, `GameStyle.levelChip`), so Home and the menu are
  one look. Data-driven: a game added to the manifest is a card; the validator now allows 32 games an extension.
- **The level a person chooses is theirs** (`GameSettings.levels`, by `extension/game`): set in the center, by
  "play tic-tac-toe on hard" or by "make it harder", and sent whenever that game opens without a level; "Default"
  lets the game pick (a puzzle's last level). The AI's choice of level is not remembered as the person's.
- **The app's own game sentences** (`IntentGameCommands`, `GameCommandWords`, `GameSlotWords`), after a game's own
  `say` sentences and before extensions' commands: whole sentences for *rematch / play again*, *make it harder /
  easier / too easy*, *resume the game*, *a random game*, *show my stats / my scores / game center*, *pause the game*
  (puts it away, no tool), *turn game sounds off / on*, *back to the games* (the menu); and **a game's name with
  slots around it**: a level word, a quiz's `topic` and `count`, a number game's range (`min`, `max`) and who guesses
  (`mode` mine / yours, Playtime's words), e.g. "trivia about space, hard, 10 questions", "jouons au morpion
  difficile", "guess a number between 1 and 1000", "you guess my number up to 500", "daily sudoku", "today's word".
  Conservative as the rest of the parser: once the slots and the words that only carry a sentence ("let's", "play",
  "jouons", "しよう") are out, what remains must be exactly one game's name (its title in the person's language or one
  of its `say` sentences, carried words out alike), slots only where they mean something (a topic for a quiz, a range
  for numbers), and a bare name ("copy", "memory") needs a play word or a slot, so another extension's command keeps
  it (D50). Slots are Sidefolk's for every game, checked in `GameSlots` and passed in `game.start`'s `options` beside
  `tone`, `sneaky` and `companion`; a game uses those it knows. This extends D76/D79's exception: steering a game is
  Sidefolk's own sentences in ten languages, not an extension's.
- **The AI does what the commands do:** `games.open` takes `game` `last` (resume, else the last played; after a
  relaunch, Activity's), `again` (a new round), `random`, `center`, `level` `harder`/`easier`, and the slots;
  **`games.settings`** (low risk, new) changes sounds, tone, Sneaky or a game's level. Both through Guard and audited.
- **Large titles in Home** (the founder's bug: scrolled up, the toolbar's "Playtime / Playtime" was drawn over the
  page's own header): a place with its own title (an extension's page, the Game Center, Today, On duty, a watch, You)
  marks it (`homePageTitle`); the toolbar's small title appears only once that has scrolled under the toolbar
  (`HomeTitleTracker`); a page's scroll view is cut at its frame, the toolbar's edge, so nothing slides under the
  toolbar's title or the Say bar (`clipsUnderToolbar`); an extension page's subtitle no longer repeats its title.

**Why:** the founder: Playtime's page was "very simple, boring"; make it a game center where you can do everything,
ready for more games; and make the companion much easier to steer by voice or typing. Page parts could have grown a
card grid and a stat strip, but the center needs the app's own art by game key, the Play panel's look, settings and
Activity: things an extension may not send or reach. Records keep what only the extension knows (bests, dailies) its
own, as numbers and words.

**Alternatives:** new page parts (`games`, `stats`, `continue`) any extension could arrange (more surface for a look no
other extension needs, and still no settings or kept game); a `commands` list with slots in Playtime's manifest per
game and language (hundreds of sentences each game would repeat, and older copies refuse an unknown key); counting
everything from Activity (it can't know a best time or the day's word, and older rows have no result).

**Implications:** an older Sidefolk draws Playtime's new page as its summary alone: Playtime's `minimum_sidefolk`
must name the snapshot that ships this. Playtime's page sends no sections now (`PlaytimePage.records`); its Home
words that only the old page used were dropped from `strings/`. New: `GameCenterRecords`, `GameCenter`, `GameBadge`,
`GameLevels`, `GameSlots`, `GamesSettingsTool`, `GameShelf.last`, events `gameCenter` and `gamesAway`,
`GameRequest.fresh/slots`, `LocalIntent.gameCommand`; app `GameCenterModel/View/Parts/Records/Settings`,
`HomeTitle.swift`, `HomeWindowController.Section.page`, `AppServices.keptGame/openPlayMenu`; tests
`GameCommandsTests`, `GameCenterTests`; snapshots `page-game-center*`, `window-home-gamecenter*` and
`window-home-*-scrolled`. **Not built:** an AI trivia switch in the center (it comes with D95's `aiTrivia` setting:
one row in `GameSettingsSection` once both are in), number words for counts ("ten questions": digits only), two
players' commands (D96).

**Amended by D101 (2026-11-03):** the Game Center is Playtime's own page (`hero`, `stats`, `cards`, `recent`, `badges`, `settings`, an inline scene), and the sentences are commands in its `strings/` (D100). `GameCenter*`, `GameSettings`, `IntentGameCommands`, `IntentGamesMenu`, `games.open` and `games.settings` are gone; what the person chose reaches the extension once through `settings_from`, and the section waits in `AppSettings.parked` for a copy that hasn't updated yet.

### D95 — Trivia questions made by the person's AI, through one narrow host request (2026-11-01)
*Generalised by D100: `permissions.ai` for any extension, with the same safeguards and more; this path stays until snapshot B.*
**Decision:** *builds on D75 and D79; a new reach for Sidefolk's own extensions (SECURITY T39).* With AI set up in
Settings › Brain, trivia can play any topic the person names, or one the AI picks ("Surprise me"), in their language.
Extensions still never call a model: Playtime sends the notice `sidefolk/trivia.request` (a UUID, a topic of at most
60 characters, 10–20 questions, a level, a language) and Sidefolk answers with `sidefolk/trivia.pack`, as data.
- **Who may ask:** Sidefolk's own extensions (`origin.firstParty`), switched on, one request at a time each; anything
  else is refused and logged. The person's switch, Settings › Companion › Games › "Make new trivia questions with AI"
  (`GameSettings.aiTrivia`, nil follows whether a provider is set up, so it is on by default only with AI), is checked
  by the host; the game learns it may offer the topic field from `options.ai_trivia` (the AI's name).
- **One call, nothing else:** `games.trivia_questions`, a low-risk tool never offered to a model or to other agents,
  runs through `ToolExecutor` as `Caller.extension`, so Guard weighs it and History shows "Trivia questions made by
  Claude Code". It calls `AgentRuntime.oneShot`: Sidefolk's fixed system words (`TriviaPrompt`), one user message with
  the request's fields, no tools, no memory, notes or conversation; the run is recorded like any other, so it counts in
  the person's usage.
- **Strict reading** (`TriviaPackParser`): only the JSON object asked for; each question a plain line (8–200
  characters), exactly four distinct choices, one right by index, an optional fact; no links (also bare domains), no
  markup, no control, zero-width or direction characters; a question that breaks a rule is dropped, a pack left with
  under half (or five) is refused whole. An empty list is the model declining an unfit topic.
- **Limits** (`TriviaMaker`): packs kept for the day by language, level and topic (the same topic again costs nothing),
  at most 20 calls a day, one at a time; the game waits at most about a minute, checking every 1.5 s through its own
  `after_ms`, then falls back.
- **Honest labels:** the waiting board says who writes the questions and that they aren't checked; each fact the AI
  gives is titled "Did you know? From Claude Code, not checked". The 400-question bank always works, offline or off.

**Why:** the founder: "for trivia we have a set of questions offline, but with AI we can have many more questions and
categories." Giving an extension the model would be quota theft and an injection path (T17); one typed request with
fixed words and a checked answer gives the person the feature without either.
**Alternatives:** MCP `sampling/createMessage` (any prompt, any length, refused since T17); Sidefolk's own agent writing
questions through a tool (a conversation, context and tools the request doesn't need); a host-side trivia game (Playtime
owns trivia).
**Implications:** `Sources/SidefolkCore/Games/TriviaPack.swift`, `TriviaMaker.swift`, `TriviaQuestionsTool.swift`,
`MCPClientEvent.triviaRequest`, `ExtensionHost.setTriviaHelp`, `AgentRuntime.oneShot`, `GameSettings.aiTrivia`, the
switch in Settings, `AppCoordinator.installTriviaHelp`; Playtime's `TriviaAI` and the trivia board's topic field,
"Surprise me" card and waiting board. Tested with scripted models only.

**Amended by D101 (2026-11-03):** the host request is gone (`sidefolk/trivia.*`, `games.trivia_questions`, `TriviaMaker`, `TriviaPack`): Playtime asks through `permissions.ai` and `AI.ask` like any extension, checks the answer itself (`TriviaPackCheck`), and the person's switch on its row replaces `aiTrivia`. A no carries over as a no.

### D96 — Games v2 gameplay: the companion plays like a person, any range, two people on one Mac (2026-11-01)
**Decision:** *amends D44 (the companion's hand) and D75, D79 (Playtime's engines and boards).*
- **Natural play by level.** Every engine plays like a person of its level, never one fixed sequence, its chance
  drawn before the person moves as before. Tic-tac-toe: Easy sees most wins and half the blocks and likes the centre
  and corners; Fair never misses a win and lapses one move in eight; Hard is perfect (minimax), choosing among equally
  good cells as a person would (it never lost in 1,000 tested games). Last Stick: everyone sees the end coming and never
  takes the last stick by choice; Easy rarely plays the trick, Fair mostly, Hard always (it wins every winning position);
  with no winning take it stalls. Higher or Lower's guesser picks near the middle with a level's looseness (Hard 9 %,
  Fair 18 %, Easy 28 % of the range, Easy now and then creeping on from the last answer), snaps to round numbers on a
  wide range, and thinks longer for bigger numbers: no more 50, 75, 88. Memory Pairs forgets with time (a card seen
  just now is nearly sure, one seen long ago fades; Hard barely forgets) and sometimes reaches for the card beside the
  one it lost. Quick Paws' reflexes lean late as a person's do, with a moment it wasn't looking now and then. Copy Me
  never repeats a move three times; Which Cup?'s shell player moves the gem's cup more than chance and rarely undoes a
  swap. Think pauses vary with the position. Rock, paper, scissors stays uniform and blind to the person's hand, but
  never throws the same hand three times running (D44 amended).
- **Higher or Lower on any range:** 1–100 by default; 10, 1,000 and a million on the start board, or any top up to a
  million typed in any digits; a range named in words (`options.min`, `max`, `mode`, D93's slots) is played straight
  away. Par is what halving needs (7, 10, 20); the thermometer judges distance by size on wide ranges; the number pad
  groups digits per locale and shows fewer chips for long numbers. Bests count on 1–100 only.
- **Two people on one Mac** in nine games: tic-tac-toe, Last Stick, Memory Pairs (turns), Copy Me (the same dance
  copied in turn), trivia (a question each), Quick Paws (one button, A and L by where they sit on any keyboard; a key
  before the signal gives the round to the other; nobody in time replays it), Which Cup? (rounds in turn), Higher or
  Lower and Balloon Words (each hides a number or sets a word for the other, passed with a cover), and Sidefolk's rock,
  paper, scissors (the first hand hidden behind a cover until the second is in). Guess My Animal stays the companion's:
  it is the one guessing and learning. The first board offers "vs <companion>" or "2 players"; names are typed one at
  a time or kept (`options.names`, remembered by the app from what a two-player score shows); the score shows both
  names in identity colours, the end card names the winner in neutral ink with a trophy (tone `info`; a draw stays `neutral`), the companion referees (no "I win"), and
  head-to-head tallies are kept per pair of names, apart from the games against the companion (the Activity row has no
  result, so the Play menu's stats stay the person's).

**Why:** the founder: "the intelligence when you play against Mochi should be good, and natural: in guess-my-number it
always asks 50, then 75… there's a pattern"; "I want to play much higher too"; "make it possible to play with two
players, like me and my friend on the same Mac".
**Alternatives:** a single "difficulty" randomness knob per game (still mechanical); a separate two-player app section
(the same games twice); hiding secrets by masking fields (a cover between turns works with every part as it is).
**Implications:** Playtime's engines (`Games/*.swift`), `GameKit/TwoPlayers.swift`, `Screens/Duo/`, the Kit's
`score(players:)`, `reflex(keys:)` and `Move.pressKey`/`earlyKey`, Core's `GameBoard.Score.players`,
`GameBoard.Reflex.keys`, `GameMove.pressKey`/`earlyKey`, `GameRecord` for two players, `HandsMatch+Duel`,
`GameSettings.players`, the Play panel's score bar and two-key reflex. A Sidefolk from before this shows "You" and the
companion on a two-player score and takes Space on the reflex, so Playtime with two players needs it.

**Amended by D101 (2026-11-03):** all of it is the program's now: how the companion plays, ranges, and two people's names and records. Two players' reveal in rock, paper, scissors still says "You" and the companion's name with a winner's glow, as the old code did: carried over as it was, and it doesn't meet this decision; left for the founder.

### D97 — The Calendar works like a Mac calendar: its calendars' colours, Day to Year, gestures, and changing events through Guard (2026-11-01)
*Amends D57 and D66:* the Mac's events stop being read-only once the person allows changes.
**Decision:**
- **Colours and calendars.** Each Mac or iCloud calendar's own colour (`EKCalendar.cgColor`) is on its events as a
  tinted fill, a strong edge and text in that colour, made readable by `CalendarPalette` on the theme's card in light
  and dark: only HSL lightness moves, never hue, until text reads 4.5:1 on its fill, the edge 3:1 on the card and a
  selected event's words 4.5:1 on its solid fill. Sidefolk's own things are calendars too, in identity colours (D78:
  identity, never status): reminders Tempo's blue, tasks Brew's tan, routines Nova's violet; late says so with an
  amber outline and in words. The page's own sidebar has a month to jump with and the calendars by account, each with
  its box; hidden ones are remembered (`AppSettings.calendarPage`) and left out everywhere (`CalendarReader`), so
  Today, the brief and the AI see what the Calendar shows.
- **Views.** Agenda (first, D84), Day, Week, a Month that scrolls on row by row (its title follows the month most on
  screen) and a Year (twelve small months shaded by how busy each day is). Day and Week open at the working hours or
  an hour before now, shade the night, draw now as a line with its time in the gutter, put all-day and multi-day events
  as bars across their days (`CalendarGrid.lanes`), and show as much of an event as its size has room for: up to two
  lines of title, then time, then place, then notes. A reminder is a moment, not a slab of time: a one-line pill at its
  time; in the Week one that comes back through the day (every 30 minutes) is one pill at its next time saying how
  often (`CalendarGrid.oncePerDay`), the Day shows every time. Things that overlap sit side by side, never narrower than
  60 points (110 in the Day), so a title is never a letter; past that a "+N" lists the rest and opens their details
  (`CalendarGrid.fit`: with room for one, the first keeps the width and the count sits beside or on it). The view, the
  hour's height and the sidebar are remembered.
- **Moving through time.** ⌘← ⌘→ and the chevrons step (in Arabic the next period is on the left), ⌘T or T is today;
  two fingers sideways turn the period, the page following them until it lets go, then sliding in; two fingers down
  the month scroll it on and it settles on a week; pinching Day or Week changes the hour's height. Only scroll events
  over the page are read (a local monitor that leaves with the view).
- **The keyboard and the mouse.** The arrows step through what is on screen in time order, Return opens the selected
  thing's details, Delete removes it, Escape lets go. A click selects, a double-click opens details. A double-click or
  a drag over empty time places a new thing and opens its editor there: a reminder or a task in a collection (the when
  field's words, so "every monday 9" works) through `reminders.create` and `notes.save`, or an event in a chosen
  calendar. Things are dragged to another time or day to the quarter hour, an event's bottom edge to change its
  length; ⌘Z takes back each, and each is in History.
- **Details.** A popover beside the thing: its calendar and account in its colour, when and its repeat, the place with
  Maps, a web link (http and https only), the people invited with their answers (read only), notes; then Done, Edit
  and Remove for a reminder, Edit and Delete for an event Sidefolk may change, Open in Calendar for every event.
- **Changing the Mac's calendars: yes, carefully.** D57 kept the calendar read-only because nothing needed to write
  it; a calendar people use like Calendar must. Three tools, `calendar.create` (medium), `calendar.update` (medium)
  and `calendar.delete` (high), capability `calendar.write`, through `ToolExecutor` for the person's own drags and
  clicks too, so Guard sees every change, History lists it and its Undo puts it back (a deleted event is recreated
  from its kept copy, alerts included). They work only once the person allowed changes: the first change asks in a
  sheet that says what Sidefolk will and won't do, or Settings › Trust › Your calendar. Never: an event other people
  are invited to (changing it sends them notices, so that stays in Calendar, where the person sees who is told), a
  calendar that can't be changed (subscriptions, birthdays, shared read-only), a whole repeating series (only the one
  time, as Calendar's "Only this event"); and Sidefolk never adds attendees. The AI is offered the tools only while
  changes are allowed (as `calendar.today` only while shown); `calendar.today` then gives each changeable event's id.
  A turn that read outside content never changes the calendar without the person, in any mode
  (`PermissionEngine.couldCarryOut`): calendars sync to accounts and may be shared, so a change can carry words out.
  macOS's full access, asked when the calendar is shown, already covers writing; nothing new is asked of macOS.

**Why:** the founder: "make it much better, like a real calendar … use the colours and everything; if there's space,
show details, if not, just the title … how you add things, how you scroll, how you swipe … like a built-in calendar
feature." Writing through the same tools as everything else keeps one path for Guard, History and Undo.

**Alternatives:** keeping the Mac's events read-only with Open in Calendar (adding a meeting would mean leaving the
page, the thing the founder asked to fix); writing from the view straight to EventKit (no Guard, no History, no
Undo, and a second way in for the AI later); changing whole series or events with attendees (both reach other people
or many dates with one drag); a colour of Sidefolk's own for every Mac event (the founder asked for the calendars'
own); infinite horizontal scrolling of weeks (a swipe that turns a week reads better and keeps the hour grid still).

**Implications:** Core: `CalendarEvent` gains its calendar's id and colour, place, notes, link, attendees, repeat,
writability and alerts; `CalendarInfo`, `CalendarDraft`, `CalendarPalette`, `CalendarPageSettings`,
`CalendarGrid.lanes/weeks/mainMonth/yearMonths`, `PlatformBridge.calendars/calendarEvent/createCalendarEvent/
updateCalendarEvent/deleteCalendarEvent`, `CalendarWriteTools`; a repeating event's times each have their own id
(EventKit's identifier and when it was meant to happen). App: `MacCalendar` reads colours and details and writes one
occurrence; the Calendar page is `CalendarView`, `CalendarSidebar`, `CalendarTimeGrid`, `CalendarMonth`,
`CalendarYear`, `CalendarList`, `CalendarParts` (block, bar, chip, menu), `CalendarInspector`, `CalendarEditor`,
`CalendarGestures`, `CalendarModel` (+Changes). The week's read-only note (D84's leftovers) is gone: an event that
can't change says why in its details. Debug builds: `SIDEFOLK_SAMPLE_CALENDAR=1` runs on `SampleCalendar` (realistic
colours, a meeting, a subscription, a repeating standup) instead of the person's calendar, and `calendar:swipe`,
`:scroll`, `:drag`, `:click`, `:key`, `:type`, `:crowd` (with `:film`) drive and film the page. Measured: 3,000 extra
events, a week of 522 things reads and indexes in 4 ms; idle CPU with the week or month open is the same as on
History (about 1.5% for the whole app with its companion). Not done: a real trackpad's swipe and pinch by hand (the
swipes were fed as the trackpad's events; the pinch is SwiftUI's `MagnifyGesture`), the person's own EventKit data
(the debug build wasn't given calendar access, so it ran on the sample).

### D98 — Extensions own everything: the rule, its guard test, their details in their manifests, seed packs (2026-11-01)

**Decision:** The founder's rule: "extension things will always be with the extension: screens, overlays, pop-ups,
everything. When I uninstall an extension, everything for it is gone; when I install, I get everything." The app holds
general abilities any extension can use and no code naming one. This decision is the rule, the test that keeps it, the
details that left the app, and the four extensions that were built into it. D99–D101 are the abilities and Playtime's
move.

- **The guard.** `ExtensionFreeAppTests` reads every line under `Sources`, comments included, `Resources/SeedPacks` and `Resources/Info.plist`,
  for extensions' ids, names, programs and game symbols, against `scripts/extension-free-allowlist.json`. That file
  holds only the approved exceptions: the publisher check (official means the signing identity), the seed list, themes
  (app-owned since D92), catch-me and petting (the companion's own life). Comments are covered on purpose: a comment
  naming an extension is how code written for it starts, and telling them apart would need a parser for no gain.
  Everything fails now except game code, which is reported until `transitionOver` flips to true in D101's last step.
- **Details, each a general manifest ability**, validated, for any extension:
  - `examples`: up to three requests to try, shown under the extension in Settings and searched there. They only fill
    the Ask panel; nothing is sent until the person presses Return.
  - `tools.<name>.summary`: the sentence for a call's approval card and History, a text or forms with `if`/`unless`,
    filled only from the call's exact arguments, cleaned as before. **Believed only for packs Sidefolk signed**
    (`origin.firstParty`): anyone else's could say one thing while the call does another (T1), so it is valid but never
    shown, and the validator says so. A sentence that can't be filled falls back to the title and arguments.
  - `services`: the services and hosts the program talks to, on the install sheet and in Settings › Trust for everyone,
    said as the author's word for anyone but Sidefolk, whose sandbox lets them reach any site. **Only signed packs get
    D47's reach**: the exception after outside content rests on Sidefolk's signature, and `ExtensionDetailsTests` still
    checks every address in such a program against its list. An update naming a new host waits for the person (D70);
    a first list doesn't, since it says less than the program could already do.
  - `replaces`: what D67's resting used to hard-code, still only between Sidefolk's own signed packs, so no extension can
    quiet another.
  - Words: `strings/` (D76) is the only source, and also translates examples and summaries. `BuiltInExtensionWords`,
    `BuiltInExamples`, `BuiltInToolSummary`, `BuiltInServices`, `ExtensionOverlap` and the catalog strings only they used
    are gone.
- **Seed packs.** World Clock, System Vitals, Weather and Calculator are ordinary gallery extensions now, with their
  sources in sidefolk-addons. The app carries their signed packs and a data list (`Resources/SeedPacks`, the only place
  they're named). A fresh Mac installs them once, on or off as the list says, offline, each checked as a download is
  (size and digest against the app's list, signature against the gallery's team). Then the gallery updates them, and
  removing one is remembered (`Addons/seed-packs.json`, which lists only what is left to install). An app update never
  touches them and adds no new seed to a Mac that has had its seeds. A restore brings back only those in the backup. A
  pack that doesn't check out stays out, says why in Settings › Add-ons with Try again, and is tried again at launch.
- **Existing copies.** A stored origin of `bundled` now reads as `official`: same folder, data and switch, no reinstall.
  They are the person's to remove and the gallery's to update. Their versions were raised (`1.2.0` → `1.3.0`) so the
  gallery's `1.3.0-snapshot.n` is newer. Until that update arrives such a copy has no summaries or examples, and its
  approval card shows the title and arguments; its words already come from its `strings/`.
- **Builds.** `scripts/seed-packs.py` takes the newest version each entry's `minimum_sidefolk` allows from the signed
  catalog, verifying everything. A release can't go out without them: `release.yml` checks first, `build-app.sh` stops
  when `SIDEFOLK_RELEASE` is set, `release.sh` verifies what the app holds. Any other build warns and goes without, or
  uses `build/seed-packs` from the last fetch; `SIDEFOLK_SEED_GALLERY` points at a local signed `dist/`.
- **Dev samples** use made-up extensions (`SampleAddons`: Repo Pal, Time Zones, Mac Pulse, Sky Watch, Paste Shelf, Stay Up,
  Cast Along, Code Maker, Newsstand). `extensions/hello-folk` stays as an unshipped developer sample; the Settings row
  that offered samples from the app, which no build ever filled, is gone.

**Why:** an app update must never change an extension's screen or content on its own, and a new one must ship without an
app release. Every table by extension id in the app made both false.

**Alternatives:** a file of its own for the details, as `strings/` was, so older copies ignore it: the founder asked for the
manifest, and `minimum_sidefolk` (D83) with the sheet's "update Sidefolk" (`needsNewerSidefolk`) already handles an older
copy. Keeping the four in the app as `bundled` with a special path: exactly what the rule rules out. Reinstalling
bundled copies from the seed pack at upgrade: an app update would be touching them. Showing summaries for everyone: T1.
Remembering removals by a list of what was removed: every later seed would then look new to an existing Mac.

**Implications:** Amends D39 (no extension is built in; every one can be removed), D47 (the service comes from the signed
manifest), D55 (a seed installs once without a click, from a list the app's own signature seals), D67 (`replaces`) and D76
(no fallback to the app's catalog). Every gallery extension gains a key older copies refuse (Miraya's with D100), so its
`addon.json` names `minimum_sidefolk`: one number in all of them, which must be the snapshot that ships this, and the lead raises it. Copies from before
D83 ignore that key, are offered the update and refuse it with the validator's own words. **Order at release:** the app proved with the packs first, then the gallery published, then the app released, because a release fetches the packs (RELEASE.md). Tests that run a real extension need the add-ons checkout
(`SIDEFOLK_ADDONS_REPO`), as CI already provides; `release.yml` doesn't check it out, so its own test step skips them.
Not moved here: Miraya's drop action, which left with D100's Entries; game code (D101). SECURITY T2, T33 and EXTENSIONS › Seed packs have the details.

**Amended by the review of snapshot A (2026-11-02):** on the default Releases channel "the gallery updates them" starts when a plain version is released: every seed is in snapshots, so a fresh Mac's stays at the version it was given, and it says so (EXTENSIONS › Seed packs). A copy from before D83 is offered the update and refuses it with the validator's own words, not "update Sidefolk" as written above: `needsNewerSidefolk` arrived with D83's check. A folder or a strings file can't call itself Sidefolk, a companion's name or anything starting with Sidefolk, however cased, accented or spelled in lookalikes (`ExtensionReservedNames`); checked at install, where who signed it is known, so nothing already here is turned off. An unsigned copy taking the place of a signed one is said on the sheet, and it starts with no settings and no "always". Removing a seed that is still pending takes it off the ledger. The guard now reads the add-ons' manifests when it runs (every id and name, any case, however joined), every text file under `Sources` and `Resources` plus `Package.swift` and the catalog's English keys, and files' names; lower-case game identifiers are reported until `transitionOver`, which also asserts `Sidefolk/Play` is gone. Words the app uses for its own features stay out of it (`commonWords`). `scripts/extension-free-binary.sh` reads a built app. A name computed at run time can't be caught by either: said here so nobody thinks otherwise. `build.py --sidefolk-build N` refuses the placeholder, and the order of a release is in RELEASE.md, with the app proved before the gallery changes.

### D99 — Pack assets, the Scene and surfaces: an extension draws its own screens as native data, always framed (2026-11-02)
**Decision:** *amends D62, D75 and D79 ("no images": an extension may now show pictures and play sounds from its own pack,
inside a surface); part of the founder's rule that everything of an extension's lives in the extension (D98).* Three general
abilities, naming no game and no extension, with everything else staying as it is until D101:
- **Pack assets:** an `assets` folder named by the manifest; pictures (PNG, JPEG, WebP, HEIC: one still, the content matching its
  name, 4 MiB, 3000 px a side, 6 million pixels) and sounds (WAV, AIFF, CAF, M4A: 2 MiB, 10 s, 96 kHz, stereo), 512 files, 48 MiB,
  addressed by a relative path, checked by the validator and again at each load (a clean path, no link, the install's pin,
  caps read from the header before any pixel; a failure draws nothing), 96 MiB decoded at most. Nothing from outside the pack.
  Sounds at a fixed volume, four a second, behind the frame's speaker (off by default, in `games.speakers`), Quiet,
  fullscreen and macOS's interface sounds.
- **The Scene:** a typed, capped, validated tree the extension sends as data (`SurfaceScene`): `image`, `text`, `shape`, `symbol`,
  `flip`, `group`, the helpers `row`, `column`, `grid`, `keyset` (read into plain boxes), `companion`, `person`, `entry`, `clock`; transforms
  on every node; timed animations flattened when read into one complete path per node and property (`SceneTimeline`), so the app
  hands Core Animation whole curves and nothing is streamed: moves, scale, fade, rotate, half-turn flips, frames, sequences,
  staggers, repeats; events at a moment (a pack sound, a reaction, an announcement); areas (hover, press, highlight, a sound,
  `always`, a press timed from a moment of the scene, grid and free drags with a ghost drawn by the app); keys (exact, by class,
  by seat); timers Sidefolk keeps; theme tokens and verdict tones by name; Reduce Motion (a step isn't played and its end shows, unless
  `essential`); right to left (`mirrored()`, `ltr`); a label on every area, or it isn't one. Layers hold each node's final state, so
  nothing depends on an animation finishing; a new scene changes only what differs, by node id.
- **Surfaces:** a declared `panel` or `overlay` beside the companion, up to 720 × 676 of canvas (with the 44 pt header, about 720 tall),
  always framed by Sidefolk with the extension's icon and name (`SurfaceFrame`), a back and a close the app owns, one of each kind at a
  time, opened through `surfaces.open` (the person's words, or the AI where the manifest says `ai`), keyboard only when the person
  opened it (D75), gone with the extension. The channel is `sidefolk/surface.open|move|close`, with the game channel's limits, which
  stays until snapshot B. Moves are typed and go out only if the scene on screen offered them (`SurfaceSession`).
- **Companion references:** "the person's companion" and "the person" are nodes it can place and never read; `{companion}` in a text is
  filled in at draw time; reactions come from a fixed list (the existing moves, `pump`, `flick`, `roll`) and carry no words. An extension's
  words appear only inside its own surface.
- **The Kit** (`Scene`, `Node`, `Anim`, `Reaction`, `KeyCap`, `Drag`, `Surface`), identical in both repositories.

**Why:** the founder, 2026-11-01: "extension things will always be with the extension: screens, overlays, pop-ups, everything."
Every board in the Play panel had to be drawable from these, so Playtime can move without an app release. Each primitive came from
listing what every board part and the desktop toss do; the table is below. Measured in the debug app with Mochi on the desktop: the app's CPU with no
surface 1.7–2.4 %; with the shuffle's scene at rest 1.2–2.9 %, the main thread blocked in the run loop (`sample`: 3030 of 3138 samples), the
keyboard's (199 layers) 2.5 %; while the shuffle plays 1.5–1.8 %, since the render server runs it. Footprint 53 MB without, 61 MB with the shuffle's
pictures, 66 MB with the keyboard, 60 MB after closing.

**Alternatives:** a web view per surface (could imitate anything, ignores themes, a second engine; already refused in D75 and now by the
founder); SwiftUI as the renderer (a redraw per change, and a timeline wakes the app each frame; layers cost nothing at rest); streaming
frames or positions from the program (2 s replies, 20 a second, and CPU); an extension choosing its own window (an imitation of a
card would then be a window of its own); SVG (points at other files, D13's icon rule); custom fonts (a font is code to a decoder);
Sidefolk's named sounds in scenes (the app would keep game sounds: `surfaceExportSounds:<dir>` writes them as files for a pack instead).

**Implications:** Core: `Surfaces/` (`PackAssets`, `SurfaceScene`, `SceneTimeline`, `SurfaceMove`, `SurfaceInfo`, `SurfacePolicy`, `ExtensionHost+Surfaces`,
`SurfacesOpenTool`). App: `Surfaces/` (`SceneView`, `SceneLayers`, `SceneDrawing`, `SurfaceModel`, `SurfaceFrame`, `SurfacePanelController`, `SurfaceSounds`) and
`AppCoordinator+Surfaces`; surfaces stand one window level under `.floating`, so never over a card. A pack with `assets` or `surfaces` is refused by a
Sidefolk from before this with "update Sidefolk" (D83). `samples/scene-sample` is a fictional sample; tests and the debug app run it, nothing ships it.
Authors: EXTENSIONS › Surfaces and scenes; threats: SECURITY T40.

How each board part maps (Playtime's move, D101): prompt and speech bubble: `text` on a `path` shape; eyebrow, chip: `capsule` and `text`; answer tiles: `group`
with an area (`value`, `key`, `hover`, `press`), `win`/`loss` and a `symbol`, a shake as `keys` on `x`; grid: `grid` of areas, stamps and drops as `keys`, cards as `flip`;
score bar: `person`, `companion`, `text`, pips as shapes; end card: shapes, `text`, areas, `over` with `outcome` and `tally`; timer bar: `timers` and a named `sx` run, its last
seconds a fade-in of a second bar; reveals: coin `flip`, dice `frames` and `keys`, hands `keys`, `clip` for a cut; `react` `pump`, `flick`, `roll`; note, facts: `text`; buttons: areas with `key`,
Return on the primary; the companion as a button: `companion` with an `always` area; choice: areas with `value`; pads: a `sequence` of fades with `sound` and `react`,
`blocks_input`; cups: `Anim.swap` in a named `essential` run; reflex: a press `timed_from_ms`, a delayed fade and sound, a timer, keys by `seat`; meter: a `gradient` with a named run;
number field, letters, keyboards: `keyset`, one move a key, `stagger` on `flip`; Hangul's grouping moves to the program; entry: `entry`; sticks: an area each with `highlight`;
lives: pictures; puzzle: `grid`, `path` lines, `drag` by cells with a `ghost`, `clock`; arrow-key cursors drawn by the program from key moves; bevels: two shapes and `press`; suspense: the program's scenes with `after_ms`; sounds: pack files
from `surfaceExportSounds`.

**Gaps, for D100 and D101:** a cue's `line` has no form: by the rule the words go inside the surface, so the companion no longer speaks a game's line on the desktop; a game's tone and
Sneaky reach it through D100's settings, not `surface.open`; a coin's face in gold is a `companion` node with `figure: face` and `duotone` (amended below); Activity's row is
`surfaces.use` ("Used X from Y", or what the scene's `title` says), so `GameStats` and the Play menu's numbers need Playtime's own records, and `carries` hands over the old ones; opening with words beyond whole sentences needs D100's commands, whose tool's reply opens it (amended below).
A flip is a 2D squash, as the toss has always been, not a 3D turn: `render(in:)`, which films and snapshots use, doesn't draw 3D transforms. Not verified: clicks through an overlay's clear pixels with a real pointer (AppKit's own rule); sound through real speakers.

**Amended by the review of snapshot A (2026-11-02), so Playtime can move as it is on general abilities:**
- *Opening:* a tool's reply carries `sidefolk` (`open_surface`, `close_surface`, `open_page`, `hold_answer_ms`), only ever for what its manifest declares and in answer to a call someone made through Guard; an entry can name a surface. This closes the gap this decision left: nothing an extension offered could start a surface. `surfaces.open` is what opens it, as the extension, with who asked already judged.
- *A model's words:* `surfaces.open` passes a model's arguments only as values `surfaces.<n>.arguments` lists, so no free text from a possibly steered turn reaches a program by this road; `games.open`'s topic goes too in a tainted turn. A person's click or the extension's own reply pass anything. The card and History say what goes. Risk stays low: with no free text there is nothing to weigh.
- *Costs:* `SurfaceScene.drawnBytes` (96 MiB a scene, counted on the reader's side) and a flip's samples in `maxPoints`: node counts didn't bound pixels or samples. No per-bitmap clamp: the budget alone bounds memory, and a clamp would change what is drawn.
- *Attention:* `SurfaceAttention`: only the person's moves are attention. Clocks don't keep an overlay up, they count with `next` toward the 600, and a surface put away admits nothing. Reduce Motion: `after_still_ms`, a skipped run's events at once, a press dims. Put away, animations stop on the timers' clock. An over-rate move is dropped, not fatal; a repeat waits for the last press.
- *Scene:* `scroll`, 32 figures, `figure`/`align`/`duotone` and the stand-in, `weight` to black, `italic`, `tabular`, `strike`, `runs`, `design: theme`, h:mm:ss, symbol `weight`/`mode`/`secondary`, tuned colours, per-node `highlight` looks and `rotate`, a resting hit box, clips limit hits, `submits`, `focus`, `plain`, `drag.inset`. `{companion}` is filled wherever Sidefolk shows an extension's words.
- *The speaker* no longer touches `GameSettings`: `speaker_setting` or a scene's `speaker` makes it a declared switch through `extensions.setting`; otherwise `ExtensionPreferences.speakers`, which goes with the extension.
- *Accepted for D101, no ability built:* a flip stays 2D, so dice tumble flat, and `.plusLighter`'s shine is a plain white gradient. The frame's 44 pt header replaces the game's own floating header card: that is the one look that can't move "as it is", and nobody should fake a second header in the canvas. The speaker's confirming ding on turning on isn't kept; a scene can play its own. A companion hidden when an overlay opens goes again with it; a panel keeps it out, as it does today.

### D100 — What any extension can declare: rich pages, commands in every language, entries, settings, AI help, a History row (2026-11-02)
**Decision:** *the founder's rule (D98): the app gives only general abilities. Amends D39, D50, D62, D74, D75, D76, D79, D84's drop card, D93, D95 (SECURITY T41).* These are
general: nothing here names a game or an extension, and all of it can replace what the app does only for games (table below). The old game code keeps working untouched until snapshot B.
- **Richer pages** (`ExtensionPage+Rich`): new parts `stats` (a strip of up to six numbers), `cards` (a grid of up to 48, `size` small or large: a picture, title, detail, a line of record, when, badge, a tick, up to three buttons, a small menu), `tabs` (2–6, each holding sections, no tabs inside; switching never asks the program), `badges` (earned or how far along), `recent` (up to 20 lines with tone and when), `settings` (the extension's rows, drawn by the host from its schema). `hero` gains `scene`, `figure` and `says`; a section gains `picture`. **Pictures are addressed, never fetched** (`PagePicture`): `{"pack": path, "dark": path}` in the pack's `assets` folder (D99's addressing, read through `PackAssetReader`, pinned, sized and one frame), `{"data": name}` as before, `{"companion": "face"|"full"}` and `{"person": true}`, which Sidefolk places and the extension never reads. One primary per page across cards and tabs too. Unknown parts stay skipped.
- **Commands with slots** (amending D50, D76, D79): a command may have a `name`, under which `strings/<language>.json` holds its sentences (`commands.<name>`), so a sentence is matched in all the languages the extension has, whatever the app's language. Slots: D50's kinds, bounds (`{count:integer:1-50}`, `{topic:text:40}`), and enums (`choices`: `{level:level}` gives the value whatever word was said). **A name with parts**: `names` and `with` naming shared `parts` ("on {level:level}", "{count:integer} questions", "with a friend" → `{"players": 2}`) in any order around it, with `carry` words that only carry the sentence (`words`, `lead` saying a name is meant, `inside` for languages without spaces, `endings` for particles), per language. Conservative as ever: once parts and carrying words are out, exactly the name must remain, and a bare name needs a lead word or a part. Sentences without slots are compared through `CommandText.key` (a table, not a regular expression: a parse runs on every key). **Conflicts:** Sidefolk's own understanding always comes first and the validator tells the author what never arrives (`report.shadowed`, in `sidefolk ext validate`: a note, never a refusal, because the app's words may grow with an update); a sentence that answers an approval, in any of the ten languages, can't be a command; two extensions claiming a sentence get neither, it goes to the AI (D50), and the install sheet says so; a sentence runs as `Caller.command` through `ToolExecutor`, so Guard asks as usual. "make it harder" and "rematch" are plain commands the extension handles. This replaces D76's "commands stay English" and D79's and D93's exceptions, which go with the old code.
- **Entries** (`entries`): up to 8 items for the companion's menu, the Pocket's ⋯ menu and a right click on the menu bar, and one tab in Ask (two extensions' at most in the row); each opens its own page, runs its own tool as the person through Guard, or holds a submenu. **Drop actions** (`drops`): `kinds`, glob `patterns` on a link's address without its query or a file's name, `title`, `detail`, `tool`, `input` with `{value}`; a file goes under an argument the tool lists in `paths`, so Guard checks it. Offers follow Sidefolk's own choices on the card (a link gives up its reminder for the first), at most three, each naming its extension. **Miraya's "Play on TV" moved** to its manifest; `DropChoice.playOnTV` and the app's Miraya constants are gone. Everything is read from the manifest through `ExtensionShelf` as it is shown, so an extension that is off or gone leaves nothing behind. An item from anyone but Sidefolk's own extensions carries its name; the install sheet lists what it adds.
- **Extension settings** (`settings`, in order: `switch`, `choice`, `number`, `text`, each with a default): the host stores them per extension (`ExtensionPreferences`, in the database under a key of its own, so a backup carries them and an uninstall removes them, surviving updates), passes them with every request as `settings` beside `language` and sends `sidefolk/settings.changed`, draws their rows on the page and under Settings › Add-ons, and Settings' search finds them. Every change goes through **`extensions.setting`** (low risk, in History): the person's click, or the extension for itself (`sidefolk/settings.set`); never a model, another agent or another extension (their words are their author's, D24: an extension that wants the AI to change something offers its own tool).
- **What it used to have:** `settings_from` names a section of Sidefolk's own settings; a signed Sidefolk extension receives it once (`sidefolk/settings.carry`) and returns the settings to keep. The mechanism knows no names: `AppSettings.parked` keeps sections this copy doesn't know, so a section the app retires stays until it is given, and `AppSettings.section` reads either. It is how D101 moves `GameSettings`.
- **AI help** (`permissions.ai`: `purpose`, `daily_cap` 1–200, default 20): any installed extension may declare it. On the install sheet with its purpose and cap, a caution; more of it is a widening update (D70). `sidefolk/ai.request` {request, prompt ≤ 8,000 characters, label} is answered once by the notice `sidefolk/ai.answer`, to that program alone. One at a time each, the person's switch per extension (`setAIAllowed`, on its row and page), the same words again the same day cost nothing, the count kept in `ExtensionPreferences`, so a relaunch doesn't reset it. It runs through **`extensions.ai_help`** as `Caller.extension`, never offered to a model or another agent: History has a row ("Hello Abilities asked your AI: …"), `AgentRuntime.oneShot` makes the call with **no tools, no memory, no conversation**, a fixed system frame that says the request is untrusted, the extension's words inside marks they can't close, cleaned and capped answers. The extension validates what it gets; the Kit's `AI.ask` gives it `.answer(text, madeBy)` or `.refused(reason)`, `AI.available` the AI's name while it may ask. D95's narrow path stays beside this until snapshot B.
- **Activity:** `sidefolk/activity.add` {text, key, result}: one row in History through **`extensions.activity`**, in the extension's words marked as its own, at most one every five seconds, only for itself.
- **Kit** (both repositories, identical): `Block.stats/cards/tabs/badges/recent/settings`, `Picture`, `Card`, `PageTab`, `Achievement`, `RecentItem`, `Hero(scene:figure:says:)`; `ExtensionSettings`, `AI`, `Activity`, `Extension.carry`, `settingsChanged`. **Sample:** `extensions/hello-abilities`, plain Python, one of each; it doesn't ship.

**What replaces the app's game-only code (snapshot B, D101):**

| Today | Becomes |
|---|---|
| `GameCenterView`, `GameCenterParts`, `GameCenterRecords` (app and core), `GameCenter`, `GameBadge`, `ExtensionPage.games` | The extension's page: `hero` with `scene`, `figure`, `says`; `stats`; `cards`; `recent`; `badges`, worked out by the program from its own records |
| `GameCenterSettings`, `GameSettings`, `GamesSettingsTool` | `settings`, `extensions.setting`; `settings_from` for what the person chose; a tool of its own for the AI |
| `GamesOpenTool` | Tools of its own (with D99's surfaces): opening, `last`, `again`, `random`, the center as its page |
| `GameLevels`, `GameSlots` | `choices`, slot bounds, the program's own stepping |
| `IntentGameCommands`, `GameCommandWords`, `GameSlotWords` | Commands with `names`, `parts`, `choices`, `carry`, in `strings/`; proved sentence by sentence in `CommandFrameTests` |
| `IntentGamesMenu`, `IntentGames`, `GameMeta.say` | Commands on a tool that opens its surface |
| `TriviaMaker`, `TriviaPack`, `TriviaQuestionsTool`, `TriviaHelp`, `sidefolk/trivia.*` | `permissions.ai`, `AIHelper`, `extensions.ai_help`; the check of a pack moves into the program |
| `GameRecord`, `games.play` rows, `GameStats` | `extensions.activity` with `key` and `result`; counted by the program |
| AskHeader's Play tab, the Pocket's Games…, the companion's Play menu entries | `entries` with `places` |
| The drop card's Play on TV | `drops` (moved now) |

**Why:** the founder: everything of an extension's goes with it. The Game Center could only be drawn by the app because pages lacked its parts and the app held its settings, words and AI access (D93's reasoning, which no longer holds). **Alternatives:** per-game exceptions in the validator (a game name in the mechanism); declaring commands outside tools (D50's place is good, and a command with no tool has nothing to run); a web view for rich pages (D62, D98's first answer); settings the program stores itself (the host couldn't draw, search or back them up, nor keep an AI switch out of its reach); matching only the person's language (a person speaks what they speak; and today's games match all ten); refusing sentences Sidefolk's own words claim (an app update would then turn installed extensions off); letting the model change settings by name (an author's words in every run, D24).

**Implications:** manifests with these keys need a Sidefolk that knows them: `minimum_sidefolk` (D83) on anything using them; every add-on that names one holds the same placeholder until the lead sets the real snapshot just before release. `CommandFrameTests` reads the old word tables: at snapshot B they move into the test or into the extension. Pages read pictures through D99's `PackAssetReader`, the one reader of a pack's files, which takes only a picture's path for a picture. **Not built:** dynamic entries (they are the manifest's, not the program's), settings shown only under a condition, a conflict shown in Settings after install (the install sheet says it).

**Amended by the review of snapshot A (2026-11-02):** a page can draw a `scene` inline, its areas running the extension's own tools: smaller than a colour on each part, and a future relook then needs no app release, so the Game Center's look stays Playtime's. `carries` (`store`, `history`) with `settings_from`, for Sidefolk's own only: copies, because a build still reading the app's record can run until snapshot B. `{"ai": false}` in the carry's reply sets the person's switch off; it can't turn it on. `sidefolk/settings.set` is held to one a second, last value winning, no row for an unchanged value. Text caps hold at most 8 marks on a character, a prompt 32,000 bytes, a text setting 8 bytes a character. The surface's `say` comes after all of Sidefolk's own understanding and is reported to the author like a command's; a game's sentence keeps its place in the chain until the old code goes (moving it broke the old `gameCommand`s), and yields to Sidefolk's own (`claimsAsItsOwn`). An approval word in a sentence is refused at install, warned about when already installed, and never matched: the list may grow with an update, and that mustn't turn off an extension. Requests carry settings whether or not they name their language. An Ask tab shows whose it is. **History and "everything is gone":** rows in the extension's own words (`extensions.activity`) go when it is removed; rows of what its tools did, a surface's "Used …" and an AI request stay, because History is the person's record of what ran on their Mac and a removed extension shouldn't be able to erase that. **AI help on Codex:** Codex always adds the person's `AGENTS.md` with no switch, and the answer goes to a program, so while that file holds anything, requests are refused with `off` and the switch says why. A clean `CODEX_HOME` holding only the login was the other way; rejected without a live test, because Codex rewrites its login file when it refreshes it, and a copy or link could leave the real one stale.

### D101 — Playtime moved onto the abilities; the app keeps no games (2026-11-02)
**Decision:** *the last of the founder's rule (D98). Amends D75, D79, D93, D95, D96.* The app keeps no games: with no extension there is nothing of them anywhere, and removing Playtime leaves nothing. Everything of Playtime's lives in its pack: every game's screens, words, art, sounds, its menu and the Game Center. It opens as one surface, `play`, through a tool's reply (`open_surface`), and an app update can't change it; a new game or look ships with a Playtime update alone. The move is:
- **The stage** (`extensions/playtime/Sources/Stage`): the Play panel's layout in boxes. A game's screen still says a `Board`, as it always has, and `BoardDrawing` makes it a `Scene`: each part in a file of its own, every value read from the panel's SwiftUI. Layout needs heights, so `TextFit` measures words with Core Text, which works in the sandbox and takes microseconds; `{companion}` is measured as a usual name and shrinks if it must. What the panel kept for a board (what is typed, the arrows' cursor, a keyboard's page) is `LocalParts`, saved with the session, one move a key; `Suspense` is `GameSuspense`, in the program: a verdict is held back during its build-up and read again from the state when the moment comes, so nothing shows a result early, and the founder's rule is a test on the boards the bot really plays.
- **The table** (`Table/`): `PlayTable` is one surface session holding the menu and the game on the table; a game left open is saved at each move and kept ten minutes when another opening ends the session, as the panel kept one. `GameTable.Driver` erases a screen's types. A game ending writes one row through `extensions.activity` (`activity: false` on the surface), and the menu's numbers count Playtime's own `plays`.
- **Commands** (`tools.open`, `put_away`, `game_settings`): every sentence the app's tables answered, by language, in `strings/`; proved against the pack itself by `GameCommandsInThePackTests`. **Entries:** Pocket and Ask's tab, and a submenu of every game on the companion. **Settings:** tone, sounds, Sneaky, and each game's own speaker and level (`listed: false`); `settings_from: games` and `carries` bring what the person chose and History's rows of games played, once. A "no" to AI trivia stays a no.
- **The Game Center** is Playtime's page: `hero`, `stats`, `cards`, `recent`, `badges`, `settings`, worked out from its own records.
- **AI trivia:** `permissions.ai`, `AI.ask`, and the app's checks of a pack moved to `TriviaPackCheck`. The person's switch replaces the setting.

- **Rock, paper, scissors and the desktop's coin, dice and hands** are Playtime's: the match as a game like the others (`RockPaperScissorsScreen`; the app's `companion.handsScore` and `companion.handsDuels` through `carries.store`), and `toss`, a tool with sentences in ten languages (the app's were English only) whose reply opens the overlay `toss` with what it drew, holding the AI's words until it lands. An overlay is one scene while it flies and one when it has landed, which closes itself after five seconds; Again draws anew and writes its own row.

**General abilities this needed, for any extension:** `listed: false` on a setting (for what you hold per thing you have many of: shown only where you name it); a tool may hold 32 commands of 24 sentences, 400 sentences an extension (a game's name in ten languages needs them; a parse is still a table look-up); a command's reply that opens a surface or page lets Ask step aside, as a quick intent does; a card's `color` is the tile a pack picture stands on; `L` looks a word up directly rather than copying every table (it ran dozens of times a board, and took 3 s to draw the menu in a debug build). `surfaceExportArt` and `surfaceExportSounds` wrote the app's drawings and sounds as files for the pack, and went with them.

**From moving the word games, general again:** a `keys` path's first key at `t` 0 was dropped (`SceneTimeline`), so nothing rose, popped or flew from where it said: it now starts there. An area that `submits` a field is drawn at half its opacity while the field is empty, as a disabled button was. Scene text wraps with `lineBreakStrategy = .standard`, as `Text` does everywhere else. Debug only: `surfaceEntry`, `surfaceSubmit`, `surfaceBack`, `SIDEFOLK_REDUCE_MOTION=1`. A note for whoever compares looks: `snap` and `surfaceFilm` use `render(in:)`, which ignores Core Animation filters, so an old panel's SwiftUI `.brightness` lips only show in `screencapture -l <window>`.

**Accepted differences, by D98 and D99:** the frame's 44 pt header replaces the game's own card, so its subtitle and the title's size go; the companion says nothing on the desktop or aloud (a cue's `line` has no form); dice tumble in 2D; a shine is a plain gradient; "i think of a number" is a whole sentence, so it takes no range after it (its residual is "think of a number", which the person guessing also says).

**Why one surface, and boards kept inside the program:** a scene per game would have moved every game's look by hand at once, and a mistake would be in fifteen places; the board stays what a game says, and only the program knows it. A relook (`sandbox/games-relook`) changes the stage alone.

**Alternatives:** a surface per game (16 surfaces at the cap, and the menu would be another program state to keep in step with them); measuring text in the app with a `fit` height (the reader in Core has no fonts, an extension's layout would depend on the app's release); a filter inside the app for the old look (exactly what the rule rules out).

**Implications:** `minimum_sidefolk` holds the placeholder until snapshot B's number is known (RELEASE.md). The board model (`Board`, `Cue`, `Move`, parts) left the Kit for the pack, as did the Kit's `GameRecords`; the Kit has no game channel. `CommandFrameTests` keeps its words in the test (`CommandFrameWords`). To add a game: EXTENSIONS › Surfaces and scenes.

**Amended by moving the table props (2026-11-02):** three defects in what snapshot A shipped, found by filming them beside the old panel, each general and in the app: a `shadow`'s `dy` fell up the canvas (the view's geometry is already flipped); a node changing size between scenes swung about its middle while `transition_ms` eased it, so the whole board jiggled when a part below it came or went (a new size now shows at once with its top left where it was, and only where it goes eases); and a key `seat` was refused when the layout typed something else for it, so two players' keys worked only on a US keyboard. A debug run can ask for Reduce Motion with `SIDEFOLK_REDUCE_MOTION=1`, without touching the Mac's setting; `surfaceKey` of one letter also presses that seat.

**Snapshot B, what left (2026-11-03):** `Sources/SidefolkApp/Play` with its art, `Home/GameCenter*`, `Sources/SidefolkCore/Games`, `GameSettings`, `IntentGameCommands`, `IntentGamesMenu`, `IntentGames`, `IntentChance`, `GameCommandWords`, `GameSlotWords`, `CompanionToss`, `TossStage`, the game channel, `ExtensionPage.games`, the manifest's `games`, `InterruptSource.games`, the Pocket's and Ask's fixed entries, 300 catalog strings. `ExtensionFreeAppTests.transitionOver` is true and no game entry remains in the allowlist; `extension-free-binary.sh --strict` runs in the release path, now reading binaries as well as names (its verdict used to miss them), and the words it and the guard look for come from each manifest's surfaces and entries. **What stayed, general:** `CompanionCue` and `CueLimiter` (a surface's reactions, and `CueDirector` playing them), `SceneReading`, `SceneOutcome`; catch-me and petting as the companion's own life.

**A copy from before (`ExtensionManifest.retiredKeys`):** a manifest naming `games` was made for an older Sidefolk. It isn't broken, so strict decoding takes that one key and the rest isn't judged (its parts answer to what that Sidefolk read). It stays listed, with its page in Home saying so, and offers "Update Playtime" instead of a switch: `AddonUpdateActions.updateOutOfDate` takes the gallery's newest whichever channel the person follows, since this copy doesn't run until then, through the usual rule (permissions it adds wait for the install sheet). Nothing of it runs or is offered. In memory only: its stored record is untouched, so its data folder, what the person chose (`AppSettings.parked`), `kv` and History's rows are all there for the update's `settings_from` and `carries`. A pack naming `games` can't be installed; the sheet says it was made for an older Sidefolk. Tested with the real snapshot.8 manifest (`Tests/Fixtures/playtime-snapshot-8`, version as the gallery stamps it). A `ResultCard` of a kind this copy no longer has reads as a plain card, so a past coin flip stays in History.

**Live, on this build:** every game opened from the menu and answered a move; the Game Center; the coin overlay landing with Again; removed, nothing left (menus by the code and tests, Ask's two tabs, the sidebar, its folders and row gone). "play a game" and "flip a coin" with nothing installed get the plain "That needs AI". Idle CPU in the debug build, the app's process over 12 s with the companion out: 5.4–5.8 % with no surface, 5.2–5.5 % with Sudoku at rest, 5.4–5.7 % with the cups at rest (main thread in the run loop). Settings' search for "game" finds one row, "Presentations, games and video calls", about other apps being full screen: left as true.

**Found closing it:** a command's reply is what a person reads on Ask's card, so a tool's reply mustn't be written for a model: the toss said "Flipped on the user's desktop…" there; it now says "Heads!". History keeps a removed extension's `surfaces.open` rows, as D100 says.

**Amended by comparing it with the old games, game by game (2026-11-03).** Everything here is general unless it says Playtime.
- **No result before the build-up, on every road.** `hold_answer_ms` reached only the AI's words about a tool that changes something: a person's command got its card and its spoken line at once, and a read-only tool's hold was never read, so "flip a coin" said Tails! while the coin was in the air. `AnswerHold` reads every finished tool, and the runner carries it to the card.
- **Listing extensions was 4 s of a core for anyone with Playtime** (every AI request, launch, each `.dataChanged(.extensions)`): a tool's commands were compiled per listing, each command recompiling its parts in every language. Now per runtime, and a part once per vocabulary. Debug: `open`'s commands 1.75 s to 0.1 s; five listings of the real pack under 0.5 s, tested.
- **An overlay asked for from Ask takes Ask's place** (Ask stays for one the AI opened, whose words need it), and an overlay on screen that changes size stays where it stands (`SurfacePolicy.resized`), so a coin doesn't land 500 pt from where it flew.
- **Sentences:** parts may stand around a whole sentence (`with` on `say`), so the old chance patterns' every way through fits; the companion's name carries a sentence; a character of a script without spaces is a word; a part needs a word or a mark of its own (`+{n:integer}`). Every sentence of the old tables, whole (190 for the menu, 84 for who guesses, every way through the chance patterns), is in `GameSentencesFromTheOldTablesTests`, with the pack and without. So "i think of a number" takes a range again, and that accepted difference goes.
- **Settings:** `follows` (one write for all, a press for one) replaces 17 rows and a minute for "game sounds on"; `sidefolk/settings.set` is untouched. `segmented`.
- **`trusted_only`:** D99's "a topic goes in a tainted turn" had gone with `games.open` (T40).
- **History:** a signed pack's reply can say what the call did (`row`); a surface a tool opened writes no row of its own. A setting a tool changes still writes its own row beside the tool's: every change goes through `extensions.setting`.
- **Pages dressed from the pack:** D100's "the Game Center's look stays Playtime's" was true only of the backdrop. A hero's `tile` and `wash` and bubble, a stat's `color`, a button's `round` and `accent`, a section's `banner` and `wide`, its `detail` drawn when it doesn't fold, settings in a `grid` with pictures, a signed pack's `ai_title`. Parts rather than an inline scene: a scene scales with the window, and these must keep their text sizes and wrap in every language. Compared side by side with the old center at one size.
- **A scene with no speaker** (`"speaker": false`). **A word in context** (`L("Solved", context: "games")`), since Daily Word's "Solved" and the Game Center's want different words in five languages. **Reactions paced:** `pump`, `flick`, `roll` and effects at the sounds' pace, a dropped one being a moment passed; a prop's change waits its turn and the newest wins. **The install sheet's count** leaves out "No access to your files". **Carried for good:** after a carry the named store keys are deleted, and which were carried survives removal, so a reinstall doesn't bring old numbers back; History's rows stay the person's record.
- **The guard:** ids from what a surface takes and an entry's input, a name with commas, words of chance with or without the add-ons; CI fails with no manifests unless told (`SIDEFOLK_GUARD_WITHOUT_ADDONS`); what an exception matches is pinned; the binary check exits 2 having read nothing. `gamecontroller` isn't looked for: catch-me's own icon uses it.
- **Playtime:** a game hidden by ✕ is the one to Continue (the session file; Sidefolk tells the program nothing when it hides); leaving for the menu puts props away; `TextFit` measures in the rounded face scenes draw with.
- **The crash found in catch-me wasn't catch-me's.** A card near the screen's top fitted above the companion without its tail and not with it, so it flipped over and under at every layout until AppKit gave up (`_postWindowNeedsUpdateConstraints`). Found by logging the window's frames: 303 and 657, every pass. `CardPlacement` counts the tail's room. Any card with the companion standing high could do this; it predates this branch. 0 of 32 fresh-launch runs died after the fix, 3–6 of 20–30 before, in the same loop.

**Left for the founder:** the props the app draws for a reaction (`gem`, `balloons(n)`, `sealed_card`, `magnifier`, `cards`, in `CompanionCue.Prop` and `PropView`) are a fixed general list no decision approved by name, and a new look for them would need an app release. Either a reaction names a picture from the pack (a general ability; the art would move to the pack), or this list is approved here as general.

### D115 — What "done" means: the reply is checked against what ran, and a reminder marked done finishes its task (2026-11-03)
**Decision:** *amends D49. Dev ideas, items 3 and 4.*
- **Replies.** `ReplyCheck` runs on every brain's reply in `AgentRuntime`, so Claude Code, Codex and API models alike, and adds what really happened beneath the model's words, in the app's language. A step that changes something, failed and wasn't then done again (same tool, same words) is told whatever the reply says: "Not done: “…”." and why. A reply making a firm claim when no call of any kind worked gets "Sorry, that didn't actually happen: no action ran. Nothing was changed." A reply saying it couldn't, when something did succeed, gets "Done so far: …". It stays in the conversation, so the model reads it next turn. Words are checked in all ten languages (`UnbackedClaim`): "firm" means about what Sidefolk does, so "I've added comments to the code" passes. `LoopBackend`'s one extra turn also fires after calls that all failed, never after one that worked or one the person refused; the CLIs run their own loop, so they get the correction without that turn.
- **The quick path.** A tool's own `isError` no longer shows as done (`LocalIntentRunner`); everything else there already came from `ToolExecutor`.
- **Reminders and tasks.** All of it goes through `ReminderScheduler.complete` and `settleLinks`, so the Pocket, Home, the Calendar, bubbles, notifications and tools agree:

| What happens | What follows |
|---|---|
| Reminder marked done, its task open | Task done. A series stops with it (as the bubble's Mark done already did). Undo reopens the task |
| Reminder marked done, it belongs to a note | Nothing else: a note has no done |
| Task done | Waiting reminders end: a one-off done, a series stopped (D49) |
| Task to the Trash | Waiting reminders end; restoring brings back those still ahead (D49) |
| Task deleted for good | Reminders cancelled (D49) |
| Task reopened | Reminders it ended come back if still ahead (D49), a series marked done among them, since the task ended it; a one-off the person marked done, or anything they cancelled, stays so |
| Reminder snoozed or cancelled | Task unchanged |

**Why:** the founder: "when the companion says an action is done, it is actually completed", and a reminder marked done left its task open everywhere but the bubble. *Why add rather than replace the model's words:* a reply can hold a good answer beside a false claim, and the correction is true either way, even when the check misfires on a sentence about the past. *Why told always after a failure:* the claim words can't be complete, and a failure is what ToolExecutor knows for certain. *The handover recommended a reopened task's reminder stay cancelled;* D49's return is kept, because it was tested and decided, makes reopening a task marked by mistake undo everything, and only ever brings back times still ahead. Flagged for the founder.
**Alternatives:** a second model call to judge the reply (costs quota and can be wrong in its turn); replacing the reply (loses the answer); a card for the correction (words also reach voice and the next turn).
**Not covered:** a reply that does one thing and claims another too ("saved it and set a reminder" with only the save run), or that reads something and claims it changed it: a failure is told, a thing never attempted beside something that worked isn't. Claims outside the words listed pass. Other linked pairs, checked: a collection deleted from Home moves its items to the Trash, so their reminders follow; an archived collection's reminders still fire, which is what the person set; Apple Notes copies are independent once copied; watchers have no linked records.

### D116 — Running apart from shown: every watcher runs, three places to show a live value, and their order (2026-11-03)
**Decision:** *amends D35, D84, T4, T24, T29. Dev ideas, items 6 and 7.* A live value (`Watcher.Mode.report`) has a `display`, whatever it costs to run:
- **Beside** the companion: always visible, in the person's order. `WatchLimits.maxBeside` is 3, the places the corner has always shown. **Notify:** hidden, and a pin for 8 seconds beside the companion at each reading, once a minute at most, one at a time: kept nowhere, so it fills no History and spends no attention budget, and only while the person is Open to everything (not in Focus or Quiet). **Quiet:** runs silently; "Running Quietly" in the companion's menu and the Pocket's ⋯ lists what each last read.
- **No count for the person or Sidefolk's agent at their word:** `maxActive` (50), the four live values and the five command watchers are gone for them. What runs without the person's words (routines, extensions, a turn that read outside content) keeps a ceiling of 50 together (`maxUnattended`). A new live value with no place left runs quietly rather than being refused, and says so. What keeps it calm is what always did: the floors (5 s, 10 s, 60 s), one request a minute per host, four checks at once, the lifetimes. Measured on a debug build, 60 s of `ps`: 1.4 % CPU with 5 live values, 1.7 % with 200, all read every 10 s. Those are metrics, the cheapest kind; web and command watchers cost more per check, and only those floors bound them.
- **Other agents:** *the founder's question, the handover's recommended answer.* Together they get 25 (was 10), then asking: refused for room, the error tells them to call `watch.more_room`, which is medium and always asks them (`ExternalToolPolicy.alwaysAsks`, so no setting makes it automatic), and which refuses every other caller, since Auto and Full access answer for Sidefolk's own agent. A yes adds 25, up to 200, and is kept. They hold at most 2 of the 3 places beside the companion (T29); past that theirs run quietly. They get `watch.pause`, `watch.resume`, `watch.update` and `watch.reorder`, for their own only.
- **Order:** `sort_order`, shared by the corner, On duty, All watchers and `watch.list`; from before, the order they were made. `watch.reorder` swaps within the places the named ones hold, so an agent moves nobody else's.
- **All watchers** (`HomeSelection.watchers`, from On duty): drag to arrange, where each shows, Symbols and Units, pause, resume, stop. A live value's own page has the same choices.
- **Value formatting** (item 7): `value_prefix`, `value_suffix`, at most 8 characters, plain (`displaySafe`). A word gets a space, a sign doesn't; the value is isolated (FSI … PDI) so digits never reorder in Arabic. With neither set, a value is exactly what it was. Migration `v7-watcher-display`; the first three from before stay beside, in order, looking the same, and a fourth, which only Home ever showed, runs quietly where it can be found.
- **A watch for changes has no place to show:** it tells when something changes, and `display` says nothing for it.
**Why:** the founder: no limit, managed in one place, the agent able to arrange them, and the companion must not take more desktop. The cap belongs to the room beside the companion, not to running.
**Alternatives:** a bigger strip (the founder complained of its room); refusing the fourth value (a limit by another name); per-agent room (their names are self-chosen, T4); asking on every watcher past the number (a runaway agent would ask hundreds of times).
**Not done:** an agent's "ask once" is the agent's to keep: each further call asks again, which only ever costs them a refusal. An agent may set its own value back beside the companion after the person moved it, while there's room.

### D117 — Notebooks are arranged and dressed by the person, a task can be due, and agents can read what was written (2026-11-03)
**Decision:** *amends D53 and D97. Dev ideas, items 8 and 9, and the first of 10.*
- **Order:** drag in the sidebar or `notes_arrange`; `collections.sort_order`, alphabetical until someone arranges them, a new one last after that, the Inbox always first. Migration `v8-notebook-order-due`; a backup is the database, so it carries it.
- **Look:** 90 icons (`CollectionLooks.symbols`, each checked to exist), emoji, the twelve colours, and any other colour stored as `#rrggbb` and drawn through `CalendarPalette`, which moves only its lightness until it reads on this theme's cards in light and dark. Identity, never status (D78): it colours this collection's icon and nothing else.
- **`notes_collection`:** name, icon and colour for agents too. It is always asked of other agents, whatever Settings says, since naming a collection is what they otherwise can't do (T4), and a name they give reads as theirs (T3). `notes_arrange` follows "Change and delete notes".
- **A task's due date,** distinct from a reminder: a due date says when, a reminder when to nudge, and a task can have either, both or neither. `items.due_at` had sat unused since v1; `due_all_day` says it's a day, kept as noon so a few time zones don't move it. `due` on `notes_save` and `notes_update`, a calendar button in the editor, a line under the task, late in amber and in words (D78), and the Tasks tab puts what's due first.
- **On the Calendar (D97):** in the tasks colour with a tick, an all-day chip or at its time, "Due" and who it came from, done from there with Undo. Not draggable yet. *The founder's question, the handover's recommended answer:* **never written to Apple Calendar**, which would clutter the person's real calendars.
- **For item 10:** `notes_get` reads a note in full (asked like other reading); `append` on `notes_update`; "Sidefolk Dev" finds "Sidefolk-Dev" when only one fits; a search also finds what's in a collection of that name, after what says the words, never About you and only for three letters or more. The direction itself is [research/notebook-proposal.md](research/notebook-proposal.md), and waits for the founder.
- **The label "written while reading untrusted content"** stays: only agents read it, as `notes_list` says who wrote a note. It means Sidefolk's agent saved it in a turn that had read outside content, so reading it back taints a turn (T3), which is right even for words the person dictated in that turn. The person never sees it in the Notebook; About you says "Noted while reading outside content".
**Why:** the founder's notes. Tasks and reminders stay two things because they are: most due dates want no nudge.
**Alternatives:** the due date as a kind of reminder (a nudge nobody asked for); a separate `calendar` of Sidefolk's in Apple Calendar (the founder's real calendars); free-form custom colours as they are (one dark or pale would vanish on a card).
**Not done:** dragging a due task on the Calendar; "by friday" in typed quick notes (the AI takes `due`, the local parser doesn't yet).

### D120 — The companion can answer for Sidefolk itself (2026-11-03)
**Decision:** *the founder, showing a companion offering to "build a small extension" to find out whether Sidefolk had an update.* Built-in tools, for Sidefolk's own AI and not other agents, which have `status`:
- **`sidefolk.about`:** version, companion, AI, theme, appearance, language, extensions on and off.
- **`sidefolk.updates`:** looks now for a newer Sidefolk and add-ons, through the same `UpdateChecker` and report as the menu's Check for Updates, with no window of its own. A failed look is a failure, never "up to date", and a gallery out of reach says add-ons weren't checked. A development build says it doesn't update itself. Add-ons follow the person's own automatic setting, as any look does.
- **`sidefolk.install_update`:** medium, so Guard asks; it opens the update window, which checks the signature and asks before restarting. It says what it came to (downloading, ready to restart, already under way, nothing newer), and never restarts by itself.
- **`sidefolk.open`:** the update window, a page of Settings or a place in Home. **`sidefolk.look`:** appearance and theme by name, with Undo.
- **`mac.software_updates`:** `softwareupdate --list`, read-only; installing stays in System Settings. It reaches Apple, so it can take a minute and has a longer limit.
- **`ContextBuilder.reach`** tells the model these are its own, and never to offer an extension for them.
**Why:** it can do a lot, so not knowing its own version reads as broken. The app always knew; nothing let the AI ask. By the founder's rule (D98) this isn't an extension's: it's the app's own.
**Alternatives:** a prompt line with the version (no updates, stale in a long conversation); typed sentences without AI (a later addition: the menu has Check for Updates).
**Not done:** switching companion in words (gallery companions must be installed first); these answer through the AI only, so with no AI set up it's the menu.

### D118 — Conversation titles for agents on duty, and the companion as the Dock's icon (2026-11-03)
**Decision:** *dev ideas, items 11 and 12.*
- **Titles.** A hook's payload has no title, but it gives `transcript_path`, and Claude Code writes `custom-title` and `ai-title` lines there; Codex keeps `thread_name` in `session_index.jsonl`. *The founder's question, the handover's recommended answer:* yes, the title line only, on this Mac only. `ConversationTitles` reads the last 256 KiB, parses only lines that declare a title, keeps nothing else, believes a path only inside the agent's own folder and never through a link, at most every 20 seconds a session. The person's own name beats the agent's. `sessions.conversation_title` (migration `v9-session-title`) stays apart from `title`, the first prompt, so a row with no title says its project rather than guessing. A title isn't given to the model (T2): only the person sees it. Two titled conversations in one folder stand apart in On duty, the Pocket and the lane, amending D90's one line; one with none, like a subagent, joins them.
- **App icon.** A setting in Settings › Companion, off by default. `NSApp.applicationIconImage` paints the Dock only, while the app runs: the bundle isn't touched, the signature stays good, and Finder and Launchpad keep Sidefolk's, which the setting says. A companion carries `appicons/<id>.png` in the app, a gallery pack or a folder (D85); with none, its portrait on a tile in the app icon's shape, so the setting does something for every companion today. The menu bar's mark stays Sidefolk's: it has to be one colour to follow the bar.
**Why:** the founder: "help users with multiple active sessions", and companions as the app's identity.
**Alternatives:** the first prompt as the title (a guess, and conversation text); changing the bundle's icon (breaks the signature); no icon without a carried one, as the handover said (a setting that does nothing, since no companion carries one yet).

### D119 — Read a few linked pages without asking, in this conversation (2026-11-03)
**Decision:** *amends D47. Dev ideas, item 13.* Research asked at every page, since once a page is read each new address waits (T2). On a card for reading a page, Allow's menu now has "Allow, and read a few pages it links to without asking". After that yes, `web.fetch` goes without a card for **links on a page read since the yes, byte for byte**, and nothing else:
- **An address the model wrote still asks,** even a link spelled another way (`%61`) or with something added. A model can put what it knows in an address it writes; a link's words came from the page. A broad read-only mode, which the handover first sketched, would have reopened that (T42).
- **Off until they say so, on the card itself,** for Sidefolk's own agent, never under "Ask each time", never for an address with a query, and not in a conversation from before a restart, whose reads nothing here remembers.
- **It ends** with the conversation, within the hour (*the founder's question, the handover's recommended answer*), after 12 pages, when another card asks, and for good in that conversation once any tool comes back but reading pages and a few named harmless ones. The rule is that way round because a tool that reads something personal needn't say so, and an extension's rarely can.
- **What `web.fetch` always was stays:** GET only, no cookies or sign-ins, no local addresses, content untrusted. Each visit is in History, marked as this.
- **Pages list their links to the model only under a yes** ("Links on this page:", at most 40, those it actually rendered: nothing hidden, `http` and `https`, no local addresses), so it costs nobody else anything. They didn't before, so it couldn't click through at all, only guess. A link off to another site that repeats words from the address just fetched isn't counted: it may be a server echoing what the model wrote.
**Why:** the founder: "reduce the friction of asking for permission for every single site" when clicking through pages.
**Found in review before release:** the first version compared decoded addresses, so a model could spell a message in `%61`s of a listed host; a regex on a page's raw HTML could freeze a read for anyone on a page built for it (now the page's own single-pass scanner); and `http://%6Cocalhost` reached this Mac past T11 whatever the mode (now refused).
**Alternatives:** any address after a yes, with queries stripped (a path carries as much); a setting rather than the card (a standing risk for an occasional need); per-domain grants (D47 has them; research crosses domains).
**Residual, in T42:** a hostile page can steer which link is followed, and About you and matching notes are in the prompt from the start. The budget bounds it: about six bits a link, so some characters per yes, and the person is asked again.

### D121 — Noor: a gallery companion that builds what Meshy can't make, with real fur (2026-11-03)
**Decision:** Noor, a baby moth, joins the gallery in 3D only, worn by name with no `CompanionChoice` (D77, as Piko). He is a
new way of making a companion, with no engine change: Meshy's model gives only his proportions. The rig cuts its wings,
feathers and rosette away, remeshes the rest into a clean closed body, and adds those as skinned parts textured with
paintings. The character file draws his fur in shells over the body: stacked copies of its triangles, where each strand
narrows outward and leans into a clump, half as many layers in a small window, and coarser, softer strands the smaller he is drawn.
The body has no texture: the rig marks zones (bare, fur, ruff) and the material colours them. The face's outline is drawn
in the surface. He rests sitting up. `frame.sidefolk` is 2.7, and the character file raises the body's box for the feathers
so hops stay under the window's top, since `roomAbove()` only reads the body mesh.
**Why:** the founder compared Meshy's raw model with its design image and called it "very cheap". Its fur was a sculpted
crust, its wings flat plates through the hips and its inlay blurred, and tuning doesn't fix those. The founder's condition
for approving him was that this quality was really reachable, so two proof rounds came before any rig.
**Measured on this Mac, against Spark in the same debug app, alternating, with other apps running (noisy):** idle, CPU 8–12%
of a core against 16–19%, and the whole Mac's GPU 33–40% against 29–33%; dancing, CPU 22% against 40%, GPU 36% against 34%. A
run an hour earlier, on the same geometry, read much the same difference at a higher level. Older Macs aren't measured.
**Alternatives:** tuning Meshy's texture and sculpt (the first proof: cheap up close); a second Meshy model (the same flat
wings and crust); a `CompanionChoice` case (needs an app update and his name in `ExtensionReservedNames`, which would refuse
the Noor extension's name).
**Implications:** a companion's gallery page and install read the catalog's translated words (D76), which they had ignored: until that reaches an app release, his page is in English on published copies. Up close he is a very good real-time character, not the concept's painted stills: his fur is short pile
with soft tufts, not long silky strands. 3D only for now: a 2D form (D59) isn't made. The technique is in the
`sidefolk-3d-character` skill. Fur costs the GPU, so a new companion that uses it is measured there, not only in `top`.

### D134 — The Notebook is a place of its own, not a jump to a collection (2026-11-03)

**Decision:** Home's Notebook row and ⌘3 open the Notebook's own page. In order: its count, a search across everything, the open tasks that are late or due within a week (five at most, finished with a click), every collection as a tile (what's in it, open tasks, last change) with New collection last, what's pinned anywhere (six at most), and Trash and Archived. ⌘N there and New › Note from any other place make a note in the Inbox. Deleting or archiving the collection on screen lands here. The sidebar's section under the places is now called Collections. This narrows D84, where the row stood for "wherever the Notebook was".
**Why:** the founder: "you click there, then the selector jump to another sidebar icon... If I want that thing in the sidebar, I would just click it." The row was a redirect, with the same word twice in a row. It leads with what the sidebar can't show, so it's worth a click with two collections as well as with twenty, and it is the first part of direction A in `docs/research/notebook-proposal.md`: the view across collections, without bulk selection or quick dates.
**Alternatives:** removing the row (⌘3 and "open Notebook" would have nowhere to go); a list of everything (Search everywhere and Today's captured list do that); a stats dashboard (counts that nobody acts on); a recent feed (Today has one). A due date further than a week off is the Calendar's.
**Worked out from what's loaded:** `NotebookOverview` in Core, from the live items `NotebookModel` already reads, with no new query. It's computed when the Notebook changes and when the page opens, so a page left open over midnight shows yesterday's "late" until then.

### D135 — A web watch's first look says what it couldn't see (2026-11-03)

**Decision:** a watch must have something to watch (PRODUCT E5). A first look with no text at all is a failed check: no baseline is kept, the card says "I can't read <site>", On duty shows the reason, and it keeps trying with the usual backoff. "Tell me when these words go" with the words absent on the first look doesn't fire: the card says they aren't on the page as Sidefolk sees it, and it fires only after they were seen and then went. HTML with under 80 characters of text gets a note on its first look and is watched. A `contains` already true on the first look still tells at once, as designed. A blank baseline kept from an earlier version counts as no baseline.
**Why:** a page that needs JavaScript or a sign-in was confirmed as working and then watched nothing, or fired "“X” is gone" about words it had never seen.
**Known gap, kept rather than guessed at:** a sign-in page that answers 200 with text looks like any page, so "any change" and `contains` on it watch the sign-in page. There's no reliable general way to tell, and a guess would wrongly flag real pages.

### D105 — A page can hold state and move around itself (2026-11-03)
**Decision:** a page may say where it is without running a tool. `sidefolk/page.render` gets `state` (an object of at most 4 KB, kept by the host per open page while Home is open) and `width` (its column in points, rounded to 10); a background reading says `background: true` and may be answered with the summary alone, except by a page with `history`. Page JSON gains `back` (Back's label, drawn while there is a state to return to, ⌘[) and `bare` (it draws its own head). A control may name one of these instead of `tool`: `go` `{set, push, back}`, `copy`, `file` `{tool, param, types, input}`, `allow` (`place`, `schedule`) or `settings` (`notifications`, `attention`, `place`). `switch`, `choice` and `field` take `go` with `key`; a field may be `live`. A `tabs` tab may hold `go` instead of sections, the part's own `sections` being what the program drew for it, and `tint` colours the picked tab; tabs that don't fit become a labelled menu, for every page. A tool's `open_page` stays a plain string and also takes `{page, state, push}`, still only when a person started it. A manifest entry with a `page` may name `state`.
- **Why not more tools.** Going to a tab or holding a draft isn't something the person did to anything: it shouldn't be in History, and shouldn't be refused while a tool is held. What changes anything still runs a tool, through Guard. The five-page limit stays: a page with places in it is one page.
- **Why not a sheet or a route type.** State is enough: a sheet is a state whose page draws a sheet. The host stays out of what a program's places are.
- **A scene's areas can only `go` or run a tool.** An area shows no words of its own to go by, so what is copied, opened or asked for hangs on a button that says so (T12).
- **`copy`** runs `clipboard.write` as the person, so the capability switch holds and History has the exact words, and the page shows them too. **`file`** is the system's open panel, then the tool with a read of that file alone for that one call (`ToolExecutor.execute(pickedFile:)`, as a dropped file has, T12); other path parameters are taken out of its input. **`bare`** keeps two lines that are Sidefolk's: what went wrong with a click, and "Added by …".
- **Reading:** one reading in flight per page, with one more after it if something changed meanwhile, so a click is never undone by the read before it. Kit requests run in order, so a program must not fetch inside a render.

### D106 — An extension may ask for the person's place (2026-11-03)
**Decision:** `permissions.place` `{purpose}`. Off until the person says yes to Sidefolk's own question, per extension (`allow: "place"`, or a switch in Settings › Add-ons), recorded by `extensions.consent` (their click only, not a model, an agent or the extension). While allowed, requests carry `place` `{city, region, country, country_code, latitude, longitude, time_zone, updated_at}` (null when Sidefolk knows none; `time_zone` can be missing) and `place_share`; a running program also hears `sidefolk/place.changed`, and a real move asks for a new plan (D107). `sidefolk/place.search` → `sidefolk/place.found` goes through `extensions.place_search` to Sidefolk's own place search, so Guard, the network switch and History all see it; it needs the permission but not the yes, since only the words typed leave, one in two seconds.
- **The yes is to terms:** the pinned purpose and whether it has the internet. An update changing either asks again (T30).
- **Coordinates are the two-decimal ones the weather uses.** A program with `network` could send them anywhere and a tool's reply could put them before a model: the question says so. It is why this is a question and not an install line.
- **Clearing the extension's data leaves the person's place alone**, and removal ends delivery.

### D107 — An extension may tell the person at a moment it plans (2026-11-03)
**Decision:** `permissions.schedule` `{purpose}`, the person's yes as in D106. Sidefolk owns one timer (`OccurrenceScheduler`, beside `ReminderScheduler`) and tells them through `AttentionCenter`, so no extension's process has to be awake and a watcher's five minutes are no part of it. `sidefolk/occurrences.plan {reason}` (`start`, `wake`, `daily`, `consent`, `place`) is a request whose reply is the whole plan; a program may also send `sidefolk/occurrences.replace` after a change. Plans go through `extensions.occurrences`, at most one in ten seconds, none when nothing changed; the program hears `sidefolk/occurrences.result`. At most 256 pending, 35 days ahead, 64 told a day.
- **A plan that couldn't be made leaves the plan there is.** An answer that isn't a plan changes nothing: a failed asking must never read as "nothing is planned".
- **Identity is the id:** told or missed once, never again, whatever later plans say. A lower revision is refused. It lives in `KVStore`, so every wipe and export of Sidefolk's data has it.
- **Late:** up to 2 minutes late it is still told; older is missed and silent, so waking never floods. Past `expires_at` a notice is taken back, even if it was only held. A new one of a `group` takes the last one's place.
- **Off** means off at the moment of telling too: disabled, resting, failed its check on disk, the yes taken back. Removal forgets everything, its numbering too.
- **Whose words:** the title is the extension's, so its name always goes in the body, on the desktop and in macOS. None of it reaches a model (T43).
- **`system_fallback`:** handed to macOS at quit (reminders first, at most 20, none from a source the person keeps off the desktop) and noted, so the next launch doesn't say it again. A click on one opens nothing: Sidefolk wasn't running.
- **Changing T24, for the founder to look at:** these notices skip the 90-second spacing, as reminders do, and keep the budgets: at a prayer's time, after someone else's card, spacing would make it wrong. With `system_fallback` they reach macOS while the person is away from the keyboard, where anything else waits for their return; never in Quiet. The person's ceilings, Focus and Quiet hold on every road.

### D108 — A page can dress itself and draw to its width (2026-11-03)
**Decision:** page JSON `dress` `{ground, card, line, picture}` and `max_width` (640–1320). Colours come as `{light, dark}` pairs and a pair the theme's ink can't be read on is left out (a light colour under 0.6 luminance, a dark one over 0.12): text, controls and focus rings stay the theme's, and the dress is opaque, so Reduce Transparency and Increase Contrast are as they are everywhere. Cards read it through an environment value in `cardSurface`, which only an extension's page sets. `PageScene`'s limit rises from 960 × 720 to 1320 × 1600: a scene as wide as the render's `width` draws 1:1, without shrinking its words.
- **Why not per-page theming of everything:** `Theme` is the person's. Sidebar, toolbar, the app's own sheets and every control stay theirs; a page dresses only its own ground and cards.
- **`accent`** in the dress is the fill of a filled button and the tint of switches on that page; white goes on it, so a colour too light to hold white words is left out.
- **A `table` part:** `{"columns", "first", "rows": [{"label", "symbol", "detail", "cells"}]}`, a cell being words, a `switch` or a `choice` (tool or `go`). What has several settings per thing takes one line each, and stacks when the window is narrow. Each control is read out with its row and column.
- **The keyboard in a page's scene** (found building Noor, for every page): a page's scene took no keys, so whatever hung on an area was out of reach without a mouse. Tab now goes from area to area in reading order and on out of the scene, Space or Return presses, the ring is the system's focus colour, and what is in a scroll box comes into view.
- **`"ai": false` needs a sentence, or a page or surface** to reach it from (it needed a sentence): what a person clicks needn't be offered to a model or typed.

### D109 — A page can lay itself out to its edges, hold native controls inside a scene, and draw its Today tile (2026-11-03)
**Decision:** three general abilities, none naming an extension.
- **`bleed`**: a bare page with no margins and no gaps between its parts. Its scenes keep their own margins; anything Sidefolk draws on it (a form, a table) keeps Sidefolk's. Back has no visible button there, because the page draws its own: the key and VoiceOver's name for it stay.
- **`inlays`** on a page scene: a field, a choice, a switch or a button at a place in it, at most 24, inside the scene. The scene draws the well or the pill, the system does the typing and the choosing, with its keyboard and its VoiceOver. A field is plain words; a choice is a menu over what is drawn; a button says its own words, so it may do what a scene's area may not, such as copy (D105). Anything else is dropped.
- **`tile`** on a page: at most 720 × 300, drawn on Today across the column instead of the summary. A picture of the summary only: no areas, a click opens the page, VoiceOver reads the summary.
**Why:** the founder asked for a page to match its approved design, not resemble it. A column of Sidefolk's cards can't hold a search box inside a header band, a menu inside a calendar's head, or a two-event tile on Today.
**Alternatives:** building those screens into the app (D98 rules that out); drawing fake fields in a scene (no typing, no VoiceOver); a whole web view (a second renderer, and pages stay data, D62).

### D136 — Ask is a shortcut: results go soon, by whether they reached the person, and History keeps them (2026-11-03)

**Decision:** *amends D90.* A result's time starts when it first reached the person, and how long it stays depends on whether they were there:

| | Watched it arrive, or saw it another way | Came while they were away, from their first look |
|---|---|---|
| **Quick** (a value, a lookup, a roll) | 20 seconds | 1 minute |
| **Answers and things made** | 2 minutes | 10 minutes |

- **What counts as reaching them:** on screen in Ask's own tab (not behind Today or a lone permission slip); an animation that showed it (dice, a coin, `holdAnswer`); a surface or page the extension opened; the companion doing the trick; or the words said aloud. Being told "finished" isn't reading it, so that keeps the longer time.
- **Nothing goes before it reached them,** and the midnight rule is gone.
- **At most eight requests,** pins aside: a ninth pushes out the oldest, seen or not. A pin, and an approval or question waiting, never go that way. This replaces 40 entries.
- **Asking something new tidies** what's past its time, wherever the pointer is. Otherwise nothing fades while the pointer is on Ask or Ask has the keyboard.
- **Pins outlast quitting,** in the database's `kv` (so backups carry them, the export lists them and Delete everything takes them). A pin is an explicit keep: it stays past History's retention until unpinned, cleared or its conversation deleted (T19). What comes back is what it said: no undo or think harder, and Reply only while History still has the conversation. Notices, spoken lines and failures aren't saved.
- **History keeps a command's answer:** an extension's command logged its tool's name ("Calculate"); it now logs what it answered ("2+2 = 4", at most 160 characters, redacted). Only for commands the person ran, since an AI's calls have their conversation. Never for an extension with clipboard access: History isn't a second clipboard, so those still log the tool's name. Nor for an extension with `permissions.act` or `permissions.events` (T44): its answers can carry what it read through Sidefolk or heard.
**Why:** the founder: "if I ask it like 100 time in 30 minutes... I will have 100 thing in the list", "this is like a shortcut... nothing is lost"; and "if I roll a dice and the animation appear... I see it". D90's 2 and 30 minutes were an archive's times. And the promise that everything is in History wasn't true for quick results.
**Alternatives:** one short time for everything (an answer that arrived while away could go unread); fading while the panel has the keyboard (it would take text someone is reading); counting a whisper as seen (a "finished" doesn't carry the answer).
**The numbers are constants in `ResultLifetime`,** and easy to change once they've been lived with.

### D137 — Test runs can stay out of the way; waiting for the app to become regular did not keep windows out of full-screen spaces (2026-11-03)

**Decision:** a debug run with `SIDEFOLK_QUIET_WINDOWS=1` opens normal windows without bringing anything forward; `snap` still reads them; clicks and keys need a run without it (AGENTS.md). Home, Settings and the other normal windows also wait, at most a second, until the app has become regular before they activate and order in (`WindowActivation`). The companion, Ask and cards stay over full-screen apps on purpose.
**Why:** the founder: "suddenly in Claude window itself, the application appears" while another session tests.
**What it did not do:** the wait was meant to stop normal windows landing in another app's full-screen space, and it doesn't. Measured with another app full screen and Home opened through the dev channel: the old build and this one both put Home on that space, 3 of 3 each, with Sidefolk never frontmost. The theory that the switch to a regular app was too slow was wrong. Snapshot 916 shipped this; its notes say so. Also measured: forcing activation (`activate(ignoringOtherApps:)`) makes Sidefolk frontmost and the window still lands there; `[.managed, .fullScreenNone]` kept it off that space, 2 of 2.
**The fix:** `WindowActivation` sets `[.managed, .fullScreenNone]` while it places the window, activates, and goes back to `.fullScreenPrimary` 300 ms later, so the window can still go full screen itself. Refused that space, the window opens on the desktop and macOS goes there: it was asked for, so taking the person there is the cost. Measured 3 of 3 with no click.
**Limits:** in 916 quiet mode moved the window off-screen, and macOS kept a corner of about 40x52 points on screen; it now hides by alpha. A test run's companion and panels still show, and sessions have to opt in. These tries opened Home without a click; a real click hasn't been measured.
**Alternatives:** quiet by default for any `SIDEFOLK_HOME` (`make dev` is the founder's own use of a debug app, and other sessions' checks need real focus); `.moveToActiveSpace` (it would bring windows into the very space they shouldn't join).

### D156 — The MCP server keeps up with its clients: annotations, cancel, a tool list that follows the app (2026-11-03)
**Decision:** *the founder's "all" on the audit at [research/mcp-tools-audit-2026-11-03.md](research/mcp-tools-audit-2026-11-03.md). No new reach.*
- **Annotations:** every tool in `tools/list` says `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`, for external callers only. By name in `ExternalSpecs`, since `mutates: false` on `notify.user` and `ask.user` doesn't mean read-only; a tool in no list counts as destructive, MCP's own default.
- **Cancel:** MCP `notifications/cancelled` reaches the call on the same connection through the internal `tools/cancel`, named by a handle the bridge sends on `tools/call`. A question or card goes away and counts as "no" (L8), and no reply follows, as MCP asks. `AttentionCenter.ask` now ends when its task is cancelled, which a dropped connection also gets.
- **The list:** `listChanged: true`. A session that got an empty list because the app wasn't running looks every 5 s, tells the client once when the tools differ, and stops. A call also checks, at most every 30 s, so a Trust change shows up.
- **Not in this batch: Codex's tool timeout.** `ask_user` may wait 10 minutes, and from memory Codex gives up on a tool after 60 s, so `tool_timeout_sec = 630` in what Connect writes would let a question outlast it. Measuring that default takes a live call, which the founder hasn't said yes to, and a value shipped from memory is a guess presented as a fix. It waits on `team/tools-a4`.
**Why:** a session opened before Sidefolk had no tools until it reconnected, and a client that gave up left a question on the desktop with nobody waiting for the answer.
**Alternatives:** *holding a connection open and pushing*: 8 sessions would fill the app's room, and idle ones are closed for that reason. *A timer while connected*: the same, so the check rides on calls. *`mutates` as the read-only hint*: wrong for the two tools that reach the person. *MCP resources and prompts*: another way to read the person's data, with nothing tools can't do.
**Not verified:** a real Claude Code or Codex session as the client: the tests speak MCP over pipes to a whole Sidefolk. A client that ignores `list_changed` stays as it was; calls work once the app is up.

### D157 — Change a watcher, a reminder or a trashed note in place (2026-11-03)
**Decision:** *amends D116. No new reach for other agents: only what stopping and making again already allowed, on what's theirs.*
- **`watch.update`** takes `title`, `interval_minutes`, `level`, `mode`, `contains`, `not_contains` and `becomes` as well as a live value's display, through `WatcherEngine.edit`, for anyone who may manage the watcher. No `target`: another address is a new watch. Words for another kind are refused rather than ignored. Every limit `add` holds to holds here: the floors, critical only on the person's own, and an agent's watcher never lasts longer; a live value made fast stops as soon as a fast one would.
- **`reminders.update`** (new): `title`, `when`, `notes`, `level`, through `ReminderScheduler.edit`, keeping its id, its note or task and its series. Words written now carry their writer's source (T3). `reminders.snooze` and `reminders.complete` join `saving`, like `reminders.cancel` their own only (`canManage`). `reminders.complete` stays on `completeWithTask`.
- **A reminder is no way round the notes setting:** finishing a reminder finishes its open task (D115), so with "Change notes" not on Allow, an agent is refused and told about `notes_update`.
- **`notes.restore`** (new), in `changing`: by id, with no listing of the Trash; not About you. Reminders come back as D115 says.
**The correction:** dev ideas and the coordinator recalled `watch.update` as always asking. On main it is in `saving`, as D116 reads, and it stays there: an agent changing its own watcher has no more power than stopping and re-creating it, which needs no card.
**Why:** "check every hour instead" meant stop and create, losing the history, and a mistaken `notes_trash` couldn't be undone by whoever made it.
**Not done:** changing `target`; a reminder's repeat can be changed but not taken away by words.

### D158 — Reads by date, and any day of the calendar (2026-11-03)
**Decision:** `notes.list` takes `due_before` and `due_after`, soonest first; `reminders.list` takes `from` and `to`; `agenda.today` takes `day`, that day's reminders and tasks due with no running counts. `DateWindow` reads them: a day with no time means all of it, and a bare "today" counts, which the time parser has no word for since it rolls forward. **`calendar.find`** (new, Sidefolk's own agent only): `from`, `to`, `query`, 90 days at most and 60 events shown, so "what's on Friday" and "when's my dentist" work and events further off can be changed by id. Typed without AI: "list my reminders", "what am I watching", "what's on my plate", "what's due this week" (`IntentListing`), in English like the rest of the parser.
**Why:** `calendar.today` refused "friday", and nothing answered "what's due this week".
**Alternatives:** *the calendar in `agenda.today`*: it would read the calendar without its card, since the agenda is low risk.
**Implications:** the same calendar and card as `calendar.today` (medium, "Reads private data", untrusted), with more in one read; SECURITY's calendar section says so. Other agents get no calendar tool.
**Not done:** "move my stretch reminder to 6pm" with no AI still offers a new reminder with those words; "next week" isn't a word `DateWindow` reads.

### D159 — The `sidefolk` command for scripts (2026-11-03)
**Decision:** *the founder's yes by name.* `sidefolk notify`, `ask`, `remind`, `note`, `tools`, `call <tool> [json]` and `status --json` (`ToolVerbs`). A new door to the same room: each goes to the app as the external client `sidefolk-cli`, through `ExternalToolGateway`, Guard and the audit trail, so `call` reaches exactly what `sidefolk mcp` does, Trust's groups included. A test holds that no `extensions.*` tool, nor files, shell, web, clipboard or calendar, can be reached under either spelling. `ask` exits with the chosen option's place from 0, 10 for no answer; 11 when a tool fails, 69 when Sidefolk isn't running.
**Why:** `make test && sidefolk notify "Tests passed"` and a git hook that asks first shouldn't need an MCP client.
**Alternatives:** *a command per tool*: the four people want have words of their own, and `call` covers the rest.
**Implications:** T4 says so. Any program running as the person could already start `sidefolk mcp`. English like the rest of the command.

### D144 — A scene may say the direction of its own words (2026-11-03)
**Decision:** *amends D99.* A scene can say `"direction": "rtl"` or `"ltr"` (Kit: `direction(rightToLeft:)`). Present, it decides how the scene lays out, on a surface or a page, instead of the app's language; left out, nothing changes. It names no extension.
**Why:** the founder wants Playtime in a language of its own, chosen in Playtime: an English Mac and the word of the day in Arabic. An extension's words were already its own to choose (`Language.use`), but the direction of its scenes followed the app, so Arabic drew left to right on an English app. The reverse already worked, through `"mirror": false`.
**Alternatives:** the extension mirroring its own scene tree (a copy of `SurfaceScene.mirrored()` in a pack, with its animations, areas and drags); reversing only letter rows and leaving the rest (half a language); a per-extension language setting in the app (the app would then have to know every extension's languages, and the choice belongs with what is being played).
**Implications:** the reader takes the keys it knows, so a copy from before this draws such a scene in the app's direction rather than refusing it (tested, and run with Playtime on the debug app from before this); an extension sends the key only when it differs from the app's. The frame stays in the app's language and direction, as do a page's parts outside a scene.

### D130 — Two themes on one calm design: Sidefolk is the new default, Harbor a painted theme of its own (2026-11-03)
**Decision:** *amends D84 and D92.* The founder found the old Harbor cold and its colours off, and approved a rework, then
shaped it through several rounds:
- **Sidefolk, the default:** colours from the app icon and logo (navy ink and action in light, the scarf's turquoise softened
  for action in dark, a dim desaturated midnight), Mochi in a tidy studio in the sidebar, the helpers' places on soft 3D hills on
  Today. Values in `ThemeTokens.sidefolk`, art in `Resources/Themes/sidefolk`.
- **Harbor:** the painted harbor the founder picked, at night in dark and in a pale morning in light, with Mochi on the jetty.
  It has the id `dev.sidefolk.theme.harbor` and lives in `Resources/Themes/harbor`.
- **Calm first, for all-day use:** light is really light and dark really dark; everything follows the appearance setting.
- **The sidebar is plain, with art only in its header:** the founder's idea, in every theme with a header. The theme draws
  the selected row (`sidebarSelected`), solid and 3:1 from the sidebar, which `ThemeCheck` now holds; macOS's blue or grey
  is off (`SidebarHighlightOff`), so it ignores the Mac's accent colour, a deliberate departure from Apple's guidance so
  contrast is known. Arrow keys were checked against a control; real clicks and drag weren't.
- **Today, in every theme:** a scene with the greeting, one decision in view with the rest as one line each under Next up,
  the day as a vertical list with its moves kept (drag, ← →, ⌘Z), On duty as quiet rows, no count pills. `DayRail` and `DayLine`
  are gone. The scene appears on Today only, its sky behind the toolbar on other pages, which are rounded sheets.
- **New optional roles and keys, with stand-ins:** `sidebar*`, `onSidebarSelected`, `sceneInk*`; `material.depth`, `scene`,
  `sceneDark`; `companion.header`, `headerDark`, `logo`. Older themes keep working. A theme without art gets a plain header.
- **Moving:** nothing tells who chose the old `harbor` id and who was given it, so everyone on it moves to Sidefolk once
  (`ThemeSuccession`), with a whisper saying Harbor is still in Settings › Appearance.
- **Logos** now use About's family art.

**Why:** the founder's reasons were UX before looks: "you are a UI UX designer", contrast and accessibility, an everyday tool that
mustn't tire the eyes. An independent pixel audit found what eyes had missed; `sidefolk-theme`'s `LESSONS.md` keeps it all.

**Alternatives:** a recolour of Harbor (the founder asked for real change); a dark sidebar in light mode, a whole-window scene
and a strong midnight blue (too strong, kept in the local sandbox for possible themes); a meadow for the default's sidebar
(pretty, but Sidefolk works beside you).

**The other themes move to the gallery:** the founder chose two built-ins (narrowing D92, which kept them in the app so they'd
work offline). Paper Garden, Night Studio and Marshmallow keep their ids in sidefolk-addons. Whoever wears one keeps it: their
setting stays, and at launch it's fetched by itself while Update add-ons automatically is on, on any channel, since nobody chose
to lose it by hiding snapshots (`ThemeSuccession.toFetch`, `fetchThemeThatMoved`). Until it comes they see the default, each launch
and each add-on look try again, and a whisper says so once. The worn one shows in the gallery on any channel, and any of the three on this Mac keeps updating on any channel, worn or not. The app ships first and the gallery publishes straight after (Add-ons first, D98), so a wearer who updates inside that gap sees the default until the next look after the publish, within six hours. Their `minimum_sidefolk` is the first snapshot without them: a copy that still has them built in doesn't see them as something to get. Snapshot 1075 kept them built in, so the new default didn't wait for the gallery.

**Brand art:** Mochi's solo portrait and full-body image follow the newer design too (masters `rabbit-portrait.png`, `mascot-mochi.png`; the old ones in `Brand/archive/mochi-2026-10/`). The app icon stays as approved.

**The live 3D Mochi follows it, with the same model and rig:** deep navy ear tips, a deeper scarf, bigger darker eyes with quieter reflections, and an open smile at rest (`face.moods`, for Mochi only). Its portrait and avatar are redone. Its build stays slimmer than the art, since that would need a new model. The 2D Mochi stays the flat drawn style.

**Today's keys (added 2026-11-03):** the queue's rows take the keyboard when clicked, with macOS keyboard navigation on or off (`.focusable(interactions: .edit)`): before, their keys reached nothing with it off, which is the default. That would make key answers reachable after a click, and another agent's question has Yes as its main answer (an independent read found this), so on Today no key says yes: not an approval, a question, a reminder's Done or a skipped step. Those take a click on the button. Keys move and snooze, Delete says no once the row has been in view for 800 ms, and Return opens a waiting session. Next up's hint says only what works. **Alternatives:** ⌘Return as the approval key (never run on a real approval, and a steady press could answer several); a hint for keys that do nothing. **Known:** the row with the keyboard shows no highlight, and the keyboard may not stay in the queue after an answer.

**Colours a theme leaves out (added 2026-11-03):** nobody is refused over a role they never wrote. A stand-in that wouldn't read gives way to one that does: the sidebar's inks take the surface when its ink doesn't read on a sidebar the theme did write, and a pale accent moves toward the ink until the selected row stands 3:1 with a readable label. Stand-ins go per appearance, so a role written for only one keeps it. If a stand-in still fails, the words name the role to write. A required colour left out comes from the default, which can change under a theme, so on a copy Sidefolk keeps that failure is a warning: the theme stays rather than going to the default with no word. **Alternatives:** a whisper saying the theme was dropped (the person loses a theme that worked yesterday, for a colour they never chose); keeping Harbor's old colours as the fill (a palette kept only for this).

### D138 — The companion can stay off full-screen apps, and the person chooses how it reaches them there (2026-11-03)

**Decision:** a setting in Settings › Companion, also set by asking the companion (`sidefolk.look`), off by default so nobody sees a change: "Hide over full-screen apps". On, the companion and its words go invisible while the frontmost app is full screen, stay on ordinary desktops and over ordinary windows as today, and come back by themselves. Dropping `.fullScreenAuxiliary` was tried first and measured not to work: the panel stays on a full-screen space all the same. Ask, the menu bar, palettes and extensions' surfaces are opened on purpose and are unchanged.
**When something needs them there,** cards, agents' approvals and questions go the way they chose (`FullScreenNotice`):
- **A notification from the menu bar** (the default, the least in the way that still reaches them): `SystemNotifier`, Sidefolk's own notifications. Clicking one for an approval opens its slip there. If the Mac's notifications are off for Sidefolk, it reaches them as the third choice does.
- **The companion comes, then goes back:** it joins that space with the card or slip, and leaves once it's answered, or after 30 seconds with nothing done and the pointer elsewhere. Left alone, a card folds into the count and a slip keeps waiting.
- **Nothing until I leave:** no popup; what waits shows when they leave, and the count on the menu bar has it meanwhile.
Whispers wait in all three: they need nothing, so they aren't worth interrupting a full-screen app. Critical alerts stay a notification, as today. An ordinary settings key, no migration.
**Why:** the founder chose this reading, over "behind every window" (which would also cover Chrome in a normal window, and can still be added as a third choice), and asked for all three ways of being reached.
**Whether it's full screen** uses the existing `Fullscreen.isFrontmostFullscreen`: a window of the frontmost app covering a whole screen. Something can wait for a maximised window that isn't really full screen; it shows on the next space change.
**Verification status:** see HISTORY. Measured on a real full-screen space: off, the panel stays as before; on, it's gone over the full-screen app and back after leaving it. Not measured: the visit, the notification and a real click.

### D110 — An extension may use Sidefolk's tools through Guard, and the person may read a plan once (2026-11-03)
**Decision:** `permissions.act` `{purpose}`. The notices `sidefolk/tools.list`, `tools.check` and `tools.call` (answered by `tools.listed`, `tools.checked`, `tools.result`) run through `ExtensionActionGateway`, built like other agents' gateway (T4): its own `ToolExecutor` over a closed registry of facades, caller `.extension(id)`, one card at a time per extension. A call asks every time and never offers "Always". `sidefolk/plan.approve` shows a card with what a plan will do, in full, in the host's words; after a yes, a call that fits the plan needs no card and History says `plan`. Other extensions could use this for a nightly export, a focus ritual, a weekly report: anything that repeats while nobody is at the Mac.
- **Why not more grants.** "Always allow" names a tool, and a tool can do anything its arguments say. A plan names the exact call. The person reads what happens, not what could.
- **What a plan may leave open.** Written values only, plus filled-in words in a closed host table (`ExtensionActionPolicy.fillable`): `notes.save`'s `text`, `reminders.create`'s `title`, `notify.user`'s `title` and `body`, `ask.user`'s `question`. Those stay inside Sidefolk and are shown as the extension's. Anything parsed as a time or a selector, a tool of another extension, or anything that could carry words off the Mac keeps its card each run. The security review's finding decided this: "the plan is deterministic, so outside text is safe" isn't sound, because determinism fixes the tool, not what a tool does with its text (T44).
- **Who gets plans.** Only an extension that can't reach out by itself (no `network`, `media`, `exec`, write folders, clipboard, screen or UDP; `media` because the certificate service it needs can fetch from an address). What a plan's reads return goes to the program, so from there it must be able to reach only what the person read. An extension with `act` and the network still works, on a card each time, and the sheet warns.
- **When a card may start.** `plan.approve` is taken only within 30 seconds of the person's click or command to that extension, or a clean turn of Sidefolk's own agent: never from a timer, a steered model or another agent (T3).
- **What holds whatever a plan says.** Turned-off capabilities, folder boundaries, "Ask every time", "ask each time" for the internet, high risk, a changed tool (`definition`), a call whose scope moved (`reach`), and a per-plan daily budget. A plan's owner is its pack's permissions and origin: a copy under the same id that isn't the same has no plans.
- **Closed list.** Named built-ins, plus other sandboxed extensions' tools the model may use. Never an MCP server's (they run unsandboxed, T16), memory, skills, extensions' settings, command watchers or anything with `.shell`. Sidefolk says what only reads (`reads_only`): its own tools and its signed extensions'; another author's `mutates: false` isn't taken (D71), since a practice run and a retry rest on it, and notices aren't reads.
- **Ends:** a plan ends with `ttl`, by Settings › Add-ons (`extensions.plan_end`, the person's click only), by `plan.forget`, or with the extension. Its program hears `plan.ended`.
- **Decision record for reviewers:** the first design let every standing call through while tainted and tracked taint per run; both went after the review, because a run id is the program's to change. Medium and up are evaluated as tainted instead, as for other agents.

### D111 — A watch an extension made tells it, not the person (2026-11-03)
**Decision:** a watch whose `source` is `extension:<id>` publishes `AppEvent.watchFired`, and the host sends that extension `sidefolk/watch.fired {watch, title, summary}` in place of the notice. It tells the person in its own way, and the watch still shows in On duty, as its source. No manifest key: an extension gets such a watch only through `watch.create` under `permissions.act`, so only on a card or a plan the person read. Only its own: no other watch, no reminders or agent sessions. A first design had `permissions.events` for those; the review showed their titles and folders would leak without a card, and no one needs it yet. Others could use this for a stats page counting downtime, or a log of what changed.

### D112 — A tool may be offered to other agents, always on a card (2026-11-03)
**Decision:** `tools.<name>.agents: true` puts a sandboxed extension's tool in `ExternalToolGateway`, under one new person's group, Settings › Trust › What other agents may do › "Use tools extensions offer them": Ask each time (the default) or Off. There is no Allow: Sidefolk can't tell what such a tool does, so it is raised to at least medium and, as for every external call, asked each time and never "Always" (T1, T4). An MCP server's tool can't opt in. Extending the closed list this way keeps T4: nothing reaches an agent unless an author marked it and the person answers each call. A plan can't be started from such a call (D110). Others: a project tracker's "add a task", a note-taker's "file this".

### D113 — Three page parts: a rail of steps, a value edited in place, several of a few options (2026-11-03)
**Decision:** generic parts, nothing about any product. `steps`: a line threading through rows with a state (`done running waiting failed skipped pending`), a result word, a badge, a depth up to 2, folded output, and hooks to the program's own tools for select, reorder (drag, menu, VoiceOver actions: three ways to one move, among a row's own only) and insert. `field` with `id`: shows `value`, commits on Return or on leaving it, no button; `kind` `text multiline time number`, `tokens` are chips that put a value at the caret, up to 8,000 characters (a plain field keeps 500). `choice` with `multiple` and `selected_all`: the tool gets the set. Older copies skip `steps` and draw the others as before. Others: a recipe, a release checklist, a build pipeline, a day's timeline; a template field with merge values; weekday or tag picks.
- **Why a native part, not a scene.** A page's scene takes no keys. A rail is the screen's main control: it has to be reached by keyboard and read by VoiceOver.
- **Not added:** routes and page state, which D105 already gives.

### D114 — Sideflow: teach your companion a routine, an extension and nothing but (2026-11-03)
**Decision:** Sideflow is an ordinary gallery extension (`sidefolk-addons/extensions/sideflow`, `dev.sidefolk.sideflow`). Its model, engine, journal, templates, words, icon and screens are all there; the app knows nothing of it and has no check of its id. It uses D105 (state), D110 to D113, AI help (D100) and background work (D63). Product and design notes: `extensions/sideflow/design/DESIGN.md` in that repository.
- **A flow is something you could read aloud.** A rail of sentences, not a node canvas. Triggers: by hand or by name, a schedule, a watch. Steps: any tool, write with AI, ask me, compose text, if, wait (a day at most). Left out on purpose for now: loops, parallel steps, flows calling flows, drops, connectors with accounts.
- **Three honest states.** Draft: nothing runs. Practice run: reads what Sidefolk vouches for, changes nothing, says what the rest would do. On: runs under a plan the person read. An edit to an On flow stays a draft until applied: what runs is what they allowed.
- **Recovery.** A write-ahead journal: a step's start is on disk before its call. After a stop a read or a question goes again; a step that changes things is never repeated by itself, and the person says whether it happened. Waits are instants on disk. A card nobody answered parks the run as "Needs you".
- **Same product by talking.** Tools for the companion and for connected agents, no-AI sentences for the common shapes, one saved state. Agents write drafts; only the person's click or request starts a card.

### D125 — A tree of cards that arranges itself (2026-11-03)
**Decision:** a page part, `tree`: cards one under another, branches that split and join again, each card with a kind, a sentence, a soft tile, a state (`none pending active done skipped attention`) and a pill; hooks to the program's own tools for select, insert and reorder; a searchable `picker` opened from its + buttons; small floating `tools`; a line in one or two colours. Sidefolk lays it out and draws it, with zoom, a small map, keyboard and VoiceOver. `Card.tree` draws one small at a card's foot, `Card.press` makes the whole card a button, and a tool's reply may carry one for its card in Ask (`tree` in its asks, `ToolReply.showing(tree:)`), which then stays as something made does under D136: two minutes, or ten from a first look. Field `tokens` are drawn as chips inline, the text staying as it was written.
- **Why (founder, 2026-11-03):** the founder rejected Sideflow's first look ("very simple, very ugly, not clear") and approved a builder like this from a reference, in Sideflow's own colours. It reverses "no canvas" in D114: nothing is dragged about, so nothing can get messy, and branches read at a glance as a rail's indented rows didn't.
- **For any extension:** a decision, a recipe with a choice, an onboarding, a pipeline. It holds no meaning of its own.
- **Ported, not invented:** how branches are measured and spaced comes from Activepieces (MIT), named in `TreeLayout` and in THIRD_PARTY_NOTICES.md. Nothing of its name, logo or code beyond that.

### D126 — A page may take the window (2026-11-03)
**Decision:** `workspace` on a bare page: `side` sections go in a column of places at the start, `trailing` ones in a column at the end, each scrolling on its own, and a tree in the middle fills what's left; Home's sidebar folds while it shows and comes back as the person had it, and the toolbar's button still opens it. Narrower, the places go first and then the end column sits under the middle. New parts for it, any page may use them: `bar` (a compact head: the way back, title, state, a sentence, actions, a ⋯ menu), `nav` (places, with the extension's own icon and name at the head if it asks), `notice` (what a person will receive, drawn as it arrives), `ticks` (recent results, each a mark and its word), and `companion` (the person's own companion at the page's corner, and beside what's active on a tree; the extension never reads it).
- **`accent` (the founder, 2026-11-03: flat, "different colors from the shade for different purposes"):** one or two flat colours on a page: the first fills its main button and switches, the last marks what's selected. Without it, the theme's. `dress.accent` wins, and a dressed page's selections keep their look. Sideflow's are `#6E4BF2` and `#2A6FE8`, from its icon. A tree's line keeps its two colours, the page's only gradient: the founder's choice, asked directly.
- **Why general:** D98. Sidefolk draws all of it from data; an extension still says what's true, never how it looks. The Say bar and the toolbar stay Sidefolk's.

### D127 — A flow can reach every tool (2026-11-03)
*Amended by D189: in a signed extension's plan a server's tool may stand, named, with its program checked, within limits; everything else here holds.*
**Decision (the founder's, 2026-11-03: "Both, always on a card"):** `ExtensionActionPolicy` offers every other extension's tools, those kept from the model and high-risk ones too, and every MCP server's, and the named list of Sidefolk's own grows to nearly all of them. What runs outside a sandbox or can run anything (MCP servers, an extension with `.shell`) is high risk for this caller: a card every single time, never in a plan, never "Always". Still not reachable: `extensions.*`, `skills.*`, `profile.*`, an extension's own tools.
- **Why:** the founder: a flow should be able to use "every single thing that app can do" and any extension. An audit found flows reached 28 of about 67 built-ins.
- **Reverses:** the part of D110 and T44 that left MCP servers and can-run-anything out altogether. **Doesn't touch:** contained-only plans, folders, switched-off capabilities, Ask every time.
- **With it, `attention.set`:** Open, Focus or Quiet from a tool, always with an end, 1 to 1440 minutes, so nothing stays silenced by a job that forgot. Medium, for the companion and for extensions. A plan may hold it, written out in full (the founder, 2026-11-03: asked "Should a turned-on flow be able to set Focus or Quiet without asking each time?", "yes"), so the person reads it once on the card and it then runs by itself. Exactly that: Open, Focus or Quiet, with an end of at most a day. Per-source interrupt levels (D88) and quiet hours have no tool and aren't in this; they could silence a source indefinitely, and the founder wasn't asked.
- **What a plan's step filled in stays out of History.** Asked "When a flow fills found note text into a later step, what should History save for that step?", shown that History would otherwise keep the words on this Mac, with secrets hidden, and in any export: "Step as written". A call on a plan with slots logs its summary and arguments from the template and "length N" as its outcome; a failure says only that it failed. The flow's own Runs tab still shows the words: they are in its data folder and go with it. Found by running it for real: a notice's own row in History showed the words too, so a notice or question a step filled in now reads "<extension>: a notice" there (`AttentionItem.historyTitle`), and shows in full on the desktop and in Today. A run from a draft has no plan, so its program says what it filled in (`written` on `tools.call`), and Sidefolk checks that fits. A reminder a flow filled in fires with its own title, and History shows it: asked "Should History show the title when a reminder a flow filled in fires?", told note text could land there: "Show its title".
- **Plans' closed table grows by two:** `notes.search`'s `query` (asked "Should a turned-on flow be able to search your notes unattended, using words filled in when it runs?": "Yes, unattended", shown that a steered flow could pull a note's content and pass it on) and `voice.say`'s `text`.
- **"More from a flow" (the founder's pick):** `voice.say` (aloud, with an extension's name, not in Focus or Quiet) and `appearance.set` (light or dark, a theme, a companion that's there). They named no other settings, so nothing about trust, connections, the AI or add-ons has a tool.
- **What "everything" honestly means:** reachable. Unattended only for what the person read exactly; run-time values that pick a target, deletion, MCP and shell ask each time.

### D128 — A flow may hand the companion a whole job (2026-11-03)
**Decision (the founder's, 2026-11-03: "using my normal trust settings"):** `companion.job`, a tool never offered to the model. It runs a turn of Sidefolk's own agent, in a conversation of its own, as `Caller.agent`: each tool it uses passes Guard under the person's mode, as anything they typed would, and shows in History. A plan may let a job written out in full stand; words filled in at run time ask each time, because they would steer the model.
- **Risk the founder took:** in Auto or Full access a job can finish alone, and what it reads can steer it within what those modes allow. Taint holds as in any turn. A job may use MCP servers and what runs programs (asked "should the job be able to use MCP servers and shell commands?": "Yes, under my trust settings", shown that text it reads could steer it into running commands with no card).

### D129 — An extension may hear what happens (2026-11-03)
**Decision (the founder's, 2026-11-03: "Yes, with titles too"):** `permissions.events` `{purpose}`, on the install sheet with a caution. A running program hears `sidefolk/happened {name, at, title?, detail?}` for `reminder.fired`, `reminder.created`, `note.saved`, `calendar.starting` (five minutes before), `companion.finished`, `agent.finished`, `attention.changed`, `mac.woke`. No card each time.
- **Revisits D111**, which left this out because titles would leak without a card. The founder chose titles. Every extension with the permission hears the words, whatever else it can reach (the founder, asked "Extensions that can reach the internet: should they hear reminder and meeting titles too?": "Yes, titles for all", shown that they could be sent off the Mac without a card). The install sheet says so. Gaining a reach re-asks at update, as any widening does.
- **Not counted:** what an extension itself did, so a flow can't set itself off through its own note.

### D140 — Sidefolk saves an extension's result beside the file the person handed over (2026-11-03)
**Decision:** a tool may declare `outputs`, the file endings it makes. Its program writes in its own data folder and names what it made in its reply (`sidefolk.outputs`, Kit: `ToolReply.saving(data:as:beside:)`). Sidefolk, not the sandbox, then moves the file beside the source. The sandbox gains no rule and never opens the person's folder for writing. Rules, all enforced by `ExtensionOutputs`, most of them the coordinator's:
- Only beside a file the person dropped or picked for this very call (`ToolContext.handedOver`, set only by Sidefolk's own code, never from input, and gone on a retry or in a plan). Never a system, protected or hidden folder.
- The data file: a regular file with one hard link, reached by walking down from the data folder with no link followed anywhere. Reading elsewhere through Sidefolk's own privileges is the main risk.
- The name: bare, no path parts, no leading dot, no invisible or direction characters, at most 200 bytes, and starting with the source's whole name, followed by a space or a dot (so "trip small.jpg", never `CLAUDE.md`).
- The ending: declared by the tool and on Sidefolk's own list, which holds nothing that runs. A manifest can't widen it.
- At most 32 GB a file, 64 GB and 64 files a call. Never overwrites: placing is an exclusive rename, and a name in use gets a number.
- The saved file is `0644`, loses the program's attributes and carries macOS's quarantine mark.
- Each placement is its own row in History, and the install sheet says so.

**Why:** the founder wants results beside the original, without a folder grant. A sandbox rule to create files in a folder could let a program change other files there, whereas this leaves a converter unable to touch that folder at all.

**Alternatives:** a write grant on the parent folder (wider than the job, and prompts); a sandbox grant of one new path (only some rules could express it, and the program would choose the moment); saving only in the data folder (the person would have to fetch it).

**Reviewed:** an independent security review found a critical hole in the first version: a data folder swapped for a link let a program have `~/.ssh` saved as a photo. It also found an older hole of the same kind in the data folder's own profile. Both are fixed, with tests, along with its other findings. A second round found one medium race (a folder swapped during a save) and four small issues, also fixed (SECURITY T45).

**Implications:** placing runs after the call, off the host's actor, so a file that appears always has its row. `outputs` raises the risk floor to medium. Output is written twice when the destination is on another disk. Conversion needs room on the home disk. Open, Show and Undo come later (D142) and build on `PlacedFile`, which records what was placed. The source still needs a `"read"` parameter in `paths`. SECURITY T45.

### D141 — A dropped file is the person's own act: one call's read, several files at once, and the card is the yes (2026-11-03)
**Decision:** the founder's, for all file drops ("All drops"), against the reviewers' recommendation of the new kind only. No shipped or planned extension declares a file drop today, so the exposure is local third-party ones and future ones. An offer with `kinds: ["file"]` runs its tool as `Caller.user`, with `pickedFiles` set only by Sidefolk's drag code. New: `tools.<name>.file_lists` (one read-only list parameter, at most 64 regular files, each granted by itself), `{values}` in a drop's input, and a drop's `menu` (at most 12 choices of at most 30 characters, on the same card, since the read ends with the call). Link, text and folder drops are unchanged; a folder in a drag means no offers.

**The card:** Noor's conditions. Sidefolk's own words come first and name who reads what and whether it could leave the Mac. The extension's offers sit apart under its name. Exact count and every name reachable. Nothing pre-selected, Return doesn't choose, clicks ignored for 400 ms. Sidefolk's own choices stay, smaller.

**Why:** dropping a file is the person's explicit act on that file, and today's alternative for an unshared file is a card offering the whole folder. A list, not a higher cap on `paths`, because that cap counts parameters of one string each, and Sideflow's flows already go through `scope(for:)`, so each listed file gets Guard's normal check.

**Alternatives:** the new kind only, leaving `{value}` drops as they were (the reviewers' choice); a higher `paths` cap; a second step for more choices (it would have no read).

**Reviewed:** an independent security round found the card's internet claim false for one system service, which moved behind `network` as its own sandbox hardening. HEIC and AVIF can't be written without that service, so `media` keeps it too (the founder's call, 2026-11-03): an extension with `media` can't claim the internet is closed, and its card says instead that other things it's allowed to use could carry the file out. With none of those ways, the card says "It can't go online by itself" (the founder's wording, 2026-11-03): "by itself" because two extensions working together can still pass data along (SECURITY). The card also counts `ai` and `place` as ways out. It found a file's name could reach the AI as the person's words after a refusal, so a drop's refusal now stops there. Menu items and page controls no longer carry paths (they could read in a shared folder with no card). The click guard re-arms on a new drop and covers keyboard and VoiceOver, an extension's name can't hold a line break, and a handed-over path must be a regular file on both routes.

**Implications:** `ExtensionCommandCall.handedOver`, set only here. `ToolExecutor.execute` gains an additive `pickedFiles`, leaving Noor's `pickedFile` as it is. A list in a plan asks on a card unless it's exactly what the person read, since a list only matches byte for byte; either way it reaches only shared folders. The cap on list values in History's arguments rises from 20 to 64 **for every tool**, so that a drop's files all show. SECURITY T12, T43.

### D143 — Sound files under `media` (2026-11-03)

Converting a sound in the sandbox failed: writing AAC gave `fmt?`, and 24-bit WAV raised an exception (16-bit WAV doesn't need this). Core Audio finds its codecs through `com.apple.audio.AudioComponentRegistrar`, so `media` now opens that one service too, and its install line names sound ("Can use the Mac's media tools for pictures and sound"). Measured with a sound program under the media rules with and without the service, and with every format through the real host. An independent review ran: no sound or device access comes with it, a component one process registers stays invisible to another, and the registrar opened no sockets. A second review found it adds one small reach: a `media` extension can list the audio components installed on the Mac (134 in the test, one not Apple's). With trustd also under `media`, the certificate fetch happens with or without the registrar, so the registrar adds no way out. Out-of-process units are refused. Not tested: a real third-party or AUv3 unit loading. The reviews ran without the built gallery, so their shipped-extension sandbox tests didn't run; the full suite against a built gallery covers those. The rule matches by name, so `media` also reaches the root instance of this service. Existing installs get the rule with no new question, since it's a host rule under a permission they already hold. Video stays a separate decision: it would add the encoder service to `media`, where only `screen` has it now.

### D142 — Open, Show in Finder and Undo on a file Sidefolk saved (2026-11-03)
**Decision:** a result that saved files (D140) gets Sidefolk's own card: its title and sizes measured from the real files, not the extension's words, and three actions. The founder's words on Open and Show, asked "May Sidefolk open and show files that an extension just created?": "Allow both". Sidefolk draws them, they run only on the person's click, only on a file Sidefolk placed itself, and an extension can't ask for them, so D63 otherwise stands.
- **Open** is drawn only for images, audio, video, PDF, plain text and CSV, and only if the contents fit: not a program or script, and the right start for formats that have one. Anything else gets Show in Finder alone.
- **Show in Finder** only reveals the file.
- **Undo** moves the file to the Trash through the undo path every tool uses, so History offers it too. It acts only on what is still exactly what was placed (same device, inode, size and time). A file changed since stays, and the card says so. The original is never touched.

**Why:** the person wants the new file at once, and an extension must not be able to launch things.

**Alternatives:** Show only (safer, one more step; the founder chose both); letting extensions ask for Open (D63 keeps that closed).

**Implications:** `ResultCard.files` holds `PlacedFile`s and is saved with the conversation, so an old card re-checks identity at each click. A page's `file` action shows a save that failed. Dragging the file out of the card comes with D150's card. SECURITY T45.

### D150 — A file's card is frosted from its own picture (2026-11-03)

The founder approved the look ("your file sets the colour") and chose to wait for it before Formatic reaches the gallery: the plain cards didn't match its icon ("the book cover looks very nice, but when you open it's very different").

**Decided:** for any extension's file offers, working card and saved-file card, Sidefolk draws a frost from the person's file. It's general, and the app names no extension.

- **One picture per card, at thumbnail size.** The frost is only the background. Everything on it is white or neutral, never sampled from the picture, because the founder stopped a version that put the picture everywhere.
- **Measured, not judged.** A picture counts only if it still has colour once blurred and under its scrim (average chroma at least 0.10 as shown), because an audit found stripes and pale tints passing a test made before the scrim and turning to grey on the card. The scrim is the least that keeps white text at 5.6:1 on the blur's brightest part (`FrostMeasure`).
- **A file with no picture, or none with enough colour,** gets a frost from the extension's mark, never from its icon: reviews showed a few kilobytes of PDF can keep whoever draws them busy for minutes, and validating a PDF's cost didn't hold up. With no mark, a plain dark ground. With no picture at all, the small mark its manifest names (`mark`) stands in, inside the frame. With neither, a plain dark ground and an empty sheet.
- **The picture comes from the system's thumbnail service, out of process,** and the card waits at most two seconds for it before using the fallback above. It's in Sidefolk's memory only for the card's life and never reaches the extension. The service keeps its own cache, as it does for Finder. Only a regular file Guard wouldn't keep private is drawn, and files another app sent through the Service, with no click behind them, get no picture.
- **What Sidefolk says stays outside the frame:** the trust line, file names and counts, in Sidefolk's own type and colours. The frame carries only the extension's name and words. Open, Show and Undo are Sidefolk's own buttons. A pack picture appears only as a small mark inside the frame or beside the extension's name, never on Sidefolk's ground. A dull photo keeps its place on the sheet, on a frost from the mark, since showing a picture and frosting with it are two questions.
- **New manifest keys on a drop:** `tag` (a format's name from a fixed list, so it can't say anything else and needs no translation) and `mark` (a picture in its pack, read through the same checks as any pack picture).
- One file can be dragged off its saved-file card.

**Security:** T46.

**Not built:** the approved "Stop" on the working card. It would have to really stop the call, which hasn't been shown, so it isn't there. The bar doesn't claim progress: it moves without saying how far.

### D151 — Send to Sidefolk from Finder (2026-11-03)
**Decision:** a macOS Service, "Send to Sidefolk", in Finder's right-click menu for files. macOS hands the selected files to Sidefolk as a drag does, and they arrive on the same drop card with the same grant (D141). The person can give it a keyboard shortcut in System Settings. It needs no permission of its own.

**Why:** the founder asked for an easier way in than dragging, in the spirit of Filee's. This is the smallest one, and it doesn't watch anything.

**Alternatives:** a global shortcut that asks Finder for its selection (needs Automation permission); the ring (D152).

**Implications:** any app can send files this way, and unlike a drag it needs no click. So nothing runs until the person chooses on the card, it doesn't take the keyboard, and it leaves alone what the person is in the middle of (SECURITY T43). Service names aren't translated yet.


### D152 — The ring of what a file can become (2026-11-04)
**Decision:** *the founder's words on snapshot 1177, "now there is no ring", read by the coordinator as the go, within what they approved on 2026-11-03: dark glass, a vivid slice, at least 8 choices, its shortcuts on the page.* Holding a key with the pointer at rest during a file drag, or ⌃⌥F with files selected in Finder, opens a ring at the pointer: the offers extensions make for those files, then their menus' choices, taking turns between extensions, at most two sets of eight, with the file in the middle and Sidefolk's own line under it. Letting go on a slice, or clicking one, runs that choice as the card's does: the same read of exactly those files for that one call (D141), the same working card and saved-file card. The middle and the outside choose nothing. Off until the person turns it on, on any page that places Sidefolk's `file_ways` part.
- **General:** it draws any extension's offers from their manifests and names none. The manifest gains `menu_title`, and a menu choice's `tag`, `detail` and `skip` (names it's pointless for, like the format the file already is); an extension may declare 20 offers, up from 6, and the card still shows three.
- **What it watches:** the ring watches nothing while it's off. On, only a pressed left button starts ten looks a second, ended by its release: at the drag's change count, which says nothing of what's dragged, and the modifier state any app can see. It reads the file list only once the key is held. So it needs neither Accessibility nor Input Monitoring. Separately, the companion notes the same change count on every press, whatever the ring's switch says, so all of its corner can take something dragged.
- **It takes a deliberate hand (the independent review's first finding):** ⌥ is also how Finder copies, so a copy on its way somewhere mustn't run anything. The ring opens only with the pointer still for a third of a second. Where the pointer already is chooses nothing, even when the ring had to shift at a screen's edge: it must move onto a slice and rest there a moment, and the first 0.4 s don't count (`RingAim`). A slice lights, and the cursor changes, only when a release would count. Letting go of the key off any slice closes it, and the drag goes on to what's under it. A drag nothing can use meets no ring at all. It never answers a drop as a move: a source may delete its copy on that.
- **Several files:** the middle shows the first name and how many more, and over the middle every name, one to a line. Past five, or with a name too wide for its line by its measured width, the ring leaves them to the card, which shows them all (D141). During a drag it says to use the companion, in words a drop passes through.
- **What's different from the proposal (RING.md):** Tab can't turn the ring during a drag, since reading keys from another app needs Accessibility. ⇧ does, and the scroll wheel may (not tried during a real drag); Tab and the scroll wheel do when the shortcut opened it. ⇧ is therefore not offered as the ring's key. The shortcut has no key until the ring is first turned on, and macOS's own or Sidefolk's keys, palettes' too, turn it off with a line saying so. Setting keys makes the shortcut library unregister them whichever name held them too, so after any change each of Sidefolk's shortcuts takes its own again. The shortcut asks Finder for its selection only with Finder in front, by Apple Events from a child process (`FinderSelection`), which macOS asks about once: a Service can't be given ⌃⌥F, and a press with another app in front shouldn't act on a selection left behind earlier.
- **A drop must be what the ring showed:** a different list from the one it read when it opened closes it and runs nothing.
- **The slice's colour** is the file's own hue, strong and dark enough for white words at 4.5:1 (`FrostMeasure.vivid`), a coral when it has none. The frost tints only the glass under it (D150): everything else on it is white and neutral.
- **Also from the founder's report:** the page's Choose a file can open the real card (`drop_card`, an act on any button). The whole of the companion's corner takes a file during a drag, not just its outline. A failed choice brings the card back, unless the person has moved on. The working card has a Stop that ends the process doing that work, matched by its files, the newest if they went twice, so no result reaches the person's folder, and the extension's page and other work go on; if the work had already finished, its result shows. A file with no picture shows macOS's icon for its type on the card. The plain card, when nothing installed offers anything for a file, says extensions can add more and links to the Gallery, naming none.
**Why:** the founder asked for "a shortcut or a panel, perhaps a circle, so that you just do this or that", approved this one, and found its absence the first thing wrong.
**Alternatives:** *a global key monitor for Tab:* needs Accessibility, for one key. *Reading the drag from the start, to open at once:* reads what's being dragged in every drag for nothing. *A Service for the shortcut:* macOS doesn't promise the key, and it can't be ⌃⌥F by default.
**Implications:** SECURITY T49. Not on by default. The ring can't be reached by VoiceOver during a drag: the card and Send to Sidefolk stay the complete way to do everything. A test run never watches, and a test's ring opens off every screen (`SIDEFOLK_QUIET_WINDOWS`, `ring:` commands): an early version opened under the founder's pointer and took two clicks.

### D170 — A page composed like an app's screen (2026-11-03)
**Decision:** general abilities, none naming an extension: sections as cards, side by side by weight or joined in one card, with controls at their title's end; a branded head with a state and "updated" with a refresh; `metric`, `heading`, `preview`; a `plain` hero with a `ring` and `chips`; `bar`, `menu` and `pills` choices; selectable, scrolling list rows with arrow keys; a search field; heads-ups and host controls placed by the page; `palette` and `refresh` acts; an installed app's icon as a picture (docs/EXTENSIONS.md). The founder's approved homepages for Miraya, Clipboard, Your Mac and Keep Awake are built in their extensions on these, in sidefolk-addons.
- **Why not screens in the app:** the hand-off for those designs pointed at a file routing pages by extension id, from a checkout 369 commits behind. D98 rules that out and its guard test fails on it. Everything here passes the three questions in the `sidefolk-extension` skill, and the pages can change with a pack update alone.
- **Reverses part of D108:** a `dress.accent` too light for white was left out; two approved dark palettes (violet, amber, periwinkle) need it, so it now holds near-black words, chosen by the same 4.5:1 line. Text and controls otherwise stay the theme's, so these pages' ink is the person's theme's, not the mockups' near-black: asked by D108, not changed here.
- **What the independent review changed:** a whole row's `press` may only `go`, since the arrow keys fire it with no words on screen. `shape: "icon"` holds only a tool or `go`, and a switch can't carry `palette` or `refresh`. `{"app": path}` reads only where apps are installed, off the main thread, after following links, and only a real application. `accent` and `selected` must hold white or show at 3:1, and `well` must be readable. A page can put heads-ups first but not hide one that's on. A hidden copy can't be pinned: a pin would have kept it past its two minutes, in the palette too.
- **Also:** a bare page doesn't draw its summary, so its summary's button no longer takes the page's one primary (D74). New tools `pin_copy` and `delete_copy` give the page what the palette could already do, on the same history, kept from the model.

### D160 — Widening what agents can do, one step at a time (2026-11-03)
**Decision:** *the founder's "all" on the audit's group B. Reverses D42 in two places and amends T4; each step has its own commit and SECURITY entry.*
- **Agents can list collections.** `collections.list`, the companion's tool, joins `reading`: names and counts, so a card by default, and for them never About you. Three tools needed names they couldn't get.
- **Agents can make a collection, on a card every time.** `collections.create` joins `alwaysAsks`. *Reverses D42's "never":* the fear was a hostile repo adding "URGENT" beside the person's own, and a card answers it, as D117 did for renaming. The name is recorded as the agent's (T3). `notes.save` still never makes one: only a call that went through the card can (`ToolContext.personWasAsked`). What can't be seen goes before the card and before the check against About you and the Inbox, and a rename's card says the new name. Letters from another script that look the same aren't caught: the card shows them as they are.
- **Agents' watches can run longer.** `until` on `watch.create`, up to 7 days, said when it's made. *Amends T4's 24 hours.* It's in the external spec only, so the spec a standing plan fits is unchanged. The room (D116) and the floors don't move, a live value keeps its own ends, and changing a watcher never lengthens it. **The week is for one start:** resuming gives another day, as it did, and an agent could always make a new one; capping resume would only look like a limit, so what bounds an agent is its room and the floors.
- **Agents can change the person's reminders, on a card every time.** `reminders.cancel`, `complete`, `snooze` and `update` on one that isn't theirs. *Reverses D42's "only its own".* The card names the reminder and the one change it asks about, short enough to show whole and with no line limit (`ReachesOthersRecords`); what runs is what it showed, a time settled when asked and words as they read; only the person changes how it repeats. An important one isn't touched at all: no card asks to end, move or reword what the person said breaks through Quiet, and finishing a task that has one is refused, through the agent's own reminder too (T24). `notes_update` and `notes_trash` are held the same way (below). A yes is for that call and doesn't make it theirs: new words are marked as outside words but not the agent's own, so that reminder then fires as an ordinary one. With "Change notes" Off it's refused. Only the whole id reaches one, and what's wrong with the words is said first, so nothing can be probed, and a yes doesn't read out its title.
- **`ToolContext.personWasAsked`** is what opens these and `collections.create`. `ToolExecutor` sets it from what happened: this call's own card, answered yes, for another agent. `ExternalFacade` keeps it only where that card asked about this. Sideflow found the first version set it in the facade, which its flows also go through.
- **The companion can read History and see agents' sessions.** `history.recent` and `agents.sessions`, for Sidefolk's own AI only, on a card, as outside content. *Found in review:* a row's summary can quote what a tool was given, and History never meant it for a model, so a copied text or a command would have reached the AI provider. Summaries are quoted only for a list of tools, for calls that worked, with secrets out and only words shaped like plain words kept; the rest say which tool ran, and a notice from a command, a watch, a session or an extension is told by its kind. A self-chosen client name reads as calling itself that. An agent's notice and question titles stay in: "what did it tell me" is the point, and SECURITY says what that leaves.
- **An important reminder holds its note too (decided with the coordinator on the founder's standing instruction, 2026-11-03).** Another agent's `notes.update` marking a task done, and `notes.trash`, refuse when that would end an important reminder on that note, as `reminders.complete` does, on Allow with no card and on Ask after a yes; so does `notes.update` changing the note's title, while any important reminder is tied to it, even an ended one, since a reminder that carries its note's title follows a rename and comes back when the task reopens (D49). The person and extensions aren't held. The stricter of the two options; the other was a card naming the reminder.
**Why:** "add this to my shopping list" failed when the agent couldn't see the list's name or make it, "watch this all week" meant coming back every day, an agent told to cancel the dentist reminder could only say no, and the companion couldn't answer "what did I miss?".
**Alternatives:** *the refusal naming the collections*: a read with no card. *A setting for making collections*: a standing yes for what a hostile repo would want. *Longer than a week*: an agent's watch outliving the task it was for.
**Not done:** a card isn't bound to the reminder as it stood: the person editing it while the card waits runs under the card's words on the newer reminder. A refusal by whole id says a reminder is important. A rename's card shows the name the agent used, which may be a loose match for the collection. B7, `files.write`, waits for Formatic's D140.

### D145 — Playtime's accepted redesign is a remaster, and stays in its pack (2026-11-03)
**Decision:** the redesign the founder accepted on 2026-11-03 is what ships, in the add-ons repository: Playtime's own palette and clay art, the 26 concepts as the target, and one layout rule for all sixteen games: fixed zones (header, stage with a bubble of one size, play room, dock, footer), so nothing moves when words or state change. A companion stands in one place per game, as a whole figure, and reacts by moving. Clicks that build toward a rule break hold its warning for a second, so a double click to reach a mark doesn't flash an error.
**Why:** the founder judged the experience, not the pictures: "not just the reskin". Their example was the bubble going from one line to two and moving the board's border during play.
**Alternatives:** new images on the old screens; a bigger scene language in the app for it. Scenes already had what it needed, except direction (D144).
**Implications:** no app change but D144. The frame stays the app's (D99), so concepts' "Playtime" bar doesn't appear. Result and limitations are recorded in the hand-off's `implementation/RESULT.md`.

### D146 — Rock, Paper, Scissors is Pop-up Toys (2026-11-03)
**Decision:** *the founder's choice, direction B, replacing concept 13's hands.* Rock, a paper and scissors are toys on the mat. The chosen one travels into its box, the others leave, and the two boxes open on a spring to act on each other. Nothing stays behind faded.
**Why:** the founder found the old round cheap and gave permission to propose better.
**Alternatives:** the proposal's other directions, in the hand-off's `rps-proposal`.
**Implications:** the game's rules and records are unchanged. The toss tool's manifest words say toys and Rock, Paper, Scissors, not hands.

### D147 — Coin and dice are real 3D toys, rendered ahead (2026-11-03)
**Decision:** *the founder's choice, direction C.* The toss on the desktop plays frames of clay coins and dice rendered in Blender, one real rotation per frame, through `Anim.frames`. The coin's heads wears the companion's portrait. The result is drawn first and the frames lead to it.
**Why:** the founder wanted it to "look like animation and 3D stuff". Scenes have no live 3D (D99), and the pack can carry pictures.
**Alternatives:** adding live 3D to scenes: a large ability for one toy; keeping the drawn coin and die.
**Implications:** the pack grows by the frames, to about 8.7 MB zipped. Blender sources are in the hand-off's `toss-source`.

### D148 — Game language (2026-11-03)
**Decision:** *the founder's choice: "All of Playtime".* A setting, `game_language`, and a globe on Playtime's menu put everything Playtime draws in a language of its own: menus, games, the page and the toss. Sidefolk's frame, sidebar and Ask stay in the app's language. "As Sidefolk" is the default.
**Why:** an English Mac and the word of the day in Arabic.
**Alternatives:** a setting per game; following only the Daily Word.
**Implications:** uses D144 when the direction differs from the app's, and says nothing otherwise. The page's summary for the app stays in the app's language.

### D180 — A watch that keeps its word, a folder shared where it's needed, one hidden file by its facts (2026-11-04)
**Decision:** *the founder's findings on snapshot 1177, on the coordinator's go.* Three general abilities. (1) A watch an extension made has no rest after it fires, since it tells only that extension (D111); `watch.create` takes `cooldown_minutes`, which only an extension may set below 5; Home says when a watch is resting. (2) A page's button may ask to share a folder (`share`): Sidefolk works out the folder, asks in its own words, and `folders.share`, reached by the person's click alone, records it in History. `sidefolk/tools.check` says when a refused call needs its path shared, and the click works out the folder. (3) `watch.create` of kind `file_changes` or `file_appears` may name one hidden file: its size and time only, on a card or a plan the person read.
**Why:** a flow's file watch said "every 30 s" and looked again after 30 minutes: the rest that spares a person a ringing watch applied to a watch that rings no one. "That folder hasn't been shared" was a dead end with the way out in another window. And a status file in `~/ws/.tmp` could never be watched at all.
**Alternatives:** Sideflow passing a short cooldown (the words would still lie for every other watch, and flows already on would need approving again). Asking inside the plan's card (a plan can't grant a folder, and sharing is wider than one flow). Letting a hidden folder be shared (T10.2 keeps those closed: one file's facts are enough). A deny list of secret hidden folders (it always misses the next one).
**Implications:** T10 has the rule and its limits. An extension can show the sharing question only on a click on its own page; it names a path, and the person reads the folder. Sharing is as wide as Settings › Trust's: what they allow to use shared folders can read it. Sideflow's flows on watches run on every change unless they ask to rest, held back by its runaway limit.

### D190 — A save changes only what its author changed, and an extension's name is found on this Mac first (2026-11-04)
**Decision:** a note is saved with what its author started from, and only the fields they changed since are written, over the note as stored, in one transaction (`NoteEdits`, `NotebookStore.save(_:from:)`). The Notebook's open draft, `notes.update` and its undo all save this way, and the open note takes in a change an agent stored meanwhile. The same field changed by both goes to the later save. Also: the Say bar and the Ask panel match installed extensions and the gallery's last stored list by name before the AI is asked, and Return on an extension's name opens it, with the AI one key away on ⌘Return (`ExtensionHit`).
**Why:** the founder's `notes_update` "worked" and the app showed the old words. Reproduced through the real MCP path: the open draft was written back whole and replaced what the agent had stored, so the success message, `notes_get`, `notes_trash` and the app disagreed. For the search, the founder was told his words would go to the AI, "a waste of tokens", for a name already on this Mac.
**Alternatives:** refusing an agent's update while the note is open in Home (an agent can't know, and the person loses the update); reloading the note without merging (loses what the person types meanwhile); locking a note while it is open.
**Implications:** nothing is lost by either side's edit to a field the other didn't touch. The words of a note both changed at once are the later save's. Still read-then-write whole: `ProfileFacts.keep` and `write`, `NotebookModel.setDue` (a window of milliseconds). A word that only an extension's description holds finds it but never makes it the one Return opens.

### D185 — Full access is full access, Auto is easygoing, and what you allowed is listed and can be taken back (2026-11-04)
*Amended by D188: "extensions keep their own rules" no longer holds for a signed extension's plan, which Full access answers for the person's own click.*
**Decision:** *the founder's words on snapshot 1177: "If the user chooses full access he should assume full access is full access. Auto should be more easygoing. And a lot of things keep asking every time."* Sidefolk's own agent only (other agents, extensions and routines keep their own rules, T4, D37 invariant 3).
- **Full access** asks nothing, after outside content too, except text to read in full (saving a skill, which outlasts Full access, and removing notes from Apple Notes, which shows its list) and, if the person chose it, the internet's "Ask each time" (D47). It works in any folder inside the person's home that isn't protected, shared or not, for the call alone, and only for Sidefolk's own agent (not a typed extension command, whose folder the extension names): the home folder itself, `~/Library`, hidden files and folders, other users' homes, other volumes and Sidefolk's own data are never open to it (protected places are matched without regard to case, since `~/BIN` is `~/bin`), and a link out of the home leads out. A folder outside the home still asks. What the person switched off stays off. The sheet says all this, including that a page or file Sidefolk reads can hide instructions that nothing then stops it from following, and its end defaults to "When I turn it off" (still offered: in an hour, tonight). Every way of turning it off (Today's banner, the Pocket, the expiry) goes back to the mode it replaced.
- **Auto** asks only for what can't be taken back, what could carry data out after outside content (an address the person didn't type, a program, an extension, the clipboard, memory or calendar), and a folder that isn't shared. After outside content it now runs the rest (reads of the clipboard, calendar, History and Apple Notes, and writes to the notebook and Apple Notes copies carry nothing off the Mac; a step that changes how Sidefolk itself behaves, such as Focus, its voice, an update or a job for the companion, still asks), and a change to files inside a folder the person shared with write access: sharing it is the consent to change files there.
- **Remembered answers.** "Allow for this request" is also offered for an extension's own tool after outside content, only one that reaches nothing (no network, no program, no address or service named: a yes given while a page steers must not cover later calls the same page steers), and in Auto for what goes to the Trash. A call covered by such a yes is logged as that (`allowed_for_request`), so History tells a click from a carried-over yes. Trust lists these as "Allowed for now" with Stop on each, and "Forget everything I allowed" takes back every "Always allow" and every such yes; folders, and the sites and services listed under "Using the internet", stay. A card from another agent reading the notebook can open Settings › Trust's "Read your notes and reminders" for all agents (not a grant for one agent: names are self-chosen). The folder card's main button is now "Share folder": the folder is shared for good (listed in Trust, removable), and "Just this time" is in its menu, except after outside content, when the card says so and the main button is "Allow" for this call; Sideflow's `folders.share` (D180) stays the person's click alone.
- **Unchanged:** the audit log (every call is a row with its decision, in every mode), Undo, the Trash, capabilities off, protected places, the command watcher refusal after outside content, a hidden file watched by its facts on a card (D180), "Always" never offered after outside content for a site, service or extension, other agents' and extensions' gateways.
**Why:** four rules stacked: Full access still asked after any read, Auto stopped being easygoing after the first read (almost every tool that lists or reads marks the turn), answers weren't remembered, and moving files to the Trash asked every time. The cost is in the residual risks below: the person's choice, said plainly.
**Alternatives:** keeping the shared list for Full access (then Full access still shows folder cards, the founder's complaint). A timed Full access by default (it falls back to asking without being asked, which reads as "full access isn't full access"). "Always" for sites, services and extensions after outside content (that reopens what D47 and the audit's F1 closed). A planned-job allowance for file moves (a state machine inside Guard; the shared folder is the consent, and Undo and History are the way back).
**Implications:** `sidefolk.install_update` now declares `.system` (so Auto asks for it after outside content), which also puts it under the "System information" capability should a person switch that off. `PermissionEngine.answeredByMode`, `couldCarryOut(staysInShared:)`, `ToolExecutor.fullAccessFolders`, `FolderAccess.isOpenToFullAccess`, `GuardPolicy.endFullAccess`, `AllowedForNow`, `SidefolkRuntime.answer`; tests `PermissionFeelTests`, `FullAccessMeansFullTests`, `FullAccessExfiltrationTests` (Auto asks for each way out, Full access for one), `OnlyThePersonTurnsFullAccessOnTests`, `RememberedAnswersTests`, `AgentsReadFlipTests`, `FullAccessWayBackTests`. SECURITY T2 and T48.
**Residual risks:** see T48. In Full access nothing but the off switches, protected places and the person's own care stands between a page's hidden instructions and what Sidefolk can do on the Mac; in Auto, after outside content, files inside shared folders can be changed or moved between them, notes copied from Apple Notes and reminders and the notebook written without a card (Undo, History and the Trash are the way back).

### D191 — A snapshot build starts on the snapshots channel (2026-11-04)
**Decision:** *amends D46 and D65.* "Versions to offer" that the person never set follows the build that runs: a snapshot (`0.1.0-snapshot.N`) offers snapshots, an official release offers releases. A choice already made is kept whatever the build (`UpdateSettings.effectiveChannel(running:)`). Nothing is written to the settings, so the default stays a default: a person who moves from a snapshot to the release is on releases, and one who chose still has their choice.
**Why:** a fresh install of a snapshot landed on Releases, where nothing is released yet, so the gallery, add-on updates and the Say bar's extension search showed nothing until Show snapshots was found and turned on. Everyone who installs a snapshot is, by that, someone who wants snapshots.
**Alternatives:** writing `.snapshots` into the settings at first launch (loses "never chose", so the release would keep them on snapshots); a build-time default in the image (a second place that has to agree with the version).
**Implications:** the Settings wording ("Snapshots are test builds that come out before a release. Add-ons follow this too.") still fits and is unchanged. A build made on this Mac has no release stamp, so it reads as a release and keeps releases only.

### D220 — Studio: the default theme and the shared parts it needs (2026-11-04)
**Decision:** *amends D130 and D84's sizes.* The founder asked for the Studio direction (a calm, professional refinement; seven boards in the local handoff) to be built with every existing feature kept: the images are a design direction, not a feature list. It lands in stages, tokens and shared components first, so this entry grows with them.
- **Theme data (the default only):** the palette (page #F5F7FA / #151B24, cards #FFFFFF / #1D2633, sidebar #F8FAFC / #121923, wells #E9EEF4 / #222D3C, ink #243B5A / #E2E8F0, action #304E78 / #8BCED0, light #62BFC7), the system face for titles, cards at 14 and panels at 16, line depth and no scene on Today. Its theme.json and `ThemeTokens.sidefolk` say the same values.
- **A new optional role, `focus`:** the keyboard's ring, 3:1 from a card and the page (`ThemeCheck.focusProblems`). A theme without it uses its accent, or its ink where the accent is too pale, so every other theme keeps working untouched.
- **Shared, in every theme (D84):** a type scale with 14 pt reading text and 12 pt metadata; taller buttons, fields and rows; a control border at about 3:1; `.focusRing` on the shared buttons.
- **The sidebar and Today (stage 2a):** the companion on a strip of its studio, or a line beside its face under 680 pt; the collections folded after the first three when there are more than five (the Trash with them, opening by itself when the place the person is on is inside); the Gallery, Settings and Attention pinned at the foot. Today has the date, a greeting that shrinks in a narrow window, Needs you, Next up that folds past six, and Captured today as rows.
- **The other screens (stage 2b):** a page title in the page on each place, the toolbar's small one showing once it scrolls away; On duty in one column, so every state has its whole words; History by the day; Calendar's subtitle under its title; shorter introductions on Attention and Brain (the steps' details as tooltips); a "Say in Home" row beside the two shortcuts a person can change. Calendar was never opening at midnight: the snapshot tool scrolled pages to the top, and its shots now keep the page's own scroll.
- **The last group (stage 3):** Trust's four modes as a list, a mode's example a click away, always open on the chosen one and on Auto, which turns on with one click; Allow and its menu joined as one split button on every permission card, Permissions' Share folder included; a New button that says New; a theme with no picture runs its page up under the toolbar. Full access's sheet, the ring and the drop card stay as they are: what they say is theirs. Keys and answers didn't change, so a firm card still takes ⌘↩ and never Return.
- **Hover isn't the only way:** a `ListRow`'s actions are also in its ⋯ menu, for the keyboard and VoiceOver. It adds a small menu to rows the boards draw bare; an action a person can't reach wasn't worth the cleaner picture.
- **Themes with a scene** (Harbor) keep it, and Today and the sky behind the toolbar work as they did.

### D181 — A page never takes Home's sidebar away (2026-11-04)
**Decision:** *the founder's finding on 1177: "suddenly the sidebar disappear and side flow sidebar appear there. So that's confusing... it shouldn't be like surprising like that."* This amends D126. Home's sidebar stays as the person left it whatever page shows. A `workspace` page shows its own column of places only with room beside it (1120 points of its own width); with less, they're behind a button with its name at the top of the page. A person who wants more room folds the sidebar themselves, with the toolbar's button.
**Why:** going to a place in a sidebar shouldn't move the sidebar. D126 folded it to give a tree room, and the cost was not knowing where the app's own places had gone.
**Alternatives:** Keeping the fold and animating it, or asking once (still a surprise, and a question). Merging the page's places into Home's sidebar under its name (a page's places would become Sidefolk's parts, and D98 keeps them data the page owns; worth another look if two columns still feel like too much).
**Implications:** a tree has less width in a small window, which its fit and zoom take up. Every workspace page gets this, with nothing to change.

### D182 — Keys, a value menu and a tree you can fold, for any page (2026-11-04)
**Decision:** *the founder's A5, A6, A9.* General page abilities, for Sideflow's Save, undo and guided forms and anyone else's: a short list of keys a page may ask for while it shows (`cmd+s`, `cmd+z`, `shift+cmd+z`, `cmd+d`, `cmd+return`, `cmd+f`); a field's values in one menu under headings instead of chips, up to 64; a tree with Move to, an outline, arrows and Delete on the board, fold and find, a `hint` on an empty branch, up to 128 cards and 8 ways out of one. `PageAct.copy` carries up to 60,000 characters.
**Why:** "not really clear how to check changes, save or edit" and "you don't know where to put the condition and where to put the else".
**Alternatives:** any key a page names (it could take ⌘Q or hear typing, so a short list). Keeping fold and find in the extension (they'd make a tool call per look, and they change nothing).
**Implications:** keys run a tool as the person, through Guard, like a click. Sideflow's editor, engine and forms stay in the extension: its plan may ask for up to 1000 actions a day when it has a loop, which the card says.

### D198 — What a Sideflow condition can't answer stops the step (2026-11-05)
**Decision:** a tool's answer stays the words it said, and is read as a record or a list only when something looks inside: a field, a loop, a data step, a parameter that says it takes a list, from a whole value. A record without a field has nothing there, and so does a step that never ran, so "is empty" and "mentions" say so. `is_not` and `not_contains` stop the step, saying why, about what they can't have seen: a step that gave nothing, a name or path not there, a null, something empty given to a flow. They can be answered about an empty list or record, a field that's there and empty, and an optional form field left blank. Anything about a field of plain words stops the step. A check that settles an "or" or "and" wins over one that can't answer. A practice goes on and says so. `false` counts as empty to a condition, not to a data filter; the word "no" is a word. A choose path goes exactly first, then by a whole word; a value that matches none takes Otherwise, which shows in the run's story. No pattern gets every script right, so the path is written as the word appears: Arabic joins "ال" to a word, so "الفاتورة" doesn't mention "فاتورة".
**Why:** filled in as nothing, a reply without `errors`, or "Service unavailable", read as a reply saying there are none, and the deploy after it ran. Each stricter rule tried first broke honest flows: `{{item.email}} not_empty` on a row without one, an optional form field, a read tool finding nothing.
**Alternatives:** failing on every missing field (common conditions stop working). Parsing answers when they arrive (a bare `{{r}}` stops being what the tool said, and an existing `contains` flips). Leaving it as it was (the deploy).
**Implications:** Sideflow's add-ons only, in the flow guide for agents. `is_not` on an empty value is the one case a flow already on could newly stop at, and it says why. Run-time only: `problems` can't see a missing path ahead of time.

### D183 — A tool that's gone can be waited for (2026-11-04)
**Decision:** *the roadmap's "show whether a run is waiting for a … missing extension", the founder's order to finish it.* Calling a tool that isn't offered now answers `unavailable`, not `denied`: nothing happened and it may come back. The list of tools says who offers each one, in that extension's or server's own name, and a page's button can open Settings › Add-ons. Sideflow uses these for a Connections page and for runs that wait for what's missing, up to 7 days, then ask the person.
**Why:** an extension switched off for an afternoon shouldn't fail every run that gets to it, and "denied" reads as the person's no. A program can't wait for a no.
**Alternatives:** accounts and keys in Sidefolk, which the roadmap asks for later and which need a security decision of their own: out. A flag on `denied` (older programs would read it the same, but it says two things at once). Failing the run and leaving it to the person (a schedule would fail every time for as long as it's off).
**Implications:** adds no reach. The tool's name, plan and card are checked as for any call when it comes back, and a definition that changed no longer fits its plan, so it asks. An older program reads `unavailable` as `lost`, so a pack that uses it names the snapshot that has it. The name in the list is the extension's own words, for people only: treat it as a label. A server that's listed but not answering isn't "gone": that call still fails as it did.

### D186 — A flow is approved once, as one plan, and Run and Turn on are the same approval (2026-11-05)
**Decision:** *the founder's, on the coordinator's word: "I approve, and after that, I do nothing." His yes to the five decisions of D186–D189 is quoted in D189.* A flow's plan is the unit the person reads and allows (bound to the extension's permissions and origin: an update of the add-on itself does not ask again, a changed server program does). Run the first time, Turn on, and a practice that does more than read all send the same `plan.approve` for the same plan id, with `intent` ("run" or "turn_on") choosing the card's title; one card, one Approve. After it, nothing the card listed asks again, on any run, unattended too. A step with no tool of Sidefolk's behind it counts as read: `{kind: "ai", reads}` ("what these steps read goes to your AI") and `{kind: "flow", name}` ("it sets off B, which has its own approval", B staying on its own plan). A step may also be `{kind: "value", as, reads}`: it passes words on, is never shown, and gives a later step the furthest source of what it reads. The limit is 64 *different* lines (the same line under other names is one to read, shown with "× N"); the plan may hold up to 256 rows. `sidefolk/plan.check` says, for a body and with no click, card or change, what would stand, ask or be refused and what is new, so an editor can mark it. The card is built by the host in Sidefolk's words, in sections: what it reads, changes, sends out, hands to the AI, sets off, still asks each time, outside content and limits; every line is shown, a server's one by one.
**Why:** the first Run asked a card per action, a server call asked on every run for ever, an edit showed the whole card again, and Full access didn't reach flows. "If I need to approve every single thing, then what's the point?"
**Alternatives:** per-line ticks on the card (T51's first design: more clicks, same risk). A card each run (nothing unattended).
**Implications:** the Sideflow side of this is its own landing; an old Sideflow keeps working (the new fields are optional). A plan saved before this has no provider kept for a step on another extension's tool: those ask until it's approved again (T52). *L3:* Settings › Trust lists each approval (its name, whose it is, when it last ran, how many actions today, the words the person read, and Revoke); a plan nobody has used for 60 days ends, and its extension is told why (`plan.ended`, reason `idle`), so the flow can pause and say so; a long card says there is more to read; the card's main button says "Approve", with a line above it saying what else it approves when words from outside content go to a server or another extension's tool. *L3, as replayed on the final L1 (2026-11-06, taking the safer option on each point the founder's night delegation left to the session):* an idle plan ends (it does not just pause: its extension asks again with a full card), the 60 days count from its last standing run or, if it never ran, its approval, and the end is a row in History (`plan_ended`) as well as a `plan.ended` message to the program, made when its extension next asks anything, when Trust is listed and when the app starts (so an extension that stopped or was switched off still leaves it), once per plan, and the row says whether the extension was told (an extension that is not running is not told later: it learns the plan is gone by asking again, and needs a new approval); `plan.check` says why a card comes (`why`: ask_every_time, not_signed, mode_asks, first_time, terms_changed, line_asks, in_click_only, or what keeps the record from being whole: too_many_entries, entry_too_long, name_too_long, secret_like, names_alike, unknown_tool) and the line, as the card numbers it, so an editor can tell its author; it only names the reason, it changes nothing; a plan's past (when it last ran) is kept only across the approval of the live plan it replaces; a last run dated ahead of the clock is not believed beyond a day; Revoke is the person's own click and already has its row (`extensions.plan_end`); Trust shows the whole plan as its card says it, never only what the last edit added, and says when nobody read all of it (Full access answered it, or Auto let lines through; not lines read on a card that stand only in Full access); the long-card cue and the Approve note only add words, they do not change what is allowed.

### D187 — An edit asks only about what is new (2026-11-05)
**Decision:** on `plan.approve` for a plan the person already read, the host works out what the standing plan covers: the same tool from the same provider, definition and reach, the same written values, and no value coming from further out than before; words may change only in a tool's open fields (D110's table). A step the person read as asking each time is covered too. Nothing new and terms no wider: no card, the plan is replaced and History says it was covered. Something new: a card with only the new lines and "N things you already allowed". Wider terms (more actions, a longer time, another way of starting) are new. A field newly said by the extension to be the person's own, and words in a tool's open field that now come from outside content, are new too, whatever they were before. In Auto, an edit whose new steps only stay inside Sidefolk (a tool of Sidefolk's own that is not high risk, has no way to carry anything out, and writes or tells: a note, a notice, a question, a reminder, a change or removal of one of those; a read whose answer goes back to the add-on, such as files, calendar, agenda, notes or Apple Notes, always shows a card in Auto, which the founder chose on 2026-11-05; the companion's move (`companion.play`) asks too) asks nothing, and History records it as its own kind ("allowed in Auto without a card") with the lines named on the row; those lines were read by nobody, so they stand only while Auto is on, any other mode shows them as new in a card first, and an edit read in a card makes them read. Ask every time still shows the card. Pause and Resume ask nothing. If an edit is answered while the person ended or changed the plan meanwhile, nothing is saved (`changed`), so what they took away stays away.
**Why:** "if I make edits and click run again, I shouldn't approve the same things again and again."
**Alternatives:** asking about the whole body each time (today). Comparing exact values (a changed note text would ask).
**Implications:** coverage is the host's decision, not the program's. A step removed needs nothing.

### D188 — Full access answers a signed flow's plan for the person's own click (2026-11-05)
**Decision:** amends D185 ("extensions keep their own rules") for one case. When Full access is on, an extension signed by Sidefolk asks a plan within seconds of the person's own click or typed command to it, and Guard, which checks the mode itself, answers it: no card, History says "Full access". The click answers one plan, once, and only while the call it made is still running (and within ten seconds of it): a button that has returned, a timer, a turn of the agent that comes after leaves nothing to answer with, so an unrelated click never opens a window for another plan. A turn of Sidefolk's own agent is not the person's hand (it gets the card that reads in full), nor is a click already used for a plan, and another extension's plan keeps its card in every mode: its program is untrusted (T44). What a call of the person's asks for is the extension's choice, not bound to an id: T53 says what remains. A plan with a job for the companion (agent power) is answered like any other here: in Full access running is the approval. History says so in its own words for the approval itself ("answered by your own click under Full access: nobody read this plan, and it stands for later runs"; "allowed in Auto without a card") and for every call under a plan Full access answered, or under a line Auto let through ("fit a plan nobody read"); the approval's row records them in full (one header per line and one entry per field, numbered), and a flow too large or odd to be recorded in full on one History row always shows its card, in Full access too. A plan Full access answered, which nobody read, stands only while Full access is on: when it ends the plan asks for a card first, as the mode it replaced returns (D185). Within any plan, a step that would ask under another mode (a place filled from outside content, the clipboard) is marked as standing only in Full access. Refused in every mode: text to read in full, a program that runs anything, outside words into a field that runs code.
**Why:** "of course with Full access, I guess, it will not need anything."
**Alternatives:** Full access answering any extension's plan (any extension with `act` could widen itself); the agent's request counting as the person's.
**Implications:** Trust's note and the Full access sheet no longer say extensions always keep their own rules: they name this one exception.

### D189 — A server call may be in a plan, named, checked and bounded (2026-11-05)
**Decision:** amends D127 ("a card every single time, never in a plan") for a signed extension's plan. A server's tool, or another extension's, stands in a plan when the card names it with its program, its definition and provider are pinned (T52), its program can be checked (a compiled program, hashed; a launcher, interpreter, build tool, script or system tool such as `npx`, `node`, `make` or a shell can't be, and asks each time, saying which of those it is on that line). A built-in tool that runs a program (shell) is refused in every mode; for a server's tool nobody can know (an MCP tool never says what it runs), so what holds there is the pin, the card naming it, the field rules (a field named like code never takes outside words) and the person's switch. The launcher list is a closed guess, not an allow-list: a compiled runner that isn't on it is pinned by its own hash while what it runs is not. Values may be filled from the flow's own steps. The host takes every filled value as outside content, except the person's own typed answer, the clock, and what a signed extension says comes from the person. The card says in words where outside words go. Outside words go only into plain text fields the card names (a body, a message, a title: a plain string with such a name); a field that says where a call goes, or anything else, asks (it stands only in Full access, as the sheet for Full access says a page can hide instructions), and a field that runs code (a command, script, sql, shell and the names listed in T53) is refused in every mode, whoever says the words are the person's, a typed answer included. What the host takes as the person's own (an `ask.user` step, the clock) is read from names the program writes, so a place or a choice filled from it stands only in Full access too; only a signed extension's `from` claim, said on the card, stands there in every mode. A flow that reads the person's own things and outside content and fills a server line from them stands, with a plain warning on the card naming what goes to which server. Trust has a switch, on by default: a flow may pass what it reads or wrote to servers and other extensions' tools (words from a page or a file, and also the person's own notes, reminders and calendar, what their AI wrote and what other servers answered; what the person typed into the flow is not held back); off returns those lines to asking, for plans already read too. A value the extension says is the person's own (claimed) is not held back by the switch, and moving a field from outside words to a claim is new. A plan has an action limit a day and a run; past it a call is stopped, not asked, History says so and the extension pauses the flow. Each call's History row says where its filled words came from.
**The founder's yes (2026-11-05, 21:20 JST, relayed by the coordinator):** "For the 5 decisions you were waiting from me, you have my explicit yes. Proceed, please." The five: (1) a flow may use a server's tool after one approval when its program is a compiled, hash-checked file (launchers and scripts ask each time); (2) the case where a flow reads the person's own things and outside content and sends words to a server is a plain warning on the card, not an ask; (3) the Trust switch "A flow may pass what it reads to servers" is on by default; (4) a place-type field filled from outside words asks in Ask and Auto and stands only in Full access, and code fields are refused in every mode; (5) under Full access the person's own click answers a signed extension's flow (one click, one plan, only while that call runs, ten seconds, that extension's own). This is not a yes to merge, push or release L1.
**Why:** "a flow should be able to use every single thing that app can do."
**Alternatives:** every filled server field asks each run (the flow people want, "read a page, write it with my AI, post to Slack", never finishes alone). Whatever the card says stands (a page could pick the destination).
**Implications:** T53 holds the analysis and what stays residual.
### D184 — A tool's answer can hold fields (2026-11-04)
**Decision:** *the roadmap's optional output schema and structured outcome.* A tool may answer with fields beside its words: `structuredContent` from an MCP server, `ToolReply.with(data:)` on the Kit. A tool may say what they hold with `outputSchema`, or `tool(output:)` on the Kit. A caller through `permissions.act` gets them as `data` and the schema as `output_schema`; the words stay what they were. Sideflow lets a step use `{{step.field}}` and offers each field in its value menu, and `{{step}}` is the words everywhere it goes: a sentence, a loop, a call, what a repeat, a lane or a called flow gives.
**Why:** a flow shouldn't have to ask an AI to pull a number out of a sentence a tool already had as a number.
**Alternatives:** fields only, or fields written into the text (both change what existing tools and every model read). Guessing fields from text that looks like JSON (the words of a page could then pose as data).
**Implications:** optional, so nothing else changes. Fields are as outside as the words are. They reach only the program that made the call, never a model or History, and not from a companion job that could carry them off; a flow can put one in a sentence by name, and that sentence goes where any sentence goes. A server that sends fields and no words at all has the fields written out as its words, as it always had. Fields are cleaned of hidden characters at every level, as words are. Over 256 KB they're dropped and the words stand. The schema isn't part of a tool's definition hash, so saying more about an answer doesn't end a plan. A step that fills a field into a call still only fills what the plan's closed table allows.

### D195 — A program can follow a call it made, and ask it to stop (2026-11-04)
**Decision:** *the roadmap's long jobs and cancellation, the part that fits one call.* With `permissions.act`, a program making a call hears `sidefolk/tools.progress {request, progress, total, message}` when the tool reports it, and can send `sidefolk/tools.cancel {request}`. An MCP server is asked with `_meta.progressToken` and told with `notifications/cancelled`. On the Kit: `Actions.call(request:progress:)`, `Actions.cancel` and `ToolProgressReport.report`. Sideflow shows how far along a step is, and Stop tells the step under way.
**Why:** a long step looked frozen, and Stop could only wait for it to end.
**Alternatives:** an instant Stop that only changes a label, which the roadmap rules out. Durable job handles that survive a restart, with status and results fetched later: a bigger contract no tool here needs yet, so left out.
**Implications:** cancelling a card makes it go away and nothing happens. Past that the tool is only told. The caller stops waiting, and a server may finish anyway, so the answer can only say "may or may not have happened", and Sideflow records it that way. Progress is the tool's own words: cleaned, 120 characters, at most one a second, heard only by the caller, never by a model or History. A call is still limited to 10 minutes, and one under way when Sidefolk quits comes back as "interrupted", as before.

### D196 — An event says which one it is (2026-11-04)
**Decision:** *the roadmap's event ids.* `sidefolk/happened` carries an `id`, the same for everyone who hears that happening. Sideflow keeps the last 300 on disk and acts on each once, and a flow can have several ways to start (`also_when`, schedules and events, up to 8 in all), with one run per moment however many match.
**Why:** "told twice" shouldn't mean "ran twice", and a flow that runs at 9 and when a note is saved shouldn't take two flows.
**Alternatives:** a replay of events missed while off (more than anything here needs, and it would run things long after). Several watches on one flow (each watch has a title and a plan step to look after, so a watch stays the first way only).
**Implications:** no new reach: the card lists every way it starts, and adding one is a change that needs the card again. An extension that ignores `id` hears what it did before.

