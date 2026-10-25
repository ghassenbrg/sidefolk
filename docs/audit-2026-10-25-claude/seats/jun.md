# Jun: senior product/UI designer (native Mac apps)

## 1. Seat & method
I spent years shipping native-quality Mac apps, and I judge craft: hierarchy, density, type, colour, iconography, light/dark parity, and whether something feels like a Mac app or a web page in a frame. I looked at all 68 screenshots in `shots/` (light, dark, full, overlay) and at the five approved mockups in `creative-design/review-2026-10-24/`. I read `src/tokens.css`, `src/dashboard/redesign.css` and `creative-design/DESIGN-SYSTEM.md`. I also took my own WebKit shots in `council/jun-shots/` (800 px width, keyboard focus, the Examples menu, the dark overlay) and pulled the computed styles of every button.

## 2. First 30 seconds
The companion is lovely. The 3D Pip on the desktop (`overlay-idle.png`, `overlay-permission.png`) has real charm, and it is the one thing here that looks like a product. The window looks like a competent Bootstrap admin panel that was re-skinned in cream. Every card, input, button and segment has a dark grey 1 px outline. Every control is 44 px tall. Grey text links sit next to outlined buttons next to mint buttons, and the window draws its own controls instead of using the platform's. I'd guess "Electron app" before "Mac app". Dark mode is consistent but cold: warm cream in light becomes blue-slate in dark, so the two themes read like two different brands.

## 3. Scores
- **Clarity of purpose: 5.** Today makes sense. But the sidebar adds Actions, Sessions, Terminal, Characters and nine Settings pages, so the focus spreads thin.
- **Ease of use: 5.** Reminder rows carry five actions (`light-reminders.png`). Notebooks get three levels of navigation (`light-notebook.png`). A mode toggle looks exactly like the action buttons ("Asks first", `light-sessions.png`).
- **Visual quality: 4.** The companion is an 8; the window is a 4; the overlay cards are a 6. Below the approved mockups on every screen.
- **Usefulness to me: 4.** A dev-session watcher is nice, but nothing here beats Reminders.app plus a menu-bar item.
- **Trust & safety: 5.** The permission card is clear. But "Allow everything from this session" is an underlined grey text link (`overlay-permission.png`), and raw codes like `rate_limit` (`overlay-failed.png`) and `(sky)` (`overlay-spark.png`) leak through.
- **Release readiness: 3.** No design QA pass is visible: native form controls are unstyled, icons are duplicated, focus rings are broken, and date formats are inconsistent.

## 4. Top problems, ranked

