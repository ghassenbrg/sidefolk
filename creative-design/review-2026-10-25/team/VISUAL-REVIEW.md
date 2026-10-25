# Visual review of the rendered proposal

Reviewed `02-today.png`, `06-work-log.png`, `11-setup.png` and `22-today-dark.png` as design renders. These are not captures of the shipping application. No production code or design code changed during this review.

## Judgment

The proposal is materially more coherent than the previous reference: time-led rows, one prominent mint surface, actual clay Pip, controlled desktop density and a readable work log. The light and dark versions clearly belong to the same product. Setup is the strongest identity moment: the user meets the actual companion while doing a useful task.

There is still room between “competent Mac utility” and the distinctive daily companion the user requested. Improve the hierarchy and the visual relationship between capture and remembering. More ornamental graphics would not solve that gap. The following refinements are the highest-value changes before handoff.

## 1. Start Today with the live thing that needs a decision

In the Today renders an overdue dentist reminder appears before the live Claude request. That puts a low-pressure old item in the first and most scannable position while a held approval has a short lifecycle. Move Needs you directly under the date/title. Put the overdue reminder at the beginning of the reminder agenda, with its original time and factual Overdue text. This also removes one separate section heading and makes the page read more like a day than a collection of widgets.

The final visual order should be: title/date; one mint attention surface when relevant; a single reminder agenda containing overdue and upcoming; recent writing and real session activity in the quiet secondary column. On a calm day, omit the attention section entirely.

## 2. Differentiate notebook navigation from application navigation

Work log currently repeats the main sidebar's mint selection pill in a second navigation column. Two nav rails, two active pills and a vertical divider produce the strongest remaining configuration-app impression. Keep the required notebook list/detail relationship, but make it look like an index within a notebook:

- Put the label **Notebooks** above the list, not “YOUR NOTEBOOKS” below existing items.
- Use an inline weight change plus a short mint edge marker for the selected notebook, rather than a second full mint nav pill.
- Drop the vertical divider between notebook index and writing. Keep the 24–28px whitespace gutter.
- Give Log a small default/inbox descriptor in the index or a short line under the selected notebook heading. The destination should be immediately clear.

This is a hierarchy change using the existing palette, not a new navigation pattern. The main sidebar remains the application navigation; the notebook index feels like part of the document.

## 3. Make the writing itself own the Work log page

The work log's top stack contains page title, subtitle, wide search field, notebook title, composer and week grouping before any saved writing appears. At the shown height, barely two entries are visible. Reduce this stack so returning to the log feels like opening a record of your work.

Recommended refinement: put compact search and the project filter in the page-header actions; keep the selected notebook title; collapse the empty composer to a single labelled “Add a note to Log…” line that expands on focus. When a user comes through Add note or Quick add, expand and focus the composer immediately. Keep a selected destination visible throughout. The normal reading state should reveal three or more short entries without scrolling at the reference window size.

The `All projects` filter visibly breaks onto two lines in a very small control. Give it a stable minimum width of roughly 100px and keep its text on one line. This is an obvious polish defect in the current render.

## 4. Give Pip fewer, better-sized appearances

The Today request has a tiny full-body Pip next to its metadata, while the sidebar has another full-body Pip. The request avatar becomes a few visually noisy pixels and adds little to identity. Show a deliberately cropped face/upper-body portrait in the 36px avatar using the same canonical WebP, or omit the miniature when the larger sidebar companion is already clearly the speaker. Do not invent a new mascot rendering.

The setup wave is appealing, but the large sprite shows a faint green edge and softness at its displayed size. Before production, export an appropriate-resolution transparent frame from the existing approved source or reduce the display size; do not enlarge the small runtime frame beyond its clean detail. Inspect on both paper and dark charcoal backgrounds. This is an asset-quality task, not an invitation to regenerate Pip.

## 5. Use quieter action chrome consistently

The outline around Add reminder is stronger than the surrounding hairlines and feels slightly like a form control perched over the page. A quiet labelled action can work here because Review request is the local primary action. Use one consistent treatment for secondary header creation actions, with icon + text, subtle surface on hover, and a visible focus ring. Keep explicit primary mint buttons inside capture/save contexts.

Remove repeated separators that read as accidental doubling: the Today recent-log preview shows a bottom rule followed almost immediately by a second rule before the next date. Each entry boundary needs one hairline. The dark render makes this duplication particularly clear.

## Keep

Keep the exact color values, logo assets, 13px window density, generous page gutter, opaque surfaces, actual Pip/Spark artwork and the quiet separation of upcoming reminders from recent writing. Keep the setup's real reminder fields, explicit resolved date/time and one Save reminder & continue action. Keep dark mode's cream text and restrained mint; do not add blue or purple “tech” accents to make it feel more advanced.

The proposal should remain recognizably Sidefolk when the companion is hidden: its time-led agenda, held-note capture and dated writing should provide that identity. These refinements strengthen that aim without widening feature scope or claiming any release gate has passed.
