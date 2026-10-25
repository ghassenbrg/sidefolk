# Elena — principal engineer / architect

## 1. Seat & method
20 years shipping Mac and Tauri/Electron apps; I decide whether this code can carry a public v1. I read src-tauri/src (all 24 modules, closely: main, hooks, bus, prefs, settings, crew, sessions, codex, inside, notes, actions, mcp), src/commands.ts, when.ts, access.ts, companion.ts, main.ts and dashboard/app.ts. I ran typecheck, vitest and cargo test, and ran two probes from scratchpad/council/elena-probe/ (the full-access regexes and the date parser, using the repo's own code). I also read RELEASE.md, STATUS/DECISIONS and two screenshots. I did not open any audit-2026-10-25 or output/playwright folders.

## 2. First 30 seconds
The Rust core is better than I expected for something built in three days. Files are written atomically with fsync and 0600 permissions (settings.rs:131). The installers back up configs before changing them. Finding which app hosts a Claude session (lsof, then a walk up the process tree) is clever, and the unit tests are honest. The layer above it is a different story. Every pivot left its own words behind: pet 235 times, companion 231, crew 93, look 86, Spark 97, worker 86, Familiar 22. The truth about what is happening lives in a webview that reloads itself when you change its colour. And "full access" is a homemade denylist of 9 regexes standing between an agent and your disk. I can build on this core, but I would not ship it as it is.

## 3. Scores
- **Clarity of purpose: 4.** The code still describes itself as "A 3D familiar" (Cargo.toml) and "A crew of 3D desktop pets" (tauri.conf.json longDescription). AGENTS.md still says three.js, which was removed.
- **Ease of use: 5.** The date parser itself is good, but the routing in front of it sends everyday phrases to "unknown" or to "run" (§4 #6).
- **Visual quality: 7.** light-home.png and overlay-permission.png are clean and consistent with the design tokens.
- **Usefulness to me: 6.** Bringing hook-based permission requests to wherever I am is real value. Most other features duplicate apps I already have.
- **Trust & safety: 3.** The full-access bypasses are proven (§4 #1), the hook endpoint has no authentication, and the app is unsigned.
- **Release readiness: 2.** No signing and no updater, and RELEASE.md itself says "Nothing here has been run yet". A corrupt settings file stops the app from launching. Most features have never been checked by hand in the real app.

## 4. Top problems, ranked

1. **Blocker: "Full access" auto-allows anything that isn't on a bypassable denylist.**
   - **What:** companion.ts:174 auto-answers "allow" when `stillAsk` returns null. `stillAsk` only looks at the `command` kind, so file writes, web fetches and MCP tools are never checked.
   - **Evidence:** my probe of access.ts. Auto-allowed: `rm --recursive --force src`, `find . -delete`, `git push origin +main`, `python3 -c "shutil.rmtree('src')"`, `curl … -o i.sh && sh i.sh`, `git checkout -- .`, `truncate -s0 db.sqlite`, `echo x > ~/.zshrc`. Also auto-allowed: writes to `~/.zshrc` and `.git/hooks/pre-commit`, web fetches to any URL, and any MCP tool. The card offers "Allow everything from this session" directly under an `rm -rf` (overlay-permission.png).
   - **Fix:** cut it. If the feature must stay, hand off to the agent's own modes (start_session already uses Claude's `--permission-mode auto` and Codex's sandbox). Never maintain a homemade classifier.

2. **Blocker: no distribution pipeline.**
   - **What:** the app is unsigned and not notarized, with no updater and no CI. scripts/release.sh has never run.
   - **Evidence:** docs/RELEASE.md, steps 1–2. `macOSPrivateApi` rules out the Mac App Store.
   - **Fix:** Developer ID signing, notarization and tauri-plugin-updater, plus a GitHub Actions macOS build that runs all the checks.

3. **Major: the webview, not the core, owns the domain state.**
   - **What:** open requests (`Companion.requests`), full-access state (overlay localStorage, access.ts:5), live sessions and Spark workers all live in the overlay page. Rust stores the status as an untyped `serde_json::Value`, and the window receives it as a 1-second polled snapshot (main.ts:321, prefs.rs:303).
   - **What breaks:** the overlay calls `location.reload()` whenever look, colour, size or art style changes (main.ts:240, 264, 269). Any open permission card then vanishes from both the overlay and the window, while Claude waits up to 60 s.
   - **Also:** crew.json is an untyped `Value` whose schema exists only in TypeScript (main.ts:76–83), and no data file carries a schema version, even though crew.json and settings have been reshaped many times.
   - **Fix:** move requests, sessions, access and workers into typed Rust structs with versioned files and migrations. Both webviews then just subscribe.

4. **Major: launch and runtime are fragile.**
   - **Corrupt settings stop the app from launching:** `Store::load` passes a JSON error straight up (settings.rs:94). Then main.rs:337 `.expect("Sidefolk failed to start")` fires, and with `panic = "abort"` one bad byte in settings.json means the app never starts.
   - **No single-instance guard:** two launches give two overlays.
   - **Fixed port 47821, no warning on failure:** if the bind fails, it is only logged with `eprintln` (hooks.rs:49), and every agent feature goes dead with no message to the user.
   - **No authentication on the hooks:** `/claude/event` and `/claude/permission` have no token (decision 21), while `/mcp/call` does.
   - **Fix:** move a corrupt file aside and start from defaults, add the single-instance plugin, show the port conflict in the UI, and put a per-install secret in the hook URL.

5. **Major: blocking work on the main thread.**
   - **What:** about 50 of the 74 Tauri commands are synchronous, so they run on the main thread.
   - **Worst case:** the window refreshes every 3 s (dashboard/app.ts:326) and each refresh calls `integrations`. That reads and parses `~/.claude.json` and `~/.codex/config.toml` from disk every 3 s (mcp_setup.rs:52). (inferred: `~/.claude.json` can grow to several MB.)
   - **Other cases:** `voices()` spawns `say -v ?`; `save_character` sends base64 PNGs over IPC; draft_summary waits on claude/codex with no timeout (notes.rs:293).
   - **Fix:** make these commands async, cache by file mtime, and push events instead of polling.

6. **Major: the parser's routing has bugs, but the grammar idea is right.**
   - **The date engine works:** my probe shows chrono already gets "call mom at 5pm" → today 17:00 and "dentist friday 3pm" → Fri 30 Oct 15:00.
   - **Routing gate:** the last line of `parse()` only tries a reminder when the text starts with today, tomorrow, in N, every…
   - **"at 3" bug:** when.ts uses `forwardDate` before `workingHours`, so "at 3" becomes 03:00 tomorrow and then 15:00 tomorrow. That is the 14:50-tomorrow bug the chair hit.
   - **Second time dropped:** only `results[0]` is used, so the "9:30" in "tomorrow standup 9:30" is lost.
   - **"make coffee" runs as a command:** `make` is in `EVERYDAY`, and the guard against a following English word doesn't cover "coffee".
   - **Fix:** about four small fixes, plus a corpus of 200+ everyday phrases as a test (today: 7 tests in commands.test.ts, 19 in when.test.ts).
   - **Model fallback, my answer:** keep a deterministic grammar for anything that acts (run, start, open), because it must be predictable. Add an *on-device* fallback (Apple Foundation Models on macOS 26, guided generation into the same typed `Command` union) only for the "unknown" bucket, and always show a confirm card. Never fall back to a cloud LLM without asking. It costs quota and breaks the "no tokens" promise.

7. **Major: dead code and leftovers from the pivots.**
   - **Codex driver:** codex.rs (399 lines, the app-server driver) is reachable only through the `dispatch` command, which no TypeScript calls, and through a debug endpoint. README.md:107 still says "used again in phase 6".
   - **Old names in identifiers:** crew.rs/crew.json, `save_pet`, `pet_action`, `pets[]` in the status payload, the `Familiar` class.
   - **One build warning:** unused `first` at notes.rs:350.
   - **Fix:** delete what is dead and rename to one vocabulary.

8. **Major: the tests only cover pure functions.**
   - **What exists:** 100 vitest tests in 13 files (300 ms) and 34 Rust unit tests (3 ignored).
   - **What's missing:** zero tests for the hook HTTP flow, permission timeout and defer, the overlay↔window protocol, or the installers against real configs (the installer tests are ignored).
   - **Real app:** agents can't see the screen, so most features are hand checks still waiting on the founder (STATUS "Blocked on the user").
   - **Fix:** run the axum router in-process with fake hook payloads, test requests surviving an overlay reload, and keep a human release checklist.

9. **Minor: process debt.**
   - 65 commits, 53 of them on 24 Oct.
   - The history adds +55,533 and deletes −27,314 lines: about half of everything written was later thrown away.
   - memory/STATUS.md is 553 lines of interleaved, partly contradictory entries from two agents.
   - **Fix:** freeze scope and keep one owner per area.

10. **Minor: loose ends.**
    - **Terminal buffer:** the kept PTY buffer is trimmed in the middle of escape sequences (inside.rs).
    - **Lost logs:** 20 `eprintln` calls go nowhere in a release GUI build.
    - **Good:** local crash.log and page.log plus the "Copy report" button (prefs.rs).
    - **Fix:** add an opt-in crash upload later, never by default.

**Hard numbers:**
- **Size:** 15,828 lines in 86 files: TypeScript 7,412 + 643 test lines, Rust 6,201, CSS 1,572.
- **Panics:** 113 non-test `unwrap()`s, 96 of them `lock().unwrap()` (acceptable with `panic=abort`), plus 5 `expect`s.
- **CPU:** 16.9% (three.js) → 8.7% → about 1.3% today with sprites (PHASE1.md, RELEASE.md). That is fine.
- **App size:** 8.6 MB, of which 5.2 MB is crew art (321 files in public/).
- **Checks:** typecheck clean, vitest 100/100, cargo 34 passed + 3 ignored, 1 warning.

## 5. Feature verdicts
| Feature | Verdict | Why |
|---|---|---|
| Pip desktop companion | KEEP | Sprites cost about 1.3% CPU; it is the product's face |
| Talking by typing (parser) | REWORK | Four routing bugs, a phrase corpus, and an on-device fallback for unknown text only |
| Tell bar in window | KEEP | Same parser, one code path |
| Reminders | KEEP | Solid store and native scheduling; needs the hand checks |
| Notes & notebooks | KEEP | Plain Markdown files: portable, cheap, done well |
| AI "Draft a summary" | LATER | Spawns a CLI with no timeout and spends quota |
| Quick commands | REWORK | Require `$`/`run` or flags; never guess "make coffee" |
| Saved actions | LATER | Not core to v1 |
| Open app/folder/URL | KEEP | Small and safe |
| Watching Claude Code/Codex | KEEP | The differentiator; the hooks code is sound |
| Permission requests on companion | REWORK | Move the state into Rust so requests survive reloads |
| Per-session full access | CUT | Bypassable denylist (§4 #1) |
| Start sessions | KEEP | Uses the agents' own safe modes |
| Open/continue session | KEEP | Clever host detection; hand-check every terminal |
| Sparks | LATER | Second companion, more state; earn it first |
| Terminal inside Sidefolk | CUT | PTY + xterm competes with real terminals; 326 lines plus a dependency |
| Calendar heads-up | LATER | EventKit permission request is extra friction in v1 |
| Morning brief | LATER | Nice, but depends on the journal |
| Weekly wins | CUT | Off-mission |
| Ten characters + 3D/2D | CUT | 5.2 MB, and changing them reloads the overlay; ship one |
| Make-your-own import | CUT | 698 lines of image code for no v1 value |
| Accent colors | LATER | Cosmetic, and it triggers a reload |
| Sounds & spoken voice | LATER | Cut voice, keep 2–3 sounds |
| Setup guide | KEEP | Must install the hooks and verify a test request end to end |
| Settings (9 categories) | REWORK | Three categories at most |
| CLI `sidefolk here` | LATER | Needs an admin prompt and a symlink; depends on Sparks |
| MCP tools | KEEP | Token-protected and small; keep notify, ask and remind |
| Dock app + window | KEEP | A real Mac app is expected |

## 6. What v1 should be
**For developers running Claude Code or Codex on a Mac: a quiet desktop companion that shows what your agents are doing, brings their permission requests to you wherever you are, and takes quick reminders and notes. Local, free and signed.**

**Must-haves:**
1. Signed, notarized and auto-updating, built by CI.
2. Domain state in Rust, with typed, versioned files and loading that survives a corrupt file. Single instance, and a visible warning on a port conflict.
3. A permission flow that cannot be lost by a reload, with a hook secret and no homemade auto-allow.
4. A parser that passes 95% or more of a 200-phrase corpus, confirming before it acts.
5. A setup guide that installs the hooks with a backup and proves the round-trip.

**Must-cuts:**
1. Per-session full access.
2. The terminal inside Sidefolk.
3. The crew, the 3D/2D styles and the character importer.
4. The dead codex.rs driver.
5. Weekly wins and spoken voice.

**Vote: RESTART THE UI ON THIS CORE.** Keep about 70% of the Rust: hooks, sessions, settings and atomic writes, reminders, notifications, notes, mcp, installers, overlay/panel. Keep the pure TypeScript modules too (when.ts, commands.ts after the fixes, frame.ts, pip.ts). Re-layer so the webviews only display state and Rust owns it. Then rebuild the window (about 3,000 lines today) on the existing tokens as a view driven by pushed events, not a 3-second poll. A full restart would throw away the hard Mac integration work (NSPanel, lsof host walk, Ghostty AppleScript, UNUserNotifications, EventKit) for nothing.

**Engineering before public v1 (about 4–6 engineer-weeks):**
- State into Rust plus a versioned schema and migrations: 4–6 days.
- Window rebuild on events: 5–8 days.
- Robustness (async commands, timeouts, corrupt-file handling, single instance, port check): 2–3 days.
- Security (cut full access, hook secret): 1–2 days.
- Parser fixes plus corpus: 3 days, and +3 for the Foundation Models fallback.
- Signing, updater and CI: 2–3 days once the keys exist.
- Delete about 1,800 lines (codex.rs 399, inside.rs + terminal.ts 326, characters.rs + character-import.ts + dashboard/characters.ts 698, recolor 59, voice.rs 75, calendar.rs + calendar.ts 240), and park about 500 more.
- A hand-check matrix on a real Mac, then 3–5 outside developers for two weeks.

## 7. The one thing
**Love:** any agent's permission request reaches me in under a second wherever I am, and I can *prove* Sidefolk never approves anything I didn't. **Uninstall:** a force-push or `rm --recursive` goes through because I once clicked "Allow everything from this session".
