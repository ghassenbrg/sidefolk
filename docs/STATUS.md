# Status

Updated: 2026-10-26 (overnight build, orchestrated by Claude).

## Done (on `rework`)
- Spec (docs/PRODUCT.md), architecture, decisions D1–D15, product/security/macOS reviews adopted
  (docs/SECURITY.md, docs/MACOS-NOTES.md, docs/VOICE.md, docs/FOUNDING.md).
- Core: storage (GRDB, schema v1), Guard (risk, caller, taint, hardened path policy), approvals,
  executor + audit + undo, attention policy/center, settings, diagnostics/redaction, companion mood,
  runtime container, interfaces for brain/platform.
- App shell: design tokens/components, Ask panel (cards, approvals), bubbles, status item,
  notifications, environment monitor, login item, packaging script (`make dev`, `make app`).
- Tests: 28 passing (Guard, executor, mood).

## Bridge (branch of the bridge worktree, not yet wired into the app)
- `Sources/SidefolkCore/Bridge`: `LocalAPIServer` (unix socket per T6, same-uid peers, hello,
  JSON lines ≤ 1 MiB, 8 connections, idle 10 min, 60 calls/min, 4 concurrent), `BrainTokenRegistry`
  (RunTokenRegistry), `ExternalToolGateway` (T4 allow-list by name, notes reads always ask, never
  "Always" for external callers), `AgentFacingTools` (`notify.user`, `ask.user`, `status`),
  `SessionTracker` (Claude Code hooks → AgentSession + attention), `JobTracker` (`sidefolk run`),
  `MCPStdioBridge`, `HookForwarder`, `CommandRunner`, `ClaudeCodeBackend` (T7: probe, isolated argv
  and env, prompt over stdin or a 0600 file, init-event check, usage via BrainUsageReporting).
- `Sources/SidefolkCore/Integrations`: `AgentIntegrations` for `~/.claude.json` mcpServers,
  `~/.claude/settings.json` hooks and `~/.codex/config.toml`, with backups and exact removal.
- `sidefolk` CLI: `mcp`, `run [--title] -- cmd`, `hook <Event>`, `status`.
- Verified: `swift test` (bridge suites: socket, tokens, policy, MCP over pipes, hooks, jobs,
  integrations, backend with a fake `claude` script and the real `sidefolk mcp` helper end to end).
  Not verified: a live Claude Code brain run (needs the ignored canary test from T7, one tiny call)
  and the hooks inside a real Claude Code session.
- Next: the app starts the server at launch (handle `.alreadyRunning`), registers
  `AgentFacingTools` + status, calls `SessionTracker.start()` and `JobTracker.reconcile()`, passes
  `ClaudeCodeBackend.make(provider:…)` to `BrainFactory.standard(claudeCodeBackend:)`, and shows the
  integration previews in Settings.

## In progress (parallel agent worktrees under .claude/worktrees)
- Character rig/folks/icon, time & local understanding, watchers, built-in tools, brain,
  bridge (socket/CLI/Claude Code backend/integrations), extensions + skills, Home + Settings UI.
- Uncommitted in main checkout: Companion/CompanionWindowController.swift, Onboarding/ (wait for
  the character merge and the coordinator's AppServices implementation).

## Next
- Merge agent branches, wire everything in AppCoordinator (AppServices impl, intent runner,
  agent runtime, scheduler/watchers/extensions/bridge startup), end-to-end QA, adversarial review.
