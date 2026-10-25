# Seat: Maya (ops manager, not technical)

## 1. Seat & method
I'm Maya, 38, an operations manager. I live in Outlook, Teams and Notion, and Apple Reminders on my iPhone. I tested as a black box. I used the screenshots in shots/, docs/GUIDE.md and the README's "Use it" section, and drove the live preview with my own WebKit script. I typed 51 phrases into both the Tell bar and the companion field and clicked through setup. Raw output: council/maya-phrases.txt (27 phrases), the output of council/maya-more.mjs (24 more), and council/maya-views.txt (text of every screen). Screenshots are in council/maya-shots/. I didn't open any source code, memory/ or the plan documents.

## 2. First 30 seconds
The bunny is adorable. "Hi, I'm Pip. Keep a small reminder or a dated note. No AI connection needed." is exactly what my colleague promised, and "Set a two-minute reminder" is a great first button (maya-shots/setup1-after.png). Then step 3 is titled "AI tools, when you need them" and talks about Claude Code, Codex, "work sessions" and "review requests" (maya-shots/setup3.png). Then I land on Today, and the first thing it says needs me is "Run a command?" from "Codex · Work session 04c1" (light-home.png). I'd think I installed the wrong app, or that something is running on my laptop. My gut: a cute shell around a programmer's tool, and I'm a guest in it.

## 3. Scores
- **Clarity of purpose: 4.** Setup step 1 is crystal clear. Everything after it (sidebar "AI tools > Sessions", "Actions", the help card) says "this is for developers".
- **Ease of use: 5.** The preview line under the field ("↵ Remind you Fri, Oct 30 02:00 PM: submit expenses") is genuinely great. But 18 of my 51 natural phrases got "I don't know that one yet", and I have to learn the magic words "remind me…".
- **Visual quality: 8.** It's calm, warm, well spaced, and the 3D bunny is lovely. The Reminders and Add-reminder dialog look like a real Mac app (light-reminders.png, light-new-reminder.png).
- **Usefulness to me: 3.** Its reminders live only on this Mac (GUIDE "Privacy": everything stays in ~/Library/…), so they never reach my phone. It doesn't connect to Outlook or Teams, and its notes duplicate Notion.
- **Trust & safety: 4.** Ordinary words become "Run this in your terminal?" ("less email please", "touch grass", "make coffee"). A pop-up asking me to Allow `rm -rf node_modules…` (overlay-permission.png) would scare me.
- **Release readiness: 3, for someone like me.** The reminder parser has date bugs, the app is unsigned (per the brief), and the jargon is everywhere.

