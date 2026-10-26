# 60-second demo video

One take per shot on a real Mac, cut together. Everything shown must be real: no mock-ups, no sped-up
AI answers without saying so. Captions carry the story (most people watch muted); the voice-over is
optional and says the same thing.

## Before recording

- A clean macOS user account or a fresh data folder, a plain wallpaper, the Dock hidden, Do Not
  Disturb on, the menu bar tidy. 2560 × 1440 or 1920 × 1080, 60 fps.
- Mochi as the companion, Presence *Always*, approval mode *Ask once per kind*.
- Claude Code (or Codex) connected as the AI, and the `sidefolk` command installed.
- Downloads shared with Sidefolk beforehand (so the watch doesn't stop to ask for folder access on camera),
  and a `report.pdf` ready to drop in from another folder.
- A few notes saved the day before ("Launch checklist", "Show HN draft") so the question in shot 6 has
  something to work from, and three PDFs in Downloads for shot 7.
- A project whose `npm test` fails after about five seconds with a readable error.
- Voice on, Spoken replies *Only when I spoke*, a good Apple voice installed.
- Music: something quiet and licensed `[FOUNDER: track and licence]`.

## Shot list

| Time | Shot | What happens on screen | Caption | Voice-over |
|---|---|---|---|---|
| 0:00–0:05 | Desktop, wide | Mochi stands on the bottom edge, blinks, glances at the pointer. | This is Mochi. | This is Mochi. It lives on your desktop. |
| 0:05–0:13 | Ask panel, close | ⌘⇧Space. Type `remind me in 10 minutes to stretch`. The hint reads "Reminder · Today … · no AI". Enter: the reminder card. Tempo sits down beside Mochi (a reminder is due within 15 minutes). | Plain words. No AI needed. | Tell it things in plain words. Reminders and notes are handled on your Mac, without AI. |
| 0:13–0:20 | Ask panel, then desktop | Type `tell me when report.pdf appears in Downloads`. Cut: drop `report.pdf` into Downloads in Finder. Scout appears; Mochi steps forward with a bubble. | It keeps watch. | It keeps watch: pages, sites, files… |
| 0:20–0:25 | Desktop, close on Mochi | Type `tell me the CPU every 10 seconds`. A "CPU 18 %" pill appears above Mochi and updates once. | Live values, at a glance. | …and the numbers you care about. |
| 0:25–0:33 | Terminal beside Mochi | `sidefolk run -- npm test`. Byte sits beside Mochi. The test fails: a bubble "npm test failed (exit 1)" with the last error lines and Copy command. | Your terminal can reach it. | Your terminal and your coding agents can reach it too. |
| 0:33–0:42 | Ask panel | Type `which of my launch notes should I do first?` (check that the hint says it uses AI; "what … did I save" questions are answered without AI). Mochi thinks, then the answer card. Keep the real wait, or cut it and show "(sped up)". | Bring the AI you already use. | For answers, it uses the AI you already have. |
| 0:42–0:49 | Ask panel, then Activity | Type `move the PDFs in Downloads into Downloads/Invoices`. The approval card "Move 3 files?" lists them. Click Allow; Mochi hops. Cut to Activity showing the row. | You decide what it may do. | It asks before it changes things, and keeps a list of everything it did. |
| 0:49–0:55 | Desktop, close | Hold ⌘⇧Space and say "remind me in twenty minutes to call Sam". Ears up while listening; release; the card, and one short spoken line. | Talk to it, if you like. | And you can talk to it. |
| 0:55–1:00 | End card | Settings › Companion gallery for one second, then the logo on white with the URL. | Sidefolk · for macOS 15 or later · `[FOUNDER: URL]` | Sidefolk. A small companion for your Mac. |

## Cut-downs

- **30 seconds:** shots 1, 2, 3, 5, 6 and the end card.
- **15 seconds:** shots 1, 2 and 3 with the end card; caption "Notes, reminders and watches. On your
  desktop."

## Notes

- Shot 7 needs the AI to list and move files; rehearse it on the recording setup. If Downloads isn't
  shared, a second card asks for it, which is honest but slower.
- Don't linger on Settings › AI or Agents: they show other companies' logos (see CHECKLIST.md).
- Show the "no AI" hint clearly in shot 2; it's the point people remember.
- Export a version without captions for Product Hunt, and a square 1080 × 1080 one for social posts.
