# Founding discussion (summary)

Sidefolk started as a brainstorm with ChatGPT (shared conversation titled "sidefolk"). It is the
seed of the product, not its specification. This page records what it proposed so later readers can
see where ideas came from and how they evolved (see DECISIONS.md).

## The idea
- A companion that lives on the desktop — part pet, part assistant, part productivity layer. Its
  advantage over a chat window is presence: it can notice things and react at the right moment.
- "It notices things so you don't have to remember to ask." Glanceable states (sleeping, listening,
  thinking, working, monitoring, needs permission, done, problem) are an interface in themselves.
- Not annoying: graded interruptions (ambient, gentle, attention, critical), silence during
  entertainment or presentations, "teach my companion" policies.

## Interaction ideas
- Text, voice, direct UI and drag & drop all express the same intents. A global shortcut opens a
  tiny input; Enter, and it disappears while the companion keeps working.
- Drag things onto the character (files, images, links, text) and pick an action.
- "What was I doing?" recap; contextual suggestions; a "life feed" of what's happening now.
- Props communicate activity: laptop, binoculars, clock, approval card, magnifier, backpack.

## Architecture ideas
- The companion is a persistent personal agent runtime; the character is its UI. Sessions and
  models are disposable workers; memory, notebook, jobs, permissions persist.
- Memory belongs to the companion, not the model: structured memory, context packages with a
  budget, checkpoints instead of endless transcripts.
- Model routing: deterministic first, cheap model, smart model, coding agents (Codex/Claude) as
  workers. Monitoring is deterministic and costs no tokens.
- Ten primitives: remember, write, schedule, watch, notify, execute, observe, build, ask, connect.
- Jobs (running, watching, waiting, scheduled, needs input, completed) live independently of chats.
- The companion is an MCP server (agents can add notes, reminders, watches, ask the user) and an
  MCP client (tools). Skills sit above tools. A "Workshop" lets it build new skills safely.
- A deterministic permission engine separate from the AI (inspired by Meta Muse's "Sentinel"),
  an activity/audit trail, local-first storage, no accounts, no cloud backend, one Mac, one user.
- Extensibility as a core principle: tools, skills, watchers/triggers, context providers, UI and
  embodiment contributions; manifests with risk and permissions; generated skills follow the same
  sandbox rules.

## Identity
- Name: Sidefolk — "AI that lives by your side". Tagline: "A Friendly AI Desktop Companion".
- Main character: white rounded robot, navy visor, aqua eyes. The Folk Family — colorful helpers —
  represents skills, tools and extensions. (Since 26 October 2026 the main character is Mochi, a
  white rabbit with navy ear tips and an aqua scarf; the robot stays a companion you can pick: D29.)
- Palette: Navy #0F2D5B, Aqua #2ED4D9, Coral #FF7B6B, Mint #7DD3A7, Light Blue #93C5FD.
- Personality: friendly, modular, supportive, extensible, delightful.

## Explicitly out of scope at the start
Accounts, sync, mobile, web, cloud VMs, payments/shopping, glasses, multi-user, enterprise.
