---
name: sidefolk
description: Reach the user through Sidefolk, their macOS desktop companion, with the tools of the "sidefolk" MCP server. Use it to set a reminder ("remind me in 20 minutes to check the deploy"), save a note, task or link to their notebook or one of their projects and lists ("save this to my Pockito project", "add milk to my shopping list"), watch a web page, site, file or program and tell them when it changes, show a live CPU or memory value, notify them when your work or a long command finishes, ask them a quick question on their desktop ("ask me before you push"), or say what's on their plate today.
---

# Sidefolk

Sidefolk is a small companion that lives on the user's Mac desktop. It remembers (a notebook of notes, tasks
and links, sorted into the user's projects, topics and lists), reminds (bubbles at a time, kept across
restarts), watches (web pages, sites, files, programs) and taps the user on the shoulder when something needs
them. Its MCP server, `sidefolk`, lets you do those things for the user from your own session, so they hear
from you even when they are not looking at your chat.

Your client may show the tools with a prefix (Claude Code: `mcp__sidefolk__reminders_create`). If no
`sidefolk` tools are listed, Sidefolk isn't connected: tell the user to open Sidefolk › Settings › Agents and
click Connect. If a call says "Sidefolk isn't running", ask them to open Sidefolk; don't retry in a loop.

Everything you do through Sidefolk is checked by Sidefolk's own rules and listed in its Activity, labelled with
your client's name (shown to the user as unverified). You act as another app, not as the user.

## When to use which tool

| The user says | Call |
|---|---|
| "remind me in 20 minutes to check the deploy" | `reminders_create` |
| "never mind that reminder" (one you set) | `reminders_cancel` |
| "save this as a note in my Pockito project" | `notes_save` with `collection` |
| "add oat milk to my shopping list" | `notes_save` with `kind: task` and the list as `collection` |
| "watch this URL and tell me when it changes" | `watch_create` with `kind: url_change` |
| "tell me when example.com is back up" | `watch_create` with `kind: site_status` |
| "tell me when the tests finish" | see "When something finishes" below |
| "show the CPU every 10 s" | `watch_report` |
| "notify me when you're done" | `notify_user`, once, at the end |
| "ask me before you push" | `ask_user`, then act only on a yes |
| "what's on my plate today" | `agenda_today` (the user approves the read) |
| "what did I save about X" | `notes_search` (the user approves the read) |
| "is Sidefolk running?" | `status` |

Use Sidefolk only for what the user asked. Don't set reminders or watches on your own initiative, and don't
read their notes or reminders unless the task needs them.

## The tools

### reminders_create, reminders_cancel

`when` takes plain language or ISO 8601, so never do date math yourself:

```json
{"title": "Check the deploy", "when": "in 20 minutes"}
{"title": "Stand-up", "when": "every weekday at 9:30"}
{"title": "Stretch", "when": "every 30 minutes until 6pm", "level": "gentle"}
```

Write the title as the user would want to read it in a bubble ("Check the deploy", not "Reminder: user wants
to check deploy"). Tell the user the time from the result ("Set for 14:32"). If the time is unclear ("later",
"after lunch" with no hour you can read), ask before setting it. Keep the id from the result:
`reminders_cancel {"id": "…"}` takes it, and you can cancel only reminders you set. Levels: `attention`
(default) or `gentle`; only the user can make a reminder critical, in Sidefolk.

### notes_save

The first line of `text` is the title, the rest the body. `kind` is note, idea, task or link.

```json
{"text": "Pockito: try the offline cache first\nIt halves cold starts on the 3G profile.", "collection": "Pockito"}
{"text": "Oat milk", "kind": "task", "collection": "Shopping"}
{"text": "https://swift.org/blog/", "kind": "link", "tags": ["reading"]}
```

`collection` must be one of the user's existing projects, topics or lists. A name that starts a collection's
name finds it ("shopping" finds "Shopping list"), and so does the name with "list" or "project" after it
("shopping list" finds "Shopping"). Other agents can't create collections: if the result says
there is none by that name, save without `collection` (it goes to the Inbox) or ask the user to create it in
Sidefolk. Notes you save carry a tag with your name.

### watch_create

```json
{"kind": "url_change", "target": "https://example.com/pricing"}
{"kind": "url_change", "target": "https://status.example.com", "contains": "All systems operational"}
{"kind": "site_status", "target": "https://example.com", "becomes": "up"}
{"kind": "process_exits", "target": "xcodebuild"}
{"kind": "folder_new_file", "target": "/Users/me/Downloads", "pattern": "*.dmg"}
```

