# Sidefolk

A 3D familiar that lives on your desktop and gives your AI agents a body. It is alive on its
own (no tokens), acts out what Claude Code and Codex are doing, comes to get you when they
need an answer, and can hand work to the agent you already have installed.

This branch is the **Phase 0** rework: throwaway spikes that de-risk the stack before the real
build. Findings and measurements are in [docs/PHASE0.md](docs/PHASE0.md). The previous
Electron app is preserved at the `legacy-v0` tag.

## Run it

Requires Rust (stable), Node 22+, and macOS 14+.

```sh
npm install
npm run dev        # desktop overlay (Tauri dev build)
npm run web        # browser preview at http://127.0.0.1:1420 (add ?zoom=3 to inspect)
npm run build      # optimized src-tauri/target/release/bundle/macos/Sidefolk.app
npm run measure    # CPU/RAM of the built app and its WebKit helpers
```

The pet has no Dock icon. Use the menu bar icon to quit or move it to the display under your
cursor.

In the browser preview, number keys play fake agent events: `1` think, `2` read, `3` edit,
`4` run, `5` permission question, `6` done, `7` failed, `8` prompt, `0` end.

## Try it

- **Pet it:** click to poke, drag to pick up, fling to throw. It wanders, waves when your
  cursor comes near, follows the cursor with its eyes, and falls asleep when you stop moving.
- **Watch Claude Code:** start a session with the Sidefolk hooks loaded for that session only
  (your own settings are untouched):

  ```sh
  claude --settings hooks/claude-settings.json
  ```

  The pet thinks, reads, works, and celebrates along with the session. Permission prompts
  appear in its speech bubble for 60 seconds (Allow / Deny / In terminal) before the terminal
  prompt takes over.
- **Hand work to Codex:** double-click the pet, type a request, press Enter. Codex runs in
  `~/Library/Application Support/dev.sidefolk.companion/playground` (override with
  `SIDEFOLK_WORKDIR`) and asks the pet before running commands.

## Layout

```
src/                 overlay page (TypeScript + three.js)
  pet/rig.ts         placeholder bunny: primitives on a real skeleton, one skinned mesh
  pet/clips.ts       procedural clips sampled into ordinary AnimationClips
  pet/pet.ts         mixer, crossfades, gaze, blinking, squash, props
  mind.ts            behavior: routine, reactions, agent directives, drag/throw physics
  agents.ts          folds agent sessions into one thing to act out
  bubble.ts          speech bubble: lines, permission questions, prompt
  input.ts           click-through hit testing against the skinned mesh
src-tauri/src/       Rust core
  overlay.rs         transparent work-area window, cursor stream
  hooks.rs           127.0.0.1:47821 endpoint for Claude Code HTTP hooks
  codex.rs           codex app-server JSON-RPC driver
  bus.rs             shared event shapes and pending permissions
hooks/               Claude Code hook settings
scripts/measure.sh   resource measurement
```
