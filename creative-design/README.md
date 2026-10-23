# Sidefolk — creative direction

24 October 2026 · Concept package v2

**A small crew. By your side.** Sidefolk gives your agents a recognizable presence: a companion you can identify before reading a project name. Warm enough to keep around; clear enough to trust with a permission request.

Open **[the visual lookbook](index.html)** for the artwork, roster, crew combinations, logo directions and interface ideas in one place.

## Recommended direction

Keep **Pip as the hero**, with **Byte the cat and Patch the fox** as the first named crew. Start with the existing 3D bodies. Offer **Soft 3D**, **Ink & Geek**, and **Pocket Anime** as distinct art families over time. Preserve each character's silhouette, identifying accessory and name across styles. A style is a visual preference, never a different set of agent capabilities.

**Selected by the user: Pip Signal**, the bunny-head mark with a mint status dot and rounded lowercase wordmark. The exact selected reference is preserved in `references/selected-pip-signal.png`; the standalone logo is `images/07-pip-signal-logo.png`. Side by Side and The Den remain exploratory alternatives. Pip Signal remains the brand across all character collections.

For work, add the **Studio Collection**: Calder, Finch, Orbit, Slate, Vale and Dot, each explored in 2D and 3D. Recommended work companion: Slate; most neutral: Dot. The **[clickable app prototype](app-prototype.html)** and **[UX specification](APP-UX.md)** show a friendly interface for technical and nontechnical users.

## Contents

- [Character roster and crew recipes](CHARACTERS.md): 18 named characters, personalities, states and nine possible crews.
- [Professional collection](PROFESSIONAL-COLLECTION.md): six office-friendly characters and three additional crews.
- [App UI/UX specification](APP-UX.md): setup, home, requests, crew, reminders, preferences, empty/error states.
- [Clickable app prototype](app-prototype.html): local sample flows; no live agent actions or persistent changes.
- [Visual design system](DESIGN-SYSTEM.md): identity, palettes, typography, interaction patterns, accessibility and motion.
- [Production handoff](PRODUCTION.md): existing support, proposed 2D/3D contracts, art corrections and an incremental delivery order.
- [Machine-readable roster](characters.json): stable concept IDs, art families and rollout groups. Design data only; not an app import format.
- [CSS tokens](tokens.css): proposed light/dark theme values, used by this lookbook only.
- [Exact generation prompts](prompts.json): first-round built-in image generation prompts and output filenames. [Version 2 prompts](prompts-v2.json) cover the selected logo, professional collection and expanded app screens.
- `images/`: generated character, logo and interface boards, plus the standalone logo concept.

## Artwork

| Board | What it explores |
|---|---|
| [Soft 3D crew](images/01-soft-3d-crew.png) | Pip, Byte, Patch, Loom, Moss, Relay |
| [Ink & Geek](images/02-ink-2d-crew.png) | Pip, Byte, Patch, Stack, Nib, Pico |
| [Pocket Anime](images/03-anime-crew.png) | Pip, Byte, Patch, Sora, Yuna, Kite |
| [Logo directions](images/04-logo-directions.png) | Side by Side, Pip Signal, The Den |
| [Design system](images/05-design-system.png) | Permission card, den, appearance picker, status and dark theme |
| [Earlier standalone logo](images/06-side-by-side-logo.png) | Side by Side exploration; not selected |
| [Selected logo](images/07-pip-signal-logo.png) | Pip Signal on ivory; user-selected identity |
| [Studio Collection](images/08-professional-crew.png) | Six professional characters, each in 2D and 3D |
| [Onboarding](images/09-onboarding-experience.png) | Welcome, appearance, optional connection |
| [Home and request](images/10-home-and-request.png) | Plain-language progress and explicit decisions |
| [Crew and preferences](images/11-crew-and-preferences.png) | Appearance and comfort settings |

## Scope and status

This is a creative exploration, not a change to the app's approved character contract. Generated boards are raster concept art: they are not rigged GLBs, animation atlases, vector logo masters, or screenshots of shipped features. The current app has bunny/cat/fox 3D bodies; 2D rendering and the other species require implementation. Brand and character names are working proposals, not researched trademark claims.

The artwork intentionally explores a wider world. The production notes identify where the generated images need to return to Sidefolk's small-screen constraints. Existing roadmap and runtime files remain authoritative.

The selected logo is an opaque raster on ivory. The exact user reference remains authoritative; a transparent vector master still needs production. The unused alpha experiment is marked as a draft in `references/`.
