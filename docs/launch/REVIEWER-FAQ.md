# For reviewers

Short answers for writers and reviewers trying Sidefolk 0.1.0. `[FOUNDER: …]` marks what only the
founder can fill in.

## Getting it

**Where do I download it?**
`[FOUNDER: review build or DMG link]`. Until a notarized DMG exists, it is built from source with Xcode 26
or later (`make app`, see the README). A build made on your own Mac opens without Gatekeeper warnings.

**What do I need?**
A Mac with Apple silicon and macOS 15 or later. No account. AI is optional: Claude Code or Codex signed in,
an API key, or Ollama or LM Studio. Voice works best on macOS 26 or later.

**Is there a press contact?** `[FOUNDER: email]`

## Ten minutes with it

1. Open it. Mochi says hello and sets a real reminder two minutes out, without AI.
2. Press ⌘⇧Space and try: `remind me tomorrow at 9 to send the deck`, `add oat milk to my groceries list`,
   `watch example.com/pricing`, `tell me the CPU every 10 seconds`. Watch the hint line: it says what Enter will
   do and "no AI".
3. Double-click Mochi for Home: Now, the Notebook, Activity.
4. Settings › AI: pick Claude Code, Codex, an API key or a local model, then ask a real question.
5. Ask it to tidy something in a folder you choose. Read the approval card, then look at Activity and
   try Undo.
6. Settings › Companion: try another companion and watch it think, work and sleep.
7. Optional: Settings › Voice, turn on voice input, hold ⌘⇧Space and talk.
8. Optional, for developers: Settings › Agents › Connect Claude Code, then ask Claude Code to "leave me a
   note in Sidefolk", or run `sidefolk run -- sleep 5` in Terminal.

## What it is and isn't

**Is it a chatbot?**
No. Requests end in results (a saved note, a reminder, an answer card), not a transcript. Short history is
kept for follow-ups and never shown as a chat log.

**What does it do without AI?**
Notes, ideas, tasks, lists, "About you" facts, reminders with repeats, watches on pages, sites, files,
folders and programs, live values, quiet mode and search, from plain English. The drop buttons (Save,
Remind me…, Watch) work in every language.

**What needs AI?**
Questions, open-ended jobs ("organise my Downloads"), Apple Notes organising, and having it write an
extension.

**Which AI does it use?**
The one you pick in Settings: Claude Code or Codex on your existing plan, an API key (Anthropic, OpenAI,
Google Gemini, Mistral, Groq, xAI, DeepSeek, OpenRouter), Ollama, LM Studio, or any OpenAI-compatible
server.

**Does it cost tokens when idle?**
No. AI runs only when you send a request that needs it. Watches, reminders and live values are plain code.

## Privacy and safety

**What leaves the Mac?**
Only requests to the AI you chose (Settings › AI shows exactly what was last sent), pages you asked it to
read or watch, place names to Open-Meteo when you ask for the weather, the words it speaks if you chose an
ElevenLabs voice, and traffic from extensions you allowed online. No account, no telemetry, no analytics,
no crash reporter. The full table is in the README's Privacy section.

**Can the AI do anything it wants?**
No. A fixed set of rules (Guard) checks every action: what it touches, how risky it is, who asked, and
whether the request read something from outside. Files are touched only in folders you shared; deleting
means the Trash. You choose how often it asks: Ask every time, Ask once per kind (default), Auto, or Full
access, which is turned on only through a sheet that explains it.

**What about prompt injection?**
Anything read from outside (web pages, files, notes, extension output) marks the request as untrusted;
after that, anything that could change things or send data out asks first, in every mode. Remaining risks
are written down in docs/SECURITY.md.

**Can other agents take over?**
Claude Code, Codex and other MCP clients get a small fixed set of tools (notes, reminders, watches,
notify, ask). No files, no commands, no web, and they can never approve anything.

**Does it listen all the time?**
No. Voice is off by default; when on, the microphone opens only while you hold the key, speech is
recognised on the Mac, and the audio is never stored.

## Known limits in 0.1.0

- No notarized release yet (snapshots are signed and notarized). From the snapshot that has it on, Sidefolk looks for new
  versions on GitHub and asks before installing one.
- Apple silicon only; most testing has been on macOS 27.
- Typing commands without AI understands English only.
- No calendar, Mail, Music or Shortcuts; no scheduled AI routines.
- Watches run only while the app runs (reminders fall back to macOS notifications).
- Extensions can't keep API keys yet or be limited to particular sites.
- The nine translations are new.
- Voice is the newest part: checked with recorded audio, `[FOUNDER: update once tried with a real
  microphone]`.

The complete list is in [../RELEASE-NOTES.md](../RELEASE-NOTES.md).

## Background

**Who made it?** `[FOUNDER: one paragraph]`

**Why a rabbit?** Mochi is the mascot. There are twelve other companions, including the original robot.

**How is it built?** Native Swift 6: AppKit, SwiftUI, and Core Animation for the characters; SQLite for
data. Extensions are MCP servers run in a macOS sandbox. Details in docs/ARCHITECTURE.md.

**Is it open source?** `[FOUNDER: licence decision. Today the code is public on GitHub and all rights
are reserved.]`

**What's next?** `[FOUNDER: only what's committed. Candidates in docs/STATUS.md: a "Today" timeline,
calendar awareness, signed extension packages.]`
