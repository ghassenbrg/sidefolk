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
swift test                       # core tests (Swift Testing)
make dev                         # build + assemble build/Sidefolk-dev.app + launch with SIDEFOLK_HOME=build/dev-home
make app                         # release build/Sidefolk.app (ad-hoc signed)
swift run sidefolk-render out/   # character contact sheets for visual review
```

## Rules

- Tests and dev runs never touch the user's real data or agent configs: use `SIDEFOLK_HOME`, temp
  folders, and pass paths explicitly. Never edit `~/.claude*`, `~/.codex` yourself; the app may
  change them only when the user clicks, after confirmation and a backup.
- Live model calls cost the user's quota: keep them rare and tiny; tests use scripted models.
- Every tool runs through `ToolExecutor` (Guard + audit). No side doors.
- No fake features: nothing shown as working unless it works.
- Match the surrounding code: small files, comments that explain why, no dead code.
- Commit in coherent milestones without Co-Authored-By trailers.
