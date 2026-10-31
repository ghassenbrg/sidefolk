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
| `LightPool(state:)`, `LightPoolState`, `ShoulderBadge(state:count:)` | `LightPool.swift` | the companion's state as light, with its VoiceOver words; an alert pulses once |
| `.lanternGlass(radius:elevation:)` | `ThemeMetrics.swift` | e2 for small glass on the desktop (pins, tips), e3 for the Sidecard |

### The desktop (phase 2)

The parts above, placed and wired, in `Sources/SidefolkApp/`. The logic that decides is in the core and tested
(`DesktopLight`, `AgentLane`, `Understanding`, `ApprovalRequest.slipTone/takesReturn`).

| Part | File | What it does |
|---|---|---|
| The floor: `FloorModel`, `FloorUnderlay` (pool), `FloorOverlay` (badge, extras), `FloorExtras`, `MiniPin`, `AgentDot`, `FloorTip` | `Companion/CompanionFloor.swift` | the light under the feet, the count on the outer shoulder, pins as icon + number and agents as round faces above the folks; details only in a tip on hover; the extras fade and shrink while the person types in a window under them or passes the pointer through |
| `CompanionWindowController.area(box:folk:extras:)` | `Companion/CompanionWindowController.swift` | the corner the companion takes; with everything on it is no bigger than before D84 (281 × 159 pt at the medium size, 3D) |
| `SidecardController`, `SidecardModel`, `SidecardView`, `SidecardItemCard` | `Sidecard/` | whisper (6 s, a line runs out the time, waits under the pointer, grows into a card on click), card (source line, ≤ 3 answers with the rest in ⋯), the stack fanned from the count, "All clear" |
| Ask: `AskView` on `SidecardSurface`, `SayBarField(size: .desktop)`, the understanding row, `GlanceView` (resting: Needs you, Next up, Working) | `Ask/` | the Sidecard's Ask size, its tail toward the head; requests as one card each with their words inside |
| `PermissionSlip` | `Ask/PermissionSlip.swift` | the approval rebuilt: calm or firm strip, Guard's face, one sentence, what it touches, Allow with "Always…" in its menu, exact request folded; firm never takes Return (⌘↩ with a `KeyHint`) |

Settings and the menu bar (phase 4), in `Sources/SidefolkApp/Settings/` and `StatusItem/`:

| Component | File | Use |
|---|---|---|
| `SettingsRoot` (sidebar, search, page), `SettingsTab` (title, symbol, tile tint) | `SettingsRoot.swift`, `SettingsTab.swift` | the window; tabs are tiles like System Settings |
| `SettingKey` (tab, section, title, detail), `SettingsNavigation`, `.settingAnchor(_:)`, `SettingsRow(_ key:)`, `SettingsToggle(_ key:)` | `SettingsCatalog.swift` | every searchable row; a new setting gets a key, or search can't find it |
| `SettingsPage` | `GeneralSettingsView.swift` | a tab's column, 720 at most, leading; scrolls to a jumped-to row |
| `SettingInlineControl` | `SettingsRoot.swift` | the control itself in a search result (switches, short choices) |
| `AttentionDial` (cards or compact), `AttentionUntilMenu`, `AttentionSpan` | `AttentionSettingsView.swift` | Open, Focus, Quiet and their ends, here and in the Pocket |
| `TrustHero`, `RadioDot`, `FullAccessSheet`, `FullAccessEnd` | `ApprovalSettings.swift` | the four modes as cards with an example each |
| `PocketView`, `PocketModel`, `PocketContent`, `PocketActions` | `StatusItem/` | the menu bar's popover; content gathered by `AppCoordinator+Pocket` |
| `InstallPreviewSheet` (steps `.who`, `.touch`), `InstallPermissionRow` | `InstallPreviewSheet.swift`, `InstallReviewParts.swift` | the install passport |

### Home's parts (phase 3)

In `Sources/SidefolkApp/Home/`; use them for any new place in Home.

| Component | File | Use |
|---|---|---|
| `HomePage` | `TodayView.swift` | a place's scrolling page: content ≤ `contentMaxWidth`, `contentPadding` (24 under 900) |
| `.lanternTile(bar:)` | `TodayParts.swift` | a tile's surface with its 3 pt state bar (Today's watch and value tiles) |
| `NeedsYouCard` | `TodayView.swift` | one thing that waits: folk avatar, "who · time", the card's words, a 3 pt amber bar, the keyboard's ring |
| `FolkCard` | `OnDutyView.swift` | a folk's group of rows: avatar with its live ring, name, role, count |
| `SidebarSquircle`, `PageSquircle`, `SidebarNook` | `HomeSidebar.swift`, `ExtensionsSidebar.swift` | 20 pt tinted icons in the sidebar; the companion's nook |
| `SayPanel`, `SayWords` | `SayPanel.swift` | what typed words will do, from `IntentPlan`: sentence, chips, AI chip, keys |
| `PersonAvatar`, `CompanionAvatar` | `HistoryView.swift` | who did something, beside a sentence |
| `GalleryArt` | `HomeGalleryView.swift` | a gallery picture filling a card's top |

## Not built yet (phases 2 and 5)

On the desktop (phase 2 left these): the stack's arc animation, the choice card for drops, the evening wrap, voice's
level-reactive pool, keyboard answering of cards outside Ask. Home is built (phase 3, D84; its theme layouts are
retired); Settings, the Pocket, Full access with an end and the install passport are phase 4 (above). The 16 text fields
still on `.roundedBorder` move to `.fieldChrome` as their screens are rebuilt. Reduce Transparency and Contrast versions
are phase 5.
