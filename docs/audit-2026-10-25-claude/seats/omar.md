# Omar: security, privacy & release engineering

## 1. Seat & method
I've shipped notarized Mac apps with Sparkle and the Tauri updater, and I've done security reviews of developer tools that sit next to AI agents. I read every Rust module that touches the outside world: hooks.rs, mcp.rs, bus.rs, actions.rs, sessions.rs, inside.rs, claude_setup.rs, mcp_setup.rs, journal.rs, prefs.rs, voice.rs and notes.rs. On the frontend I read access.ts and companion.ts, plus the CSP, capabilities, Info.plist, Cargo profile, RELEASE.md and release.sh. I ran the full-access deny-list against 31 command variants in node. Nothing touched port 47821, and I didn't open the other audit's folders.

## 2. First 30 seconds
The Rust core is more careful than I expected after three days of work. It has atomic writes, byte-for-byte backups, a check for files changed under you, a constant-time token compare, AppleScript and shell quoting with tests, and `/dev/*` routes compiled out of release builds. The policy layer on top is a different story. "Full access" is a regex deny-list that only looks at Bash commands, and a public build has no signing, no entitlements, no updater and no way to uninstall. Today I wouldn't let it answer permission prompts on my machine.

## 3. Scores
- **Clarity of purpose: 6.** "A body for your agents" is clear. Reminders, notes and the crew of characters dilute it.
- **Ease of use: 6.** The setup asks for confirmation before each config edit, which is good. Too many switches. (Partly inferred.)
- **Visual quality: 7.** The permission card is calm and shows the folder and the full command (overlay-permission.png).
- **Usefulness to me: 5.** Answering permissions away from the terminal is the killer feature, but I can't trust the full-access path.
- **Trust & safety: 3.** The deny-list is bypassable, file edits and MCP tools are auto-allowed, the port can be squatted, and prompts are journaled.
- **Release readiness: 2.** It has never been signed or notarized. No entitlements, no updater, no uninstall, never run by an outside user.

## 4. Top problems, ranked

**1. Blocker: "Full access" can be bypassed and covers far too little.**
- **What's wrong:** `stillAsk` returns null for anything that isn't a command (src/access.ts:23). Under full access, every Write, Edit, WebFetch and MCP tool call is auto-allowed, including writes to `~/.zshrc`, `.git/hooks/*`, `~/.ssh/authorized_keys` or `~/.claude/settings.json`.
- **Bash coverage is weak:** I ran 31 variants through the exact regexes after the same `clip(…, 2000)`. 26 were auto-allowed, including:
  - `rm --recursive --force ~/proj`, `rm important.db`, `find . -delete`
  - `git push origin +main`, `git -C . push --force`, `git push --delete origin main`, `git -c a=b reset --hard`, `git checkout -- .`
  - `bash <(curl …)`, `curl … | tee f | sh`, `bash -c "$(echo cm0gLXJmIH4= | base64 -d)"`, `python3 -c "shutil.rmtree(…)"`, `r=rm; $r -rf ~`
  - `osascript … with administrator privileges`, `gh repo delete --yes`, `terraform destroy`, `aws s3 rm --recursive`, `psql -c "DELETE …"`
- **Truncation bypass:** the check runs on the clipped detail (hooks.rs:149 clips to 2000 characters). `echo <2000 chars>; rm -rf ~` is auto-allowed because the dangerous tail is cut off before the regex sees it.
- **Easy to grant, hard to revoke:** "Allow everything from this session" is offered on every card when full access is off, even for `rm -rf node_modules …` (overlay-permission.png; companion.ts:204 only hides it when full access is on and the command is risky). One quiet click gives full access, and it persists in localStorage across restarts and `--resume` (access.ts:45-53).
- **Fix:** a deny-list can't be the safety boundary.
  - Replace it with an allow-list policy: read-only tools, plus Edit/Write only when the resolved path is inside the session's git root and not under `.git/` or dotfiles. Bash only from a short allow-list of prefixes (`git status|diff|log`, `npm test`, …). Everything else asks.
  - Better still, hand "full access" to the agents' own modes: Claude's `acceptEdits`/auto mode, which start_session already uses (actions.rs:141), and Codex's sandbox.
  - Never auto-allow a truncated or multi-line command.
  - Full access ends with the session (SessionEnd) and isn't persisted.
  - Remove "Allow everything" from the card and keep it in the Sessions view.

**2. Blocker: no uninstall, and leftovers keep trusting the port.**
- **What's wrong:** removing the app leaves several things behind:
  - Nine HTTP hooks in `~/.claude/settings.json`, including PermissionRequest with a 90 s timeout (hooks/claude-settings.json).
  - MCP entries in `~/.claude.json` and `~/.codex/config.toml` pointing at a deleted binary.
  - A LaunchAgent (main.rs:219, `MacosLauncher::LaunchAgent`).
  - A root-owned `/usr/local/bin/sidefolk` symlink.
  - The data directory.
