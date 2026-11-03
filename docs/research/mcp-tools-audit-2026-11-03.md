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
