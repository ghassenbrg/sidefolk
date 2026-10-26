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
  holds the key. The microphone is open only while the key is held (the orange dot is honest), the
  Mac's own microphone is preferred (AirPods stay out of call quality), and the capture is rebuilt
  when the audio hardware changes. Audio is never stored; the words join history as text, marked spoken.
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
Services show their own logo where Simple Icons has one (16.35.0, CC0: Anthropic, Claude Code,
Gemini, Mistral, DeepSeek, OpenRouter, Ollama, LM Studio), as vector PDFs drawn as templates in the
ink colour; the rest keep monograms or symbols. Credits and trademark note in
`Resources/Brand/third-party/README.md`.
**Why:** the founder runs Codex at different efforts per model (gpt-6-luna at extra high, gpt-6.1-sol
at high) and asked for logos so the services are recognisable. Offering a level a model rejects
would turn a setting into a failed request; offering nothing where support is unknown is honest.
**Alternatives:** one effort for both slots (can't express the founder's setup); every level for
every provider (requests that fail); Codex's "ultra" (it delegates to sub-agents, which the isolated
brain switches off, D26); enabling Anthropic thinking explicitly (changes models whose default is
off); drawing logos for OpenAI, Groq and xAI (imitations of trademarks); full-colour logos (clash
with the folk-colour tiles and dark mode).
**Implications:** the per-family tables go stale as providers ship models; a model Sidefolk can't
place shows no control until the table learns it. The CLIs tell Sidefolk themselves, so they stay
current. Logos load from resources: dev builds see them with `SIDEFOLK_RESOURCES`.

### D37 — Approval modes, and no task left waiting on a question (2026-10-26)
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
