# Sidefolk guide

Sidefolk puts Pip, a small companion, on your Mac's desktop (or Spark, the robot: Settings →
Companion). Pip holds your reminders and a dated
log of what you got done. If you use Claude Code, Pip also taps you when a session needs you and
takes you back to it. Everything stays on your Mac, and nothing uses AI unless you ask for it.

## Talk to Pip

Click Pip and type. The same field is at the top of the Sidefolk window. The line under the field
says what Enter will do before anything happens.

| Say | What happens |
|---|---|
| remind me tomorrow at 9 to call the bank | A reminder. Pip holds the note when it's due, even after a restart. |
| every weekday at 9 to check mail · every 2 weeks on Friday… | A repeating reminder. |
| 10 minutes before the call at 3 | A reminder ahead of something. |
| note for evaluation: shipped the login migration | A dated note in that notebook. |
| note: idea for the landing page | A dated note; Pip asks which notebook. |
| notes · reminders | Opens the list. |
| open api in VS Code · open a terminal in api · open github.com | Opens it. |
| open session · open api session | Brings that Claude Code session forward, or continues it. |
| rename to Bun · hide · help | |

**Commands (Labs).** With Settings → General → Labs → Commands on, text that starts with `$` is
a command: `$ npm test in api`. You see the exact command and its folder first, then it opens in
your terminal. Plain sentences never run as commands.

**Starting sessions (Labs).** With Settings → General → Labs → Start sessions on, "start a claude
session in api" opens a new Claude Code (or Codex) session in your terminal.

Every card has ×. Closing a request only hides it; it waits in the window until it's answered.

## The window

Open it from the Dock, the menu bar icon, or "open Sidefolk".

- **Today** (⌘1): what needs you, your work sessions, what's coming up.
- **Reminders** (⌘2, ⌘N for a new one): add, edit, repeat, snooze, history.
- **Notes** (⌘3): notebooks, search, edit, copy as Markdown.
- **Sessions** (⌘4): running and finished Claude Code sessions. It appears once Claude Code is
  connected.
- **Settings** (⌘,): searchable categories. **Appearance → Theme** offers System (the default),
  Light and Dark.

## Claude Code (optional)

Settings → AI tools connects Claude Code. Each change is explained first, and a backup of its
settings is kept.

- When a session asks for permission and you aren't in a terminal or editor, Pip shows the request:
  the full command and folder, then Decline, Allow once, or Answer in Claude's window. Pip never
  answers on its own.
- When a session finishes or fails, Pip says so once.
- "Open" brings the session forward. In Terminal and iTerm it selects its tab; other apps come
  forward, and you pick the session there.
- Codex: its companion tools (notes, questions, reminders) can be connected too. Watching Codex
  sessions is not available yet.

## Privacy

Your companion, reminders, notes and logs stay in
`~/Library/Application Support/dev.sidefolk.companion`. "Hide from screen recordings" keeps Pip
out of screen sharing. While it's on, Mission Control shows a dark patch where Pip stands, so it's
off by default.

## Something wrong?

Settings → About & data → **Copy report**, add what happened, and send it. The report contains
versions, settings and recent errors, never your reminders, notes or names.
