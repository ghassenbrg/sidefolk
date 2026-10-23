# Decisions

Newest last. Each entry: what, why, and what would change it.

1. **Start over (Oct 2026).** The Electron dashboard app was a chat/to-do app with a pet
   sticker. Kept at tag `legacy-v0`; nothing ported but ideas.
2. **Product: an agent familiar.** The pet is the body, face and router for the user's agents,
   not an agent itself. It never replaces Claude's or Codex's own UIs; it links into them.
   Developers who run agents come first.
3. **Stack: Tauri 2 + TypeScript/three.js, thin Rust core.** Measured 3.65 MB app, 111 MB, 0.4%
   CPU hidden vs Electron 334 MB, 322 MB, 6.3%. The pet's mind lives in TypeScript; Rust only
   does windows, cursor, processes, sockets.
4. **macOS first,** Windows second.
5. **Observe agents with hooks, drive them with native protocols.** Claude Code HTTP hooks to
   127.0.0.1:47821; Codex through `codex app-server`. ACP is the planned adapter for other
   agents.
6. **Overlay = non-activating NSPanel** (`tauri-nspanel`) on every Space, click-through except
   on the pet's mesh and bubble. Keyboard focus only while typing in the bubble.
7. **One hero character:** an ivory chibi bunny with charcoal points, mint scarf, and a floating
   status light. Spec and rig contract in `art/HERO.md`.
8. **Character pipeline: Blender script → glTF.** `art/blender/build_hero.py` builds mesh,
   vertex colors, armature and actions headlessly and exports `public/models/hero.glb`. The
   script is the source of truth for the model and its clips until an artist takes over the
   `.blend`.
9. **Shared memory in `memory/`** so any agent can pick up the work.
10. **Daily-driver defaults (implemented 23 October 2026):** global shortcut ⌘⇧Space toggles hide / show at
    cursor; sleep after 2 minutes of OS idle time; Claude Code hooks installed into the user's
    global settings only from a tray click with confirmation and a backup. **Permission hold
    policy:** when a terminal, IDE or the Claude app is frontmost, that app asks at once; otherwise
    the pet holds the request for up to 60 s. Reason: global hooks reach every session, and a
    stalled terminal prompt would be worse than no pet.

11. **Installer preserves other integrations.** Use ordered JSON, remove only handlers pointing
    at Sidefolk's localhost URL prefix, back up exact bytes before atomic replacement, and refuse
    stale confirmations. Tests target a copy via `SIDEFOLK_CLAUDE_SETTINGS`; only a user's confirmed
    tray action may write real global Claude settings. Foreground lookup failure defers permission
    immediately, so an AppKit scheduling problem cannot stall the agent's own prompt.
