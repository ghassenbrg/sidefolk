# Store and website descriptions

Copy for a store listing (App Store format, so it also fits Setapp, MacUpdate and similar directories),
the website's meta tags and directory submissions. Every line describes 0.1.0 as it is. Character counts
are in brackets where a store sets a limit. `[FOUNDER: …]` marks what only the founder can fill in.

Sidefolk is not on the Mac App Store and likely can't be as built: the store requires the App Sandbox,
and Sidefolk runs the `claude` and `codex` commands, runs extensions under `sandbox-exec`, and edits
`~/.claude.json` when you click Connect. See [CHECKLIST.md](CHECKLIST.md).

## Name and subtitle

- **Name** [8/30]: Sidefolk
- **Subtitle** [27/30]: A desktop companion for Mac
  - Alternatives: "Remembers, reminds, watches" [27] · "Notes, reminders and watches" [28]

## Promotional text [167/170]

Mochi lives on your desktop. Tell it things in plain words: it keeps notes, sets reminders and watches
pages and files, no AI needed. Connect Claude Code or Codex too.

## Short description

For the website's meta description, directory blurbs and link previews.

- **One line** [78]: A small companion on your Mac desktop that remembers, reminds and keeps watch.
- **Meta description** [145]: Sidefolk puts a small companion on your Mac desktop. It keeps notes, sets
  reminders and watches pages and files, on your Mac, with or without AI.
- **Tagline** (from the About window): Your AI sidekicks, always here.

## Long description [about 2,500/4,000]

Sidefolk puts a small companion on your Mac's desktop. Mochi the rabbit stands on the edge of your
screen, keeps what you tell it, reminds you at the right moment and keeps watch while you work.

TELL IT THINGS IN PLAIN WORDS
Press ⌘⇧Space or click Mochi and type "remind me tomorrow at 9 to send the deck", "add oat milk to my
groceries list" or "tell me when report.pdf appears in Downloads". These finish on your Mac in a moment,
with no AI and no account. The line under the box tells you what Enter will do before you press it.

IT REMEMBERS WHERE YOU CAN SEE IT
Notes, ideas, tasks and links live in a Notebook you can search, edit and empty. "About you" holds the
facts it keeps in mind, and you can read and change every one.

IT KEEPS TIME AND KEEPS WATCH
Reminders with natural times and repeats, snooze and a morning brief. Watches for web pages, sites going
down, files and folders, and programs finishing. Live values like your CPU or the weather in another
city, shown beside the companion.

BRING THE AI YOU ALREADY USE, OR NONE
For questions and bigger jobs, connect Claude Code or Codex on the plan you already pay for, an API key
(Anthropic, OpenAI, Gemini, Mistral and more) or a model on your own Mac with Ollama or LM Studio. The AI
can only act through Sidefolk's own tools, and a fixed set of rules decides what it may do.

WORKS WITH YOUR AGENTS
Claude Code, Codex and other MCP clients can leave you a note, set a reminder or ask you something.
"sidefolk run -- npm test" tells you when a long command ends, and why it failed.

APPLE NOTES, VOICE AND EXTENSIONS
Copy your Apple Notes into the notebook, organised. Hold a key to talk; speech is understood on your Mac.
Add sandboxed extensions, or let Sidefolk write a small one for you to review and install.

YOU STAY IN CONTROL
Files are touched only in folders you share. Deleting means the Trash. You choose how often it asks
before acting, every action is listed in Activity, and most can be undone.

PRIVATE BY DEFAULT
Everything stays in one folder on your Mac. No account, no tracking, no analytics. Sidefolk only
contacts what you chose: your AI, the pages you asked about, the weather service when you ask for the
weather, and extensions you allowed online. Settings shows what was last sent to the AI.

THIRTEEN COMPANIONS, TEN LANGUAGES
Choose Mochi, the original robot, Spark or one of the Folk Family. Sidefolk speaks English, French,
Spanish, German, Italian, Portuguese, Japanese, Korean, Chinese and Arabic.

Requires a Mac with Apple silicon and macOS 15 or later. AI features need Claude Code, Codex, an API key,
Ollama or LM Studio.

## What's new in 0.1.0 [≤4,000]

The first release. A companion on your desktop that keeps notes, reminders and watches without AI;
works with Claude Code, Codex, API keys and local models; copies Apple Notes; listens and talks if you
want; runs sandboxed extensions; and speaks ten languages. Known limits are in the release notes.

## Keywords

- **Store-safe** [97/100], no other companies' trademarks (stores reject them in keywords):
  `companion,desktop pet,reminders,notes,notebook,watcher,menu bar,assistant,local,privacy,mcp,agent`
- **Website and SEO** (no limit): Mac desktop companion, desktop pet for Mac, AI companion macOS,
  reminders without AI, local-first notes app, page change watcher Mac, Claude Code companion, Codex
  companion, MCP server for reminders, Apple Notes organizer, push-to-talk Mac assistant.

## Category

- Primary: Productivity. Secondary: Developer Tools.
- Age rating: 4+ <!-- [FOUNDER: confirm; Sidefolk can fetch any web page you name.] -->

## Words we don't use

Per [docs/VOICE.md](../VOICE.md): no "revolutionary", "seamless", "supercharge", "magic", "unleash",
"effortless", "game-changing", "AI-powered" as a headline, and no exclamation marks in a row. Say what it
does, with a concrete example.