## 4. Top problems, ranked
1. **Blocker: a normal sentence can turn into a terminal command.** "less email please" is previewed as "Run `less email please` in your home folder, in your terminal (you confirm first)". "touch grass" opens a "Run in your terminal?" card with a "Run in terminal" button (maya-phrases.txt [27]). "make coffee" does the same (overlay-make-coffee-reply.png). I don't know what a terminal is, and a big green button is asking me to "run" something. **Fix:** turn commands off unless the user opts into developer mode. Even then, only treat text as a command when it starts with a known command word *and* doesn't read like English.
2. **Blocker: reminders don't reach my phone.** The GUIDE says reminders stay in the app's folder on this Mac. Apple Reminders is on my wrist and in my pocket. **Fix:** v1 should save to Apple Reminders (EventKit), or at least send macOS notifications that sync. Pip becomes the cute way to *add and nag*, not a separate silo.
3. **Major: you have to say "remind me".** Things I'd naturally type all failed: "dentist appointment thursday 2:30", "don't forget team lunch tomorrow 12:30", "lunch with Priya tomorrow at noon", "call Sarah back", "add eggs to grocery list", "cancel the dentist reminder", "snooze", "find my notes from monday" (maya-phrases.txt [4,6,8,14,22,23]; maya-more output). **Fix:** treat any text with a date or time as a reminder. Treat anything else as "Save this as a to-do or note?" instead of "I don't know that one yet".
4. **Major: wrong times.** "remind me tonight to water the plants" became "today 09:00 AM" ([26]). "remind me at 3" became "Set a reminder (then pick when)", so the 3 was ignored. "end of day" and "every other week" weren't understood either. The chair also found "tomorrow standup 9:30" set for 9:00 and "10 minutes before" landing on the wrong day. A reminder app that gets the time wrong once gets deleted. **Fix:** tonight means 20:00, end of day means 17:00, and a bare "at 3" means the next 3:00 during waking hours. Add tests for these.
5. **Major: the reminder text gets mangled.** "remind me on Nov 3 at 10am about performance reviews" was saved as "**on about** performance reviews" ([11]). **Fix:** strip "on <date>" and "about" properly.
6. **Major: the jargon count on my screens (distinct unfamiliar terms):**
   - Setup step 3: 4 (Claude Code, Codex, work sessions, review requests).
   - Today: about 11 (AI tools, Sessions, Codex, Claude, Work session, 04c1, 7b3e, api, "Run a command?", launch-notes.md, nightly build).
   - Reminders: 3 ("api", "set by Claude", nightly build).
   - Notes notebook: 4 (Copy as Markdown, Show in Finder, "api", Draft a summary that needs Claude Code or Codex).
   - Sessions: about 12 ("Asks first", Spark, "Project companion options"…).
   - Actions: 7 (npm, deploy, staging, ~/git/api, Run quietly, Run in terminal, Commands).
   - Settings > AI tools: about 15 (iTerm, Command line tool, `sidefolk here --name Backend`, "Companion tools for Claude Code", Default terminal…).
   - Settings > About & data: 6 (~/Library/Application Support/dev.sidefolk.companion, Logs, issue, work session…).
   - Settings > Privacy: 1 (Mission Control).
   - The companion's "help" card: about 12 (ls -la, npm test, api, VS Code, spark, claude session, deploy, login migration… in overlay-help-reply.png).
   - The "I don't know" reply: 2 ("run commands", "work sessions"; overlay-unknown-reply.png).

   **Fix:** a non-developer mode that hides Sessions, Actions, the AI tools settings and all developer examples. The help card shows life examples (dentist, laundry, payroll).
7. **Major: no small talk.** "hi pip" and "thanks!" both get "I can set reminders, run commands and open your work sessions." For a *desk buddy* that's cold. **Fix:** about 20 canned friendly replies (greetings, thanks, "good morning", "how are you"), all local.
8. **Major: calendar.** "what's on my calendar today" isn't understood. "next meeting" answers "Turn on the calendar heads-up in Settings → Reminders & calendar first" ([15],[16]). My meetings are in Outlook. Whether Outlook's calendar shows up in "your Mac's calendars" depends on my setup (inferred), and I'd never know. **Fix:** ask for calendar access in setup, with one plain sentence, and understand "what's on today" and "what's my day".
9. **Minor: "next tuesday" on a Sunday meant the Tuesday two days later** ([10]). That's ambiguous. Show the date in the confirmation (it does) and offer "the week after?".
10. **Minor: the reminder confirm card adds a click.** Every typed reminder needs Save after Enter ([3],[5]…). The preview line already confirmed it, so let Enter save and show Undo, as notes already do ([13], "Noted in Notes… Undo").

**What worked well:** "remind me friday at 2 to submit expenses", "remind me at 4 to pick up the kids" (16:00, correctly assumed afternoon), "in 20 minutes", "in half an hour", "every monday at 9 prepare the weekly report", "note: vendor contract renews in March", "note for budget: …" (asks "Start budget?"), "open outlook" and "open teams" (previews look right; actual opening needs the desktop app), "what can you do" → help. I'd call 14 of 51 phrases right, 4 wrong or garbled, 2 dangerously turned into commands, and the rest not understood or only half done.

