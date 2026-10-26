# Sidefolk 0.1.0: release notes

<!-- FOUNDER: release date, and the download link once a notarized DMG exists. -->
The first version of Sidefolk: a small companion that lives on your Mac's desktop. It remembers,
reminds and keeps watch, and your AI agents can talk to it.

## What's in it

### The companion
- A character on the bottom edge of your screen whose body shows what it is doing: listening,
  thinking, working (with a prop for the kind of work), waiting for your OK, happy, worried, alert,
  asleep. It holds still when nothing happens: about 0.04 % of one CPU core at rest in a release
  build (D35).
- Thirteen companions on one animation engine: Mochi (the default), the original Sidefolk robot,
  Spark and the ten folks. Each takes a name, one of four colours and an optional scarf (D30).
- Folks on duty beside it: Tempo while a reminder is close, Scout while something is watched, Byte
  while an agent or command runs.
- Presence: Always, Only when needed, or Menu bar only. A menu bar item with a Now list.
- Drop a file, link or text on it: Save, Remind me…, Watch, Ask.

### Asking
- ⌘⇧Space (or a click on the companion) opens the Ask panel. A hint under the box says what Enter will
  do and whether it uses AI.
- Without AI, in English: reminders with natural times and repeats, notes, ideas, tasks, list items,
  "About you" facts, watches, live values, quiet mode, search and stop (D4).
- Every request ends in a card, not a transcript. Cards for saved things offer Undo; an answer that
  ends with a question offers Reply.

### Memory
- Notebook: Inbox, About you, projects, topics and lists of notes, ideas, tasks and links. Full-text
  search everywhere (⌘F). Trash for 30 days. Notes saved by agents are tagged and say who saved them.

### Time
- Reminders that survive restarts, with snooze, done, repeats from every minute to every month (with
  an end, such as "until 6pm"), a summary of missed ones and a morning brief. macOS notifications are
  scheduled as a fallback when Sidefolk quits.

### Watching and live values
- Watches: web page changes (meaningful ones), a site down or back up, a file appearing or changing, a
  new file in a folder, a program exiting, a command you approved, and watches from extensions. A local
  address (localhost, your network) can be watched when you ask for it yourself (D21).
- Live values (D35): CPU, memory, battery, free disk, network, the weather somewhere (Open-Meteo, no
  key), one value on a web page or API, or a command's last line, every few seconds or minutes. Shown as
  pills beside the companion and in a Live section on Now, with Pause and Stop.

### AI, if you want it
- No AI needed for the basics.
- Claude Code (your Claude subscription) and Codex (your ChatGPT plan), run with their own tools
  switched off so they act only through Sidefolk's tools (D8, D26).
- API keys: Anthropic, OpenAI, Google Gemini, Mistral, Groq, xAI, DeepSeek, OpenRouter. On this Mac:
  Ollama, LM Studio. Any OpenAI-compatible server.
- An everyday model and a "Think harder" model, each with its own reasoning effort where accepted
  (D36). Settings › AI shows exactly what was last sent; Test sends one tiny request.

### The Mac's own apps
- Apple Notes: list, read, copy into the notebook (organised by the AI, in batches of up to 50, with
  progress), and move to Recently Deleted only after a whole copy and only with your approval each
  time. Apple Reminders: read open reminders (D38).

### Voice (off by default)
- Hold the Ask shortcut or press and hold the companion to talk; release to send. Recognised on your
  Mac (SpeechAnalyzer on macOS 26 and later; the older on-device recognizer, labelled "basic", on
  macOS 15). Audio is never stored (D34).
- One short spoken reply, by default only when you spoke; Apple voices or ElevenLabs with your key.
  Every companion's mouth moves with the voice.

### Agents and MCP
- `sidefolk mcp`: an MCP server for Claude Code, Codex or any MCP client: save a note, set a reminder,
  watch (no commands), notify, ask you, status. Reading your notes or reminders asks first (SECURITY T4).
- One-click Connect for Claude Code and Codex, after showing every change, with a backup (D16).
- Optional Claude Code hooks: the companion notices when a session needs you or finished.
- `sidefolk run -- <command>`: tells you when a long command ends, with its last error lines when it
  fails (D23).

