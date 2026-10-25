# Sam — UX research & accessibility

## 1. Seat & method
UX researcher; WCAG 2.2, VoiceOver and keyboard audits. A Nielsen heuristic pass plus 7 scripted task walkthroughs in Playwright WebKit on the live preview (`council/sam-walk.mjs`, `sam-a11y.mjs`, `sam-probe.mjs`; screenshots in `council/sam-shots/`), and code reading of `src/dashboard/*.ts`, `bubble.ts`, `main.ts` and `tokens.css`. I couldn't test the real overlay or VoiceOver itself; those points are marked "(inferred)".

## 2. First 30 seconds
The window is calm, with readable type, real focus rings and states written out in words. Then I type something ordinary to "Talk to Pip" and get "I don't know that one yet". It looks like a chat and behaves like a command line; participants will read that as "broken". The window's accessibility is well above average for a 3-day build. The desktop companion, the part the product is named for, barely works without a mouse.

## 3. Scores
- **Clarity of purpose: 4.** The window says "Today / Reminders / Notes" and the companion says "Talk to Pip". A first-time user can't tell whether this is a reminders app, a pet or a dev tool.
- **Ease of use: 4.** The core tasks work once you know the incantation. The natural phrasing fails, and the most obvious form (the Add reminder dialog) traps you with a fake date.
- **Visual quality: 7.** Consistent tokens and spacing, a coherent palette, and good dark mode contrast.
- **Usefulness to me: 4.** Reminders and dated notes are useful but thin (only a 10-minute snooze, no date browsing). The developer request flow is the strongest part.
- **Trust & safety: 6.** Permission cards show the exact command and folder, and nothing is preselected (`bubble.ts:14`). "Allow everything from this session" sits one tap from Allow, and "make coffee" is routed to the terminal.
- **Release readiness: 3.** There are task-blocking bugs in the main form, the companion has no keyboard path, and messages are timed out.

## 4. Top problems, ranked by impact on real users

1. **Blocker: the Add reminder dialog fakes a pre-filled date.** The Date field shows "10/25/2026" in grey, but its value is `""`. This is WebKit's placeholder for an empty date input, and the app's real engine is WebKit. I filled in the text and the time and pressed Save, and got "Choose a date and a time." (evidence: `sam-shots/t2-dialog-saved.png`; the script logged `date input value: ""`). Every first-time user who types "Call mom, 5:00 PM" hits this error.
   *Fix:* default the date to today, or to tomorrow when the time has already passed. Better still, make one "When" field that accepts "5pm" and shows what it understood.

2. **Blocker: "Talk to Pip" looks like a chatbot but is a fixed phrase list.** In both the window and the companion, `call mom at 5pm`, `call mom tomorrow 5pm` and `remember that dad likes blue scarves` all ended in "I don't know that one yet" (logged by `sam-walk.mjs`; `t2-overlay-typed-unknown.png`). The parser clearly saw a time in the text but still won't offer a reminder. Meanwhile `make coffee` becomes "Run this in your terminal?" (`overlay-make-coffee-reply.png`), which is the wrong kind of fallback for a calm assistant. The live "↵ preview" line is the one good mitigation, and it's Nielsen #1 done right.
   *Fix:* rename the field to something like "Quick add". Any text containing a time becomes a reminder draft; any other text becomes a note in an Inbox. Shell commands only run with an explicit `$` or `run` prefix. Never answer "I don't know": always produce an editable draft.

3. **Blocker (accessibility): the desktop companion has no keyboard or VoiceOver path.** The pet is a set of `IMG` elements with no tabindex or label (`sam-a11y.mjs` output). The summon shortcut only moves the pet to the cursor and never opens the field (`main.ts:306-311`). The overlay hands keyboard focus back after clicks (`main.ts:227`). Permission cards are deliberately never focused (`bubble.ts:14`), so a VoiceOver user hears the polite announcement but can't get to Decline or Allow (inferred, from code). Inside the page, the card buttons do tab correctly (`Close → Decline → Allow once → …`).
   *Fix:* ⌘⇧Space should open the field with focus in it. Add a second shortcut that focuses the newest card. Give the pet an accessible name and state ("Pip, Codex needs you").

