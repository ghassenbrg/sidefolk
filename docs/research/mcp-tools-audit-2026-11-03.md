# MCP and in-app tools: the audit, and what a turn costs

The audit behind D156 to D160, on `origin/main a9325036`, with a debug app on its own home and a script speaking real
MCP to `sidefolk mcp`. The page the founder approved is at https://claude.ai/artifact/6Xmq8dQcHPGM5PCMYwcRUN.

## What a turn costs (A12)

One typed request ("move my stretch reminder to 6pm") took a Codex brain 72,007 input and 153 output tokens over 3 steps,
about 24,000 a step. The founder pressed "Answer with Codex" on the debug app's card during the audit, which is how a live
figure came to exist at all.

Measured without any model call, by counting what Sidefolk hands over (bytes, and about 4 bytes to a token):

| What | Bytes | About |
|---|---:|---:|
| The tools offered, 68 of them: names, descriptions, schemas | 43,833 | 11,000 tokens |
| The largest: `watch.report`, `watch.command`, `reminders.create`, `watch.create`, `watch.update` | 3,166 to 1,795 each | |
| What can be reached, the rules and the persona in the prompt | 3,656 | 900 tokens |

So Sidefolk's tool list could be up to about half of each step, if Codex holds all of it in the turn, which wasn't checked:
ARCHITECTURE says Codex doesn't list its tools up front. The rest is Codex's own and the conversation.

**Not known:** how much of it Codex caches and bills less for, and what Claude Code does with the same list. Measuring that
takes live calls, so this stops here. Nothing changed. If it matters, the first thing to look at is the five largest
descriptions, which D116 and D157 have made longer.

## For the next audit batch

Written on `1d9f09a3`, for snapshot 1075 and after.

**A question for the founder: can a task being finished end an important reminder? (D42, D160)** An agent's `reminders.cancel`,
`complete`, `snooze` and `update` never touch an important reminder, and finishing another reminder won't end one beside it
(`ReminderTools`, `wouldEndAnImportantOne`). `notes_update` marking the task done and `notes_trash` have no such check, so
they can still end an important reminder on that task. That's how they worked before D160, under "Change notes": on Ask, a card
that names the note and not the reminder; on Allow, no card. D160 didn't widen this, but the rule now reads as stronger than it
is. The fix, if wanted, is small: the same check in those two tools for an external caller, either refusing or saying on the card
that an important reminder ends with it. A card is the better fit, since it's the person's own task. Sideflow's plans
call the same tools, so its plan rules need a look first.

**`media` and contained: closed.** The gap was `isContained` ignoring `media`, which D141 calls a way out. `79caa352` (T44)
fixed it, with `mediaIsntContained`, and both places that give plans (`ExtensionHost+Actions`) read `isContained` when a step
runs, so a saved plan doesn't keep it. Two things it leaves, neither urgent:
- `isContained` is a list someone has to remember: a new ability counts as contained until it's added, which is how this gap
  came about. A fix: one test that turns on each ability in `ExtensionPermissions` and requires it to be either in the list or in
  a named set of those that stay contained, so a new one fails until someone decides.
- `carriesOut` counts `ai` and `place`, and `isContained` doesn't. SECURITY calls them ways out by design on the drop card; I
  didn't find that written down for plans, and an extension with `events` and `place` hears titles and can send 80 characters
  to the place search. Not tested. It needs one look by whoever owns D129, and a line in SECURITY either way.

**Still limits, from D160.** A card isn't bound to the reminder as it stood: the person's edit while it waits runs under the
card's words. A refusal by whole id says a reminder is important. A rename's card shows the name the agent used, which may be a
loose match. `Redactor` is patterns, so a secret it doesn't know, in a notice's title or a note's title, can reach the model
through `history.recent`; only words shaped like an address are left out, by shape.

**`Redactor` reads what it's given.** `history.recent` found a key split by an invisible character (`sk-ant-\u{200B}…`) going past it, and now cleans first. Other callers pass raw text, so T20's other uses have the same gap. A fix: strip what can't be seen inside `Redactor.redact` itself, with one test, then drop the order here. Also seen, not reachable through a summary, which `ToolExecutor` clips to 240: `redactOpaque` looks quadratic on long non-ASCII text (500 KB, 50 s, debug build), so another caller with long text is worth one look.

**Waiting on someone.**
- A4, Codex's `tool_timeout_sec`, on `team/tools-a4`: needs one tiny live call, with the founder's yes, to learn the default.
- B7, `files.write`: D140 is on main now, so this is only waiting for the founder's yes by name. It must not share `placed`,
  `placing` or `handedOver`.
- B8, web search: not built until the founder chooses a provider and who pays.
- What a turn costs (above): the five largest descriptions are the first place to look, only if it matters.

**Never checked with a real client.** Claude Code or Codex as the client on the new tools, annotations, a cancelled call taking
its card away, the tool list following the app, and the reminder and collection cards on screen. The MCP script and the suite
cover the protocol, not what those clients do with it.
