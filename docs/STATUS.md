# Status

Updated: 2026-10-26 (overnight build, orchestrated by Claude).

## Done
- Spec (docs/PRODUCT.md), architecture, decisions D1–D15, product review adopted.
- Core foundation: JSON, IDs, paths, SQLite schema v1 (GRDB), stores, event bus, tool contract,
  Guard (risk, caller, taint, folders, protected paths, grants), approvals, executor with audit and
  undo, attention policy + center, settings, diagnostics with redaction, brain/platform interfaces.
- Tests: Guard and executor (20 passing).

## In progress (parallel worktrees)
- Character rig + folks + icon (SidefolkCharacter, sidefolk-render).
- Time & understanding, watchers, built-in tools, brain (providers/loop/context).

## Next
- Bridge (local API, `sidefolk` CLI: mcp/run/hook), extensions, app shell, Home, Settings, onboarding.
