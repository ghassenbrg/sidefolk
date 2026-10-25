# Leo (seat `leo`): senior backend engineer, core target user

## 1. Seat & method
I run 3–6 Claude Code and Codex sessions a day in Ghostty, iTerm and the Claude desktop app. I've used terminal bells, Claude Code's own Notification hooks and menu-bar monitors. I judged this as a user first: README, docs/GUIDE.md, the chair's screenshots, and my own WebKit Playwright run (scratchpad/council/leo-run.mjs, shots in scratchpad/council/leo-shots/). In that run I put 3 projects in parallel, sent 2 permission requests at once, fired done/failed while a request was waiting, tried 9 agent phrases, the New session form, and the AI tools settings. After that I checked the behaviour in hooks.rs, sessions.rs, access.ts, commands.ts and codex.rs.

## 2. First 30 seconds
"Cute bunny, and the permission card is genuinely good." It shows the full command, the folder, Decline / Allow once, and a way to hand it back to the terminal (overlay-permission.png). Then I read the window: reminders, notebooks, weekly wins, ten characters, make-your-own character. My reaction was "this isn't for me, it's a lifestyle app with an agent tab." The sidebar puts Reminders and Notes above Sessions (full-sessions.png). For me the agent part is the product, and here it is one pillar out of four. Then I opened the code and found the deal-breaker: with my terminal in front, the pet doesn't ask me anything. My terminal is always in front.

## 3. Scores
- **Clarity of purpose: 4.** It pitches "gives AI agents a body," but the app opens on reminders and notes, and the agent features read as a side panel.
- **Ease of use: 6.** The permission and new-session cards are clear. The typed parser is brittle: "start codex in web with fix the flaky test", "ask claude to fix the tests in api", "sessions" and "allow" are all unknown (my run log).
- **Visual quality: 8.** It's calm, polished and readable, and the 3D Pip is charming.
- **Usefulness to me: 4.** Today it misses my main case (terminal frontmost, many tabs), can't see Codex at all, and in Ghostty or Claude desktop it can't jump to the right tab. If those were fixed I'd give it 8.
- **Trust & safety: 5.** Good: config backups, an explained installer, an Origin check on the hook server, MCP calls need a token. Weak: a regex deny-list "full access", a silent 60 s hold on Claude Code, and nine global hooks on every tool call.
- **Release readiness: 2.** It's unsigned, has had almost no real-app hand checks (STATUS.md:327, :329, :356–357), and Codex support is claimed but not there.

## 4. Top problems, ranked

1. **Blocker: requests skip the pet whenever any terminal, editor or the Claude app is in front.**
   - Evidence: `should_hold` returns false when the frontmost app is on the `defer_to_app` list (Ghostty, iTerm, VS Code, Claude desktop…) (hooks.rs:208–245). The settings text says so too (full-settings-tools.png).
   - Why it matters: I'm in Ghostty tab 2 while tab 5 waits. The request stays in tab 5 and Pip says nothing. "Terminal is frontmost" does not mean "the user can see this session."
   - Fix: you already know each session's host app and tty (sessions.rs Host). Defer only when *that session's* tab is the focused one. Otherwise show it on the pet.
2. **Blocker: Codex sessions in a terminal are invisible.**
   - Evidence: the only event sources are the Claude hooks plus MCP. STATUS.md:353 says "Codex CLI sessions in a terminal still ask in Codex (no hook)". `codex::dispatch` is only reachable from the dev endpoint and an unused command (hooks.rs:164, main.rs:160). Yet the sample data shows "Codex · api · Needs you" (light-home.png, light-review.png), so the preview oversells it.
   - Fix: wire Codex's `notify` program (agent-turn-complete) and/or tail `~/.codex/sessions` rollout JSONL for status. If that doesn't make v1, remove "Codex" from the watching claims.
