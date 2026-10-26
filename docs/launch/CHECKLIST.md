# Public release checklist (not code)

What stands between 0.1.0 and a public launch that isn't a code change. Nobody has been contacted and
nothing has been published; every "next action" is for the owner to take. Status as of 2026-10-27.

**Owners:** *Founder* (decisions, accounts, money, signatures), *Founder + lawyer* (legal wording),
*Engineering* (an agent or developer can do it once the founder decides), *Design*.

**Order:** the P0 rows block any public download; P1 rows block the launch posts; P2 can follow.

## Legal and identity

| # | Item | Why it matters | Owner | Status | Next action |
|---|---|---|---|---|---|
| 1 | **Licence** | P0. The GitHub repository is **public**, the README explains how to build it, and LICENSE grants **no right** to use, copy or modify it. People will build it anyway, and contributors can't contribute. D17 left this open on purpose. | Founder + lawyer | Undecided | Choose: open source (MIT / Apache-2.0 / GPL-3.0), source-available (e.g. PolyForm Noncommercial, BSL), or closed (make the repo private, ship binaries only). Then update LICENSE, the README's licence section and the GitHub "license" field. |
| 2 | **App name and trademark search** | P0. "Sidefolk" is the app, bundle ID (`app.sidefolk.Sidefolk`), CLI and domain. Renaming after launch costs users their permissions and settings. | Founder | Not done | Search USPTO, EUIPO, WIPO and JPO for "Sidefolk" in classes 9 and 42; check the App Store, Setapp, GitHub and npm; consider filing. Do a lighter check for "Mochi" (several apps use the word) and keep it as the mascot's name, not a product name. |
| 3 | **Bundle ID and domain match** | P0. The bundle ID `app.sidefolk.Sidefolk` implies owning `sidefolk.app`; sample data mentions `sidefolk.app` and `staging.sidefolk.app`. macOS keys permissions (microphone, Automation, notifications) to the bundle ID, so it must not change after the first public build. | Founder | Unknown | Confirm `sidefolk.app` is registered to you; if not, register it or choose the final domain and bundle ID before signing. |
| 4 | **Third-party logos in the app** | P1. Settings › AI and Agents show Claude, OpenAI/Codex, Gemini, Mistral, Groq, xAI, DeepSeek, OpenRouter, Ollama and LM Studio marks (LobeHub Icons, MIT, which grants no trademark rights). Anthropic's guidelines say use is limited to what Anthropic permits and that it supplies its own logo files; OpenAI's and xAI's pages couldn't be read (Resources/Brand/third-party/README.md). | Founder | Not asked | Write to Anthropic (marketing@anthropic.com, as the third-party README suggests) and OpenAI's brand contact describing the use (identifying the service in Settings only). Until answered: keep logos out of marketing, use names as plain text, prefer screenshots without Settings › AI/Agents. If anyone says no, swap that row to a monogram (one line in `AIChoice.logo`). |
| 5 | **Terms for driving Claude Code and Codex on a user's plan** | P1. Sidefolk runs the user's own `claude -p` and `codex exec`; the launch copy says "use the plan you already pay for". | Founder | Not checked | Read Anthropic's and OpenAI's current consumer terms and usage policies for third-party apps invoking their CLIs; adjust the wording in DESCRIPTIONS.md and the posts if needed. |
| 6 | **Open-Meteo terms** | P1. Weather values and the Weather extension call Open-Meteo's free API straight from users' Macs. Its terms (checked 2026-10-27) allow the free API for **non-commercial** use only, under 10,000 calls a day, data under CC BY 4.0. | Founder | Attribution added to THIRD_PARTY_NOTICES.md and the README | If Sidefolk is paid or commercial: take an Open-Meteo plan, ask them, or switch provider. Engineering: show "Weather data by Open-Meteo.com" in the app where weather appears. |
| 7 | **Privacy policy** | P0 for a website and any directory listing. | Founder + lawyer | Not written | Base it on the README's Privacy table: no data collected by the author; what goes to the AI provider, sites, Open-Meteo and ElevenLabs, and only when the user chose it; local storage, retention (7 days of history, 7 days of logs), export and delete. Publish at a stable URL and link it from the README and About. |
| 8 | **Terms of use / EULA** for the binary | P1 | Founder + lawyer | Not written | Short terms: as-is, the user is responsible for what they approve, third-party services under their own terms. Shown on the website; the DMG can carry it as a licence agreement. |
| 9 | **Who publishes** | P0. The Developer ID name appears in Gatekeeper and in "© 2026" lines (Info.plist says "© 2026 Sidefolk", LICENSE says the founder). | Founder | Undecided | Decide: individual or company. Make the copyright line the same everywhere (Info.plist, LICENSE, About, website). |

