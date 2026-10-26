# Sidefolk 0.1.0 — release notes

The first version of Sidefolk: a friendly AI companion that lives on your Mac.

## Highlights
- A companion on your desktop with a body that shows what it is doing, and the Folk Family helpers
  that sit beside it while reminders, watches and agents are on duty.
- Plain-language notes, ideas, tasks, reminders, watches, quiet mode and search — instant, local, no AI.
- Bring your own brain: Claude Code (your Claude subscription), Anthropic API, or OpenAI-compatible
  endpoints including Ollama.
- Reminders that survive restarts, with snooze, repeats, a morning brief and notification fallback.
- Watchers for web pages, sites, files, folders, processes, approved commands and extensions.
- `sidefolk` command-line helper: an MCP server for your agents, `sidefolk run` for long commands,
  Claude Code session awareness, `sidefolk ext validate`.
- Sandboxed extensions with permission review and tamper detection; plain MCP servers; skills.
- Guard: deterministic permissions, approvals in plain language, folder sharing, Activity log, undo.
- Home window (Now, Notebook, Activity, Trash) and Settings; export or delete all your data.

## Requirements
macOS 15 or later on Apple Silicon (the build script produces arm64; a universal build is a release-time option). Claude Code, an API key or Ollama for AI features (optional).

## Known limitations
English language understanding only; no voice input or calendar awareness yet; watchers and reminders
run while Sidefolk runs (system notifications cover reminders while it is quit); network-enabled
extensions can reach the local network; no automatic updates yet.
