# Agent guide

Sidefolk is a native macOS desktop AI companion (Swift 6, SwiftPM, AppKit + SwiftUI + Core
Animation). A small character lives on the desktop, remembers, reminds, watches, acts through
permissioned tools and extensions, and other AI agents can reach it over MCP.

## Start here

1. [docs/STATUS.md](docs/STATUS.md): where Sidefolk is now, in progress, next, known gaps, how to verify.
   [docs/HISTORY.md](docs/HISTORY.md) keeps what was built before, newest first.
2. [docs/PRODUCT.md](docs/PRODUCT.md): V1 spec. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how it fits.
   [docs/DESIGN.md](docs/DESIGN.md): Lantern's tokens and components, for any screen (D84).
3. [docs/DECISIONS.md](docs/DECISIONS.md) before changing anything a decision covers; add new major decisions there.
4. Before you stop, update docs/STATUS.md (what changed, what is half done, exact next step, how verified). When a
   piece is done, move its entry to the top of docs/HISTORY.md and keep STATUS short.

## Commands

```sh
swift build                      # everything
make test                        # core tests (Swift Testing), serially: swift test --no-parallel (D18), ~40 s
make dev                         # build + assemble build/Sidefolk-dev.app + launch with SIDEFOLK_HOME=build/dev-home
make app                         # release build/Sidefolk.app (Apple Development identity if present, else ad hoc)
swift run sidefolk-render out/   # character contact sheets for visual review
swift run SidefolkApp --ui-snapshots out/   # Home, Settings, the Sidecard and Ask, the Pocket, games, light and dark, sample data
```

Agents can't see the screen. To check the running debug app:
- `swift scripts/dev.swift snap` writes a PNG of every visible Sidefolk window to `$SIDEFOLK_HOME/snapshots/`
  (read them as images); `swift scripts/dev.swift "ask:…"`, `respond:<action>`, `dismiss`, `approve`, `deny`,
  `home:<place>`, `settings:<tab>`, `pocket`, `find:<query>`, `drop:<url or path>`, `game:<id>/<game>` drive it (list at
  the top of the script).
- Use a fresh short `SIDEFOLK_HOME` (the socket path must stay under 104 bytes), e.g. `build/qa-<timestamp>`.
- `SIDEFOLK_REDUCE_MOTION=1` in a debug run is Reduce Motion for surfaces, without touching the Mac's setting. `snap` draws a surface's final state and no SwiftUI filters: `surfaceFilm:<s>` shows what is moving, and `screencapture -l <window>` what the screen really shows.
- `sidefolk` (in `build/Sidefolk-dev.app/Contents/Helpers/`) with the same `SIDEFOLK_HOME` talks to that app.
- Voice without a microphone or speakers: `say -o /tmp/x.aiff "remind me at 5 to stretch"`, then
  `swift run SidefolkApp --voice-transcribe /tmp/x.aiff`, `--voice-say "<answer>" out.caf`, or
  `swift scripts/dev.swift voice:file:/tmp/x.aiff` in the debug app (ARCHITECTURE › Voice). For an answer without
  spending quota: `swift scripts/dev.swift "brain:scripted:<answer>"` (debug app on a SIDEFOLK_HOME only); the log's
  `voice` lines say what was decided and played.
- `--ui-snapshots --language <x>` runs in several languages at once are safe from each other's catalogs now (each run
  stages its own folder), but an Arabic run beside others has still come out laid out left to right (cause unknown):
  render Arabic on its own when you review right to left.
- When a test run seems stuck, run it through `script -q log.txt swift test --no-parallel < /dev/null`:
  plain redirection buffers the output, so the last lines lie about where it stopped.

## Skills

Project skills, in `.claude/skills/` (Claude Code) and mirrored in `.agents/skills/` (Codex): keep both identical.

- `sidefolk-extension`: an extension end to end, to the gallery or a local folder.
- `sidefolk-3d-character`, `sidefolk-2d-character`: a companion's 3D model and its 2D form.
- `sidefolk-theme`: a theme from a concept or reference images ("brainstorm a theme around …"), checked, reviewed
  in snapshots and delivered as a folder or a gallery theme.

`skills/` holds what ships to other people: `sidefolk` (Connect installs it for other agents, D42) and the public
`sidefolk-extension` and `sidefolk-theme` for anyone building with the app, without this repository.

## Rules

- Tests and dev runs never touch the user's real data or agent configs: use `SIDEFOLK_HOME`, temp
  folders, and pass paths explicitly. Never edit `~/.claude*`, `~/.codex` yourself; the app may
  change them only when the user clicks, after confirmation and a backup, and only the copy on the
  user's own data folder: on any other `SIDEFOLK_HOME`, Connect and the `sidefolk` command link write
  stand-ins in `$SIDEFOLK_HOME/agent-configs/` (`IntegrationLocations.forApp`, D86). Keep it that way.
- Live model calls cost the user's quota: keep them rare and tiny; tests use scripted models.
- Every tool runs through `ToolExecutor` (Guard + audit). No side doors.
- Nothing that belongs to an extension is ever built into the app: when an extension hits a limit, add a general
  ability every extension can use, or leave the feature out and say so (the `sidefolk-extension` skill, section 0).
- No fake features: nothing shown as working unless it works.
- Match the surrounding code: small files, comments that explain why, no dead code.
- Commit in coherent milestones without Co-Authored-By trailers.
