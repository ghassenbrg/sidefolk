# CTO round 2 (Marcus, seat `cto`)

All three papers agree on the core:
- B-led for developers, with the ≥30% gate for widening.
- Full access deleted; the request lifecycle and all state move into Rust.
- A fail-closed hook transport.
- Series-based reminders, quick-add with no English turned into shell, and no model in v1.
- One ivory Pip; the terminal, catalog, importer and voice deleted.
- macOS 14+ on Apple Silicon; free; no App Store.

So I only list what changes or what's still disputed.

## 1. Where I now agree and change my position

| Topic | Round 1 | Now | Why |
|---|---|---|---|
| Logo | Redraw it later to match ivory Pip | **Frozen as is.** The ivory character appears wherever Pip speaks. | CPO is right. `creative-design/review-2026-10-24/README.md:24` records the founder's constraint: "keep the current logo exactly". The CEO's redraw breaks it too. |
| Window | Polish and re-plumb | **Re-implement the view layer on the kit**, after P1 | `dashboard.css` (895 lines) and `redesign.css` (149 lines) are two style layers fighting each other. Re-plumbing touches every view anyway, so a rewrite costs only a few more days. |
| Start session | Stable for Claude | **Beta**, with a prompt field and native modes | CPO's middle ground. It's not why people install. |
| Agent work in the log | An automatic, opt-in "Agents" lane | **A one-click "Log it" suggestion**, storing only project + first prompt line | Simpler, nothing to redact, and the log stays in the user's voice. |
| License | Apache-2.0 | **MIT for the code; Pip's art and name reserved** | No engineering difference. |
| Journal | 30 days with redaction | **7 days, first line only, plus Clear** | Less to leak. |
| Accent / scarf | Later | **Stable, but only after P1** | Today every look change reloads the overlay (`main.ts:240,264,269`). Once state lives in Rust, a reload loses nothing. |
| Corpus | 250 phrases | **300, including 50 adversarial** (CPO) | Stricter is better. |
| Settings | 4 sections in the window | A separate ⌘, window is fine (4 or 5 panes) | Cheap once Rust owns the state. |

## 2. Strongest objections

1. **Codex can't be stable in v1 (against the CEO).**
   - Today nothing watches Codex CLI. There is no hook path, and the only driver, `codex.rs`, has no caller.
   - The rollout JSONL files are an internal, undocumented format that changes between versions.
   - `notify` is a turn-complete signal; nobody has shown it can say "needs you".
   - A one-week phase that ends with "Codex goes STABLE" would make the status claim depend on a format we don't own. **Codex stays beta in v1 whatever the spike finds.** It goes stable in v1.x after a version-pinned matrix.

2. **Exact tab in tmux and Ghostty is promised without code (both papers).**
   - `sessions.rs:26` returns no host for tmux. No tmux targeting exists.
   - "switch-client by tty" is two steps: find the client attached to that server, then find and focus the terminal hosting that client.
   - The only Ghostty AppleScript we have opens windows (`sessions.rs:229-259`). Nobody has shown that it reports a terminal's tty.
   - **v1:** tmux shows "running in tmux on ttys004 · Copy attach". Ghostty is bring-forward until a spike proves exact tab. A capability-matrix row is required before any UI says "exact".

3. **The CPO's parallel phases break our own rules.** CPO phase 2 (window rebuild) runs in parallel with phase 1 (trust and state). That rebuilds views on a state layer that's being replaced, and it breaks WIP=1, which all three of us signed. The founder is the only verifier. I adopt the CEO's "at most 2 verifiable items a day", and I sequence it as **P1 state → views**.

4. **The CEO's schedule is about a week short.** CEO phase 1 (2 weeks) holds:
   - moving state into Rust
   - the request lifecycle
   - the socket sidecar
   - raw bytes and diffs
   - routing and focus-release
   - store recovery and schema versions

   My sizing for that content is 13–16 agent-days plus founder checks, so about 3 weeks. I hold my estimate: **7–8 weeks to private beta, 10–11 to public v1.** Scope is the lever, not the date.

5. **Small corrections that matter for engineering:**
   - **"No mutex unwrap under `panic = abort`" (CEO)** is busywork. With abort, a panic kills the process before any lock can be poisoned. Remove `unwrap` on IO and parsing; leave the 96 `lock().unwrap()`.
   - **"Claude behaves exactly as if never installed" (CPO [FIGHT])** is achievable, but only if the hook line is a guarded wrapper: `test -x <sidecar> && exec <sidecar> hook || exit 0`. Otherwise an app dragged to the Bin leaves hook errors on every event. I'm adding this to the spec.
   - **Hold time:** 45 or 60 s are both fine, as long as it stays under the installed 90 s hook timeout (`claude-settings.json`). Today `PERMISSION_WAIT` is 60 s (`hooks.rs:23`).

## 3. Non-negotiables for the CEO's ruling

1. **Sidefolk never auto-answers.**
   - `access.ts` is deleted.
   - Allow is offered only after the whole raw operation has been shown.
   - A request that expired or was released can never become an Allow; Rust's lifecycle enforces this.
   - Risk labels are warnings only and never the policy.
2. **No outside user enables approvals until three things exist:** the fail-closed sidecar on a Unix socket (with the guarded wrapper), Disconnect & uninstall, and the signed updater with its blocked-versions kill switch.
3. **No silent data loss.** `store.rs` quarantines unreadable files and never overwrites them. Each store has corruption tests before beta.
4. **Claims match the verified matrix.** Codex is beta. tmux and Ghostty get exact tab only after a passed spike. Sample and preview data show only real capabilities.
5. **Order and proof.** State moves into Rust before the views are rebuilt. WIP=1. Done means tests plus the founder's dated check with a build hash.

## 4. Factual errors in their papers, checked against the source

| Claim | Source says |
|---|---|
| CEO and CPO: MCP `presence` "goes with Sparks" | False. `mcp.rs:316-322`: `presence` reports whether the user is active, idle or away, from keyboard and mouse idle time. It has nothing to do with Sparks. It's tiny, and it's the signal for "hold when away". **Keep it stable.** |
| CPO: accent colors are "at no cost" | False today. A look change triggers `location.reload()` (`main.ts:264,269`), and that drops any open permission card. It becomes free only after P1. |
| CEO/CPO: tmux exact pane, and Ghostty tty/cwd match | Not implemented, as explained in objection 2. |
| CEO: Codex status through notify + rollout files | No such code exists. The only Codex code is MCP plus the dead `codex.rs`. This is new work and unverified. |
| CEO/CPO: hide from recordings on by default, "cards hold secrets" | The idea is right, but there's a reason it's off: `settings.rs:24-27` says turning it on blanks the overlay in Mission Control. The overlay now covers only the companions (`c2b6544`), so the founder must hand-check that the patch is acceptable before the default flips. |
| CPO: a quit app "keeps firing for about a week" | That's a plan, not a fact. Today `notifications.rs:44` queues **only the next occurrence**, so it's part of the P2 work. |
| CEO: "16 of 16 seats" want full access deleted | Close but not exact. Claude-council Omar voted REWORK (an allow-list or native modes), not delete. The conclusion still stands: no seat defends the deny-list. |