3. **Major: "Open session" doesn't land on the right tab in Ghostty, VS Code or Claude desktop.**
   - Evidence: tty-based tab selection exists only for Terminal and iTerm. Every other app just gets `open -a` and the message "Select your session in its window" (sessions.rs:181–206). With 6 Ghostty tabs, that is exactly the babysitting I want gone.
   - Worse: a live session in tmux/ssh has `app: None`, so it falls through to `claude --resume <id>` in a new window while the original process is still running (sessions.rs:288–300). That means two writers on one session (inferred; not checked against Claude Code).
   - Fix: Ghostty 1.3 has AppleScript (already used at sessions.rs:257); match by tty or cwd. For tmux, run `tmux switch-client`/`select-window` by tty. Never resume a pid that is still alive; say "it's running in tmux on ttysNNN" instead.
4. **Major: holding Claude Code for 60 s can strand me.**
   - Evidence: while the pet holds the PermissionRequest (hooks.rs:22, :272), Claude Code is blocked on the hook and shows no prompt (inferred from hook semantics). If I alt-tab to that tab, I can't answer there until the timeout.
   - Fix: when the session's host app becomes frontmost, auto-resolve with Defer (the frontmost polling already exists).
5. **Major: with many sessions I can't tell them apart.**
   - Evidence: the badge folds everything into "Working · Claude · editing App.tsx +2" with no project name (ov-3projects.png). Sessions are labelled "Work session 04c1" (full-sessions.png), even though the first prompt is already captured (hooks.rs:93, UserPromptSubmit).
   - Fix: label each session as project + first prompt line. On click, the pet shows a compact list ("api · needs you / web · working / docs · done").
   - Sparks also fix identity, but 6 projects means 7 creatures on my desktop.
6. **Major: "Allow everything from this session" is a homemade deny-list.**
   - Evidence: in a running session, every Edit/Write and every command that doesn't match 9 regexes is auto-allowed (access.ts:9–25, companion.ts:177). Regexes that miss obvious cases: `rm --recursive`, `git push origin +main`, `find . -delete`, `xargs rm`, edits to `~/.zshrc` or `.git/hooks`.
   - It also means something different from "Start with full access", which uses Claude's own `--permission-mode auto` (STATUS.md:313).
   - Fix: one meaning. Either flip the session into Claude Code's own mode, or rename it "Auto-allow tests & reads" and use an *allow*-list.
7. **Major: it can't hand work to an agent.**
   - Evidence: the New session form has Tool, Folder and Full access, but no prompt (win-newsession.png). "start codex in web with fix the flaky test" is not understood. So "hand them work" from the pitch isn't delivered.
   - Fix: add a prompt field that runs `claude "<prompt>"` / `codex "<prompt>"` in the chosen terminal.
8. **Minor: a destructive command looks like any other.** The `rm -rf node_modules …` card has the same look, with green Allow once as primary (overlay-permission.png). Reuse `stillAsk` to flag risk and make Decline the default.
9. **Minor: done/failed events are hidden while a request is open.** With a request pending, firing done and failed left only the request card on screen (ov-done-while.png). Queue them behind it.
10. **Minor: footprint and docs.** Nine global HTTP hooks (2 s timeout) fire on every tool call; a hung Sidefolk could stall each one (inferred). README says screen-recording hiding is on by default; GUIDE says off.

**Against what I already have:** Claude Code's Notification hook plus `terminal-notifier`, Ghostty's bell, or Claude desktop's notifications already cover ~70% of "finished / needs you" for free. Sidefolk wins only on (a) answering a permission from anywhere, (b) one click to the *exact* tab, (c) per-session auto-allow. Today (a) is off in my main case, (b) works only in iTerm/Terminal, and (c) is a regex. Fix those three and I'd switch; otherwise my 15-line hook script wins.

## 5. Feature verdicts

