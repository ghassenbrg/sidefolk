# Build plan: the new Home and themes

2026-10-30 · Complete scope, in build order. It replaces the earlier step-1 plan: nothing here is deferred, and the
order only says what is built first. Harbor is the default while the others are built.

Rules that hold throughout:
- Every action keeps going through `ToolExecutor`, `ApprovalBroker` and the attention store.
- A theme is data and never code.
- No fake features: each item ships with what makes it real.

## A. Theme foundation

1. **Tokens at runtime.** `Theme` keeps every name (`Theme.ink`, `Theme.Space.l`, `Theme.Font.title`…) but resolves
   it through an `@Observable ThemeStore` held by `AppServices` and injected into every window's environment.
   Harbor's values are today's exactly, so UI snapshots before and after must match pixel for pixel. Folk colours
   and collection colours stay app-owned.
2. **Roles:** background, surface, surfaceRaised, sunken, line, ink, inkMuted, inkFaint, accent, onAccent,
   accentSoft, selection, focus, link, attention, success, warning, danger, highlight. Each has a light and a dark
   value.
3. **Type:**
   - display: system, rounded or serif;
   - text: always system;
   - exact: mono;
   - scale: 0.9 to 1.15;
   - weight bias;
   - density: compact, regular or relaxed, which scales `Space`.
4. **Shape:** radii for controls, cards, fields and windows, clamped (controls 4 to 999, cards 0 to 28).
5. **Material:** a solid or translucent sidebar, plus an optional paper grain (a PNG tile at 6 % or less).
6. **Motion:** calm, bouncy or none. Reduce Motion always forces none.
7. **Companion nook:** a style (cushion, badge, sticker, stage, rail), an optional backdrop image, and a suggested
   companion that is offered and never switched by itself.
8. **Art:** optional PNGs for empty states and the Board's art tile, never placed behind text or controls.
9. **Recipes:** navigation, today, activity and editor, each one an enum that the app's views switch over
   (section C).
10. **Manifest:** `theme.json` with format 1 (see [theme.example.json](theme.example.json)), loaded by a
    `ThemeLoader` that validates it. Validation:
    - every role is present, or falls back to Harbor's value;
    - contrast is checked in both appearances (4.5:1 for text on its surfaces, 3:1 for controls, focus and
      separators that carry meaning);
    - type values come from the allowed sets;
    - images are PNGs, at most 2 MB and 2048 px, decoded once and re-encoded by Sidefolk before use;
    - the manifest is at most 64 KB.

    Each problem has a message saying what to fix, in plain words.
11. **Settings › General › Appearance:**
    - The theme picker shows live previews of each theme in light and dark.
    - **Same as Mac / Light / Dark** stays as it is.
    - **Layout** can override each recipe ("Use the sidebar") per theme.
    - **Load theme from folder…** installs a theme from a folder.
12. **Folder themes reload live.** A theme loaded from a folder is watched: saving `theme.json` repaints every window
    within a second. This is what makes writing a theme quick.
13. **Command line:**
    - `sidefolk theme new "<Name>"` writes a manifest copied from Harbor, with comments, into a new folder.
    - `sidefolk theme check <folder>` runs the same validator and prints the contrast table.
    - `sidefolk theme preview <folder>` renders board-style PNGs of Today, the Notebook and Activity in both
      appearances, using the UI-snapshot fixtures.

## B. The shared Home: every recipe shows the same things

1. **Today replaces Now.** "Today" is already translated (reminder groups use it). The menu bar's Now entry and
   `openNow` follow.
   - The greeting card becomes a header line: the greeting, then "3 decisions · 2 reminders left today · 1 page
     changed".
   - The Ask button becomes the one bar (B4).
2. **The decision queue**, built on one `TodayModel` used by every recipe:
   - **What's in it:** pending Guard approvals (`ApprovalBroker.pending()`), sessions that need you, attention
     items and skipped steps. They are ordered by deadline, then by age.
   - **Deadlines:** `ApprovalRequest` gets an `expiresAt`, set in `requestIfRoom` from its timeout, and shown as
     "stops at 18:08".
   - **Answering:** goes through `broker.resolve`, the same as the Ask panel. A card answered in one place leaves
     the other through `.approvalResolved`.
   - **Keyboard:** ↑↓ (or ←→ in Board) move, ⏎ runs the primary action, ⌫ is Not now, Deny or Dismiss, and S
     snoozes.
   - **Safety:** another app's request (a `caller.kind` other than user, agent or command) never takes ⏎. It says
     "Another app asked: answer with a click". High risk arms after a short pause, as `SkippedStepRow` does, and
     never offers Always.
   - **Focus:** after an answer, focus moves to the next row. Rows never move under the pointer.
