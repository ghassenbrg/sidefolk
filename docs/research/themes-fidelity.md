# Themes: each board, element by element

2026-10-30 · The founder's rule for step 9 (themes-plan.md): a theme is done when its snapshots and its board in
`sandbox/theme-sandbox/` read as the same product, content and components included. This is the list that rule is
checked against. **Have** is in the app today; **Build** is new work; **Data** means the board shows something the app
doesn't record yet, so the data comes first (no fake features).

**Built 2026-10-31 (D64),** every Build and Data row below, as blocks a theme arranges, except: chips you edit with
Tab in the one bar (the Will do panel shows the parts; editing them is next), a progress bar for agents' runs (no run
reports progress yet, so none is drawn), Glance's restyle per theme, and the boards' exact sample words (the app
says its own, in its voice, without exclamation marks). Checked with `--ui-snapshots --theme` for each theme in
light and dark, French, and Arabic right to left.

## Shared by every board

| Element | Status |
|---|---|
| Header: greeting, then "3 decisions · 2 reminders left today · 1 page changed" (Harbor adds the date) | Build: counts by kind, not sentences |
| One bar result panel: **Will do** row (kind, title, chips for day, time, collection), the tool line ("reminders.create · low risk · understood on this Mac, no model call"), Ask … instead ⌘⏎, Save as a note ⌥⏎, "Tab edits a chip · Esc closes", "Nothing happens until you press ⏎" | Build: the plan as chips, Tab to edit a chip; the tool and risk come from the intent |
| Found list under the bar (Harbor): watch, note with its reminder, conversation | Have (SearchPage), restyle as the panel's list |
| Decisions show risk in words, the deadline, "Another app asked: answer with a click" | Have |
| Notebook: list, editor, **Connected** column (saved by, talked about in, related task, reminder, + Remind me) | Have (B12); column layout per board |
| Activity: grouped by time of day ("This evening"), risk chip, row opens with Undo · 11 min left, "Everyone" filter | Have, except the time-of-day groups and "Undo · n min left" wording: Build |
| Dark appearance of each | Tokens |

## Harbor · Desk (default)

| Element | Status |
|---|---|
| Two columns: left Needs you, then Your day; right Watching, Agents at work, Recently | Build (today it is one column) |
| Top bar: the one bar centred with the companion's face, "+ New ▾" menu (note, reminder, watch, collection) | Build: "+ New" menu |
| Sidebar: nook at the top (cushion), Trash and Settings at the foot | Have nook; Build the foot row |
| Watching as 2×2 tiles with a big state word (Changed, Passing, 34 %, 70 %), a sparkline for live values, "Rain tomorrow morning" | Build tiles; **Data:** keep recent readings for the sparkline |
| Your day as a rail with tomorrow beside it ("Tomorrow 10:00 Extension guide · + 2 more") | Have rail; Build the tomorrow column |
| Agents with a progress bar (Codex "running npm run e2e · 4 min") | Have rows; bar only when a run reports progress (**Data**) |
| Recently card with "Activity" link | Have |
| Glance on the desktop | Have |

## Board (Daylight, Night Studio, Paper Garden)

| Element | Status |
|---|---|
| Sidebar: wordmark with the theme's mark, Today with a red badge, Notebook with collections nested, Conversations with a count, Activity | Have, restyled |
| Nook at the **foot** of the sidebar: portrait, a speech bubble ("Evening! Three little things, then you're clear.") and "Watching 4 · next: stretch" | Build: nook placement and bubble style; the line is the nook line |
| Search field in the page header with ⌘K, and a round "+" | Build |
| Needs you as a row of cards (up to three, more scroll), ← → move, ⏎ answer, ⌫ not now | Build: horizontal queue |
| Three columns: Your day as a list with a now line and Done, "Calendar on"; Watching list with state chips (changed, passing, 34 %); Agents at work with "Recently" under it | Build: list day, watching list |
| From your notebook: three recent notes as cards, then the theme's art tile | Build; art per theme (image generation) |

## Console (Night Shift)

| Element | Status |
|---|---|
| Rail navigation: the companion's badge glowing while work runs, icons, a settings cog at the foot | Build: Rail recipe |
| Top bar: "Today · Fri 30 Oct, 17:58", command field ("type a command, a search or a question"), filters All · Agents · Mine · Watches | Build |
| Three columns: Queue (with Skipped), Agents (each session's steps, live, with risk), Signals (watches with sparklines) and Next (reminders compact) | Build; sparklines need **Data** |
| Queue keys j / k / ⏎ / ⌫, the shell command shown, a diff for a watch change, time left counting down | Build j/k; diff and time left Have |
| Your companion's own steps as a terminal-like log | Have the steps (Activity); Build the view |
| Status bar: companion watching n, guard mode, model, waiting, running, ⌘1–4 | Build |
| Editor: Markdown with tabs for open notes, collections at the left, references and outline at the right | Build: Markdown recipe |
| Activity as a Log: time, who, what, risk, result columns, mono | Build: Log recipe |

## Stage (Marshmallow)

| Element | Status |
|---|---|
| Pill tabs floating at the top (Today with a count, Notebook, Conversations, Activity), search and settings at the right | Build: Pills recipe |
| The companion big on the left in a sky that follows the time of day; naps when quiet ("naps when it's quiet") | Build; sky art per time of day (image generation) |
| Decisions as speech bubbles from the companion, another app's with its own badge | Build |
| The day as stickers (emoji, time, title; late one wiggles, still with Reduce Motion), "+ add" sticker, drag to retime | Build |
| Watching as round badges with a dot when changed, values inside | Build |
| Helpers at work with a striped progress bar | Build (bar needs **Data**) |
| Jotted today as chips | Build |
| Notebook: collections as big jars with emoji and counts, "+ New note" | Build |
| All clear: the companion cheers once when the queue empties, "Next up: …" | Build |

## Planner (Field Notes)

| Element | Status |
|---|---|
| Ribbon tabs on the right edge (Today, Notebook, Conversations, Activity) | Build: Ribbons recipe |
| Left page: big date, weekday, weather line ("Rain tomorrow in Fukuoka · from Weather" when a weather watch exists), ruled lines of the day with checkboxes, done times, reminder and calendar marks, now line, "Click a line to write · drag a line to change its time", Tomorrow, Jotted today | Build |
| Right page: "To decide" as index cards with a stamp for risk and a paper clip, Keeping an eye on (with "changed" stamps), the companion as a sticker with one line | Build |
| The one bar as a pen line with understood parts highlighted | Build (same plan data as the Will do panel) |
| Notebook with washi tabs for collections, links in the margin | Build |
| Activity as a Diary: sentences, risk stamps, "Run it now" | Build: Diary recipe |

## Order

1. Recipes as enums with every case, and the switch in Home (navigation, Today, Activity, editor).
2. Harbor's Desk to its board: it is the default.
3. Board, then the three Board themes with their art.
4. Console, Rail, Log, Markdown, then Night Shift.
5. Stage, Pills, then Marshmallow.
6. Planner, Ribbons, Diary, then Field Notes.
7. The one bar's Will do panel (shared), and the data items: reading history for sparklines, progress for runs.
