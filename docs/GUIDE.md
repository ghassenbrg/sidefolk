# Sidefolk guide

Sidefolk puts Pip, a small companion, on your Mac's desktop (or Spark, the robot: Settings →
Companion). Pip holds your reminders and a dated
log of what you got done. If you use Claude Code, Pip also taps you when a session needs you and
takes you back to it. Everything stays on your Mac, and nothing uses AI unless you ask for it.

## Talk to Pip

Click Pip and type. The same field is at the top of the Sidefolk window, and works there with Pip
hidden. The line under the field says what Enter will do before anything happens.

| Say | What happens |
|---|---|
| remind me tomorrow at 9 to call the bank · call mom at 5pm · dentist thu 2:30 | A reminder: anything with a time or a date is one. You see the time before it's saved. |
| send the report at 9 | When an hour could mean two things (9 tonight or 9 tomorrow morning), you pick. |
| tonight · end of day · tomorrow morning · this afternoon | 8 PM · 5 PM · 9 AM · 3 PM. |
| every weekday at 9 to check mail · every 2 weeks on Friday · every Monday and Thursday at 7 | A repeating reminder: it comes back on schedule whether or not you answered the last one. |
| 10 minutes before the call at 3 | A reminder ahead of something. |
| note: idea for the landing page · log shipped the release | A dated note in your Log. |
| note for evaluation: shipped the login migration | A dated note in that notebook. If no notebook has exactly that name, Pip asks (and keeps your text). |
| notes · reminders | Opens the list. |
| open api in VS Code · open a terminal in api · open github.com | Opens it. |
| open session · open api session | Brings that Claude Code session forward, or continues it. |
| rename to Bun · hide · help | |
| hi · thanks · good night | A word back. |
| anything else | Offered as a note in your Log, never sent anywhere. |

**Commands (Labs).** With Settings → General → Labs → Commands on, text that starts with `$` is
a command: `$ npm test in api`. You see the exact command and its folder first, then it opens in
your terminal. Plain sentences never run as commands.

**Starting sessions (Labs).** With Settings → General → Labs → Start sessions on, "start a claude
session in api" opens a new Claude Code (or Codex) session in your terminal.

Every card has ×. Closing a request only hides it; it waits in the window until it's answered.
The summon shortcut (⌘⇧Space by default) focuses Quick add; pressing it again keeps your draft.
⌘⇧Return focuses the newest card without choosing an answer. Escape returns keyboard focus.
In the window, Undo stays until you use or dismiss it, including after navigation. ⌘Z invokes the
latest Undo outside a text field; inside a field it keeps the usual text-editing meaning.
Closing or reloading the window ends that window’s Undo stack.

## The window

Open it from the Dock, the menu bar icon, or "open Sidefolk".

- **Today** (⌘1): what needs you, your work sessions, what's coming up.
- **Reminders** (⌘2, ⌘N for a new one): add, edit, repeat, snooze, skip one, history. Snoozing
  moves only that one: a Monday reminder snoozed to Tuesday still comes back on Monday. A
  reminder you didn't answer stays overdue on Today until you do. macOS holds the coming ones,
  so they arrive even when Sidefolk is closed; anything that came due while your Mac slept shows
  on one card ("While you were away").
- **Work log** (⌘3): your Log and the notebooks you name, one timeline of every entry by week,
  search by words or dates ("october", "last week"), edit, move to another notebook, copy as
  Markdown. **Your week** lists what you logged and finished this week, ready to copy; on Friday
  from 4 PM your companion offers it (Settings → General → Labs → Your week).
- When a Claude Code session finishes, its card offers **Log it**: the project and your first
  request, editable, go to your Log.
- **Sessions** (⌘4): running and finished Claude Code sessions. It appears once Claude Code is
  connected.
- **Settings** (⌘,): a separate window with four searchable panes: General, Companion, Agents, and Privacy & data. **General → Theme** offers System (the default),
  Light and Dark.

## Claude Code (optional)

Settings → Agents connects Claude Code. Each change is explained first, and a backup of its
settings is kept. Hooks and companion tools connect together. If disconnecting fails partway,
**Finish disconnecting** completes the removal; retrying does not reconnect it.

- When a session asks for permission and you aren't looking at it, Pip shows the request: the
  full command and folder, then Decline, Allow once, or Answer in Claude's window. Pip never
  answers on its own. If you go to that session while Pip is asking, the request moves there
  ("Moved to your terminal"). If nobody answers, Claude Code asks in its own window after
  about a minute.
- "Looking at it" means its tab is in front in Terminal or iTerm. In Ghostty, WezTerm, VS Code
  and Cursor it means the app is in front with only that one session running there; in Warp,
  tmux or over ssh, Pip always asks.
- Click Pip to see your sessions above the field, with what each is doing; click one to open
  it.
- Settings → Agents says how Claude Code's connection is doing: Connected (nothing heard
  yet), Working, Needs repair (Sidefolk moved or was updated; press Repair), or Can't listen.
- If Sidefolk isn't running, or you deleted it, Claude Code carries on as if it weren't
  installed.
- When a session finishes or fails, Pip says so once.
- "Open" brings the session forward. In Terminal and iTerm it selects its tab; other apps come
  forward, and you pick the session there.
- Codex: its companion tools (notes, questions, reminders) can be connected too. Watching Codex
  sessions is not available yet.

## Uninstalling

Settings → Privacy & data → **Disconnect & uninstall** (also in the menu bar). It removes only
what Sidefolk added to Claude Code and Codex, keeping a backup of each settings file. It also
stops Sidefolk opening at login, then quits; drag Sidefolk to the Bin afterwards. Your reminders
and notes stay unless you tick "Also move my reminders, notes and backups to the Bin". Without
the app: `/Applications/Sidefolk.app/Contents/MacOS/sidefolk uninstall`.

## Privacy

Your companion, reminders, notes and logs stay in
`~/Library/Application Support/dev.sidefolk.companion`. "Hide from screen recordings" keeps Pip
out of screen sharing. While it's on, Mission Control shows a dark patch where Pip stands, so it's
off by default.

## Something wrong?

Settings → Privacy & data → **Copy report**, add what happened, and send it. The report contains
versions, settings and recent errors, never your reminders, notes or names.

## Privacy and quiet

General has Quiet, volume and the default snooze. New installations start Quiet; changing it
does not change macOS notification settings. A snooze moves one occurrence, keeping repeats
anchored to their original schedule.

Privacy & data explains what stays on this Mac. New session history keeps the first prompt
line (up to 500 characters) and dated events for seven UTC calendar days, including today;
tool input, answers and agent output are not added. Turn off **Keep session history** to stop
new records. **Clear history…** asks before removing journal files; it keeps notebooks,
reminders and backups. Older history can contain more detail until it is cleared or expires.
Use Work log’s **Copy as Markdown** to export a notebook, or **Your week** to copy the week.

Recording protection stays off pending the Mission Control hand check. Setup offers the choice,
and Privacy & data lets you change it later. A browser preview cannot verify screen sharing.