| Feature | Verdict | Reason |
|---|---|---|
| Pip desktop companion | KEEP | Glanceable status at the screen edge beats a menu-bar dot, as long as it stays put and quiet. |
| Talking by typing (local parser) | REWORK | Narrow it to agent and session verbs plus reminders. Every miss erodes trust ("make coffee" becomes a shell command). |
| Tell bar in window | CUT | It duplicates the pet's field. Use ⌘K-style search for navigation. |
| Reminders | LATER | Fine, but Raycast/Reminders already do it. It dilutes the agent pitch for v1. |
| Notes & notebooks | CUT | Off-mission for me. Obsidian/Notes exist. |
| AI "Draft a summary" | CUT | A summary of notes is not why anyone installs this. |
| Quick commands (run in terminal) | CUT | I'm already in a terminal. A pet typing shell commands for me adds risk and no value. |
| Saved actions | CUT | Raycast script commands do this better. |
| Open app/folder/URL | CUT | Spotlight/Raycast. |
| Watching Claude Code/Codex sessions | KEEP (REWORK Codex) | This is the core. Add real Codex status and project + prompt labels. |
| Permission requests on the companion | REWORK | The best feature, but it must fire when *that* session isn't the focused tab, and release when I switch to it. |
| Per-session full access | REWORK | One meaning, using the agent's own mode, or an allow-list. No regex deny-list. |
| Start sessions | REWORK | Needs a prompt field. That makes it "hand work." |
| Open/continue session | REWORK | Exact tab in Ghostty/VS Code/Claude desktop/tmux, and never resume a live session. |
| Sparks (per project) | LATER | Good identity idea, but doesn't scale to 6. Ship one pet with a session list first. |
| Terminal inside Sidefolk | CUT | I'll never leave Ghostty. A big surface (PTY) for no gain. |
| Calendar heads-up | LATER | Nice but unrelated. |
| Morning brief | REWORK | Keep only "what your agents finished overnight / what's waiting." |
| Weekly wins | CUT | Fluff for my persona. |
| Ten characters + 3D/2D | LATER | Ship Pip, and maybe one alternative. |
| Make-your-own character import | CUT | Zero value for v1, real maintenance cost. |
| Accent colors | LATER | Only useful once Sparks exist. |
| Sounds & spoken voice | KEEP (one cue) | One distinct "needs you" sound matters. Voice: off by default or cut. |
| Setup guide | KEEP | Short: connect Claude Code, grant Automation, done. |
| Settings (9 categories) | REWORK | 3 sections at most for v1. |
| CLI `sidefolk here` | LATER | Only matters with Sparks. |
| MCP tools for agents | KEEP (`ask`, `notify`) | An agent asking me a real question from anywhere is valuable. Cut `presence` and `spark` for v1. |
| Dock app + window | REWORK | Menu-bar app + pet, plus a single Sessions window. Remove the Dock icon by default. |

## 6. What v1 should be
**For developers running several Claude Code / Codex sessions: a desktop companion that tells you which session needs you, lets you answer its permission request from anywhere, and takes you to that exact tab in one click.**

Must-haves:
1. Per-session routing of requests: defer only when that session's own tab is focused. Auto-release the hold when I switch to it.
2. Exact-tab "Open" for Ghostty, iTerm, Terminal, VS Code, Claude desktop and tmux, and never a second `--resume` of a live session.
3. Real Codex status (notify/rollout), or honestly drop it from v1 claims.
4. A session list on the pet labelled project + first prompt, with clear needs-you / working / done states and one sound for "needs you."
5. Start a session *with a prompt*, and one honest full-access model that reuses the agent's own permission mode.

Must-cuts: Notes + Draft a summary; quick commands, saved actions and open-anything; the terminal inside Sidefolk; make-your-own character and nine of ten characters; weekly wins and the Tell bar.

**Vote: RESTART the UI on this core.** The Rust core is worth keeping: the hook server with Origin check, host discovery by port→lsof→ps→tty, the backup-first installers, the MCP shim and the Codex app-server driver. The window and information architecture are built around a reminders/notes life-organizer. An agent-first product needs a different home screen (sessions first), far fewer concepts, and a pet whose card is a session switcher. That is faster to rebuild small than to prune.

## 7. The one thing
I'm in Ghostty tab 2, session 5 in another project hits a permission prompt, and the pet's ear twitches. I click it, see "api · 'add rate limiting' · Run `npm test`?", press Allow, and keep typing. If I'd rather look, one click lands me on *tab 5*. If it does that reliably with 6 sessions, I'd install it today and tell my team. If it stays quiet because "a terminal is in front," I'll uninstall it on day one.
