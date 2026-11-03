# Formatic: the Sidecard flow

> The pictures this names are kept out of the repository, in `sandbox/formatic-research/` on the founder's Mac. The icon is in `icon/` here.

2026-11-03. **The founder approved this flow on 2026-11-03**, and asked for one addition: a quicker way in, in the spirit of Filee's donut, not a copy (see `RING.md`).

The design was drawn with Sidefolk's own components, but nothing here converts,
grants or opens anything. The words are samples, and the German and Arabic are my drafts for testing layout.

To redraw it, from the worktree `/Users/ghassenbrg/git/sidefolk-worktrees/formatic-design` (branch `team/formatic-design`, base `ba69bce1`):

```bash
swift run SidefolkApp --ui-snapshots build/fd-out --only formatic
```

## The idea

You don't open a converter. You drop a file on your companion, see what it can become in plain outcomes, choose one, and
get the new file beside the original with a receipt of what changed.

| Step | What you see | Pictures |
|---|---|---|
| 1. Drop | The file with a real preview, Sidefolk's line on who reads it, Formatic's outcomes, and Sidefolk's own choices below | [board](board-light.png), [card](drop-light.png) |
| 2. Work | A small card with the two files, a moving bar and Stop. The light under the companion shows it's working | [working](working-light.png) |
| 3. Receipt | Before and after as two sheets, the real sizes, then Open, Show in Finder and Undo | [receipt](receipt-light.png) |
| After Undo | One sentence: the new file is in the Trash and the original is as it was | [undone](undone-light.png) |

## Other states

- **Several files:** fanned previews, "12 photos", and the exact total. [Names folded](drop-batch-light.png), [all names](drop-batch-names-light.png).
- **Pointer on a choice:** [picture](drop-hover-light.png).
- **Some failed:** "11 of 12 are ready", naming the one that failed and why. [Picture](receipt-batch-light.png).
- **No Open button:** a Word file gets Show in Finder only, following the Open list, plus a note to check its layout. [Picture](receipt-document-dark.png).
- **An extension with internet access:** Sidefolk's amber warning. "Courier" is made up, to show the general rule. [Picture](drop-network-dark.png).
- **Home page:** [light](home-light.png), [dark](home-dark.png).
- **The ring:** a quicker way in, in [RING.md](RING.md). [Light](ring-light.png), [dark](ring-dark.png).
- **Dark, German, Arabic:** [board](board-dark.png), [German card](drop-de-light.png), [German receipt](receipt-de-dark.png), [Arabic card](drop-ar-light.png), [Arabic receipt](receipt-ar-dark.png).

## Three directions from separate designers

After the founder rejected flat black as lazy, three designers worked separately. These are generated concept pictures, not the app, so they show the idea and not exact layout. Invented details like the menu bar's date mean nothing.

| Direction | Pictures | Strongest | Weakest |
|---|---|---|---|
| **Your file sets the colour** (recommended) | [flow](directions/file-colour/flow.png), [ring and Home](directions/file-colour/ring-home.png) | Every conversion looks different and is plainly about your file. Comes from what the product does | White PDFs and screenshots give muddy cards, so they need the icon's colours. The Home page's ring panel still looks like a gradient. Some text fails contrast |
| **Made of glass sheets** | [flow](directions/glass-sheets/flow.png), [ring and Home](directions/glass-sheets/ring-home.png) | Closest to the icon. The receipt's "74% smaller" in the overlap is the best single moment | Busy, hard to read on glass, tilted text, and the hardest to build. Several text colours fail contrast |
| **Bold solid colour** | [flow](directions/solid-colour/flow.png), [ring and Home](directions/solid-colour/ring-home.png) | Confident and easy to build | Loud, so it risks "too much" again. Coral may read as an error, and "−74%" has nothing to say when a file grows |

**Chosen by the founder (2026-11-03): Your file sets the colour.** My recommendation, drawn next, adds the glass direction's receipt, with the saving in the overlap. The Home page stays mostly plain, with the ring's shortcuts as flat rows, so the file pictures are the only rich thing on it.

## The approved look: your file sets the colour

**The founder approved this look on 2026-11-03.** Building still needs an explicit go.

Drawn with Sidefolk's own components, in `FormaticDesignSheet.swift`. These are snapshots with sample data, not a live run.