3. **The day line:** pending reminders for today and tomorrow, plus calendar events (B8), with a now line.
   - Dragging a reminder changes its time through `editReminder`, and ⌘Z undoes that.
   - Double-clicking an empty time adds a reminder there.
   - A tick marks it done.
   - Late reminders are marked.
4. **The one bar.** One `OneBarModel` and view, used in two places: Home's toolbar (⌘K) and the Ask panel, which
   becomes the same component, so its shortcut is the one bar from anywhere.
   - **Will do:** `IntentParser.parse` produces a preview: the kind, the understood parts as chips, the tool,
     the risk, and "understood on this Mac, no model call". Tab moves between chips, and each chip edits its value
     in a small popover (time, day, collection, title).
   - **Found:** notes (`NotebookStore.search`), conversations (`exchanges.conversations(matching:)`), reminders,
     watches and Activity rows. Results are grouped and capped at 5 per group, with ⌘↓ to show more.
   - **Keys:** ⏎ runs through `LocalIntentRunner`, ⌘⏎ asks the AI, ⌥⏎ saves a note to Inbox, Esc clears.
     Nothing runs while you type.
   - **Result:** the toast, with Undo when the outcome allows it.
5. **Watch tiles:** each watch shows its value, its last check, and its last change.
   - Page watches keep the last change's added and removed lines from `TextDiff.compare` in their state, capped
     at 2 KB.
   - "See the change" shows those lines.
   - A changed tile stays highlighted until it's opened.
6. **Agents at work:** live sessions (working, waiting for you, finished in the last hour) with their recent tool
   calls from the audit log by `runId`, and a progress line when a job reports one. Your own companion's work
   appears there too.
7. **The companion's nook,** styled by the theme:
   - It shows the companion's portrait or 3D stage and one line from `LiveStateSummary` ("Watching 4 things ·
     next: stretch at 17:30").
   - Clicking it opens Glance (B10).
   - It sleeps when the desktop companion sleeps.
8. **The calendar,** read-only (new decision D57). It uses EventKit and stays off until the person turns it on,
   from the day line ("Show your calendar") or Settings › Privacy › Calendar.
   - **Where events appear:** Today, Glance and the morning brief.
   - **For the AI:** only through a new `calendar.today` tool, with effect `readsPrivateData`, through the Guard
     like any other tool.
   - **When it's off:** nothing is read.
9. **Real links between things.** Built as follows, with less storage than first planned:
   - **Activity:** no new column. A row's `runId` already leads to its conversation: every reply records its run in
     `meta.runId`. `ExchangeStore.conversations(ofRuns:)` gives the kept conversation each run belongs to.
   - **Notebook:** one column, `items.run_id` (migration `v5-item-run`), which `notes.save` and `profile.remember`
     fill from the caller's run. "Changed in" comes from the Activity rows of `notes.update` and `notes.trash` that
     name the note and actually ran. Reads and searches don't count, because they touch many notes at once.
   - **Deletion:** a deleted or expired conversation links to nothing.
10. **Glance:** a small panel above the desktop companion, opened by clicking it or with its own shortcut. It
    holds:
    - the queue's top three decisions, answerable with the same safety rules;
    - the next two reminders or events;
    - changed watches;
    - running agents;
    - "Open Home".
11. **Activity rows open in place.** Each row shows:
    - the full summary, the arguments (command, paths, URL), and the outcome or error, nothing cut off;
    - who asked, and in which conversation (B9);
    - how it was allowed, in words, with a link to the rule in Settings › Privacy;
    - Undo while it can.

    Space toggles a row, and ↑↓ move between rows.
12. **The note's Connected list:** under the date and "Saved by", "Saved in '…'" and up to three "Changed in '…'"
    links, each one opening that conversation. Its reminders stay in the bell and the badge, where they already
    are.
    - D53's formatting bar stays where it is. Hiding it until text is selected was considered and dropped: the
      founder asked for the bar, and a hidden bar is harder to find.
13. **Snapshots that show real text:** `--ui-snapshots` runs without the compiled string catalog, so it shows raw
    English keys ("1 requests", where the app says "1 request") and never a translation. It should compile the
    catalog first, as `build-app.sh` does, and take a language, so plurals and every language can be checked. This
    lands with `sidefolk theme preview` (A13), which renders the same snapshots.

## C. Recipes

Every recipe reads the same models from B. They differ only in arrangement and decoration.

| Surface | Recipes |
|---|---|
| Navigation | **Sidebar** · **Pills** (floating capsule tabs) · **Rail** (icons plus a status bar) · **Ribbons** (bookmark tabs on the right edge) |
| Today | **Desk** (queue, then day rail, then tiles and agents) · **Board** (decisions in a row, three columns, notebook row) · **Stage** (the companion big on the left, decisions as speech bubbles) · **Console** (Queue, Agents, Signals in columns) · **Planner** (a two-page spread with ruled lines and index cards) |
| Activity | **Table** with rows that open · **Log** (dense mono, rows that open) · **Diary** (sentences, each one opens to the same detail) |
| Editor | **Rich** (marks hidden) · **Markdown** (marks shown, tabs for open notes) |