4. **Major (accessibility): important content disappears on a timer (WCAG 2.2.1).** Companion reply lines vanish after 5–7 s (`bubble.ts` `say(reply, 6)`). The window's toasts last 4.5 s, or 9 s when they carry an Undo (`app.ts` toast). After Delete, focus drops to `BODY` (logged), and the toast sits at the end of the DOM, so a keyboard user has to travel through the whole page to reach Undo within 9 s. Measured: after 9.5 s the toast was empty.
   *Fix:* keep Undo toasts open while they are hovered or focused, and move focus to them, or offer ⌘Z for undo. After a delete, put focus on the next row. Give lines a minimum on-screen time of about 20 s, or keep them until dismissed when VoiceOver is on.

5. **Major: the developer permission flow is good but scrolls and loses its place.** From Today it takes 2 clicks (Review request → Allow once), and the confirmation "Allowed once. Sent to Codex." is clear (`t5-after.png`). But at the window's own 1040×740 size, Allow once sits at y=769, below the fold (logged). Opening the review also moves the sidebar highlight from Today to Sessions (`app.ts` `PARENT.review = "sessions"`). After answering, the same session row still says "Needs you" while the list says "No pending requests" (`t5-after.png`; this may be stale preview data).
   *Fix:* sticky decision footer; keep the origin tab highlighted.

6. **Major: the information architecture hides the developer half and splits Settings into a second app.**
   - The "AI tools" sidebar header is hidden until something is connected (`app.ts updateNav`), and it labels a single item.
   - Actions is one of the four pillars (PLAN-V2) yet sits at the bottom next to Settings, so it reads as a utility.
   - Settings replaces the whole sidebar with its own 9-item sidebar plus "Back to Sidefolk", a mode switch that feels like leaving the app (`light-settings.png`).
   - Task 7, "connect Claude Code", takes Settings → AI tools, 2 clicks, if you know to look in Settings. That page then shows three separate connections: "Claude Code", "Companion tools for Claude Code" and "Companion tools for Codex" (`full-settings-tools.png`). That's hooks vs MCP leaking into the UI.
   *Fix:* one sidebar: Today, Reminders, Notes, Actions, then Sessions (always visible, with a "Connect Claude Code" empty state). Keep Settings as a normal ⌘, view or sheet with about 5 categories. Use one "Connect Claude Code" switch that installs both pieces.

7. **Major: notes are easy to capture and hard to find later.** `note: …` adds an extra "which notebook?" step. Search lives only on the Notes page and matches text and project but not dates: searching "October" returned nothing (logged). There's no timeline across notebooks, and the chair's run shows "show my notes" isn't understood. Task 4, "find it next month", only works if you remember the exact words or the notebook.
   *Fix:* untagged notes go to an Inbox with no question asked. Add a single "All notes" timeline grouped by month, and let the Tell bar search.

8. **Minor: error recovery is uneven.** Reminders and notes have Undo. Saved actions are removed immediately, with no confirmation, toast or undo (`actions.ts:85`). Snooze offers only "10 min" (`reminders.ts`), with no "tomorrow morning" or custom time.
   *Fix:* the same Undo pattern everywhere, plus a snooze menu.

9. **Minor (accessibility): button names are ambiguous out of context.** Each reminder row has "Open / Snooze 10 min / Edit / Delete / Mark complete", five controls with identical names on every row. Sessions repeat "Open" and "Review" the same way. In the VoiceOver rotor you'd get "Delete, Delete, Delete" (WCAG 2.4.6).
   *Fix:* `aria-label="Delete Call mom"`; keep Mark complete and put the rest in a ⋯ menu.

10. **Minor (accessibility/contrast):** body text tokens pass. Light muted text is 5.1:1, light meta and quiet buttons 5.5:1, dark mode 8.3–9.7:1, and primary mint with ink 7.7:1 (measured). But placeholders are #a9a9a9, about 2.3:1. That matters because "Tell Pip…" is the field's only visible label, and the fake date in problem 1 uses the same grey. Also, in WebKit a plain Tab only cycles the Tell input and Examples. Buttons need Option-Tab or macOS Keyboard navigation turned on (`sam-probe.mjs`). That's normal on the Mac; the per-section menu shortcuts help.

