# Launch kit for Sidefolk 0.1.0

Everything needed to release and announce 0.1.0, written to match the app as it is. Start with
[CHECKLIST.md](CHECKLIST.md): it lists what still blocks a public release and who owns each step.

| File | What it's for |
|---|---|
| [CHECKLIST.md](CHECKLIST.md) | What blocks a public release that isn't code: owners, status, next actions |
| [DESCRIPTIONS.md](DESCRIPTIONS.md) | Store-style name, subtitle, promotional text, short and long descriptions, keywords |
| [LANDING-PAGE.md](LANDING-PAGE.md) | The website, block by block, with the picture for each |
| [posts/show-hn.md](posts/show-hn.md) | Hacker News "Show HN" title and first comment |
| [posts/product-hunt.md](posts/product-hunt.md) | Product Hunt tagline, description, gallery, maker's comment |
| [posts/x-thread.md](posts/x-thread.md) | An eight-post thread for X |
| [posts/reddit-macapps.md](posts/reddit-macapps.md) | A post for r/macapps |
| [posts/linkedin.md](posts/linkedin.md) | A LinkedIn post |
| [DEMO-VIDEO.md](DEMO-VIDEO.md) | A 60-second demo: preparation, shot list, captions, cut-downs |
| [press-kit/README.md](press-kit/README.md) | Facts, boilerplate, founder quote, logos, screenshots |
| [REVIEWER-FAQ.md](REVIEWER-FAQ.md) | Short answers and a ten-minute tour for reviewers |
| [screenshots/](screenshots) | 35 PNGs, light and dark, plus French, Japanese and Arabic |

Picture paths in these files are relative to `docs/launch/` unless they start with `Resources/`.

## Rules for every word here

- **True today.** Nothing that 0.1.0 doesn't do. When in doubt, check docs/STATUS.md and
  docs/RELEASE-NOTES.md, and say what isn't done.
- **The voice** of [docs/VOICE.md](../VOICE.md): lead with the thing, short sentences, concrete examples
  ("remind me tomorrow at 9…"), warmth from plainness, no hype words, no exclamation marks.
- **`[FOUNDER: …]`** marks a decision, a link, a price or a quote only the founder can give. Search for
  `FOUNDER` before publishing anything.
- **Other companies' names** as plain text, and their logos only once they've agreed (CHECKLIST #4).

## Screenshots

`swift scripts/launch-screenshots.swift` renders the app's UI snapshots (English, French, Japanese,
Arabic) into `build/launch-snapshots/` and rebuilds this folder: the picks are listed at the top of the
script. Run it again after UI changes so the kit never shows an old screen. The hero pictures are
composites (real snapshots on a plain backdrop beside Mochi's brand art); everything else is a snapshot as
the app draws it, with English sample data in every language.
