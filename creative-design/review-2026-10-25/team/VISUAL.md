# Visual identity and component direction

Design recommendation, 25 October 2026. This is a handoff proposal, not an implemented app or a passed release gate. Source reviewed: `docs/V1.md`, `creative-design/PIP.md`, `creative-design/review-2026-10-24/`, `src/tokens.css`, `src/states.ts`, and `src/icons.ts`.

## Decision: the workday desk

Keep the name, Pip Signal mark, cream/mint/charcoal palette, system type and both shipped companions. Recompose the application. The brand already has an identifiable face; the application needs an identifiable way of helping. Its visual signature should be a dated workday, a small held note, and a clear next action. The user sees what needs them, what is coming up, and what they have captured. Settings becomes a separate utility window rather than the visual model for the whole application.

The current design reference gives nearly every section an outlined round rectangle with the same visual weight. The redesign should use three different treatments: one dominant action surface, quiet time-led rows, and a dated notebook. This establishes purpose without adding more decoration or more feature scope.

The distinctively Sidefolk gesture is **holding something for later**. Repeat a restrained visual motif: a small mint tab, a date or time, and a crisp content edge. A mint tab can mark Today, the active notebook, or the reminder currently being edited. It must not replace any status color or icon. This is a layout and token treatment, not a new illustration system.

## Composition rules

- A page has one 28px title, one short explanatory line when useful, and one primary creation action. No large welcome slogan above useful work.
- A page starts 32px from its content edges. Use 24px between sections and 12px between a section label and its content. Pages with readable prose cap the prose column at approximately 72 characters.
- Preserve large quiet areas intentionally. Fill space with a helpful empty state or readable content rather than four empty boxes.
- One elevated surface at a time: a sheet, popup or overlay card. Ordinary content uses opaque surfaces, no persistent drop shadows, no translucent glass.
- Use hairlines between list rows, not individual cards around every row. Grouped surfaces may have a 1px separator edge when needed for figure/ground separation.
- On Today, the next item requiring action is the highest-contrast content. Upcoming reminders are a time-led list. A log preview can read like a notebook excerpt, with its real date visible. All three should not look interchangeable.
- At narrow widths, stack the same content in its priority order. The main action and creation confirmation remain on the originating surface.
- A right detail pane belongs to selected content; do not permanently reserve one-third of the window for a decorative companion.

## Exact palette and semantic use

Retain all production color values. These are already coherent, meet useful contrast pairs, and keep the companion art at home in either theme. Warm cream text and mint give the existing dark charcoal a consistent family resemblance. Do not add purple, electric blue or a second accent for visual interest.

| Existing token | Light | Dark | Required use |
|---|---|---|---|
| `--canvas` | `#F7F3EA` | `#191C22` | Window background and continuous sidebar plane |
| `--surface` | `#FFFCF7` | `#242832` | Content paper, grouped list, sheet, overlay |
| `--ink` | `#272A33` | `#F7F3EA` | Main text, most icons, titles |
| `--muted` | `#636773` | `#BEC3CD` | Real secondary information; not disabled text masquerading as metadata |
| `--border` | `#DAD6CD` | `#4B515D` | Quiet hairlines; never the only indication of a required input |
| `--control-border` | `#737783` | `#9BA2AF` | Essential input/control boundaries |
| `--mint` | `#6FCFB4` | `#6FCFB4` | One primary action, small brand accent |
| `--on-mint` | `#272A33` | `#272A33` | Text/icons on mint, including in dark mode |
| `--mint-soft` | `#DCEFE5` | `#234A3E` | Selected row, capture composition area, success summary |
| `--on-mint-soft` | `#24553F` | `#C3EEDF` | Small selected-state text |
| `--focus` | `#176650` | `#9AE7D0` | Keyboard focus, 3px ring with 3px offset |
| `--terracotta` | `#C87658` | `#D99377` | Small editorial marker only; not text or warning semantics |
| `--error` | `#8A2727` | `#F4A79B` | Destructive text, error copy with named recovery |

Suggested semantic aliases reference these existing tokens and introduce no new pigments:

```css
--page-bg: var(--canvas);
--paper-bg: var(--surface);
--selected-bg: var(--mint-soft);
--selected-fg: var(--on-mint-soft);
--action-bg: var(--mint);
--action-fg: var(--on-mint);
--separator: var(--border);
--field-edge: var(--control-border);
--text-primary: var(--ink);
--text-supporting: var(--muted);
--text-danger: var(--error);
```

