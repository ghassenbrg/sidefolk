# Sidefolk 0.1.0: release notes

<!-- FOUNDER: release date, and the download link once a notarized DMG exists. -->
<!-- A draft, brought up to date on 2026-11-01 (snapshot 661); curate it before the release. -->
The first version of Sidefolk: a small companion that lives on your Mac's desktop. It remembers,
reminds and keeps watch, plays with you, and your AI agents can talk to it.

## What's in it

### The companion
- A character on the bottom edge of your screen whose body shows what it is doing: listening,
  thinking, working (with a prop for the kind of work), waiting for your OK, happy, worried, alert,
  asleep. It stands on a small light that says the same at a glance: aqua while it works, amber with a
  count when something waits, grey in Focus, out in Quiet (D84).
- Ten companions: Mochi (the default) and Spark built in, in 3D or 2D (D51, D59), and Ember, Kiko,
  Nimbo, Folio, Iris, Nori, Purl and Rune from the add-on gallery (D55, D61). Each takes a name.
- A life of its own (D43): 17 small moments (a stretch, a yawn, an ear twitch, a glance at your work,
  a sneeze…), sitting and lying down when nothing happens, a boop when clicked, petting by stroking,
  and a landing when dropped or thrown. Liveliness: Minimal (moves only when something happens),
  Balanced (the default) or Lively; Reduce Motion is respected; still while you type.
- Play with it (D44): say "dance!", "take a bow", "do a trick" or choose Play in its menu; stroke it again
  and it giggles; "let's play catch" (boop it as it hops about for 20 seconds, best score kept) or "help me
  relax" (one minute of slow breathing together). The AI can cheer with you too.
- Chance on the desktop: "flip a coin", "roll 2 dice", "roll a d20" or "rock paper scissors", and the
  companion flips, throws or plays its hand above itself, landing on a result drawn for real (the score is
  kept).
- Your own companions: a folder with `species.json` and SVG shapes, read strictly as data, listed
  under "Made by you" (`companions/template/`, and Miso as an example); a 3D companion from a folder,
  with a 2D form if it brings one (D60, D85).
- Folks on duty beside it: Tempo while a reminder is close, Scout while something is watched, Byte
  while an agent or command runs.
- Presence: Always, Only when needed, or Menu bar only. The menu bar's Pocket: the state, Focus and
  Quiet, what needs you, what's next, agents and an Ask field (D84).
- Drop a file, link or text on it: Save, Remind me…, Watch, Ask.

### Asking
- ⌘⇧Space (or a click on the companion) opens Ask beside it; ⌘K is the Say bar in Home. The line under
  the field says what Return will do and whether it uses AI (⌘Return asks the AI, ⌥Return saves a note).
- Everything the companion tells you is the Sidecard (D84): a whisper for news that fades, a card that
  waits for an answer and folds into the count on its shoulder, a permission slip for approvals.
- Without AI, in English: reminders with natural times and repeats, notes, ideas, tasks, list items,
  "About you" facts, watches, live values, Focus and Quiet, search and stop (D4).
- Every request ends in a card, not a transcript. Cards for saved things offer Undo; a long answer opens
  with Show all, and every answer offers Reply in its own conversation and Copy (D45).
- "What's my CPU?", "how full is my disk", "temperature in Fukuoka": one reading, answered at once (D35).
- Start fresh with "new conversation", ⌘N or Clear all. Conversations are kept for the days you choose,
  can be read again, continued, searched and deleted in History (D45, D84).