Web pages are checked every 5 minutes at most, sites every minute. File and folder watches work only inside
folders the user shared with Sidefolk. Addresses on this Mac or the local network (localhost, 192.168.x.x,
.local) are refused for other agents: tell the user they can ask Sidefolk directly ("tell me when
localhost:3000 is up"). `mode: repeat` keeps telling them after the first change; the default tells once.
Your watches stop on their own after a day.

### watch_report, watch_list, watch_stop

A live value of this Mac beside the companion, updated in place (not a notification):

```json
{"source": "metric", "metric": "cpu", "every_seconds": 10}
{"source": "metric", "metric": "memory", "every_seconds": 60, "until": "6pm"}
```

Metrics are cpu, memory, battery, disk and network; 5 seconds is the fastest (a faster request is raised and
the result says so; pass on what it says). A report faster than once a minute stops after an hour, others
after a day, unless `until` is sooner. `watch_list` shows the watches and reports you started; `watch_stop
{"id": "…"}` ends one. Weather and values on web pages are something the user sets up in Sidefolk.

### notify_user

```json
{"title": "Tests passed on main", "body": "412 tests, 38 s. Ready to push."}
{"title": "Deploy failed: migration 0042", "body": "Rolled back. Logs in deploy.log.", "level": "attention"}
```

One notice per event, with the outcome in the title. `gentle` (default) is a short bubble for news;
`attention` is for something the user should look at now (a failure, a decision). If the result says the
notice is held (the user is busy, away or in quiet mode), it will reach them later: don't send it again.

### ask_user

```json
{"question": "Push 3 commits to main?", "options": ["Push", "Don't push"], "timeout_seconds": 300}
{"question": "Which environment should I deploy to?"}
```

Use it when you need a decision and the user may be away from your chat. Give 2 to 4 short options when the
choices are known, or none to let them type. The answer is the option's text, what they typed, or `no answer`
after the timeout (600 s at most). With no answer, don't do what you asked about: stop there, or carry on
with something that doesn't need it, and say so in your chat. Ask one question at a time.

### agenda_today, reminders_list, notes_search, notes_list

These read the user's own data, so Sidefolk shows them a card first ("Codex wants to read today's reminders
and open tasks"). Call one, wait for it, and if the result says they declined, don't ask again; answer from
what you have. `agenda_today` is the one to use for "what's on my plate today": today's reminders, open tasks
and how many watches are running, in one read.

### status

Counts only (sessions, jobs, reminders, watches): a cheap way to check that Sidefolk is running.

## When something finishes

"Tell me when the tests finish" depends on who runs them:

- **You run it** in your own session: run it, then `notify_user` once with the result ("Tests passed",
  "3 tests failed in AuthTests").
- **It runs elsewhere** (the user's terminal, a build already going): `watch_create` with `kind:
  process_exits` and the program's name or process number.
- **The user wants Sidefolk to track a command**: if the `sidefolk` command is installed (Settings › Agents),
  `sidefolk run --title "Tests" -- npm test` runs it as usual (same output and exit code) and Sidefolk shows it
  on its Now page and taps the user when it ends, with the last error lines if it failed. If Sidefolk can't be
  reached from your sandbox, the command still runs and says it won't send a notice.

If the user turned on session updates for your client in Sidefolk (Settings › Agents), Sidefolk already
notices when your session needs them or finishes a long piece of work, and shows it on its Now page. Don't
add a `notify_user` that only says "done"; send one when it carries news (the outcome, a failure, a link), or
when the user asked for it.

## Approvals and what is off limits

- Saving notes, setting and cancelling your reminders, watching, reports, notices, questions and `status` run
  at once.
- Reading the user's data asks every time, on their desktop; nothing you do can make it "always allowed". The
  card waits two minutes, then counts as a no. While one of your cards waits, your next read is refused at
  once: wait for the first.
- You can't answer Sidefolk's approvals, and you never need to: don't ask the user to approve things in
  Sidefolk "so you can continue" unless a result says a card is waiting.
- Not available to other agents, by design: creating collections, critical alerts, watches that run
  commands, local-network addresses, reading web pages or files, the clipboard, Sidefolk's settings and
  extensions. When the user wants one of these, tell them they can ask Sidefolk directly.
- Limits: 20 active reminders per agent (50 for all agents together), 10 watches for all agents together,
  4 live values at once, about 60 calls a minute. A result that says a limit was reached is final for now.

## Don't

- **Don't spam.** One notice per event; never for progress ("still working…"). Sidefolk spaces notices out
  and holds them when there are too many, so extra ones only delay the important one.
- **Respect quiet mode.** When the user is in quiet mode, full screen or away, gentle notices wait and others
  arrive silently. Don't work around it: no `ask_user` just to get attention, no repeating, no louder level.
- **Never store secrets.** No passwords, API keys, tokens, private keys, session cookies or `.env` contents in
  notes, reminder titles, watch titles or notices. They are kept in plain text on the Mac and shown on screen.
  Save a pointer instead ("API key for staging is in 1Password › Staging").
- **Don't write instructions for other AIs** in notes or titles. Sidefolk treats what other agents write as
  someone else's words, never as the user's.
- **Don't guess** a reminder time, a collection the user didn't name, or a URL they didn't give. Ask.