### Extensions
- Sandboxed extensions (a manifest plus a program speaking MCP), with a permission sheet in plain words,
  pinned files, tamper detection, icons, and changed tools held for review (D13, D24).
- Built in: Git (clone public https repositories into a folder you name, status, pull, log), World Clock
  and System Vitals, on; Weather (forecasts and a rain watcher), off until you switch it on (D39).
- Sidefolk can write an extension for you: it proposes it, writes a text-only draft, tries it with no
  permissions, and shows the normal install sheet. Only your click installs it (D39).
- Plain MCP servers can be added; they run unsandboxed and are labelled so.
- Skills: written instructions the companion loads when needed. Three are bundled (build an extension,
  organise Downloads, weekly review).

### Control and trust
- Guard decides what runs, never the model: risk levels, folders you share, protected places, taint
  from anything read from outside, exact-command grants (D14).
- Approval modes: Ask every time, Ask once per kind (default), Auto, Full access; and what to do when
  you don't answer: keep waiting, skip the step (default, after 10 minutes) or stop the task (D37).
- Activity lists every action with who asked, risk, decision and outcome, with Undo for 15 minutes.
- Export everything (JSON) or delete everything, Keychain items included. Diagnostics export without
  your content.

### Languages
- English, French, Spanish, German, Italian, Portuguese (Brazil), Japanese, Korean, Chinese
  (Simplified) and Arabic, laid out right to left (D28).

## Requirements
- A Mac with Apple silicon and macOS 15 or later. `scripts/build-app.sh` builds for the Mac it runs on
  (arm64 on Apple silicon); a universal build has not been made or tested.
- Optional: the `claude` or `codex` command signed in, an API key, or Ollama or LM Studio, for AI.
  Python 3 and git (Apple's Command Line Tools or Homebrew) for the built-in extensions. macOS 26 or
  later for the better speech recognition.
- To build: Xcode 26 or later (Swift 6.2).

## Known limits
- **Distribution:** no Developer ID signature or notarization yet (`scripts/release.sh` is ready and
  needs the credentials), so 0.1.0 is built from source. No automatic updates (D15).
- **Platforms:** Apple silicon only. Development and most testing were on macOS 27.0.1; macOS 15 and 26
  are supported by the code but haven't been checked by hand.
- **Understanding without AI is English only.** With AI, any language works; the drop buttons work in
  every language (D28).
- **Not built yet:** calendar awareness, Mail, Music, Shortcuts, scheduled AI routines, a "what was I
  doing" timeline, a wake word.
- **Watches and live values run only while Sidefolk runs.** Live values faster than once a minute end
  after an hour unless you say otherwise; others after a day. A folder with more than 20,000 items can't
  be watched.
- **Extensions:** network access is all or nothing, so an extension allowed online can also reach your
  local network; extensions can't keep secrets (API keys) yet; no extension directory; a call runs at most
  300 seconds.
- **Apple Notes:** run on the founder's own library, where a note part Notes couldn't hand over (error
  -1728) stopped a copy; that is fixed (only that part is lost, the rest is copied) but not yet re-tried
  on the real library. Copying is the default; removing always asks and lists every note.
- **Voice:** checked with recorded audio and spoken-to-file round trips, not yet with a real microphone
  (its permission prompt, holding to talk, AirPods), and no live ElevenLabs voice yet. Recognition on
  macOS 15 is "basic". With an ad-hoc build the microphone permission is asked again after each rebuild.
- **Not yet exercised by hand:** Claude Code hooks in a real session, the notification permission
  prompt, opening at login from /Applications, several displays and fullscreen apps, Connect for Claude
  Code and Codex on a real setup, a repository clone asked of a real AI, and the menu bar's Approvals
  submenu with its Full access icon.
- **Translations** cover every string but are new, and no native-speaker review is recorded yet.
  Arabic shows "Space_Key" in the shortcut recorder, which comes from a third-party component.
- **Residual risks** are listed in [SECURITY.md](SECURITY.md): code running as you can name its own
  terminal as a session's host; extension tool names (60 characters) reach the model; in Auto and Full
  access a model can open or fetch addresses of its choosing in a turn that read nothing from outside.

## Thanks
GRDB.swift (Gwendal Roué), KeyboardShortcuts (Sindre Sorhus), LobeHub Icons, and Open-Meteo for
weather data (CC BY 4.0). See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