### Home
- Today (what needs you, what's on duty, your day, what you captured), a Calendar of everything with a
  time and, if you turn it on, your calendar (D57, D66), On duty (everything working in the background,
  with Pause and Stop), History (every action with Undo where it can, conversations, what Sidefolk told
  you), extension pages and the Gallery (D84).
- Notebook: Inbox, You (the facts it keeps about you, with Edit and Forget), projects, topics and lists
  of notes, ideas, tasks and links, pinned notes and formatting (D53). Full-text search everywhere (⌘F).
  Trash for 30 days. Notes saved by agents are tagged and say who saved them.
- Themes dress the app: Harbor, Paper Garden, Night Studio and Marshmallow built in, each its own
  atmosphere, and your own from a folder (D58, D84, D92).

### Time
- Reminders that survive restarts, with snooze, done, repeats from every minute to every month (with
  an end, such as "until 6pm"), a summary of missed ones and a morning brief.
- A reminder can belong to a task or note ("add a task to call mom at 5", or Remind me on any item): done
  or trashed, its reminders end; the card offers Mark done and Open (D49). macOS notifications are
  scheduled as a fallback when Sidefolk quits.

### Watching and live values
- Watches: web page changes (meaningful ones), a site down or back up, a file appearing or changing, a
  new file in a folder, a program exiting, a command you approved, and watches from extensions. A local
  address (localhost, your network) can be watched when you ask for it yourself (D21).
- Live values (D35): CPU, memory, battery, free disk, network, the weather somewhere (Open-Meteo, no
  key), one value on a web page or API, or a command's last line, every few seconds or minutes. Shown as
  pins beside the companion and on On duty, with Pause and Stop.
- Focus (small news waits, then comes back as one card) and Quiet (only the urgent), each until a time
  or for good, quiet hours every night, and what a full-screen app does (D84).

### AI, if you want it
- No AI needed for the basics.
- Claude Code (your Claude subscription) and Codex (your ChatGPT plan), run with their own tools
  switched off so they act only through Sidefolk's tools (D8, D26).
- API keys: Anthropic, OpenAI, Google Gemini, Mistral, Groq, xAI, DeepSeek, OpenRouter. On this Mac:
  Ollama, LM Studio. Any OpenAI-compatible server.
- An everyday model and a "Think harder" model, each with its own reasoning effort where accepted
  (D36). Settings › Brain shows exactly what was last sent; Test sends one tiny request.

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
- `sidefolk mcp`: an MCP server for Claude Code, Codex or any MCP client: save, change or trash a note,
  set a reminder, watch (no commands), show a live value, notify, ask you, status (D52). Reading your notes or reminders asks first (SECURITY T4).
- One-click Connect for Claude Code and Codex, after showing every change, with a backup (D16).
- Optional Claude Code and Codex hooks: the companion shows working sessions beside it and tells you
  when one needs you (D12, D42).
- `sidefolk run -- <command>`: tells you when a long command ends, with its last error lines when it
  fails (D23).

### Extensions
- Sandboxed extensions (a manifest plus a program speaking MCP), with a permission sheet in plain words,
  pinned files, tamper detection, icons, and changed tools held for review (D13, D24).
- Four a fresh Mac starts with, installed once and yours to remove, each a small program that needs nothing installed: World Clock,
  System Vitals, Weather (forecasts, sunrise, sunset and the moon, a rain watcher) and Calculator (exact
  sums, units, date maths) (D98).
- The add-on gallery, downloaded only when you pick one, as packs signed by Sidefolk's developer (D55):
  Git, Currency, Images, PDF Tools, QR Codes, Archives, Dev Toolbox, Feeds, Your Mac (a page of live
  gauges), Clipboard (history in a palette, ⌥P), Keep Awake, Miraya (your screen on a TV) and Playtime.
  Add-ons update by themselves when they ask for nothing new (D65, D70).
- Extensions can add pages to Home, tiles to Today, palettes, background work and games (D62, D63, D75).

### Games
- Playtime's games in a panel beside the companion, without AI (D75, D79): Tic-tac-toe, Copy Me, Quick
  Paws, Which Cup?, Higher or Lower, Guess My Animal, Balloon Words, Last Stick, Memory Pairs, Daily Word
  and trivia, against your companion; and four puzzles alone, Garden Plots, Seesaw, Sudoku and Blossoms,
  with a daily board, hints and best times.
- Instant answers (D50): an extension can answer simple sentences without the AI ("15% of 80", "time in
  Tokyo", "100 usd in eur", "new uuid"); its author decides which tools the AI sees at all.
- Settings › Add-ons: one line per extension, details on a click, search and an All / On / Off filter.
- Sidefolk can write an extension for you: it proposes it, writes a text-only draft, tries it with no
  permissions, and shows the normal install sheet. Only your click installs it (D39).
- Plain MCP servers can be added; they run unsandboxed and are labelled so.
- Skills: written instructions the companion loads when needed. Three are bundled (build an extension,
  organise Downloads, weekly review).

### Control and trust
- Guard decides what runs, never the model: risk levels, folders you share, protected places, taint
  from anything read from outside, exact-command grants (D14).
- Approval modes: Ask every time, Ask once per kind (default), Auto, Full access (which can end at a
  time you pick, D84); another app's approvals never take Return; and what to do when
  you don't answer: keep waiting, skip the step (default, after 10 minutes) or stop the task (D37).
- Using the internet (D47): ask each time, once for each site (default), or not before reading; a site or
  built-in service you allowed keeps working after Sidefolk has read a page.
- Your location, only if you choose it (D48): your Mac's location or a town you pick. The AI hears the town,
  never coordinates; the weather uses it when you name no place.
- Updates (D46): Sidefolk looks for a new version on GitHub once a day, asks before installing, checks the
  download's checksum and signature, and swaps itself in.
- History lists every action with who asked, what was decided and what happened, with Undo where it can.
- Export everything (JSON) or delete everything, Keychain items included. Diagnostics export without
  your content.

### Languages
- English, French, Spanish, German, Italian, Portuguese (Brazil), Japanese, Korean, Chinese
  (Simplified) and Arabic, laid out right to left (D28).

## Requirements
- A Mac with Apple silicon and macOS 15 or later. `scripts/build-app.sh` builds for the Mac it runs on
  (arm64 on Apple silicon); a universal build has not been made or tested.
- Optional: the `claude` or `codex` command signed in, an API key, or Ollama or LM Studio, for AI.
  git (Apple's Command Line Tools or Homebrew) for the Git extension; the others need nothing.
  macOS 26 or later for the better speech recognition.
- To build: Xcode 26 or later (Swift 6.2).

## Known limits
- **Distribution:** signed with Developer ID and notarized; snapshots so far. The updater's swap is proven
  only by the second release that carries it (RELEASE.md › Updates).
- **Platforms:** Apple silicon only. Development and most testing were on macOS 27.0.1; macOS 15 and 26
  are supported by the code but haven't been checked by hand.
- **Understanding without AI is English only.** With AI, any language works; the drop buttons work in
  every language (D28).
- **Not built yet:** Mail, Music, Shortcuts, writing to the calendar, scheduled AI routines, a "what was
  I doing" timeline, a wake word.
- **Watches and live values run only while Sidefolk runs.** Live values faster than once a minute end
  after an hour unless you say otherwise; others after a day. A folder with more than 20,000 items can't
  be watched.
- **Extensions:** network access is all or nothing, so an extension allowed online can also reach your
  local network; extensions can't keep secrets (API keys) yet; the gallery holds only Sidefolk's own; a call runs at most
  300 seconds.
- **Apple Notes:** run on the founder's own library, where a note part Notes couldn't hand over (error
  -1728) stopped a copy; that is fixed (only that part is lost, the rest is copied) but not yet re-tried
  on the real library. Copying is the default; removing always asks and lists every note.
- **Voice:** checked with recorded audio and spoken-to-file round trips, not yet with a real microphone
  (its permission prompt, holding to talk, AirPods), and no live ElevenLabs voice yet. Recognition on
  macOS 15 is "basic". With an ad-hoc build the microphone permission is asked again after each rebuild.
- **Not yet exercised by hand:** Claude Code hooks in a real session, the notification permission
  prompt, opening at login from /Applications, several displays and fullscreen apps, Connect for Claude
  Code and Codex on a real setup, and a repository clone asked of a real AI.
- **Translations** cover every string but are new, and no native-speaker review is recorded yet.
  Arabic shows "Space_Key" in the shortcut recorder, which comes from a third-party component.
- **Residual risks** are listed in [SECURITY.md](SECURITY.md): code running as you can name its own
  terminal as a session's host; extension tool names (60 characters) reach the model; in Auto and Full
  access a model can open or fetch addresses of its choosing in a turn that read nothing from outside.

## Thanks
GRDB.swift (Gwendal Roué), KeyboardShortcuts (Sindre Sorhus), three.js, LobeHub Icons, and Open-Meteo for
weather data (CC BY 4.0). See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
