# CPO, round 2 (Aiko)

All three papers agree on the big calls:
- a B-led hybrid with a gate
- Pip only
- the full-access feature deleted
- shell commands only through `$`
- repeats work like calendar alerts, and snooze never moves the series
- notes go to exact matches or ask first
- state moves into Rust
- Dock app, signing and an updater before outside users
- one-in-one-out guardrails

That's a strong base. Below is what's left.

## 1. Where I change my position

- **Build order: the trust core goes first, and the window is rebuilt after state moves into
  Rust** (CEO and CTO). I drop "phase 2 runs in parallel with phase 1".
- **CTO's two-track gate.** If the agent track fails its native tests, v1 ships with Sessions as
  beta and no approvals from Pip. I adopt this.
- **Accent colours become LATER** (CTO). Morning brief and "welcome back" become LATER (CEO).
- **Phrase corpus:** CTO's 250 phrases, with CEO's hard gates of **0 wrong times** and
  **0 English turned into shell**.
- **"Work log" as the name of the Notes section** (CEO). I accept it, as long as notebooks for
  any topic still exist. The founder's #2 says "the same works for any memory topic".
- **Settings: four sections** (CEO), as long as reduced motion and text size are visible under
  General.
- **Correcting my own paper.** The approved mockup `05-appearance-light-and-dark.png` *does* show
  the Settings category sidebar with "Back to Sidefolk". A separate ⌘, window keeps that approved
  layout and drops only the "Back" link. I still prefer it, but I'll concede to CTO's
  "same sidebar".
- **Platform:** macOS 14+, Apple Silicon only. Journal history kept 7 days.
- **Start session:** BETA or STABLE (with a prompt field, Claude Code only) are both fine. I
  object only to LATER, since it's founder priority #4.

## 2. My strongest objections

**O1. Both of you redraw the logo. That reverses a recorded founder decision.**
- DECISIONS #37 (`memory/DECISIONS.md:148-149`): the user approved the review "with the current
  logo unchanged".
- The review README makes keeping the current logo a "user-confirmed constraint".
- A redraw is also unnecessary:
  - the charcoal mark stays as the app icon
  - the ivory character appears wherever Pip *speaks* (cards, sidebar)
- If the CEO still wants a redraw, it belongs in the "where I overrule the founder" table, with
  the founder asked.

**O2. CTO's `run …` prefix and STABLE shell commands bring back the "make coffee" bug.**
- "run" is an ordinary English word.
- In today's code, `commands.ts:98` checks `^(run|\$)\s+` *before* any reminder parsing. So "run
  payroll report tomorrow at 9" becomes a terminal card.
- `open …` has the same order problem. "open enrollment closes friday 5pm" is caught by the
  open-thing rule at line 94 before reminder detection runs.
- **The fix:**
  - time detection runs before `open`
  - shell is `$` only
  - quick commands are BETA and off by default; CEO and I are already 2 to 1 on that

**O3. CEO's D3 rule "an unhandled reminder auto-files to history after 24 h as ignored".**
- For a one-off reminder this silently hides a commitment, the same "silent loss" we all
  forbid elsewhere.
- **One-offs stay Overdue on Today until handled.** Only repeat occurrences fold into history,
  when the next occurrence fires.

**O4. CTO's automatic "Agents" lane writes the agent's last summary line into the log.**
- It stores agent output, which can hold paths, secrets or customer names. CTO's own D10 then
  has to redact it.
- It turns the brag doc into a machine log the user never wrote.
- The CEO and I both propose a one-click **"Log it"** suggestion instead. It stores only the
  project and the first prompt line, and the user can edit it.
- Retention comes from the user *choosing* to keep entries. That choice is also the metric we
  want: kept entries per week.

**O5. CTO's D8 "polish; the pixels mostly stay".**
- The evidence says the pixels are the problem:
  - Jun scores the window 4/10
  - an 895-line `dashboard.css` fights a 149-line `redesign.css` override layer
  - every control is 44 px, every surface outlined, five button styles
  - the date field shows a fake value that isn't really set (B7)
- The CEO's D8 is right: re-implement each view on the component kit, against the mockups.
- I accept CTO's sequencing (after the Rust state work) and its 2-actions-per-row rule.

## 3. Non-negotiables for the CEO's ruling

1. **Quick add never dead-ends and is never wrong in silence.**
   - English never becomes shell; only `$` does, and quick commands are BETA, off by default.
   - Every reminder shows its resolved date and time before it saves.
   - Ambiguous input asks.
   - Typed text is never lost.
2. **Pip and the voice are frozen.**
   - One ivory Pip and a written character bible (`PIP.md`).
   - A voice/error table enforced by a test: CTO's check that fails on snake_case, "Error:" or
     `String(e)` in any bubble.
   - A puzzled pose, and the work signal only during real activity.
   - The logo stays unchanged unless the founder decides otherwise.
3. **The companion is accessible.**
   - The summon key opens the input field.
   - A shortcut focuses the newest card.
   - Cards can be reached by keyboard and VoiceOver.
   - Nothing important disappears on a timer; Undo stays until dismissed or ⌘Z.
   - This is a beta gate.
4. **The path for people without AI tools is a gate (my J2).**
   - "Skip AI tools" leads to an app with no developer vocabulary.
   - At least 2 beta testers are not developers.
   - Without this, the D1 widening gate can never be measured.
5. **The window bar.**
   - Views rebuilt on the kit.
   - Founder sign-off against the mockups in both themes; a design re-review scores ≥7/10.
   - Date and time fields that actually hold a value.
6. **One-off reminders are never auto-hidden** (O3).

## 4. Factual errors

- **Logo.** CEO D7 and CTO D7 both contradict DECISIONS #37 and the review README (O1).
- **Missing from the CEO's overrule table:** deleting the nine characters, the 3D/2D choice and
  custom characters reverses **Decision 38** (`DECISIONS.md:156`). The user supplied the ten
  reference photos and asked for these features. I agree with the cut, but it has to be listed
  and answered in writing like the others.
- **CEO's paper contradicts itself:**
  - D2 keeps accent colours STABLE, while D9 deletes `recolor.ts`. That file *is* the accent
    mechanism (`src/recolor.ts:1-3`).
  - D2 calls calendar "LATER, first item of v1.1". The CEO's own LATER definition keeps code
    scheduled within two releases, yet D9 deletes the calendar code.
- **CTO: the approved mockups are not what CTO describes.** CTO D8 says "polish toward the
  approved mockups", then specifies "no second sidebar, no Back to Sidefolk". Mockup 05 shows
  exactly that second sidebar. It may be the better choice, but it's a change to an approved
  design and should be named as one.
- **Hold timeout.** The code holds requests for 60 s (`hooks.rs:23`, `PERMISSION_WAIT`). CEO's
  45 s is a proposed change, not today's behaviour.
- **Figures I checked and found correct:**
  - CEO's "698 lines" of character import (309 + 173 + 216)
  - "5.2 MB" of crew art
  - CTO's quote of `settings.rs` on hide-in-recordings being off by default