## Distribution

| # | Item | Why it matters | Owner | Status | Next action |
|---|---|---|---|---|---|
| 10 | **Apple Developer Program and Developer ID** | P0. Without it a download is blocked by Gatekeeper. No Developer ID identity exists on the build Mac (STATUS). | Founder | Not done | Join the Apple Developer Program (individual or organisation, matching #9), create a "Developer ID Application" certificate, store notary credentials (`xcrun notarytool store-credentials sidefolk …`). |
| 11 | **Notarization** | P0 | Founder, then Engineering | Script ready (`scripts/release.sh`) | Run `scripts/release.sh` with `SIDEFOLK_SIGN_IDENTITY` and `SIDEFOLK_NOTARY_PROFILE`. Then on a **clean** Mac (or new user account): open the DMG, check Gatekeeper, the microphone, Automation (Notes, Reminders), notifications and login-item prompts, and that the `sidefolk` helper runs. |
| 12 | **Where downloads live** | P0 | Founder | Undecided | GitHub Releases (simplest; tag `v0.1.0`, attach the DMG and its SHA-256) or the website. The Mac App Store is very likely out: it requires the App Sandbox, and Sidefolk spawns `claude`/`codex`, runs `sandbox-exec` and edits files in your home folder. |
| 13 | **Update mechanism** | P1. D15: no auto-update, and no "Check for updates" button that can't work. Without one, every 0.1.x fix needs users to download again by hand. | Founder, then Engineering | Not built (deliberately) | Decide for 0.1: (a) "watch the GitHub repo / website for releases", said plainly in the README, or (b) Sparkle with an EdDSA key and an appcast you host (needs #10 and a URL). Data migrations are already versioned. |
| 14 | **Crash reports** | P1 | Founder | None (no crash reporter) | Decide deliberately. Recommendation for 0.1: no crash reporter (it would contradict "no telemetry"); ask users to attach Settings › Privacy › Export diagnostics (no content) plus the macOS crash log from `~/Library/Logs/DiagnosticReports`. Write that in the support page. |
| 15 | **Analytics** | P1 | Founder | None | Confirm the deliberate **no**: the README, descriptions and posts already say "no analytics, no telemetry". If that ever changes it must be opt-in and the copy must change first. |
| 16 | **Intel Macs** | P2 | Founder | arm64 only | Decide whether to ship universal. If yes, Engineering builds and someone tests on an Intel Mac; until then the copy says Apple silicon only. |

## Website, support and channels

| # | Item | Why it matters | Owner | Status | Next action |
|---|---|---|---|---|---|
| 17 | **Website** | P0 for the launch posts | Founder (+ Design) | Copy outline ready: [LANDING-PAGE.md](LANDING-PAGE.md) | Choose a host, build the one page, add the privacy policy, support and press-kit links. |
| 18 | **Support email** | P0. No contact address exists anywhere in the repo or app. | Founder | None | Create `support@<domain>` (and `press@`, or one address for both). Put it in the README, website, About and press kit. |
| 19 | **Security contact** | P1. docs/SECURITY.md has a threat model but no way to report a vulnerability. | Founder | None | Add a `SECURITY` reporting address (or GitHub private vulnerability reporting) and a line on what you'll answer. |
| 20 | **GitHub repository page** | P1. The description still says "A desktop pet for your AI coding agents." | Founder | Outdated | Update the description (use the one line from DESCRIPTIONS.md), add topics (macos, swift, mcp, desktop-companion), the website URL, a social preview image (`screenshots/hero-light.png` at 1280 × 640), and decide on Issues and Discussions. |
| 21 | **Pricing** | P0 for the store copy and posts | Founder | Undecided | Free, paid, or free with paid extras. If paid: payment provider, licence keys without accounts, refunds, VAT; and re-check #6. Every `[FOUNDER: price]` in the kit waits on this. |
| 22 | **Launch accounts** | P1 | Founder | Unknown | Hacker News account in good standing, Product Hunt maker profile (and a hunter if wanted), X handle, Reddit account (read r/macapps rules on the day), LinkedIn. Check the name "sidefolk" is free on each. |
| 23 | **Real desktop media** | P1. Every picture in the kit is an offscreen render; none shows the companion on an actual desktop. | Founder | Not recorded | Record the 60-second video ([DEMO-VIDEO.md](DEMO-VIDEO.md)) and take two or three real desktop screenshots. Add them to the press kit. |
| 24 | **Founder words** | P1 | Founder | Placeholders | Fill every `[FOUNDER: …]` in docs/launch/: quote, bio, photo, why you built it, links, price. `grep -rn "FOUNDER" docs/launch README.md docs/RELEASE-NOTES.md` lists them. |

## Checks a person has to do

These are hand checks, not code. STATUS lists them as not yet exercised.

| # | Item | Owner | Next action |
|---|---|---|---|
| 25 | Claude Code hooks in a real session ("needs you", "finished", Open session) | Founder | Connect on your own setup (it edits `~/.claude.json` and `~/.claude/settings.json`, with backups) and run a session that waits for permission. |
| 26 | Connect and Disconnect for Codex on a real config | Founder | Same, with `~/.codex/config.toml`; check Disconnect leaves the file as it was. |
| 27 | Notification permission prompt, login item from /Applications | Founder | On the notarized build, in a fresh user account. |
| 28 | Several displays, fullscreen apps, Spaces | Founder | Move the companion between displays; open a fullscreen video; check quiet behaviour. |
| 29 | Apple Notes on a real, large library | Founder | Copy (not remove) a few hundred notes in several requests; check progress, dates and attachments named. Then remove two copied notes and find them in Recently Deleted. |
| 30 | macOS 15 and macOS 26 | Founder or a tester | Install and run the ten-minute tour in REVIEWER-FAQ.md, including voice ("basic" recognizer on 15). |
| 31 | Translations | Native speakers | A short review per language, Arabic right to left in particular. `scripts/translations.py export <lang>` gives each reviewer the strings. |
| 32 | Brand sign-off | Founder | STATUS still lists the founder's look at the new wordmark, the menu bar glyph and the hero with each companion and colour. |

## Done in this pass

- README rewritten for people who have never heard of Sidefolk, with a Privacy table, AI choices,
  install, extensions, agents, languages, an honest "what isn't done yet" and an FAQ.
- docs/RELEASE-NOTES.md for 0.1.0, from STATUS, DECISIONS and the code.
- This kit: [DESCRIPTIONS.md](DESCRIPTIONS.md), [LANDING-PAGE.md](LANDING-PAGE.md),
  [posts/](posts), [DEMO-VIDEO.md](DEMO-VIDEO.md), [press-kit/](press-kit/README.md),
  [REVIEWER-FAQ.md](REVIEWER-FAQ.md) and [screenshots/](screenshots) (rebuild with
  `swift scripts/launch-screenshots.swift`).
- Open-Meteo attribution added to THIRD_PARTY_NOTICES.md.
