# Priya, Head of Product

## 1. Seat & method
I own positioning, audience, scope and the roadmap. I read README, GUIDE, PLAN-V2, DECISIONS, STATUS, the git log and key screenshots, checked a few source lines, and searched the web for the late-2026 market in agent monitors and desktop pets.

## 2. First 30 seconds
It looks good: the bunny is charming, the window is calm (light-home.png), and the permission card is clear (overlay-permission.png). Then I couldn't say what it is in one sentence. It's a reminders app, notes app, launcher, terminal, agent monitor, character studio and morning-brief bot. Several products at 10% each, and no user has touched any of them. The problem is the scope, and the process that keeps growing it, not the code.

## 3. Scores
- **Clarity of purpose: 3.** README, GUIDE and PLAN all lead with "for everyone", but every strong part (hooks, permissions, sessions) is for developers only.
- **Ease of use: 5.** The window is clean, but there are two typing surfaces, nine settings categories, Pip, Sparks, crew, styles and accents, and the parser fails on everyday phrases (BRIEF parser list).
- **Visual quality: 7.** The tokens are consistent, both themes work and the mascot is lovable. The characters screen is a developer form, not a product (light-characters.png).
- **Usefulness to me: 4.** I run 2–4 agent sessions. "Needs you" plus open-session is what I'd want, and it's unverified in the real app.
- **Trust & safety: 5.** Good: the confirm-and-backup installers, the full command shown, local-first storage. Bad: unsigned, "make coffee" offered as a shell command (overlay-make-coffee-reply.png), and "Allow everything from this session" sits one tap from Allow.
- **Release readiness: 2.** No signing, no auto-update, no outside user, no LICENSE file, and most features say "hand checks pending" (STATUS.md:484–523, PLAN-V2:322–327).