**Genuinely good:** native `<dialog>` with focus return (`dialog.ts`); focus to the h1 on navigation (`app.ts:243`); `aria-current`, `role=switch` and `role=alert`; a 3px focus ring; Reduce motion and Large text; status never shown by colour alone; settings search. Setup: 4 clicks, no dead ends, and the 2-minute "stretch" reminder is a great activation moment.

**Task clicks:** T1 setup 4 · T2 Tell bar 1 (only with "remind me") / companion 4 / dialog 6+ with an error · T3 1–2 each, Undo times out · T4 2 to capture, no way to find by date · T5 2 + a scroll · T6 5 · T7 2 via Settings (hidden in the sidebar).

## 5. Feature verdicts
| Feature | Verdict | Reason |
|---|---|---|
| Pip desktop companion | REWORK | The heart of the product, but it needs a keyboard and VoiceOver path and timers that aren't hostile |
| Talking by typing (local phrase parser) | REWORK | Make it a forgiving quick-add that always drafts something; never "I don't know" |
| Tell bar in window | KEEP | Good preview line; rename it and make it search too |
| Reminders | KEEP | Core value; fix the date default, snooze options and undo focus |
| Notes & notebooks | REWORK | Inbox by default, plus a timeline and date search |
| AI "Draft a summary" | LATER | Costs quota; not needed to prove the core |
| Quick commands (run in terminal) | REWORK | Explicit prefix only; "make coffee" must not go to a shell |
| Saved actions | LATER | A power feature; removal has no undo |
| Open app/folder/URL | KEEP | Cheap, understood, safe |
| Watching Claude Code/Codex sessions | KEEP | Clear status vocabulary; this is the differentiator |
| Permission requests on the companion | KEEP | Best-designed flow here; make it reachable by keyboard |
| Per-session full access | REWORK | "Asks first / Full access" as a toggle button is cryptic; it needs a confirm |
| Start sessions | LATER | Adds surface area; Open/continue covers the need |
| Open/continue session | KEEP | Essential follow-through from a request |
| Sparks (worker companions per project) | CUT | Another concept to learn; screen clutter |
| Terminal inside Sidefolk | CUT | Out of scope; the user already has a terminal |
| Calendar heads-up | LATER | Nice, but another permission |
| Morning brief | LATER | Unproven |
| Weekly wins | LATER | Unproven |
| Ten characters + 3D/2D styles | REWORK | Ship Pip plus 2–3 others; one style |
| Make-your-own character import | CUT | Its instructions are a 16-pose prompt essay (`characters.ts:15`) |
| Accent colors | KEEP | Cheap; text never relies on it |
| Sounds & spoken voice | KEEP | Spoken voice is a real accessibility win; let "mute" find it |
| Setup guide | KEEP | 4 clicks, real reminder at once; good |
| Settings (9 categories) | REWORK | About 5 categories, inside the main sidebar |
| CLI `sidefolk here` | LATER | Developer nicety |
| MCP tools for agents | KEEP | Merge into the single "Connect Claude Code" |
| Dock app + window | KEEP | The accessible surface; make it the source of truth |

## 6. What v1 should be
**For** developers who run Claude Code or Codex on a Mac: a calm companion that tells you when an agent needs you and lets you answer it, and that also holds your reminders and quick notes.

**Must-haves**
1. A quick-add that never fails: any text with a time becomes a reminder draft, anything else becomes an Inbox note, and both can be edited before saving.
2. Every companion action reachable by keyboard and VoiceOver (the shortcut opens the field; a shortcut focuses the newest card).
3. Permission review that fits without scrolling, keeps the user's place, and has a single connect switch for Claude Code.
4. Nothing important on a timer: Undo stays until dismissed, focus is managed after deletes.
5. One sidebar, with Settings folded into it and about 5 categories.

**Must-cuts:** Terminal inside Sidefolk, Sparks, character import, Start sessions, AI summary (for now).

**Vote: EVOLVE this codebase.** The accessibility foundations in the window (dialogs, focus, roles, tokens, contrast) are solid and would be costly to rebuild. The problems are interaction design and scope, not architecture.

## 7. The one thing
If I type "call mom at 5pm" and Pip says "Got it, call mom today 5:00 PM [Save] [Change]", I'd keep it. If it says "I don't know that one yet", my participants uninstall it in the first session.