## 5. Feature verdicts
| Feature | Verdict | Why (Maya's view) |
|---|---|---|
| Pip desktop companion | KEEP | The reason I'd install it. Cute, stays put, calm. |
| Talking by typing (local parser) | REWORK | The preview line is great. It needs any text with a date to become a reminder, small talk, and no commands for non-developers. |
| Tell bar in window | KEEP | Same parser. Fine once the parser is fixed. |
| Reminders | REWORK | The core value, but it has to sync with Apple Reminders/iPhone and get "tonight" and "at 3" right. |
| Notes & notebooks | KEEP (small) | "note: …" is nice for quick capture. Keep it simple, with no Markdown or Finder up front. |
| AI "Draft a summary" | LATER | Needs Claude Code or Codex. Meaningless to me. |
| Quick commands (run in terminal) | CUT for v1 default | Scary, and fires on English words. Developer mode only. |
| Saved actions | LATER | "npm run deploy -- staging" isn't my world. Maybe "open my weekly report doc" later. |
| Open app/folder/URL | KEEP | "open teams" is something I'd actually say. |
| Watching Claude Code/Codex sessions | CUT from my view | I'll never have these. Hide unless connected. |
| Permission requests on companion | CUT from my view | Showing "rm -rf" to a non-developer is frightening. Developers only. |
| Per-session full access | LATER | Not for me. Sounds risky. |
| Start sessions | CUT from my view | Developer-only. |
| Open/continue session | CUT from my view | Developer-only. |
| Sparks | LATER | Confusing ("Spark" is also a character's name). |
| Terminal inside Sidefolk | CUT | "Preview: no shell runs here. $" means nothing to me. |
| Calendar heads-up | KEEP, promote | "Meeting in 5 minutes, Join" is the killer feature for me. Turn it on in setup. |
| Morning brief | KEEP | "Here's your day" from a bunny is lovely, if it shows meetings and reminders. |
| Weekly wins | LATER | Nice, but only if my notes live here. |
| Ten characters + 3D/2D | REWORK | Three or four is plenty. 3D vs 2D is a setting I don't care about. |
| Make-your-own character | LATER | "pose sheets in any grid", "idle.png"… too much. |
| Accent colors | KEEP (small) | Cheap delight. |
| Sounds & spoken voice | KEEP | A gentle sound at reminder time matters more than visuals. |
| Setup guide | REWORK | Steps 1–2 are good. Step 3 "AI tools" must disappear for non-developers. |
| Settings (9 categories) | REWORK | 4 would do: General, Companion, Reminders & calendar, Privacy. |
| CLI `sidefolk here` | CUT from my view | Developers only. |
| MCP tools for agents | LATER | Invisible to me. Fine to keep in a developer mode. |
| Dock app + window | KEEP | Normal Mac app feel. The Reminders page looks like Apple's. |

## 6. What v1 should be
**One sentence:** a calm desk buddy for busy Mac office workers that turns anything you type ("dentist thu 2:30") into a reminder on your phone and taps you on the shoulder before meetings. AI-agent features stay behind an explicit "I'm a developer" switch.

**5 must-haves:**
1. Reminders saved to Apple Reminders/iCloud, so they reach my iPhone and Watch.
2. A forgiving parser: any date or time means a reminder, "tonight", "end of day" and "at 3" are handled correctly, and "cancel/snooze/what's today" work.
3. Calendar heads-up (including meetings that Outlook syncs to the Mac) with a Join button, set up during onboarding.
4. A morning "here's your day" from Pip, plus a gentle sound and a little hop when something's due.
5. Zero jargon in the default mode: no Sessions, Actions, terminal, api or Codex anywhere. A help card with everyday examples.

**5 must-cuts (for the default mode):**
1. Typing into Pip running shell commands.
2. Sessions, the Terminal tab and Actions in the sidebar.
3. Setup step 3, "AI tools".
4. Make-your-own character and 3D/2D style choice. Keep 3–4 characters.
5. The settings categories for AI tools, command line tool and default terminal.

**Vote: RESTART the UI on this core.** The engine works: the local parser with a live preview, the overlay companion, the reminder store, the calendar read. The polish is real. But the whole surface is organized around developer concepts, and my use is an afterthought. A new top level with two modes (Everyday vs Developer) is cheaper than pruning screen by screen. Restarting everything would throw away the parts I actually liked.

## 7. The one thing
**Love it if:** I type "dentist thursday 2:30" into the bunny, it buzzes my iPhone at 2:00 on Thursday, and Pip waves at me on my Mac too. That replaces "Hey Siri, remind me" with something that makes me smile.
**Uninstall it if:** Pip asks me to "Run in terminal" once more, or a reminder shows up at 9 AM when I said "tonight". It took me about 10 minutes of trying to hit both.
