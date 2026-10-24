# Sidefolk guide

Sidefolk puts a small companion, Pip, on your Mac's desktop. It keeps your reminders and notes,
and if you use Claude Code or Codex it shows what they're doing and brings you their questions.
Everything happens on your Mac; nothing uses AI unless you ask for it.

## Talk to Pip

Click Pip (or right-click) and type. The line under the field says what Enter will do before
anything happens. The same field is at the top of the Sidefolk window ("Tell Pip…").

| Say | What happens |
|---|---|
| remind me tomorrow at 9 to call the bank | A reminder. Pip holds the note when it's due, even after a restart. |
| every weekday at 9 to check mail · every 2 weeks on Friday… | A repeating reminder. Done moves it to the next time. |
| 10 minutes before the call at 3 | A reminder ahead of something. |
| note for evaluation: shipped the login migration | A dated note in that notebook. |
| notes · reminders | Opens the list. |
| ls -la · run npm test in api | A command: you see it and its folder first, then it runs in your terminal. |
| open api in VS Code · open a terminal in api · open github.com | Opens it. |
| save action deploy: npm run deploy in api · then "deploy" | A named action you run by name. |
| start a claude session in api | A new Claude Code (or Codex) session in your terminal. |
| open session · open api session | Brings that work session forward, or continues it. |
| give api a spark · send the api spark home | A worker companion for one project. |
| next meeting | What's next on your calendar (Settings → Calendar turns on the heads-up). |
| rename to Bun · hide · help | |

Every card has ×. Closing a request only hides it: it waits in the window until it's answered.

## The window

Open it from the Dock, the menu bar icon, or "open Sidefolk".

- **Today** (⌘1): what needs you, your work sessions, what's coming up.
- **Reminders** (⌘2, ⌘N for a new one): add, edit, repeat, snooze, history.
- **Notes** (⌘3): notebooks, search, edit, copy as Markdown. "Draft a summary…" asks your own
  Claude Code or Codex to group a notebook by theme; it says what it sends first.
- **Sessions** (⌘4): running and finished sessions, starting new ones, Sparks.
- **Actions** (⌘5): your saved commands and links.
- **Settings** (⌘,): size, look, sounds, privacy, connected tools, shortcut.

## Sparks and your own characters

A Spark looks after one project: it acts out that project's sessions and brings their requests,
in its own color with the project's name under its feet. Pip keeps everything else.

Settings → Your companion → **Make your own…** turns a picture into a companion: save the template,
draw (or generate) your character in its boxes, import it, check the poses, save. Only the first
box is required. It can be Pip's look or any Spark's.

## AI tools (optional)

Settings → Connected tools connects Claude Code and Codex. Each change is explained first and a
backup of their settings is kept.

- Requests come to the companion when you're not in a terminal or editor.
- **Full access** per session (the "Asks first" button next to it): requests are allowed without
  asking, except risky ones like `rm -rf`, `sudo` or a force push.
- `sidefolk here --name Backend` in a terminal gives that project a Spark (Settings → Connected
  tools → Command line tool installs the command).

## Privacy

Your companion, reminders, notes, characters and logs stay in
`~/Library/Application Support/dev.sidefolk.companion`. "Hide from screen recordings" keeps the
companion out of screen sharing; while it's on, Mission Control's desktop previews go black, so
it's off by default.

## Something wrong?

Settings → About and help → **Copy report**, add what happened, and send it. It contains versions,
settings and recent errors, never your reminders, notes or names.
