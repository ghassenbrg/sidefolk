# Visual design system — proposal

## Brand idea

**A small crew. By your side.** The identity should feel like a quiet studio full of helpful characters. Keep the UI disciplined and the personality in the pets. The wordmark is lowercase `sidefolk`; prose uses `Sidefolk`.

**Pip Signal — selected by the user.** The charcoal bunny head, two ivory eyes, mint status dot and rounded lowercase wordmark are the primary identity. Keep the selected reference's simple proportions across the app and promotional materials. The bunny mark represents Sidefolk even when someone chooses a professional robot or capsule companion. The standalone generated logo is on ivory; reconstruct vector and monochrome masters before shipping.

**Side by Side — earlier exploration.** Two unequal companions and a floating dot. Retained for comparison only; superseded by the user's Pip Signal selection.

**The Den — community alternative.** An arch sheltering three companions. Works well as a den/crew feature symbol, but can read as a home icon without the wordmark.

Logo rules: maintain clear space at least one status-dot diameter; never recolor the brand dot to imply live operational status. Use a simplified one-color mark at 16–24 px; test at actual size before export. The menu-bar template icon needs a monochrome silhouette. App-icon exports and optical corrections follow selection of a direction. The logo sheet's typography is exploratory, not the UI font specification.

## Palette and typography

| Token | Light | Dark | Use |
|---|---|---|---|
| Canvas | `#F7F3EA` | `#191C22` | Warm quiet background |
| Surface | `#FFFCF7` | `#242832` | Cards and panels |
| Ink | `#272A33` | `#F7F3EA` | Primary text |
| Muted | `#636773` | `#BEC3CD` | Secondary text |
| Border | `#DAD6CD` | `#4B515D` | Nonessential separators |
| Mint | `#6FCFB4` | `#6FCFB4` | Brand, selected surfaces; use charcoal text |
| Focus | `#176650` | `#9AE7D0` | Keyboard focus ring |
| Terracotta | `#C87658` | `#D99377` | Editorial accent, not body text |

Do not use white small text on mint. The supplied token pairs are checked with a local contrast calculation; choosing these tokens alone does not establish accessibility of the finished app. Status fills and subtle borders are decorative; visible labels carry meaning. Required control boundaries use the `control-border` token, not the pale divider.

Use the platform system sans stack for the app: `-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`. Use the system monospace stack for commands and paths. No font download is required. UI sizes: 12 px metadata, 14 px secondary, 16 px primary body, 20 px card heading, 28 px panel title. Body line-height 1.45–1.6. Editorial lookbook headings can be larger.

Spacing: 4 / 8 / 12 / 16 / 24 / 32 px. Controls: 10 px radius; cards: 18 px; panels: 24 px. Proposed minimum interactive target: 44 × 44 px. Focus: visible 3 px ring with 3 px offset, preserved in both themes. Prefer solid opaque card surfaces over wallpaper-dependent transparency.

## Status stays independent of style

Preserve the runtime orb palette from `src/pet/orb.ts`. Proposed card badges add symbols and readable words; decorative orb colors are not foreground text colors.

| Meaning | Existing orb | Proposed badge cue | Character cue |
|---|---|---|---|
| Idle | `#FFD98A` | Open circle + Idle | Settled neutral pose |
| Thinking | `#8CC6FF` | Ellipsis + Thinking | Head tilt |
| Working | `#FFB547` | Small gear + Working | Read/work clip |
| Needs you | `#FF7A2E` | Exclamation + Needs you | Raised right-paw sign |
| Done | `#6FE3B4` | Check + Done | One brief celebration |
| Failed | `#9D90B8` | Cross + Failed | Lowered ears/head, readable face |
| Asleep | `#FFE3AD` | Crescent + Asleep | Sleep pose |

The static system board abbreviates this to six badges; Thinking remains a separate state in this specification. Never use the pet's chosen coat color to define status. Allow reduced motion with static badges and clear text instead of continuous pulses. Failure text should say what failed and where to open details, not only show a sad face.

## Key surfaces

**Permission card.** Order: `Pip · sidefolk` → agent name and session identifier → exact question → command/action context → explicit choices. For example: `Codex · Session 04`, “Run project tests?”, `npm test`, **Decline** and **Allow once**. Always retain project and session identity even if the pet is obvious. Long paths and commands must wrap or expand; do not hide the meaningful end of an action. Pending or expired requests disable action buttons and show why. Petting a character never approves a request. Do not preselect Allow, and do not let a decorative animation steal keyboard focus.

**Den.** Compact list, with pet portrait, pet name, project, status word and a distinct status icon on every row. Selecting a row reveals the status card; it does not send work. Proposed filters: All, Needs you, Resting. The existing den is off-screen plus tray entries; this visual panel is a future surface.

**Appearance picker.** Select character first, then available art family, palette and accessory. Show idle and alert previews so the user can judge readability. Keep the name/bindings when changing art. Unavailable art families get “Coming later”, not a misleading active control. Imported models still follow the existing validation flow. No automatic model call just to browse looks.

**Command bar.** Short concrete suggestions: “Call docs”, “Send Byte home”, “Remind me tomorrow at 3”. Keep command interpretation local where supported; the visual system should not suggest every interaction is a chat with an LLM.

**Settings.** Appearance, Crew, Agents, Privacy, Accessibility. Use platform-like form controls, persistent labels and explicit saved/error states. Accessibility ideas include reduced motion, larger cards, high-contrast state labels and separate sound controls; this package does not claim those controls already exist.

## Motion and voice

Proposed timing: control feedback 120–160 ms; card enter/exit 180–220 ms; crew entrance 400–650 ms; celebration under 1.2 s. Motion settles when the user is reading. Repeated “needs you” events coalesce by session. A status light should not flash faster just because more events arrive. With reduced motion, make state changes immediate and keep the card; omit hops and repeated pulses.

Voice is warm and factual: “Byte · docs needs your answer.” Avoid guilt, urgency theater, “I missed you,” or claiming the pet reasoned about the project. The pet reports the agent's real state. Personalities change gesture and optional phrasing, not the meaning of an approval choice.

## Expanded app experience

See [APP-UX.md](APP-UX.md) for the complete proposed flows and [the local prototype](app-prototype.html) for a clickable walkthrough. The [Studio Collection](PROFESSIONAL-COLLECTION.md) adds workplace-friendly characters and a professional comfort preset. The first board is an exploration; later mockups and the written UX specification take precedence.
