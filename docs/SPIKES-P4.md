# P4 spikes: hosts and Codex (2026-10-25)

What docs/V1.md §7.1 and §7.2 asked to find out, what was found, and what changed. Read-only
checks on this Mac: AppleScript dictionaries (`sdef`), CLI help, and the vendors' own docs. No
host was scripted and no setting was changed. A result is "exact" only if it was proven.

## Hosts (§7.2)

| Host | Version here | Found | Result |
|---|---|---|---|
| Terminal.app | system | `tty` and `selected` on tabs | Exact, as before |
| iTerm2 | 3.7.1 | `tty` on sessions, `current session` | Exact, as before |
| Ghostty | 1.3.1 | Dictionary has `front window` → `selected tab` → `focused terminal`, with `id` and `working directory`; **no `tty`** | Stays on the fallback (frontmost and one live session). See below |
| WezTerm | not installed | `wezterm cli list` documents pane, tab, cwd and tty; not run here | Stays on the fallback until run on a Mac that has it |
| VS Code 1.143 | installed | No AppleScript dictionary; the integrated terminal isn't visible from outside | Fallback: bring forward; focus = frontmost and one live session |
| Cursor | not installed | Same as VS Code (it is VS Code underneath) | Same fallback |
| Warp, Claude desktop, tmux / ssh | — | — | Never "focused", as the contract says |

**Ghostty, in detail.** The focused terminal's `working directory` can be read, but two Claude
sessions in one folder would look the same, and the contract only allows "exact" when it's
proven. A match on working directory plus "the only live session in that folder" would be safe.
It is a small change in `Hosts::focused`, but it needs one hand check: the user grants Sidefolk
Automation access to Ghostty when macOS asks. Left for the user to decide; the fallback stays.

## Codex (§7.1, F-14)

Codex CLI 0.160.0. `codex features list` shows `hooks` as **stable**. The vendor's docs
(learn.chatgpt.com/docs/hooks) describe the following:

- **Where they live.** `~/.codex/hooks.json`, or `[hooks]` in `~/.codex/config.toml`, and the
  same files per repo.
- **Events.** `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`, `PreToolUse`,
  `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `Stop`
  and `Interrupt`. Every event carries `session_id`, `cwd` and `hook_event_name`.
- **Approvals.** `PermissionRequest` runs when Codex is about to ask for approval. A hook may
  answer `hookSpecificOutput.decision.behavior` = `allow` or `deny`. Without an answer, Codex asks
  as usual.
- **Trust.** A hook only runs after the user trusts it in `/hooks`. Trust is tied to the hook's
  hash, so a changed hook stops until it is trusted again.
- **Timeouts.** 600 s by default; `SessionEnd` and `Interrupt` get 1 s.

**What this means.** The same event shape as Claude Code means the `sidefolk hook` sidecar can
serve Codex too. That gives exact status (working, finished, needs you) from documented signals,
with no rollout-file parsing. This is better than the `notify`-only fallback.

**What it does not change on its own.** V1-D2 says "Pip never answers Codex approvals". The hooks
make answering possible, but changing that rule is a product decision for the founder. Until
then, a Codex `PermissionRequest` may only drive the "Codex needs you in api · Open" card: the
sidecar prints nothing, and Codex asks in its own window. Installing Codex hooks also asks the
user to trust them in `/hooks`. That is a one-time step to put in setup.

Next step for F-14 (P6): a Codex hooks installer, built like `claude_setup.rs` (confirm first,
keep a backup, remove only our own lines), that reuses the sidecar. Its events map to agent
events exactly as Claude Code's do.