- **Why it matters:** Claude Code trusts whatever answers on 127.0.0.1:47821. Any unprivileged process that binds the port while Sidefolk isn't running (after uninstall, before launch, after a crash) gets every prompt and tool input, and can answer `{"behavior":"allow"}` to every permission. Decision 21's reasoning ("anyone who could forge could read the token") covers clients spoofing the server. It doesn't cover the server being impersonated.
- **Fix:**
  - Add "Disconnect everything & uninstall…" (tray and Settings) that reverses all five, with backups.
  - Long term, switch to `command` hooks (`sidefolk hook`) talking over a Unix socket in the 0700 data directory. That fails closed when the app is gone, can't be squatted, and lets the token requirement come back.

**3. Blocker: signing, notarization and entitlements have never been run.**
- **What's wrong:** RELEASE.md says "Nothing here has been run yet." There's no `.entitlements` file.
- **Calendar will break:** under the hardened runtime, EventKit needs `com.apple.security.personal-information.calendars`, otherwise the calendar feature silently fails.
- **Automation probably breaks too (inferred, must verify on a notarized build):** driving Terminal and iTerm through osascript (sessions.rs:223,251) likely needs `com.apple.security.automation.apple-events` plus `NSAppleEventsUsageDescription` in Info.plist. Neither is present.
- **Fix:** add the entitlements and usage strings, then run release.sh signed once. Use a `notarytool` keychain profile or an App Store Connect API key instead of `APPLE_PASSWORD` in the environment. Archive dSYMs, because `strip = true` and `panic = "abort"` leave crash.log backtraces without symbols.

**4. Blocker: no auto-update.**
- **What's wrong:** `tauri-plugin-updater` isn't added (RELEASE.md §2). A tool that sits in the permission path must be able to ship a fix to problem 1 within a day.
- **Fix:** add the updater with a signed `latest.json`, keep the private key offline or in a CI secret, and install only with the user's consent. Add a minimum-version kill switch: refuse to answer permissions if the build is known-bad.

