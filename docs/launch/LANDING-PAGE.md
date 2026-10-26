# Landing page: copy outline

One page, top to bottom. Each block has its copy and the picture that goes with it (files in
[screenshots/](screenshots) and `Resources/`). Keep it to what 0.1.0 does. `[FOUNDER: …]` marks what only
the founder can fill in.

## 1. Hero

- **Headline:** A small companion for your Mac desktop.
  - Alternatives: "It remembers, so you don't have to." · "Notes, reminders and watches, on your desktop."
- **Subhead:** Mochi keeps your notes, reminds you on time and watches pages and files while you work.
  No AI needed for that. Connect Claude Code, Codex or your own model for the rest.
- **Primary button:** Download for Mac `[FOUNDER: link to the notarized DMG; until then "Build from
  source" goes to the GitHub README]`
- **Under the button:** macOS 15 or later · Apple silicon · `[FOUNDER: price]` · No account
- **Picture:** `screenshots/hero-light.png` (and `hero-dark.png` for dark mode). Replace with a real
  desktop screenshot or a 10-second loop from the demo video when there is one.

## 2. Three things it does well

Three short columns, each with a small picture.

1. **Tell it in plain words.** "remind me tomorrow at 9 to send the deck." Set in a moment, on your
   Mac: no AI, no account. (`screenshots/ask-panel-light.png`)
2. **It comes to you.** Reminders, a page that changed, a build that failed: a small bubble with the
   buttons you need, and quiet when you need quiet. (`screenshots/bubble-reminder-light.png`)
3. **It shows what it's doing.** Thinking, working, waiting for your OK, asleep. You can tell at a
   glance, without opening anything. (`Resources/Character/companion-mochi-small.png`, cropped to a row)

## 3. Works without AI, better with yours

- **Copy:** Notes, reminders, watches, live values and search run on your Mac. When you want answers,
  bring the AI you already use. It can only act through Sidefolk's tools, and you decide how often it
  asks first.
- **List:** Claude Code (your Claude plan) · Codex (your ChatGPT plan) · Anthropic, OpenAI, Gemini,
  Mistral, Groq, xAI, DeepSeek, OpenRouter (your key) · Ollama, LM Studio (on your Mac)
- **Picture:** `screenshots/settings-ai-light.png`
- Use the services' names as text, not their logos, unless the owners have said yes (see CHECKLIST.md).

## 4. Keeps watch

- **Copy:** Tell it what to keep an eye on. "watch example.com/pricing." "tell me when localhost:3000 is
  back up." "tell me when report.pdf appears in Downloads." "temperature in Fukuoka every minute." It
  checks on its own and tells you when it matters.
- **Picture:** `screenshots/live-values-light.png` beside `screenshots/home-now-light.png`

## 5. For people who work with agents

- **Copy:** Claude Code, Codex and any MCP client can leave you a note, set a reminder, watch something
  or ask you a question. `sidefolk run -- npm test` tells you when it's done, and what broke. Other agents
  get a small, safe set of tools: no files, no commands, no web, and they can never approve anything.
- **Code block:** `sidefolk run -- npm test`
- **Pictures:** `screenshots/bubble-command-failed-light.png`, `screenshots/settings-agents-light.png`

## 6. Your notes from Apple Notes, organised

- **Copy:** "Check my Apple Notes and move them, well organized, into the notebook." It copies them in
  batches, keeps their dates, and never removes anything from Notes unless you ask and approve each one.
- **Picture:** `screenshots/ask-apple-notes-light.png`

## 7. Talk to it, if you like

- **Copy:** Hold a key and talk. Your words are understood on your Mac and the recording is never
  kept. It answers in one short line. Off until you turn it on.
- **Picture:** `screenshots/ask-listening-light.png`

## 8. You stay in control

- **Copy:** A fixed set of rules decides what runs, not the AI. It works only in folders you share.
  Deleting means the Trash. Everything it did is listed in Activity, and most of it can be undone.
- **Pictures:** `screenshots/settings-approvals-light.png`, `screenshots/home-activity-light.png`

## 9. Private by default

- **Copy:** Everything stays in one folder on your Mac. No account. No tracking. No analytics. Sidefolk
  contacts only what you chose: your AI, the pages you asked about, the weather service when you ask for
  the weather. Export or delete everything in one click.
- **Link:** "What leaves your Mac, and when" → the README's Privacy table, or the privacy policy page
  `[FOUNDER: privacy policy URL]`.

## 10. Extensions

- **Copy:** Git, World Clock and System Vitals come built in. Add your own, sandboxed and shown in plain
  words before you install. Or ask Sidefolk to write a small one for you; nothing installs until you click.
- **Picture:** `screenshots/settings-extensions-light.png`
- **Link:** "Write an extension" → docs/EXTENSIONS.md on GitHub.

## 11. Meet the family

- **Copy:** Mochi, the original robot, Spark and ten folks. Pick one, name it, give it a colour.
- **Picture:** `Resources/Character/companions.png` or `screenshots/settings-companion-light.png`

## 12. Ten languages

- **Copy:** English, Français, Español, Deutsch, Italiano, Português, 日本語, 한국어, 简体中文, العربية.
- **Pictures:** `screenshots/home-now-fr-light.png`, `home-now-ja-light.png`, `home-now-ar-light.png`
- **Small print:** Typing commands without AI works in English for now; with AI, ask in any language.

## 13. FAQ

Take five from the README FAQ: do I need AI, will it spend my quota, does it watch my screen, can it
delete my files, where is my data.

## 14. Footer

- What's not done yet → README section of the same name
- Release notes · GitHub · Privacy policy `[FOUNDER]` · Support: `[FOUNDER: support email]`
- Credits: GRDB.swift, KeyboardShortcuts, LobeHub Icons, weather data by Open-Meteo.com (CC BY 4.0)
- Trademarks line from the README: Claude and Claude Code are trademarks of Anthropic; ChatGPT, Codex and
  OpenAI of OpenAI; Apple, Mac and macOS of Apple. Sidefolk is not affiliated with or endorsed by them.
- © 2026 `[FOUNDER: legal name or company]`

## Meta

- **Title:** Sidefolk: a small companion for your Mac desktop
- **Description:** the meta description in [DESCRIPTIONS.md](DESCRIPTIONS.md)
- **Social preview image:** `screenshots/hero-light.png` cropped to 1200 × 630
- **Favicon:** `Resources/Icon/icon-macos-1024.png`, scaled
