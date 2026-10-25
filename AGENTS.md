# Agent guide

Sidefolk is a desktop companion (Tauri 2 + TypeScript + Rust, macOS first): Pip sits on your
desktop, taps you when Claude Code or a reminder needs you, takes you to that exact session, and
keeps a dated log of what you got done.

## Start here

Several agents (Claude Code, Codex, others) work on this repo in turns. Shared memory lives in
[memory/](memory/):

1. Read [memory/STATUS.md](memory/STATUS.md): what is done, what is in progress, the next step.
2. Skim [memory/DECISIONS.md](memory/DECISIONS.md) and [memory/LEARNINGS.md](memory/LEARNINGS.md)
   before changing anything they cover.
3. Before you stop (or when you sense your session or usage limit is close), update
   STATUS.md so the next agent can continue without asking: what you changed, what is half
   done, the exact next step, how you verified things.

**The plan is [docs/V1.md](docs/V1.md)**, the binding v1 release contract: every feature's
status, the requirements by ID, the release gates, the roadmap (phases P0–P8) and the guardrails
(§13: one in one out, WIP = 1, agents never mark a gate passed). Read it before changing
anything. PLAN-V2 and ROADMAP are history.

UI work follows docs/V1.md §9 and the approved mockups in creative-design/review-2026-10-24;
Pip's look and voice follow [creative-design/PIP.md](creative-design/PIP.md) (frozen for v1).
Use the tokens in `src/tokens.css` and the status vocabulary in `src/states.ts`; don't add
colors, sizes or state words of your own.

Background reading: [README.md](README.md), [docs/GUIDE.md](docs/GUIDE.md) (what users see), [docs/PHASE0.md](docs/PHASE0.md),
[docs/PHASE1.md](docs/PHASE1.md), [art/crew/README.md](art/crew/README.md),
[docs/RELEASE.md](docs/RELEASE.md).

## Commands

```sh
npm install
npm run dev        # desktop overlay, Tauri dev build (logs go to the terminal)
npm run web        # browser preview at http://127.0.0.1:1420 (?zoom=3; keys 0-7 fake agent events, r a reminder, p switches project, c opens the field)
                   # and the Sidefolk window at /settings.html with sample data (?tab=review:codex-1)
npm run typecheck
npm test           # vitest: commands, routing, reminders, briefings, descriptions, the window's logic
npm run check:webkit  # with npm run web running: every view in WebKit (the app's engine), fails on errors
npm run build      # release Sidefolk.app
npm run measure    # CPU/RAM of the built app
npm run sprites -- pip 3d   # cut public/crew/pip/3d/*.webp from art/crew/pip/3d (art/crew/README.md)
```

Rust only: `cd src-tauri && cargo build && cargo test`. Ignored tests run real CLIs or one live
model call; run them only when that part changes (README lists them).

Driving the dev app without clicks: POST JSON to `http://127.0.0.1:47821/dev/ui` with
`{"action": "state" | "bubbles" | "welcome" | "run:<command>" | "choose:<button label>"}` and
read the `[ui]` lines in the dev log.

## Rules

- Never edit the user's global agent config (`~/.claude/settings.json`, `~/.claude.json`,
  `~/.codex/config.toml`) yourself. The app's own installers may change it only when the user
  clicks them, after a confirmation and a backup. While developing, use
  `claude --settings hooks/claude-settings.json`, a copy through `SIDEFOLK_CLAUDE_SETTINGS`, or
  point `CLAUDE_CONFIG_DIR` / `CODEX_HOME` at temporary folders.
- Live model calls cost the user's quota. Keep them rare and tiny, and prefer the
  debug-only endpoints (`/dev/ui`, `/dev/codex`, `/dev/resolve` on 127.0.0.1:47821) and the
  browser preview.
- Screen capture is not available to agents here. Verify the desktop app through its dev log
  (`[ui] ...` lines) and ask the user for hand checks.
- Commit only when the user asks, and never add `Co-Authored-By` trailers. Work happens on
  `main`; the local tag `legacy-v0` marks the old app.
- Match the surrounding code: small modules, comments that explain why, no dead code.
