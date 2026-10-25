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

## In progress (parallel agent worktrees under .claude/worktrees)
- Character rig/folks/icon, time & local understanding, watchers, built-in tools, brain,
  bridge (socket/CLI/Claude Code backend/integrations), extensions + skills, Home + Settings UI.
- Uncommitted in main checkout: Companion/CompanionWindowController.swift, Onboarding/ (wait for
  the character merge and the coordinator's AppServices implementation).

## Next
- Merge agent branches, wire everything in AppCoordinator (AppServices impl, intent runner,
  agent runtime, scheduler/watchers/extensions/bridge startup), end-to-end QA, adversarial review.
