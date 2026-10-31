# Design: Lantern (D84)

Sidefolk looks like **Lantern**: native macOS surfaces, quiet and neutral, so the companion and its light are the
only warm things on screen. State is light (a pool at the companion's feet), one deep aqua is the action colour, and
everything on the desktop is one surface family, the Sidecard. This page lists the tokens and shared components in
the app so every screen uses the same ones. The full system (with the reasoning, every ratio and the mockups) is the
founder's local design folder, not in the repository; the decision is D84.

**The reference:** `swift run SidefolkApp --ui-snapshots <dir> --only design-system` draws
`design-system-foundations`, `-controls` and `-sidecard` (light and dark, any `--language`, any `--theme`) from the
app's own tokens and components (`Sources/SidefolkApp/Dev/DesignSystemSheet.swift`). If a screen and the sheet
disagree, use the sheet's component; if the sheet looks wrong, fix the component.

## Rules

- **Themes dress, they don't arrange** (D84 narrows D64): a theme sets colours, the display face, density, radii,
  materials, the light pool's colours and the nook's art. Each place has one layout.
- **One primary per card, sheet or page.** Disabled is faded *and* flat, never the default look of a primary.
- **Colour meaning is D78's** (`StatusTone` → `Theme.color(_:)`, `Theme.soft(_:)`, `ChipTone(_:)`); always with a
  word or icon. Glow and folk colours are light and identity, never text and never status.
- **Sentence case everywhere**, eyebrows included. No ALL CAPS (some scripts have none; capitals shout).
- **Firm cards never take Return** (another app's approval, agents' questions, after outside content): ⌘Return or a
  click. Calm cards may.
- **Focus is a half circle (`circle.lefthalf.filled`), Quiet a moon (`moon.fill`)**, everywhere: `Theme.Symbol`.
- **Text floor 11 pt;** leading/trailing, never left/right; numbers, keys and paths in left-to-right isolation.
- Reduce Motion: no scale or travel, the pool is a still colour. Reduce Transparency: glass becomes the card
  surface. Increase Contrast: hairlines become `Theme.controlBorder`, the pool a 2 pt ring.

## Tokens

Core values: `Sources/SidefolkCore/Themes/ThemeTokens.swift` (Harbor is Lantern). App names:
`Sources/SidefolkApp/DesignSystem/Theme.swift`, `ThemeStore.swift` (fonts) and `ThemeMetrics.swift` (sizes, depth,
glass, symbols).

| Group | Names | Notes |
|---|---|---|
| Ink | `Theme.ink`, `inkMuted` (ink 2), `inkFaint` (ink 3, meta) | navy #0F1E36 / #EEF2F8; all ≥ 4.5:1 on every surface |
| Surfaces | `surfaceSunken` (the window's canvas), `surfaceRaised` (cards), `surface`, `well` (fields, chips, search, segmented track), `line` | `well` is new; a theme without it uses its `surfaceSunken` |
| Action | `accent` (fills), `onAccent` (its label), `accentSoft` (selection, calm strip), `link` (accent as text) | deep aqua #0B7783 / #3CD6DB, label 5.3 and 8.8:1 |
| Status | `danger`, `warning`, `success` (+ `Soft`, `on…`) | D78 meanings; theme check holds the hues |
| Light | `glow` (working), `waitGlow` (waiting) | never text; optional theme roles |
| Control border | `Theme.controlBorder` | ink 3 at 45%, for frames that aren't fills |
| Folk accents | `Theme.folkColor(_:)` | Lantern's table: Tempo #5B8DEF, Scout #F2B33D, Byte #3B6FF5, Guard #1FA88A, Pip #FF7B6B, Play #F0524F, Nova #A68BFA, Seed #52C08A, Melody #8E6CF0, Brew #C99A5B |
| Type | `Theme.Font.display` 30, `title1` 22, `title2` 17, `headline` 14, `body` 13, `bodyStrong`, `callout` 12, `caption` 11.5, `eyebrow` 11, `stateWord` 26, `number` 26 tabular, `bubble` 14, `bubbleTitle` 15, `input` 17, `mono` 12 | the theme face only on display, title1, stateWord, number (and `heading`); `hero`/`title` are display/title1 |
| Spacing | `Theme.Space.xxs…xxl` 2 4 8 12 16 24 32, `xxxl` 48, `xxxxl` 64 | scaled by the theme's density |
| Radii | `Theme.Radius.xs` 6, `control` 8, `card` 12, `panel` 18 (Sidecard, sheets, popovers), `bubble` 18 | capsules for chips, pins, the Say bar |
| Sizes | `Theme.Size.row` 44, `compactRow` 32, `sidebarRow` 30, `hitTarget` 28, `button` 28 / `buttonSmall` 24 / `buttonSidecard` 30 / `buttonLarge` 32, `field` 28, `chip` 22, `sayBarHome` 40 / `sayBarDesktop` 52, `sidebar` 232, `contentMaxWidth` 1080, `contentPadding` 32, `sheet` 520, `installSheet` 600, `sidecardMin…Max` 320–400, `sidecardAsk` 420, `stackBadge` 28, `pin` 36, `tileMin/Max` 160–240 | same in every theme |
| Depth | `.elevation(.e0…e3)` | e1 cards, e2 popovers and hover, e3 Sidecard and sheets |
| Glass | `.lanternGlass(radius:)` | material + tint + e3; opaque with Reduce Transparency |
| Motion | `Theme.Motion.micro` 120 ms, `standard` 200 ms, `enter` spring 0.32/0.86, `exit` 160 ms, `breath` 3 s; `spring`, `ease` as before | nil when the theme's motion is none |
| Symbols | `Theme.Symbol.focus`, `.quiet`, `.say` | |

## Components

All in `Sources/SidefolkApp/DesignSystem/`.

| Component | File | Use |
|---|---|---|
| Buttons: `.sf(.primary / .secondary / .quiet / .destructive / .danger / .plain, size: .small/.regular/.sidecard/.large, working:)`; `.sf(kind)` (small, as before), `.sfPrimary`… | `Buttons.swift` | hover and press veil, 0.98 press, 40% disabled, spinner while working. `.destructive` is quiet danger ink; `.danger` the red fill that confirms |
| Chip, `ChipTone` (fill + ink) | `Components.swift` | 22 tall, sentence case |
| `TouchChip(Touch)` "what it touches" | `TouchChip.swift` | `Touch(ApprovalRequest.Effect)`; amber for what reaches the person's things or leaves the Mac |
| Card surface: `.cardSurface()`, `SFCard`, `RowsCard` | `Components.swift` | e1, hairline |
| `ListRow` (+ `RowChevron`) | `ListRow.swift` | 44/32 rows, icon, title, meta, trailing value, ≤ 2 hover actions, selected state |
| `SectionHeader` (title, folk, count, detail, trailing) | `Components.swift` | |
| `Eyebrow` | `Components.swift` | sentence case, no tracking in Arabic and CJK |
| `SegmentedPicker` | `SegmentedPicker.swift` | 2–5 choices; `small`, `equalWidths`; replaces every `.pickerStyle(.segmented)` |
| `StatusBadge` (dot + word, `BadgeState.tone/.live`), `CountBadge`, `StateWord`, `StateTile`, `PinCapsule`, `FolkAvatar` | `StateViews.swift` | `Sparkline` is in `Home/TodayParts.swift` |
| `EmptyState` (with its one action) | `Components.swift` | |
| `SearchBox`, `.fieldChrome(focused:problem:)`, `CommitField` | `SearchBox.swift`, `FieldChrome.swift`, `Components.swift` | a well, no border until focus |
| `SayBarField` (.home / .desktop), `KeyHint`, `UnderstandingRow` | `SayBar.swift` | the Say bar's shell; behaviour is the screen's |
| Sidecard: `SidecardSurface` (glass, tail), `SidecardShape`, `SidecardTail`, `Whisper`, `SidecardCard` (source line or slip layout, extra, ≤ 3 actions), `SidecardStrip` (calm / firm), `SidecardStack` | `Sidecard.swift` | looks only: placement, timing and answering are the desktop's |
| `LightPool(state:)`, `LightPoolState`, `ShoulderBadge` | `LightPool.swift` | the companion's state as light, with its VoiceOver words |

## Not built yet (phases 2–4)

The desktop's behaviour (placing the pool and Sidecard by the companion, the stack's arc, pins, the agents lane, the
permission slip wired to Guard), Home's places (Today rebuilt, On duty, History, You, the Gallery in Home, the Say
bar in the toolbar), Settings' 8 tabs with search, the menu bar Pocket, Full access with an end time. The 16 text
fields still on `.roundedBorder` move to `.fieldChrome` as their screens are rebuilt. The theme-specific Today block
styles (console, planner, stage) keep their own capitals until phase 3 retires them (one layout per place).
