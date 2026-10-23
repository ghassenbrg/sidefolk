# Phase 0 findings · 23 October 2026

Four throwaway spikes to de-risk the stack before Phase 1. Machine: MacBook Pro (Apple
Silicon), macOS 27.0.1, Tauri 2.12, Claude Code 2.1.282, Codex CLI 0.160.0.

**Verdict: the stack holds. Proceed with Tauri.** Every spike worked end to end. The open
items below are known macOS window work, not unknowns about the approach.

## 1. Transparent click-through overlay

| | Result |
|---|---|
| Transparent, undecorated, always-on-top window over the display's work area | Works (`macOSPrivateApi`). |
| No Dock or app-switcher presence | Works (`ActivationPolicy::Accessory`); menu bar icon to quit or move displays. |
| Click-through except on the pet | Works. Rust streams the cursor at 30 Hz, the page raycasts the skinned mesh and the bubble, and toggles `setIgnoreCursorEvents`. Confirmed live by hovering and clicking. |
| Small moving canvas instead of a full-screen one | Works. The 320 px canvas follows the pet; the rest of the window is empty DOM. |
| Rendering stops when the pet cannot be seen | Yes. 0 frames while the screen was locked or covered. |

**Pitfalls found**

- WebKit throttled `requestAnimationFrame` to about 8 fps until the window was given
  `"backgroundThrottling": "disabled"`. After that: a steady 30 fps.
- WebKit caps the overlay at 30 fps even when 60 is requested (walking, throwing). 30 fps looks
  fine for a pet; revisit only if motion feels choppy.

**Not done yet (Phase 1)**

- Clicking the pet activates the app and takes focus from your current app. Fix: make the
  overlay a non-activating `NSPanel`; return focus after typing in the bubble.
- Not shown over full-screen apps. Fix: full-screen auxiliary collection behavior.
- One display at a time ("Move to this display" in the menu). The pet should follow the cursor
  between displays.
- Sleep uses cursor stillness; use the OS idle time instead, and hide during screen sharing.

## 2. Character pipeline

A placeholder bunny made of primitives, but rigged like a real asset: one skinned mesh on a
13-bone skeleton, an inverted-hull outline, a three-step toon ramp. 13 clips (idle, walk, sit,
sleep, wave, think, read, work, celebrate, alert, sad, dangle, fall) are written as functions and
sampled into ordinary `AnimationClip`s, so the mixer crossfades them like clips from a file.
Gaze, blinking and landing squash are layered after the mixer each frame.

- Reads as cute and legible at about 140 px; the alert sign and status pill read at a glance.
- Swapping in an artist-made glTF with the same bone names replaces `rig.ts` and `clips.ts` only.
  Blender 5.2 is installed, so the hero character can be modeled, rigged and animated there and
  exported as glTF.
- Limits of the placeholder: rigid parts (no smooth deformation), "sit" reads poorly from the
  front, poses are hand-tuned numbers.

## 3. Watching Claude Code

Claude Code's `http` hooks post straight to `127.0.0.1:47821`: no scripts, no curl. They are loaded
per session with `claude --settings hooks/claude-settings.json`, so nothing is written to your
Claude Code settings.

- **Live session (Haiku, tiny prompt):** `UserPromptSubmit`, `PreToolUse` (Write),
  `PermissionRequest`, `Stop`, and `SessionEnd` all reached the pet. `SessionStart` did not
  arrive over HTTP (it probably accepts command hooks only); `UserPromptSubmit` serves as the
  session start.
- **Permission round trip:** a question shown in the bubble and answered with **Allow** on the pet
  returned `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
  to the hook in 6 s.
- **Unanswered:** after the 60 s hold the hook returns an empty 200 and Claude Code falls back to
  its own handling. In headless `-p` mode that is a denial (seen live). `PermissionRequest` fires
  in headless mode too.
- **Open question:** in an interactive terminal session, the terminal prompt waits while the pet
  holds the request. If you are looking at the terminal, 60 s is too long. Phase 2: hold briefly
  when the terminal is frontmost, and keep the "In terminal" button.
- **Endpoint safety:** requests with an `Origin` header are refused (403), non-JSON is refused
  (415), malformed JSON is refused (400), so web pages cannot fake events. Phase 2: add a per-install
  token header (`allowedEnvVars`).

## 4. Driving Codex

`codex app-server` speaks newline-delimited JSON-RPC without the `"jsonrpc"` field:
`initialize` → `initialized` → `thread/start` (ephemeral, `untrusted`, `workspace-write`) →
`turn/start`. `item/*` notifications map to pet states. Command and file-change approval
requests become bubble questions answered with `accept` or `decline`.

- **Live:** the request "run `echo hi from codex > hello.txt`" was dispatched, then asked "Run a command?"
  on the pet, was approved, ran, and finished in 10 s. The file exists in the playground folder.
- App-server loads your normal Codex config, including your MCP servers (about 2 s to start).
- Unanswered approvals wait forever because there is no terminal to fall back to. Phase 2 needs
  a timeout policy and an "open in Codex" handoff.
- `item/tool/requestUserInput`, MCP elicitation, and permission-profile requests are answered
  with an error for now.

## 5. Cost

Measured with `scripts/measure.sh` (60 s, all processes including WebKit helpers).

| | Sidefolk (Tauri; Phase 0 unless noted) | Sidefolk v0 (Electron) |
|---|---|---|
| App bundle | **3.65 MB** | 334 MB |
| Memory, all processes | **111 MB** | 322 MB |
| CPU, overlay hidden | **0.4%** | 6.3% |
| Memory, visible daily-driver build | **244.1 MB** | not measured |
| CPU, overlay visible (daily-driver build) | **16.9%** | not measured |

The original Phase 0 and Electron runs happened with the screen locked, so those overlays
were hidden. The daily-driver visible run on 23 October used the 4.17 MiB release bundle,
15 s warm-up and 60 s sampling with the screen unlocked and pet sleep disabled. CPU is the
sum of per-process averages (100% is one core); memory is the sum of the last sample.

| Visible daily-driver process | Average CPU | Memory |
|---|---:|---:|
| Sidefolk | 5.2% | 27.0 MB |
| WebKit GPU | 3.6% | 121.0 MB |
| WebKit WebContent | 8.1% | 85.0 MB |
| WebKit Networking | 0.0% | 5.6 MB |
| Audio sandbox helper | 0.0% | 5.5 MB |
| **Total** | **16.9%** | **244.1 MB** |

The measurement script isolated both settings files, verified no existing instance on port
47821, and checked screen lock throughout. An initial attempt that included an unrelated new
Chrome helper was discarded; the process filter was narrowed before the recorded run. The
visible cost is substantially higher than the hidden baseline; these are different workloads,
not evidence of a regression from a previously measured visible run.

## Decisions

1. **Tauri 2 with a thin Rust core** is confirmed. Electron stays out.
2. **Agent observation through hooks, agent driving through native protocols** (Claude Code
   hooks, Codex app-server). ACP is the next adapter, for every other agent.
3. **The pet's mind lives in TypeScript**; Rust only handles windows, the cursor, processes and
   sockets.

## Phase 1 starting backlog

1. Non-activating panel overlay; focus returns after typing.
2. Full-screen Spaces, following the cursor across displays, OS idle time, auto-hide during screen sharing.
3. Hero character: concept sheet (image generation), then Blender model, rig and clips, exported
   to glTF; replace the placeholder.
4. Global summon shortcut.
5. Window awareness (sitting on title bars) via window frames.
6. Visible-CPU measurement and a 60 fps check.