Each recipe gets UI snapshots in light and dark, plus the small window, a VoiceOver pass (order and labels) and a
right-to-left pass in Arabic.

## D. The seven themes

| Theme | Recipes | Companion suggested |
|---|---|---|
| Harbor (default) | Sidebar · Desk · Table · Rich | Mochi |
| Daylight | Sidebar · Board · Table · Rich | Mochi |
| Night Studio | Sidebar · Board · Table · Rich | Spark |
| Night Shift | Rail · Console · Log · Markdown | Spark |
| Marshmallow | Pills · Stage · Diary · Rich | Mochi |
| Field Notes | Ribbons · Planner · Diary · Rich | Mochi |
| Paper Garden | Sidebar · Board · Table · Rich | Mochi |

All seven are made as manifests. Built in: Harbor (default), Night Shift, Marshmallow and Field Notes. In the gallery: Daylight, Night Studio and Paper Garden (D58).

Gallery themes reuse D55:
- a **Themes** shelf;
- signed packs in `sidefolk-addons` with catalog digests;
- the same install, update and remove flow.

Community themes:
- install from a folder or a `.sidefolktheme` file once they pass the validator;
- carry a "Made by someone else, not reviewed" label;
- have their images re-encoded on install;
- have no way to run code.

## Build order

| # | Work | Why here |
|---|---|---|
| 1 ✅ | A1–A2 tokens at runtime, Harbor identical | **Done 2026-10-30:** `ThemeTokens`, `ThemeStore`, `Theme` reads the store. All 232 snapshots are pixel-identical. |
| 2 ✅ | B11 | **Done 2026-10-30:** Activity rows open in place (who, the decision in words, the outcome, the arguments, the rule in Settings), Space and ↑↓, with translations in all nine languages. |
| 3 ✅ | B9 links, B11's "Asked in", B12 | **Done 2026-10-30:** see B9 and B12. ConversationLinksTests run the real agent loop and tools, including a mutation check of the "only changes that ran" filter. |
| 4 ✅ | B2 queue, B1 Today | **Done 2026-10-30:** "Today" in the sidebar, the menu bar and the Ask panel (code names stay `now`); a header line with the greeting, what needs you and the reminders left today, beside "Ask …" and the companion; Guard's waiting questions in the queue, soonest deadline first, each with "Waits for your answer until …" (`ApprovalRequest.expiresAt`); per-row keys (↑↓, ⏎, ⌘⏎ for high risk, ⌫, S), with the rule in Core (`mayApproveFromKeys`), shared with the Ask panel's card. |
| 5 ✅ | B4 one bar (Home and Ask panel) | **Done 2026-10-30:** `SidefolkRuntime.find` searches notes, conversations, reminders to come, watches and Activity. Home has a toolbar field (⌘K): while it has words, a page says what Return does (the Ask panel's hint), offers "Do it" and "Ask … instead" (⌘⏎) for words understood without AI, or "Ask …" alone when they go to the AI anyway, and "Save as a note" (⌥⏎), then what was found, each opening where it lives. The Ask panel shows the same results under its hint and takes ⌘⏎ and ⌥⏎. Everything sent goes down the Ask panel's one path (`AppServices.ask`). Not done as first written: the understood parts as chips you can edit (the hint says what was understood; editing is the Ask panel's follow-up), and ↑↓ through results (Tab reaches them). |
| 6 | B3 day line, B8 calendar (D57) | The calendar permission and tool come with it. |
| 7 | B5 tiles, B6 agents, B7 nook, B10 Glance | Desk is now complete. Harbor is finished. |
| 8 | A3–A13 and B13: the rest of the foundation, snapshots with the compiled catalog, Settings picker, CLI, live reload | Needed before a second theme. The validator also fixes two Harbor shortfalls found in step 1: `inkFaint` in light mode is 2.95:1 on white (raise it to 4.5:1), and white on the light `danger` fill is 4.27:1 (deepen the red). |
| 9 | C recipes, then each theme's manifest and art | Board first (three themes use it), then Console, Stage, Planner. |
| 10 | Gallery shelf for themes, community install | Reuses D55. |

**Done means**, at every step:
- `make test` passes.
- UI snapshots light and dark, plus the small window.
- A check in the dev app with `swift scripts/dev.swift snap`.
- Arabic right-to-left.
- STATUS updated and, where it decides something, a DECISIONS entry. The calendar is D57 and themes are D58.

After you approve the themes, this session becomes a **create-a-theme skill**: how to write the manifest, check it,
preview it, make its art, and publish it as a pack.