**5. Major: what the card shows isn't always what gets approved.**
- **What's wrong:**
  - Edit and Write cards show only the path, never the content or diff (hooks.rs:150-151).
  - "Use X?" for MCP tools shows raw JSON clipped to 2000 characters.
  - Commands are whitespace-collapsed by `clip` (bus.rs:189), which changes the meaning of quoted strings.
  - Bidi and control characters aren't neutralized.
  - In the screenshot, `-rf` and `--` render as dashes (overlay-permission.png; the font's typographic substitution).
- **Fix:**
  - Show the exact bytes: no collapsing, `font-variant-ligatures: none`, visible escapes for U+202A–202E, U+2066–2069 and other control characters.
  - Show a diff preview for edits.
  - If anything was cut, offer only "Answer in Claude's window".

**6. Major: privacy of what gets stored and shown.**
- **What's wrong:**
  - The journal keeps prompts (120 characters), every permission question with the full command up to 2000 characters, and agents' last messages for 30 days in plain JSONL (bus.rs:45, hooks.rs:290, journal.rs). Commands often contain tokens (`curl -H "Authorization: …"`, `export KEY=…`).
  - The PreToolUse hook ships every tool input, including full Write contents, to the app even though it only shows a filename.
  - `hide_in_recordings` defaults to off (settings.rs:68), so permission cards with commands appear in Zoom shares.
  - "Draft a summary" sends a whole notebook to `claude -p` or `codex exec`. It's user-initiated, but the button doesn't say so.
- **Fix:** redact secret-looking strings before journaling, add a history on/off switch and a Clear button, write a one-page privacy statement (what is stored, where, for how long, what leaves the Mac), and label the summary button "Sends this notebook to Claude".

**7. Major: the inside-Sidefolk terminal makes Sidefolk the "responsible process".**
- **What's wrong (inferred from how TCC works):** shells and agent sessions in the PTY (inside.rs:47) inherit Sidefolk's TCC attribution. Prompts read "Sidefolk would like to access Documents", and whatever Sidefolk was granted (Calendars, Automation) is available to every agent running inside it. `pty_write` also lets any page code type into a live `claude` prompt.
- **Fix:** cut it for v1, or launch shells through `/usr/bin/login`-style disclaiming and document it.

**8. Major: the webview is effectively a shell, and the hook server is unauthenticated.**
- **What's good:** I found no XSS sinks. The only `innerHTML` is constant SVG (icons.ts:35,44). The CSP is strict (`default-src 'self'`).
- **What's wrong:**
  - Every custom command is callable from both windows. That includes `run_action` with `background: true`, which runs `$SHELL -lc` with no confirmation (actions.rs:318), plus `pty_write`, `resolve_permission` and `start_session`. One XSS later (in markdown notes or imported character names), that's code execution.
  - Any local process can inject fake events and permission cards, flood the pet, or claim a session_id first so "Open session" focuses the wrong app (sessions.rs:49, first one wins).
  - There's no Host-header check. The Origin check does block browsers, since fetch sends Origin on every POST, and that includes DNS-rebound pages.
- **Fix:** scope commands per window with Tauri's app-command permissions, validate `Host: 127.0.0.1:47821`, and cap open permission cards per session.

**9. Minor: installers, CLI and hold policy.**
- **What's wrong:**
  - The CLI asks for an admin password just to symlink into `/usr/local/bin` (actions.rs:357).
  - The MCP shim is registered at `current_exe()` (mcp_setup.rs:92), so it breaks if the app ran translocated.
  - The defer list (hooks.rs:224) misses WezTerm, which Sidefolk itself supports, so WezTerm users' sessions freeze for 60 s.
- **What's good:** the settings installer canonicalizes symlinks, refuses unexpected shapes and detects concurrent edits.
- **Fix:** use `~/.local/bin`, refuse installers when translocated, and hold only when the user is idle or away.

**10. Minor: Ghostty's execute prompt is bypassed** through `initial input` (sessions.rs:257). That's acceptable only while Sidefolk's own confirmation stays mandatory on every path to `run_in_terminal`.

## 5. Feature verdicts

| Feature | Verdict | Why |
|---|---|---|
| Pip desktop companion | KEEP | The body is the product. |
| Talking by typing (local parser) | REWORK | A "make coffee" → shell suggestion is a footgun. The command path needs a clear prefix. |
| Tell bar in window | KEEP | Same parser, keyboard-first. |
| Reminders | KEEP | Low risk, local. |
| Notes & notebooks | KEEP | Local files, fine. |
| AI "Draft a summary" | LATER | Sends data off-Mac. Needs disclosure first. |
| Quick commands (run in terminal) | REWORK | Keep the confirmation, require an explicit `run …` / `$` prefix. |
| Saved actions | REWORK | Background runs skip confirmation. Confirm the first run. |
| Open app/folder/URL | KEEP | https only, no shell. Well done. |
| Watching Claude Code/Codex | KEEP | Core. Move to command hooks over a Unix socket. |
| Permission requests on companion | REWORK | Exact text, diffs, no Allow on truncated input, hold only when away. |
| Per-session full access | REWORK | Allow-list or the agents' own modes. Ends with the session. |
| Start sessions | KEEP | Maps to the agents' own modes, which is correct. |
| Open/continue session | KEEP | IDs validated, quoting tested. |
| Sparks | LATER | Scope, not safety. |
| Terminal inside Sidefolk | CUT | TCC attribution and keystroke-injection surface. Not v1. |
| Calendar heads-up | REWORK | Needs the entitlement or it's dead on a notarized build. |
| Morning brief | KEEP | Reads the local journal. |
| Weekly wins | LATER | Nice, not needed. |
| Ten characters + 3D/2D | LATER | Size and scope. One character is enough. |
| Make-your-own import | LATER | Untrusted-file parsing surface. |
| Accent colors | KEEP | Harmless. |
| Sounds & voice | KEEP | `say` args are safe, `[[` is escaped. |
| Setup guide | KEEP | The confirmation-and-backup flow is the right pattern. |
| Settings (9 categories) | REWORK | Add Privacy and Uninstall, fold the rest. |
| CLI `sidefolk here` | REWORK | No admin prompt. Use `~/.local/bin`. |
| MCP tools for agents | KEEP | The token-gated path is the best-built part. |
| Dock app + window | KEEP | Fine. |

## 6. What v1 should be
**For** developers running Claude Code or Codex on a Mac. **What it does:** a signed, auto-updating desktop companion that shows what their agents are doing and lets them answer permission requests safely from anywhere on screen, plus reminders and notes.

**Five must-haves**
1. Developer ID signing, notarization, hardened runtime with the correct entitlements and usage strings, and the Tauri updater with offline keys.
2. A one-click "Disconnect & uninstall" that reverses the hooks, MCP entries, LaunchAgent, CLI symlink and data directory.
3. Permission cards that show the exact bytes or a diff, never offer Allow on truncated input, and hold only when the user is away from the agent UI.
4. Full access rebuilt as an allow-list or delegated to the agents' own modes, ending with the session.
5. A privacy page plus history controls: redaction, an off switch, Clear.

**Five must-cuts**
1. The regex deny-list as a safety claim.
2. The inside-Sidefolk PTY terminal.
3. "Allow everything from this session" on the card.
4. Background saved-action runs without confirmation.
5. The admin-password CLI install, along with the character zoo and importer for v1.

**Vote: EVOLVE this codebase.** The Rust core is small, readable and already careful with file edits, quoting and secrets. The problems sit in a few policy files (access.ts, the hook transport, entitlements, the uninstaller) and can be fixed in days. A restart would throw away the best-engineered part to fix the worst-designed part.

## 7. The one thing
I'd love it the day I can leave my desk, see "Claude wants to edit `src/api/auth.ts`" with the diff on the bunny, click Allow, and **know** that "full access" can't quietly approve `git -C . push --force` or a 2001-character `echo` with `rm -rf ~` hidden past the cut. Ship it with today's deny-list and I'll uninstall it the first time I read access.ts.