These aliases are optional readability helpers in the future component stylesheet. Keep the production tokens as the source of truth. Do not duplicate light/dark hex literals in components.

Calculated solid-color contrast examples: light ink/canvas 12.94:1, muted/canvas 5.10:1, ink/mint 7.68:1, selected foreground/background 7.16:1. Dark ink/surface 13.31:1, muted/surface 8.34:1, selected foreground/background 7.84:1. Light terracotta/surface is 3.32:1, which is why terracotta must not carry small text. These token calculations are not a substitute for checking rendered focus, transparency, text resizing and system appearance.

## Typography and density

Use the existing platform system sans and system mono stacks. Keep the rounded lowercase brand face exclusively for the wordmark. No web font download, serif headline or novelty display face in app chrome.

| Role | Proposed window value | Use |
|---|---|---|
| Page title | existing `--text-panel`, 28px / 1.15, 650 | Today, Reminders, Work log, Sessions |
| Content title | existing `--text-card`, 20px / 1.3, 600 | Selected reminder or notebook title; not every section label |
| Prominent content | existing `--text-body`, 16px / 1.5, 500 | Reminder summary being composed, opening line of a log entry |
| Main window text | new `--text-window: 13px`, line-height 1.45 | Navigation, rows, buttons, normal form labels; implements V1-U7 desktop density |
| Supporting copy | existing `--text-secondary`, 14px / 1.5 | Instructions where space and reading matter |
| Metadata | existing `--text-meta`, 12px / 1.4 | Date, tool, host; never a title or main action |
| Operation text | `--font-mono`, 13px / 1.6 | Byte-preserved command, diff, paths and JSON |

The 13px window token is an explicit exception/migration from the older globally large component sizing. Existing overlay `--text-body: 16px` remains. Do not globally shrink `--text-body` to fix desktop density. The app's larger-text preference must scale text and row height together; avoid clipping labels in fixed-height containers.

Keep current spacing tokens 4/8/12/16/24/32px. Keep radii 10px controls, 18px grouped content/sheets, 24px overlay/panel silhouette. Do not round every semantic row; a row is rectangular inside its parent group. Use a 10px selection pill only in navigation or a selected list row.

Add a scoped density token rather than repurposing `--target`:

```css
.sidefolk-window { --control-height: 28px; --row-min-height: 52px; }
.sidefolk-overlay { --control-height: var(--target); }
```

A desktop toolbar can use 24px small buttons. A primary desktop button uses 28px. Overlay actions remain at least 44px tall. Reminder rows can be 60px when they contain two text lines. Main nav rows are 36px high, with full-row click targets; do not make every window control 44px merely because the overlay requires it.

## Brand and art

Use the canonical vectors `art/brand/pip-signal.svg` and `art/brand/pip-signal-mono.svg`. The mark carries the identity; keep the mark/wordmark relationship and geometry. The wordmark reads lowercase `sidefolk`; product prose reads `Sidefolk`. Clear space is at least the floating dot diameter. Never recolor the brand dot to represent operational state. At menu-bar scale use the monochrome template silhouette.

Use the real transparent companion assets in `public/crew/pip/3d/` and `public/crew/spark/3d/`. Avoid generating new lookalike mascots for screen production. The exact clay material, silhouette, scarf and facial proportions are already assets worth owning. Show a companion where it has a role: wave in setup, hold a reminder, listen during capture, write when a note saves, rest in a small sidebar footer. A static home view should not have three copies of Pip competing for attention.

Logo glyph means the company; actual selected companion means the speaker. If Spark is chosen, Spark appears in speaking surfaces and the sidebar presence area, while the company mark stays Pip Signal. Do not make companion choice change the UI palette, icon vocabulary or status meanings.

The proposed new asset work is limited to: one folded-ear puzzled pose; the already permitted micro-frames; a warm rim correction if necessary for dark wallpaper. Export transparent WebP using the established sprite pipeline. Test at 150px on light/mid/dark wallpapers. No new companion roster, 2D illustration family, ornamental room background or generated UI glyph set.

## Components: visual contract