1. **Major: everything is outlined, so the window reads as a wireframe and nothing has hierarchy.**
   - What: cards, the Tell bar, sheets, crew tiles, segmented controls and secondary buttons all use `--control-border` (#737783 light / #9BA2AF dark). DESIGN-SYSTEM.md reserves that token for "required control boundaries"; the 1 px border on every surface is meant to be the pale `#DAD6CD`.
   - Evidence: `redesign.css:25` (`.card.attention`), `:48` (`.sheet`), `:71` (`.crew-choice`), `.tell-row`. In the shots, every box in `light-home.png` has the same weight, and the Today card in the mockup (`01-today.png`) uses soft hairlines instead.
   - Fix: cards get no border (or the pale hairline) and a fill difference. Only text fields carry a visible boundary. Secondary buttons become filled neutral (macOS "bezel") instead of outlined.

2. **Major: touch-sized controls everywhere, so it feels like an iPad web app.**
   - What: every button measures 44 px tall (computed styles; `--target: 44px`).
   - Evidence: the five-button reminder row is 44 px of chrome for one line of content.
   - Fix: on macOS the regular control size is 22–28 px. Keep 44 px only for the overlay cards, where Fitts's law matters. Shrink window controls and row padding by about 30%.

3. **Major: native controls are left unstyled next to custom ones.**
   - What: the file input is the raw WebKit "Choose Files / no files selected", with a checkbox floating ~600 px from its label (`light-characters.png`, `full-characters.png`, `character-import.png`, `dark-characters.png`). The 22 px native selects sit beside 44 px custom inputs: Repeat (`light-new-reminder.png`), Accent colour (`full-settings-companion.png`), Voice (`full-settings-sound.png`), Fall asleep (`full-settings-accessibility.png`), and the narrow settings switcher (`light-narrow-appearance.png`). The disclosure triangles are the raw `<details>` ▶ (`light-review.png`, `full-settings-tools.png`). In dark mode the date and time digits render amber (`dark-new-reminder.png`).
   - Fix: pick one approach. Either go fully native with real AppKit-style controls, or style every control. Use a drop zone for import, a styled popup button for selects, and chevrons for disclosures.

4. **Major: five button styles with no grammar.**
   - What: mint filled, outlined 44 px, outlined 36 px/12 px text (`Open` on Notes, `Edit`/`Delete` on notebook entries), borderless grey text ("Open · Snooze 10 min · Edit · Delete"), and underlined links (the overlay's "Allow everything…").
   - Evidence: computed styles show 4 sizes and 3 border colours. `light-reminders.png` mixes three of these styles in one row. `light-setup.png` makes the side quest ("Set a two-minute reminder") a full-width primary while the real step, Continue, is a small outlined button.
   - Fix: one primary per view, one secondary, one destructive, and an overflow menu (⋯) for everything else. Reminder rows should be checkbox, title, time and a chevron, exactly as in `02-reminders-and-notes.png`.

5. **Major: the window doesn't match the approved mockups.**
   - What: the mockups have a black Pip mark, icon tiles on session rows, a dot+word status, a single row action and an inline Copy on commands (`03-sessions-and-review.png`).
   - Evidence: the build has pills plus 2–3 outlined buttons per session row and an "Asks first" toggle styled as a button. "Project companion options" is a bare card with no chevron that expands into a full Sparks form (`jun-shots/sessions-options-open.png`). The review pane nests a card inside an inset inside a code block (`light-review.png`) where the mockup has flat fields.
   - Fix: rebuild the Sessions and Review screens to the mockup. It is already approved.

6. **Major: icons are a placeholder set.**
   - What: in the Settings sidebar, Appearance is a hollow circle; Reminders & calendar and Notifications & sound share the same bell; Privacy and About & data share the same ⓘ, which also heads the Accessibility page (`light-settings.png`, `full-settings-accessibility.png`). The mockup (`05-appearance-light-and-dark.png`) already specifies a palette, shield, accessibility figure and chart.
   - Fix: use SF Symbols-style glyphs, one distinct icon per category, at a single stroke weight.

7. **Major: brand inconsistency around Pip.**
   - What: the wordmark bunny is charcoal (the "Pip Signal" identity in DESIGN-SYSTEM.md). The sidebar mascot and the companion are a cream 3D bunny with black ears. The mockups show a charcoal bunny everywhere. The sidebar bunny is ~40 px, cropped and orphaned at the bottom-left, with no meaning (`light-home.png`). Pip's avatar on request cards is the logo glyph, not the character (`light-requests.png`).
   - Fix: decide whether Pip is the logo or the character and make them the same creature. Either remove the sidebar mascot or make it live (it shows Pip's status, and clicking it calls Pip).

8. **Minor (but adds up): typography and date formatting.**
   - What: three date formats ("Sunday, October 25 at 03:09 AM", "10/24/2026", "Sat, October 3, 2026") and a leading-zero 12-hour time ("09:00 AM", `overlay-remind-typed.png`). Every settings page repeats the subtitle "Everything here can change later.", and Privacy is both page and section title (`full-settings-privacy.png`). The companion's help card is a wall of grey dot-separated phrases (`overlay-help-reply.png`).
   - Fix: one locale-aware date formatter (Today / Tomorrow / weekday, then "Oct 3") and a strict type ramp. Show the help as a list with phrases in mono.

9. **Minor: broken states.**
   - What: the Tell bar's focus ring is drawn around the inner input, inside the outer box (`jun-shots/focus-tab4.png`). The overlay field's 3 px ring outweighs its card (`overlay-field.png`). Suggestion chips truncate. The Notes search field and the notebook toolbar sit flush on their cards (`light-notes.png`, `light-notebook.png`). Sprout's caption misaligns the companion grid (`full-settings-companion.png`). The dark modal's scrim greys the page instead of dimming it (`dark-new-reminder.png`).
   - Fix: one QA pass at 3 widths and 2 themes.

10. **Minor: information architecture shown in chrome.**
    - What: Settings swaps the whole sidebar for a second sidebar with "Back to Sidefolk". Characters lives under Settings but shows the main sidebar with Settings highlighted plus a "← Settings" back link (`light-characters.png`). The Terminal highlights Sessions (`full-terminal.png`). The notebook has the global sidebar, a notebook rail and a "← Notes" link all at once.
    - Fix: Settings should be a separate standard macOS Settings window (⌘,), with a toolbar of tabs or the System Settings sidebar idiom. The main window needs one navigation level plus a content list.

The overlay cards are the best part of the UI. They need a tail towards the companion, "Allow everything" as a real destructive-styled button behind a disclosure, and status dots taken from the tokens (the idle dot is a system-ish blue, `overlay-field.png`).

## 5. Feature verdicts
| Feature | Verdict | Reason |
|---|---|---|
| Pip desktop companion | KEEP | The product's soul and its best-crafted asset. |
| Talking by typing (local parser) | REWORK | The visual design promises chat; the parser can't deliver. Show the live preview as structured chips. |
| Tell bar in window | REWORK | Merge it with ⌘K/Spotlight-style quick entry; at the top of every page it eats 80 px. |
| Reminders | KEEP | Redraw rows as checkbox, title, time and chevron. |
| Notes & notebooks | REWORK | Collapse to a two-pane list and editor; drop the triple navigation. |
| AI "Draft a summary" | LATER | A third toolbar button with unclear cost. |
| Quick commands (run in terminal) | REWORK | "make coffee" got a terminal card, which hurts credibility. |
| Saved actions | LATER | A sidebar item for one row. |
| Open app/folder/URL | KEEP | Cheap and delightful; needs no UI. |
| Watching Claude Code/Codex | KEEP | The reason the character acts. |
| Permission requests on companion | KEEP | The best card; restyle "Allow everything". |
| Per-session full access | REWORK | Not a button lookalike; a menu item with a warning. |
| Start sessions | KEEP | One button. |
| Open/continue session | KEEP | Row click, not 2–3 buttons. |
| Sparks | LATER | Second characters dilute the calm. |
| Terminal inside Sidefolk | CUT | A cream rounded box isn't a terminal; Ghostty or iTerm do this better. |
| Calendar heads-up | LATER | A one-toggle settings page. |
| Morning brief | LATER | Not seen in the UI; scope. |
| Weekly wins | LATER | Ditto. |
| Ten characters + 3D/2D | CUT to 2–3 | Inconsistent scale in the grid; dilutes Pip as the brand. |
| Make-your-own import | CUT | Its screen is the worst in the app (raw file input, prompt-paste instructions). |
| Accent colors | LATER | Polish after the basics. |
| Sounds & voice | KEEP sounds, LATER voice | — |
| Setup guide | REWORK | Primary/secondary inverted; three chips aren't a stepper. |
| Settings (9 categories) | REWORK | Merge to 4 (General, Companion, AI tools, About) in a real Settings window. |
| CLI `sidefolk here` | KEEP | No UI cost. |
| MCP tools | KEEP | No UI cost. |
| Dock app + window | REWORK | Menu-bar-first plus a smaller window. |

## 6. What v1 should be
**For developers who run Claude Code or Codex: a calm desktop companion that shows what your agents are doing, brings their permission requests to you, and keeps small reminders. A tiny, native-feeling Mac app.**

**Must-haves:**
1. One component kit with three button styles, Mac-sized controls (24–28 px in the window), hairline cards, and every control styled.
2. A dedicated Settings window (⌘,) with 4 panes and unique icons.
3. Sessions and Review rebuilt exactly to `03-sessions-and-review.png`.
4. A dark palette warmed to match the cream light theme, plus sidebar vibrancy (`NSVisualEffectView`) so the window feels native.
5. Overlay cards with a tail, consistent status dots, and no raw identifiers in the copy.

**Must-cuts:** the in-app terminal, the character importer, Sparks, the eight extra characters (keep Pip plus at most 2), and the Actions page (fold saved actions into the Tell/quick-entry menu).

**Vote: RESTART THE UI ON THIS CORE.** The character art, the overlay system and the Rust core are worth keeping. The window is 1,040 lines of CSS: `dashboard.css` (895 lines) with an "approved review" override layer (`redesign.css`, 149 lines) fighting it. Every screen needs its structure changed (rows, navigation, the Settings window, control sizes), not just its colours, so polishing would cost more than redrawing against the mockups with a small component kit. Redraw the window; polish the overlay.

## 7. The one thing
I'd love it if Pip were the only personality and the window were invisible-quality native: a menu-bar popover with today's requests and reminders, SF Symbols, vibrancy, 13 pt type and no outlines. The thing that would make me uninstall is opening the window and seeing a cream web admin panel with "Choose Files" in it. The charm of the companion makes the web-ness of the window feel worse, not better.