**The rule of restraint.** The founder stopped a version that put the picture everywhere, even in the progress bar ("you put it everywhere like a child"). An independent design review then set this rule: one picture per card, at thumbnail size. The frost is only the background. Everything on it, such as bars, chips, lines and labels, is white or neutral, never sampled from the picture. So:

- **Working card:** plain white bar, 4 pt, for every file type.
- **Receipt:** one small sheet with the new file, resting on one empty sheet to echo the icon. The result is one line of text: "4.2 MB → 1.1 MB · 74% smaller". No big before-and-after and no white label.
- **Drop card:** thin lines between choices, and quiet tags.
- **Ring:** keeps the founder's preferred dark glass and vivid slice, with the picture only in the middle. Here the founder's stated preference overrides the review, which suggested flat slices in the file's colour. Those looked dull when drawn.

**The rule for every file, including those with no picture:**

| The file has | The card uses | The small sheet shows |
|---|---|---|
| A colourful picture: photos, video frames, album art, covers | Frost from that picture | The picture |
| A picture without colour: white PDFs, scans, screenshots | Formatic's own cobalt and coral | The kind's glass mark |
| No picture: audio without art, data, text, archives | Formatic's own cobalt and coral | The kind's glass mark |

"Colourful" is measured: average chroma of at least 0.14, tried so far on two photos and one white page. It needs testing on many more real files.

**Pictures:** [flow](board-light.png), [dark](board-dark.png), [files without pictures](no-picture-light.png), [dark](no-picture-dark.png), [ring on a photo](ring-light.png), [ring on audio](ring-audio-dark.png), [second set](ring-second-light.png), [audio drop card](drop-audio-light.png), [Home](home-light.png), [dark](home-dark.png).

**Contrast:** an independent audit measured real text on the rendered pictures: 454 of 476 checks passed, and it found these failures:

- The vivid ring slice's words (4.2 to 4.3:1). Fixed by deeper colours, computed at 4.99:1. Not yet re-measured in the pictures.
- Tags and hover rows on bright frost (3.5 to 4.48:1), in the auditor's own test on hard images. Fixed by darker fills; its re-render passed.
- The "colourful" test looked at the unblurred picture, so a picture of fine stripes could pass as colourful and frost to grey. It now looks at the frost.
- The Say bar's placeholder (3.15:1 light, 4.12:1 dark): Sidefolk's shared component, not Formatic's, and reported to the coordinator.
- The progress bar's track against the card (about 1.7:1): left as it is, since the moving fill carries the meaning (fill against track passes).

The scrim is calculated per file. White text held at 5.6:1 or better on all 23 of the auditor's hard images. Not measured: live windows, German and Arabic, other ring slices under the pointer, and wide-colour files.

**What D150's review must cover** (coordinator):

- Reading the dropped file's picture for the frost: the system's out-of-process thumbnailer, with caps and a fallback, as for D141's thumbnail.
- A pack picture that tries to look like a permission slip. Sidefolk's lines stay outside the frame, in Sidefolk's type and colours.
- A contrast measurement that includes real text, independently audited before any build.

Before any build, this branch is rebased onto the current `origin/main`.

**Still honest weaknesses:**

- Frost from Formatic's own colours is a quiet blur of cobalt and coral, still the closest thing here to the gradients the founder disliked.
- Some photos give a muted brown once the scrim is applied.
- The Finder shortcut and the ring aren't proven yet.
- Live blur isn't used. The frost is one blurred image per file, which is cheap, but a file's picture has to come from the system's thumbnail service.

## The look, third pass

**Second pass:** the founder felt the first pass was too plain next to the icon ("the book cover looks very nice, but when you open it's very different"). I pushed it with gradients and glows everywhere.

**Third pass:** the founder found that too much, with too many cheap gradient components, and suggested real assets and a different way of thinking. So:

- **No gradients or glows in the interface.** One flat deep ink, thin lines and one coral. The richness comes from real pictures.
- **Real pictures do the work:** the person's own files, as sheets with a crisp fold, and a few crafted glass assets (`assets/`) in the icon's material, for files that have no picture.
- **The glass appears rarely,** like an illustration in a book: once on the Home page, and on small file assets. The cover and the inside now share one material without the inside trying to be the cover.
- **The Home page is calm:** Sidefolk's own surfaces in light and dark, one picture, one list of recent files, and plain text for the rest.
- **Sidefolk's actions look like Sidefolk's:** Open, Show and Undo use the app's own buttons, even on the dark card, so an extension can't dress them as something else.

