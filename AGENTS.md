# Agent guide

Sidefolk is a native macOS desktop AI companion (Swift 6, SwiftPM, AppKit + SwiftUI + Core
Animation). A small character lives on the desktop, remembers, reminds, watches, acts through
permissioned tools and extensions, and other AI agents can reach it over MCP.

## Start here

1. [docs/STATUS.md](docs/STATUS.md): what is done, in progress, next.
2. [docs/PRODUCT.md](docs/PRODUCT.md): V1 spec. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how it fits.
3. [docs/DECISIONS.md](docs/DECISIONS.md) before changing anything a decision covers; add new major decisions there.
4. Before you stop, update docs/STATUS.md (what changed, what is half done, exact next step, how verified).

## Commands

```sh
swift build                      # everything
make test                        # core tests (Swift Testing), serially: swift test --no-parallel (D18), ~40 s
make dev                         # build + assemble build/Sidefolk-dev.app + launch with SIDEFOLK_HOME=build/dev-home
make app                         # release build/Sidefolk.app (Apple Development identity if present, else ad hoc)
swift run sidefolk-render out/   # character contact sheets for visual review
swift run SidefolkApp --ui-snapshots out/   # Home, Settings, Ask panel and bubbles, light and dark, sample data
```

Agents can't see the screen. To check the running debug app:
- `swift scripts/dev.swift snap` writes a PNG of every visible Sidefolk window to `$SIDEFOLK_HOME/snapshots/`
  (read them as images); `swift scripts/dev.swift "ask:…"`, `respond:<action>`, `dismiss`, `approve`, `deny`,
  `home`, `settings:<tab>`, `find:<query>`, `drop:<url or path>` drive it (list at the top of the script).
- Use a fresh short `SIDEFOLK_HOME` (the socket path must stay under 104 bytes), e.g. `build/qa-<timestamp>`.
- `sidefolk` (in `build/Sidefolk-dev.app/Contents/Helpers/`) with the same `SIDEFOLK_HOME` talks to that app.
- When a test run seems stuck, run it through `script -q log.txt swift test --no-parallel < /dev/null`:
  plain redirection buffers the output, so the last lines lie about where it stopped.

## Rules

- Tests and dev runs never touch the user's real data or agent configs: use `SIDEFOLK_HOME`, temp
  folders, and pass paths explicitly. Never edit `~/.claude*`, `~/.codex` yourself; the app may
  change them only when the user clicks, after confirmation and a backup.
- Live model calls cost the user's quota: keep them rare and tiny; tests use scripted models.
- Every tool runs through `ToolExecutor` (Guard + audit). No side doors.
- No fake features: nothing shown as working unless it works.
- Match the surrounding code: small files, comments that explain why, no dead code.
- Commit in coherent milestones without Co-Authored-By trailers.
