# Agent guide

Sidefolk is a 3D desktop pet (Tauri 2 + three.js, macOS first) that gives AI agents a body:
it lives on the desktop with zero token cost, acts out what Claude Code and Codex are doing,
asks you for their permissions, and can hand them work.

## Start here

Several agents (Claude Code, Codex, others) work on this repo in turns. Shared memory lives in
[memory/](memory/):

1. Read [memory/STATUS.md](memory/STATUS.md): what is done, what is in progress, the next step.
2. Skim [memory/DECISIONS.md](memory/DECISIONS.md) and [memory/LEARNINGS.md](memory/LEARNINGS.md)
   before changing anything they cover.
3. Before you stop (or when you sense your session or usage limit is close), update
   STATUS.md so the next agent can continue without asking: what you changed, what is half
   done, the exact next step, how you verified things.

Background reading: [README.md](README.md), [docs/PHASE0.md](docs/PHASE0.md),
[docs/PHASE1.md](docs/PHASE1.md), [art/HERO.md](art/HERO.md).

## Commands

```sh
npm install
npm run dev        # desktop overlay, Tauri dev build (logs go to the terminal)
npm run web        # browser preview at http://127.0.0.1:1420 (?zoom=3 to inspect; number keys fake agent events)
npm run typecheck
npm run build      # release Sidefolk.app
npm run measure    # CPU/RAM of the built app
npm run model      # rebuild public/models/hero.glb from art/blender/build_hero.py
```

Rust only: `cd src-tauri && cargo build`.

## Rules

- Never edit the user's global agent config (`~/.claude/settings.json`, `~/.codex/config.toml`).
  Load Sidefolk's Claude Code hooks per session with `claude --settings hooks/claude-settings.json`.
- Live model calls cost the user's quota. Keep them rare and tiny, and prefer the
  debug-only endpoints (`/dev/ui`, `/dev/codex`, `/dev/resolve` on 127.0.0.1:47821) and the
  browser preview.
- Screen capture is not available to agents here. Verify the desktop app through its dev log
  (`[ui] ...` lines) and ask the user for hand checks.
- Commit only when the user asks. Work happens on the `rework` branch; `legacy-v0` tags the
  old app.
- Match the surrounding code: small modules, comments that explain why, no dead code.
