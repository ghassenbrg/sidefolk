# Themes and the new Home

2026-10-30 · Decided in D57 and D58. **The build plan is [themes-plan.md](themes-plan.md).** The boards, their HTML and the art live in `sandbox/theme-sandbox/` (local, not committed).

The boards are HTML pages rendered to PNG with headless Chrome. The text is real and set in the faces the app would
use (SF Pro, SF Rounded, New York, SF Mono), and the sample data is Sidefolk's own. Each board shows one theme: the
main Today window, the one bar, the Notebook, Activity, the companion, the other appearance (light or dark) and
numbered notes.

To rebuild them: `sh render.sh` renders every board. The three Board-recipe themes are generated first with
`python3 -I make_board.py`.

## The seven themes

| Board | Theme | For | Recipes (navigation · today · activity · editor) |
|---|---|---|---|
| [harbor.png](../../sandbox/theme-sandbox/harbor.png) | **Harbor** (default for now) | Everyone | Sidebar · Desk · Table · Rich |
| [daylight.png](../../sandbox/theme-sandbox/daylight.png) | **Daylight** | Everyone who likes it bright | Sidebar · Board · Table · Rich |
| [nightstudio.png](../../sandbox/theme-sandbox/nightstudio.png) | **Night Studio** | Evenings, calm and dark | Sidebar · Board · Table · Rich |
| [nightshift.png](../../sandbox/theme-sandbox/nightshift.png) | **Night Shift** | Developers working with agents | Rail · Console · Log · Markdown |
| [marshmallow.png](../../sandbox/theme-sandbox/marshmallow.png) | **Marshmallow** | People who want something cute | Pills · Stage · Diary · Rich |
| [fieldnotes.png](../../sandbox/theme-sandbox/fieldnotes.png) | **Field Notes** | People who think in a paper planner | Ribbons · Planner · Diary · Rich |
| [papergarden.png](../../sandbox/theme-sandbox/papergarden.png) | **Paper Garden** | People who want a calmer, softer day | Sidebar · Board · Table · Rich |

Daylight, Night Studio and Paper Garden keep the atmosphere of the earlier agent's try (`sandbox/home-design-themes/`).
They are rebuilt on our components and rules, and their shared card-grid layout became the **Board** recipe. Every
theme comes in light and dark.

## 1. What today's Home gets wrong (from the current snapshots in `assets/`)

- **Now makes you scroll to learn your day.** A large greeting, five "Needs you" rows that look the same, and the
  rest below the fold.
- **There's nowhere to type.** Search lives inside one collection, Conversations has its own, and Activity has none.
- **The companion is a picture.** Nothing in Home says what it's doing.
- **Claude Code and Codex only appear when they need you.** You can't see that they're working.
- **Activity cuts off What and Outcome,** the columns that matter for trust.
- **Links exist but are scattered:** who saved a note, its reminders, the conversation.

## 2. Principles

1. **Decide, then see, then find.**
2. **One place to type,** the same in Home and the Ask panel.
3. **The keyboard does everything the mouse does,** except approving another app's request, which needs a click on
   purpose.
4. **The companion and the agents are presences.** Say what they're doing, in words.
5. **A theme never hides trust.** Risk, the exact command, the deadline and the rule are always shown.
6. **A theme is data.** Colours, type, shape, motion, art and a choice of the app's own layouts, never code or
   wording.
7. **No fake features.** Everything on a board is either what Sidefolk does or is in themes-plan.md with what makes it
   real.

## 3. What every theme gets

