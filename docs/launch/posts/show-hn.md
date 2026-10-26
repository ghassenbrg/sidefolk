# Hacker News: Show HN

**When:** after the notarized DMG is up (a Show HN should be something people can try in a minute).
Weekday morning, US Eastern. Stay in the thread for the first three hours and answer everything,
including the critical ones, plainly.

**Title** [74/80]:

    Show HN: Sidefolk – a macOS desktop companion your coding agents can reach

Alternative [78/80]: `Show HN: Sidefolk – notes, reminders and watches from a rabbit on your desktop`

**URL:** `[FOUNDER: website or GitHub URL]`

**Text** (first comment, from the founder's account):

---

Hi HN, I'm `[FOUNDER: first name]`. Sidefolk is a native macOS app that puts a small character on your
desktop. You tell it things in plain words and it keeps them: notes, reminders, pages and files to watch.

A few choices that might interest this crowd:

- **Most of it works without a model.** "remind me tomorrow at 9 to send the deck", "tell me when
  report.pdf appears in Downloads", "tell me when localhost:3000 is back up" and "temperature in Fukuoka
  every minute" are handled by a local, rule-based parser (fuzz-tested over 600k random inputs) and
  finish in milliseconds. A hint under the input says what Enter will do and whether it uses AI.
- **Bring your own brain.** Claude Code or Codex on your existing plan, an API key (Anthropic,
  OpenAI-compatible), or Ollama / LM Studio. The CLIs run with their built-in tools switched off
  (`--tools ""` for Claude Code; for Codex, its features off, a read-only sandbox and the event stream
  watched), so they can only act through Sidefolk's tools.
- **The model never decides permissions.** A deterministic Guard checks every tool call: risk levels,
  folders you shared, protected paths, and taint: once a turn has read a web page, file, note or
  extension output, anything that could send data out asks you first, whatever mode you're in.
- **Agents can reach it over MCP.** `sidefolk mcp` gives Claude Code, Codex or any MCP client a small
  closed set of tools (save a note, set a reminder, watch, notify, ask you). No files, no commands, no
  web, and they can never answer an approval. `sidefolk run -- npm test` tells you when a long command
  ends, with the last stderr lines if it failed.
- **Extensions are MCP servers in a sandbox.** A manifest plus any executable speaking MCP over stdio,
  run under a `sandbox-exec` profile generated from its permissions, with file hashes pinned. If you
  ask for something it can't do, it can draft a small extension, try it with every permission removed,
  and show you the normal install sheet.
- **Native and cheap at rest.** Swift 6, AppKit, SwiftUI, and Core Animation for the characters (13 of
  them on one rig engine). At rest it holds still: about 0.04 % of one core in a release build. Data is
  SQLite (GRDB, FTS5) in one folder; no account, no telemetry.

It also copies Apple Notes into its notebook (Apple Events, fixed scripts, approval cards), has
push-to-talk with on-device recognition, and is in ten languages.

What isn't there yet: no auto-update, Apple silicon only, the no-AI parser is English only, no
calendar, and extensions can't hold secrets or be limited to particular hosts. The full list is in the
README.

`[FOUNDER: one or two sentences on why you built it, in your own words.]`

I'd love to hear what you'd want it to watch for you, and where the permission model feels wrong.

`[FOUNDER: pricing or licence sentence, e.g. "It's free while it's early" — only if true.]`

---

**Answers to have ready** (short, factual):

- *Why not Electron?* An always-visible window has to cost ~0 % idle; Core Animation runs in the
  render server. (DECISIONS D1)
- *Does it read my screen?* No. It knows the name of the frontmost app, nothing else.
- *Is the Claude/ChatGPT plan use allowed?* It runs your own `claude`/`codex` command as you would in a
  terminal. `[FOUNDER: confirm wording against Anthropic's and OpenAI's terms before posting.]`
- *Open source?* `[FOUNDER: licence decision; today the repo is public and all rights reserved.]`
- *Prompt injection?* Taint tracking per turn, untrusted content wrapped and capped, approvals bound to
  a hash of the exact arguments; residual risks are written down in docs/SECURITY.md.