## 4. Top problems, ranked
1. **Blocker: no chosen user.** PLAN-V2 principle 7 ("Works for everyone") doubled the scope. Non-technical users fail at the first sentence ("call mom at 5pm" and "dentist friday 3pm" aren't understood), and Apple Reminders plus Siri already does this on the phone. **Fix:** v1 is for developers who run AI agents. Reminders and notes stay only where they serve that person.
2. **Blocker: "done" means "built", not "works".** PLAN-V2 §9 requires a demo on the Mac before the next pillar starts. Phases 3→9 were committed between 14:44 and 18:50 on 24 Oct (git log), all "✓ built (hand checks pending)". That repeats the failure the plan itself named (PLAN-V2:60–65). **Fix:** a feature counts as shipped only with a dated real-app check recorded.
3. **Blocker: it can't be installed by a stranger.** It's unsigned, has no updater, and has had no outside user. **Fix:** do phase 8 before any new feature.
4. **Major: the wedge is commoditized.** The category is crowded: Vibe Island ($19.99), Notchcode, Hawky, AgentBoy, Navi (Affirm), Claude Island, VibePet, Chatnimal ($5.99 pet), Minnie (a 3D pet that approves commands in a speech bubble), OpenPets (~939 stars). **The Codex app ships its own pets**, which show running, waiting and ready states. A pet that shows agent status is table stakes. **Fix:** differentiate on reliability, jumping to the exact session, and a work log built from agent outcomes (§6).
5. **Major: the scope churns against its own plan.** PLAN-V2:284–287 parks "more characters and styles, photo-to-companion" as "Not now". About four hours later DECISIONS #38 added ten characters, 3D/2D styles and make-your-own import. Blender film assets are staged in git right now (git status). **Fix:** apply the guardrails below.
6. **Major: unknown text falls through to the shell.** Any first word that isn't recognised can become "Run this in your terminal?" ("make coffee"). Non-technical users will be confused and developers won't trust it. **Fix:** treat text as a command only when it's an explicit `run …`/`$ …` or its first word is an executable on PATH. Otherwise reply "I didn't get that" with suggestions.
7. **Major: reminders aren't reliable enough to be #1.** Start at login is off by default (settings.ts:277, light-settings.png "Turn on"), though PLAN-V2:177 says it should be the default. "tomorrow standup 9:30" → 9:00. "meeting at 3, remind me 10 minutes before" → tomorrow. **Fix:** turn login on in setup, cover these cases in the parser and its tests, and stop pitching reminders as the headline.
8. **Major: too many concepts again:** Pip, Sparks, 10 characters × 2 styles, accents, two typing surfaces, Actions, Terminal, 9 settings categories. That's the "maze" PLAN-V2 §2 diagnosed a day earlier.
9. **Minor: STATUS.md is rotting.** It's ~600 lines, and its hand-check list still names removed features (STATUS:490–504, "pick Professional… Slate replaces the bunny").
10. **Minor: no LICENSE file.** "Open source?" is still undecided, which blocks a Homebrew cask and community trust.

## 5. Feature verdicts
| Feature | Verdict | Reason |
|---|---|---|
| Pip desktop companion | KEEP | It's the brand and the visual difference from notch/menu bar monitors. One character, polished. |
| Talking by typing (local parser) | REWORK | Narrow it to the phrases that work, show autocomplete, and never fall through to the shell. |
| Tell bar in window | CUT | A second typing surface. The window should use buttons. |
| Reminders | KEEP | Narrowed: one-off, simple repeats, plus "remind me when api finishes". |
| Notes & notebooks | REWORK | Becomes the **Work log**: entries per project, auto-suggested from finished sessions, plus "note: …". |
| AI "Draft a summary" | LATER | Prove the logging habit first. Markdown export covers v1. |
| Quick commands (run in terminal) | CUT | Developers are already in a terminal, and the heuristic is a trust risk. |
| Saved actions | CUT | Shell aliases and Raycast do this better. |
| Open app/folder/URL | CUT | Spotlight and Raycast. Keep only "open session/project". |
| Watching Claude Code/Codex sessions | KEEP | The core of the product. |
| Permission requests on the companion | KEEP | The acute pain that gets people to install. Must be bulletproof. |
| Per-session full access | REWORK | Only set the agent's own native modes, clearly labelled. No Sidefolk-side auto-allow. |
| Start sessions | LATER | Nice, but not why people install. |
| Open/continue session | KEEP | The reason to click. Verify on each terminal, with honest fallbacks. |
| Sparks (worker companions per project) | LATER | v1: project color and name on Pip's card. Sparks come back if beta users run 3+ sessions and ask. |
| Terminal inside Sidefolk | CUT | We'd be building a terminal and competing with the user's own. |
| Calendar heads-up | LATER | Off-wedge. |
| Morning brief | LATER | Fold into "welcome back: what your agents finished". |
| Weekly wins | KEEP | The retention loop, built from the work log. |
| Ten characters + 3D/2D styles | CUT (v1) | Not now, as the plan said. Return later as a cosmetic pack. |
| Make-your-own character import | LATER | Creator feature for v2 or a paid tier. |
| Accent colors | CUT | Customization before value. |
| Sounds & spoken voice | REWORK | Keep one subtle "needs you" chime. Babble off by default, cut `say`. |
| Setup guide | KEEP | Rework so step 1 is "connect Claude Code/Codex", with a live test request. |
| Settings (9 categories) | REWORK | Four: General, Agents, Companion, Privacy. |
| CLI `sidefolk here` | LATER | Goes with Sparks. |
| MCP tools for agents | KEEP | notify/ask/remind only; spark/presence later. Agents pinging you is a real differentiator. |
| Dock app + window | KEEP | The window holds Today, Sessions, Work log and Reminders. Offer menu-bar-only. |

## 6. What v1 should be
**Sidefolk v1 is for Mac developers who run several Claude Code / Codex sessions at once. It's a calm companion that tells you which session needs you, lets you answer or land in that exact session, and turns what your agents finished into a work log you can hand your manager on Friday.**

Can one product serve both? Not at v1. Even the founder's own "non-technical" example, a brag doc for performance reviews, is a developer habit. Expand only if ≥30% of weekly actives use reminders or notes with no agent connected.

**Wedge.** People install it so they never miss a waiting agent and can answer without hunting for the tab. They keep it because their agents' work becomes their brag doc: it compounds, it's plain Markdown, and no competitor I found does it (inferred). Reminders make it a daily habit.

**Is the 4-pillar MVP right?** No. It's four products of equal weight. Make it one pillar (agent attention) with two satellites (work log, reminders), and cut Quick actions.

**Must-haves**
1. Bulletproof needs-you/permission flow for Claude Code and Codex: one-click install and uninstall with backups, a test request in setup, and zero wrong-session approvals.
2. Open/continue the exact session, verified on the five main terminals plus Claude desktop. Where only "bring app forward" is possible, say so.
3. Work log: finished-session outcomes suggested as dated entries per project, "note: …" capture, Friday weekly wins, Markdown export.
4. Reminders that always fire (hidden, quit, after sleep), start at login on, plus "remind me when <project> finishes".
5. Signed, notarized, auto-updating, Homebrew cask, opt-in crash reports, under 3% CPU idle on screen.

**Must-cuts:** quick commands, saved actions and open-anything · the in-app Terminal · the ten characters, 3D/2D, import and accents · the Tell bar, calendar and morning brief · Sparks, start-session and the CLI (to v1.1+).

**Vote: EVOLVE this codebase.** The Rust core, hook server, installers with backups, session locator and design tokens are the asset (PLAN-V2:71–75 says the same). The failure is scope and process, not code. A restart would rerun the same process and arrive at the same zoo. Condition: cut code by deleting it (tagged in git), not by hiding it behind settings.

**Process guardrails the council should impose**
1. **A frozen v1 list.** Anything new needs a dated DECISIONS entry naming what it displaces (one in, one out) and a 24-hour wait. "The user asked" is a reason to write it down, not to build it the same hour.
2. **WIP = 1.** Done means the founder's real-app check is recorded with a date. Agents build faster than the founder can verify, so size each day's work to what can be verified.
3. **Art freeze** until v1 ships, Pip polish excepted.
4. **Outside users before new features:** 5 in week 1, 20 by week 4. A weekly metrics review picks the next item.
5. **STATUS.md is rewritten, not appended:** 150 lines or fewer.

**Pricing & distribution.** Most monitors are free and open source, paid ones cost $6–20 one-time, and Codex gives pets away. v1 should be **free and MIT-licensed**, distributed as a signed DMG plus a Homebrew cask with Tauri's updater. **Not the Mac App Store:** its sandbox would very likely block the hook installer, AppleScript to terminals, lsof and launching shells (inferred). Any later revenue could come from a one-time cosmetic pack of characters and make-your-own (~$15), the natural paid home for the zoo. Optimize v1 for adoption and trust.

**Roadmap after v1**
- **v1.0 private beta (weeks 0–4, 10–20 developers).** Success: ≥70% connect an agent during setup. ≥60% answer a request via Pip on day 1. D7 retention (app running) ≥40%, D30 ≥25%. Open-session success ≥95% (logged locally, opt-in). Zero wrong-session approvals. CPU <3%.
- **v1.1 public launch (~weeks 5–8: Show HN, r/ClaudeAI, Product Hunt).** Add AI weekly-wins draft via the user's own CLI and project colors on cards. Success: 1,000 installs, ≥30% of weekly actives open weekly wins, under 1 crash report per 100 users per week.
- **v1.2 (weeks 9–14).** More agents (Gemini CLI, OpenCode, Cursor), start sessions, Sparks if asked for. Success: ≥25% run 2+ agent types, D30 ≥30%.
- **v2.** A character pack, team features, non-technical users only if the gate is met.

## 7. The one thing
Love: with four sessions running, Pip tells me which one is stuck, one click lands in the right tab every time, and on Friday it hands me a dated list of what I shipped. Uninstall: the first wrong session opened, wrong project approved, or reminder that silently doesn't fire. Reliability at those three moments matters more than all ten characters.

Sources: vibeisland.app/alternatives · vibecoding.app/blog/vibe-island-review · learn.chatgpt.com/docs/reference/settings (Codex pets) · hongkiat.com/blog/codex-pets-custom-hatch-guide · Product Hunt listings for Minnie, Chatnimal, VibePet · alternativeto.net (Hawky, Claude Island) · Affirm Navi · OpenPets (sourcepulse) · Notchcode (hunted.space).