**What this needs from the app, beyond options A to D** (D150, not built, not yet reviewed). It's much less than the second pass needed:

- One flat extension colour behind its offer frame, working card and receipt, drawn by Sidefolk. The receipt names the extension, so it can't pass for Sidefolk.
- Sidefolk's lines, the file count and names, and the network warning stay in Sidefolk's own colours and type. The review must cover whether a dark card can look like Sidefolk's permission slip. No colour tokens of our own: this builds on the themes session's tokens once they land.
- **The Home page needs no new page part,** read against `docs/EXTENSIONS.md` on `origin/main` (`fab80beb`, Noor's D105 to D109 included), not yet drawn with them:

| Home page | Parts on main |
|---|---|
| Title, line and picture | `bare`, with a `scene` block holding text and a pack picture |
| Choose a file… | A button with `file`, as an `inlays` control in that scene or a plain block under it. One file at a time |
| Lately | `list` rows with `{"data": name}` pictures |
| What it can make | `facts` |
| Defaults | `switch` and `choice`, or `settings` |

**Where it would differ from the picture:**

- `list` rows have no trailing columns, so "74% smaller" and the time join the row's detail line, unless the rows are drawn as a scene.
- The fold on a thumbnail has to be baked into the picture the extension saves.

**A question for the design:** a picture in Lately means the extension keeps small copies of the person's files in its data folder. They never leave the Mac, but the page should have a way to clear them, or Lately could show file-type assets only.

## Why it looks like this

- **Sidefolk speaks first.** The line with the lock is Sidefolk's own, built from the manifest, so "It can't use the internet" is a fact and not a promise. This is also where Formatic's privacy claim becomes visible.
- **Formatic's words sit in their own frame,** under its icon and name, so they can't pass for Sidefolk (Noor's condition).
- **Outcomes lead, and the format stays visible.** "Opens anywhere" comes with a JPEG tag, so people who think in formats lose nothing.
- **Nothing is pre-selected,** and Return doesn't choose, unlike today's drop card. Choosing is the yes.
- **The original's picture carries through all three steps,** so it's plainly the same thing in a new form.
- **The sizes are measured by Sidefolk** from the two real files.

## What the pictures can't show

- The card ignores clicks for a brief moment after appearing.
- "Another format" opens a menu drawn by Sidefolk, in the same card.
- The preview on the receipt can be dragged out.
- The working bar moves but shows no percentage, because long tasks with progress (option E) are deferred.

## Honest limits

- **Formatic can't look at the file before you choose.** It has no read until then, so its lines are fixed by file type. "Any transparency becomes white" shows even for a photo with none. Real facts arrive only on the receipt.
- **"Small enough to email" is a sample.** The real size rule has to be decided and tested.
- **"Choose a file…" on the Home page** relies on Noor's `file` action, which isn't on main yet, and handles one file at a time.
- **The Home page's figures and shelf are samples.** "Video" needs option D, and "searchable" PDFs and the archive formats aren't tested yet. Only what works may ship on that shelf.
- **The panel is tall,** about 500 pt with the real Ask header, and more with a long list of names, so it needs checking on a small screen.
- **These are pictures from the snapshot tool,** not a run in the live app. I haven't dragged a real file onto a real companion, and this design needs options A, B and C to work.

## What it adds to option B

- Offers from one extension are grouped in one frame, with Sidefolk's line above them.
- A menu of formats in the manifest, drawn by Sidefolk, because the grant ends with the call and a second step wouldn't have one. Its entries are the extension's words, so they stay inside its frame, with the file count and names still visible. Proposed limits, to be settled in D141: at most 12 entries of at most 30 characters. The coordinator has checked this against the other sessions, and it stays separate from Noor's `file` action.
- A preview drawn by Sidefolk from the file, which gives the extension nothing. It isn't a new grant, but it parses an untrusted file, so D141's review covers it: the system's out-of-process thumbnailing (`QLThumbnailGenerator`), a size and time cap, a generic icon on failure, nothing read beyond the dragged file, and never hidden behind the extension's words.

The `DropCard` change stays to file offers. Other sessions are working nearby (`team/themes-two` on the Sidecard's look, `team/ask-keep` on Ask's card lifetimes), and the coordinator will tell them a layout change is coming, so the rebase order is known.