| Component | Appearance | Interaction and states |
|---|---|---|
| Primary button | Solid mint, charcoal label, 10px radius, 600 weight | One per local task; text remains visible during saving; no mint pulse |
| Secondary button | Surface or transparent, ink label; only required boundaries use control-border | Hover adds mint-soft or the selected surface; keyboard focus remains separate from selection |
| Destructive action | Error text with explicit verb | Confirm the named object for irreversible deletion; no global red accent |
| List row | No own card; 16px horizontal inset, 12px vertical rhythm, hairline below | Entire title area opens details; at most two visible actions, other actions in labelled More |
| Capture field | Persistent label, paper surface, control-border, 10px radius | Example text below, meaningful result preview before save, preserves user text on failure |
| Date/time control | Real localized date/time, standard popup | Resolved date stays visible, ambiguity shown before save; never communicate a time by placeholder alone |
| Status | Existing distinct glyph + canonical word, small decorative fill | No state represented by dot color alone; status fill is not a text color |
| Segmented control | Shared inset surface, selected paper segment with hairline separation | Native radio behavior, arrow keys and roving selection; label group explicitly |
| Toggle | Platform-like switch + persistent label | Pending state if persistence is async; failed save returns value and shows recovery |
| Sheet/detail pane | Paper, single shadow if floating, clear title | Bounded scroll body; persistent footer for meaningful actions; restore invoking focus on close |
| Toast/undo | Small factual message, named action, Undo | Undo remains available until dismissed, plus Command-Z; status announcements avoid interrupting reading |
| Popup/menu | Surface, 10px radius, one shadow | Standard keyboard traversal and Escape; first item is not automatically destructive |
| Empty state | Small companion or one semantic icon, one sentence, one creation action | No fake entries or zero-value analytics; no agent setup promotion on a calm-path Today |

Permission review is deliberately plain. Show project, first prompt line/identity, host and agent before the request. Exact command/diff/content is on a contrasting paper or canvas operation plane with full accessible text, wrapping where meaningful. Keep Allow once, Decline, Answer in terminal and the hold explanation visible. Only expose Allow after the operation has been completely shown. Released, expired and failed-to-send are distinct lifecycle copy, not new `src/states.ts` state words. No agent art, gradients or celebratory illustration behind a consequential decision.

## State vocabulary and iconography

Keep exactly `Idle`, `Thinking`, `Working`, `Needs you`, `Done`, `Failed`, `Asleep`, sourced from `src/states.ts`. Use no synonym such as Active, Running, Ready, Blocked or Paused as an eighth general state. Connection health is separately governed by V1-D13, not represented through guessed session status.

Keep the current 24px icon grid and 1.75px stroke from `src/icons.ts`; 16px rendering for rows/toolbars, 20px for page-level controls. Use the existing shape per state. Where new icons are necessary, extend that source with the same grid and rounded caps. Do not mix emoji, filled vendor icons and thin hand-drawn glyphs in navigation. A vendor mark is identity metadata, not the primary navigation symbol.

Static status badges are the default in the window. Real Working events can make the companion work, but not spin every icon in every session row. Idle gets no activity light. Done animation is only triggered by real success and finishes under 1.2 seconds.

## Motion and sound

Keep current `140ms` control, `200ms` card and `520ms` entrance tokens. Use opacity with at most a 4px displacement for sheets/cards; no spring overshoot in permission decisions. Hover/focus only changes color or opacity, without moving content. Companion entrance can use the existing 520ms expressive timing. Cross-fade state frames; settle while users read.

Reduced motion sets these transitions to zero, using a clear static state. Do not animate row height after a click if it moves a target under the pointer. Sound remains an optional quiet companion blip; it never becomes the only event indication.

## Implementation sequence and acceptance

1. Create the component stylesheet against existing token names plus the scoped density tokens above. Replace the two overlapping window stylesheets through the planned P5 work; do not build an independent decorative CSS layer.
2. Build a specimen route containing every piece in light/dark, normal/larger text, hover/focus/disabled/pending/error, long labels and multilingual text. This route is a development aid, not a customer feature.
3. Apply the new page hierarchy to Today; then Reminders and Work log; then Sessions/review; then the separate Settings window and setup. Keep capture completion on its originating surface.
4. Verify WebKit layout, keyboard traversal, logical focus after async actions, system/forced theme, state words, full operation visibility and durable Undo. Native window chrome, VoiceOver, multi-display behavior and overlay readability still need human checks.
5. Compare actual rendered layouts to the review compositions. Images are an art-direction reference. Exact behavior, date formats, available actions and component semantics come from the handoff and V1 contract.

Success is a user opening the window and immediately recognizing a useful next step. A visual review should answer: Is attention different from browsing? Is capture visibly saved? Can the date and destination be read before saving? Is the work log something you want to return to? Can a quiet day be pleasant without fabricated activity? This package does not claim usability testing or gate G4 has passed.