All of it is in themes-plan.md section B, built once and shown by every recipe:
- Today, with a decision queue answered from the keyboard (another app's request needs a click);
- the one bar, which shows what it understood, and which tool will run, before ⏎;
- the day line with your calendar once you turn it on;
- watch tiles that show what changed;
- agents at work;
- the companion's nook;
- Glance;
- Activity rows that open in place;
- notes that show where they came from, with real links to conversations;
- the formatting bar appearing only when text is selected.

## 4. What a theme is, and how easy it is to make one

A theme is **one `theme.json`**, optionally with a few PNGs. See [theme.example.json](theme.example.json) and themes-plan.md
section A. It can set:
- colour roles in light and dark;
- the display face (system, rounded or serif) and density;
- corner radii;
- motion: calm, bouncy or none;
- the sidebar material and paper grain;
- the companion's nook style and a suggested companion;
- empty-state art;
- one recipe per surface.

**Making one:**
1. `sidefolk theme new "Sunset"` copies Harbor into a folder.
2. Load it in Settings › Appearance › Load theme from folder…
3. Edit `theme.json`: every window repaints as you save.
4. `sidefolk theme check` tells you what fails, in words (contrast, a missing role, an image too big).
5. `sidefolk theme preview` renders boards like these.
6. Share the folder, or publish it to the gallery as a signed pack.

`make_board.py` already works this way: three themes are just token sets over one recipe.

**The art is generated.** The four images in `sandbox/theme-sandbox/assets/art-*.png` (Daylight's sky, Night Studio's dusk, Paper
Garden's leaves, Marshmallow's candy sky) were made with the image-generation skill. Each brief named the theme's
palette, where empty space must stay for text, and "no text". They were resized to stay under the theme image cap
(2 MB, 1600 px). That step belongs in the theme skill too.

Once the themes are approved, this session becomes a **create-a-theme skill**: writing the manifest, checking it,
previewing it, making the art, and publishing the pack.

## 5. Decisions I made, and why

| Question | Decision | Why |
|---|---|---|
| Layout recipes in v1, or colours first? | **Recipes in v1.** Four navigations, five Todays, three Activities, two editors. | They're what make Marshmallow, Night Shift and Field Notes feel like different products, not repaints. Recipes are shared, so each new theme costs only data. |
| Rename Now and Activity? | **Now becomes Today; Activity stays; Conversations stays.** | The page is now the shape of your day. "Today" is already translated in every language. "Journal" would be confused with the Notebook. |
| Calendar? | **Yes, read-only, off until you turn it on** (D57). | A day line without your meetings is half a day. EventKit stays local, and the AI only reads it through a Guard-checked tool. |
| Links to conversations? | **Yes, stored** (a migration on Activity rows and notes). | "Asked in…" and "Talked about in…" are the most useful context, and they only count if they're real. |
| The one bar outside Home? | **The Ask panel becomes the same component.** | One place to type, everywhere, and no second parser or preview to maintain. |
| Community themes? | **Signed packs in the gallery, plus local install of unsigned themes that pass the validator,** with a "not reviewed" label and images re-encoded. | A theme can't run code, so the risk is small. Keeping the door open is what lets people make their own. |
| Another app's approvals and the keyboard | **Always a click,** in every theme. | It's the existing rule (`AppCoordinator.swift:562`), and themes must never weaken it. |

## 6. Built in and in the gallery (decided, D58)

The founder took this recommendation:

- **Built in:** Harbor (default), Night Shift, Marshmallow, Field Notes. These are four different kinds of people,
  and the four most different layouts. Built-ins should show what the system can do.
- **Gallery, from day one:** Daylight, Night Studio, Paper Garden. They use the shared Board recipe, so they are
  pure data packs. That makes them the best proof that anyone can make a theme, and they give the gallery's Themes
  shelf something to show at launch.

Whatever you choose, all seven are built (themes-plan.md section D), so the choice only decides where each one lives.

## 7. What I kept from the earlier try

- **Kept:** the Daylight, Paper Garden and Night Studio atmospheres; data-only manifests; light and dark for every
  theme; decisions first.
- **Changed:** their screens showed things Sidefolk can't do (email replies, meeting "Join" buttons). Here every row
  is backed by a real feature, and every board uses the same components and safety rules.
