# Third-party logos

The logos Settings › AI and Settings › Agents show beside each AI service (D36). They are not
Sidefolk's brand.

## Source and licence

- **Project:** [LobeHub Icons](https://github.com/lobehub/lobe-icons), npm package
  `@lobehub/icons-static-svg`, version **1.101.0** (published 2026-10-26).
- **Fetched from:**
  `https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.101.0/icons/<name>.svg`, on 2026-10-26.
  The SVGs in `lobehub-icons/` are those files, byte for byte.
- **Licence:** MIT, Copyright (c) 2023 LobeHub (`package.json` says `"license": "MIT"`; the
  repository's LICENSE is reproduced in `THIRD_PARTY_NOTICES.md`). MIT covers LobeHub's files and
  drawings. It grants no trademark rights, and neither the package nor its README says anything
  about the logos' owners.
- **Trademarks:** each logo is a trademark of its owner. Sidefolk uses them only to identify the
  service an option connects to, never as its own mark, and claims no affiliation or endorsement.

| Service in Sidefolk | File in `lobehub-icons/` | Title in the file | Drawn in | Owner's page |
|---|---|---|---|---|
| Claude Code (plan, and Settings › Agents); Anthropic (API key) | `claude-color.svg` | Claude | colour, Claude orange `#D97757` | https://claude.com |
| OpenAI | `openai.svg` | OpenAI | black or white | https://openai.com |
| Codex (plan, and Settings › Agents) | `codex.svg` | Codex | black or white | https://openai.com/codex |
| Google Gemini | `gemini-color.svg` | Gemini | colour, its blue, red, yellow and green gradients | https://gemini.google.com |
| Mistral | `mistral-color.svg` | Mistral | colour, its gold-to-red stripes | https://mistral.ai |
| Groq | `groq.svg` | Groq | black or white | https://groq.com |
| xAI | `xai.svg` | Grok | black or white | https://x.ai |
| DeepSeek | `deepseek-color.svg` | DeepSeek | colour, DeepSeek blue `#4D6BFE` | https://www.deepseek.com |
| OpenRouter | `openrouter.svg` | OpenRouter | black or white | https://openrouter.ai |
| Ollama | `ollama.svg` | Ollama | black or white | https://ollama.com |
| LM Studio | `lmstudio.svg` | LM Studio | black or white (its trailing bars at 30 %) | https://lmstudio.ai |

LobeHub names a file `-color` when the owner draws the mark in colour; the others are one shape.

### Choices worth knowing

- **Anthropic's API row shows Claude's mark**, the same as Claude Code. The row's own subtitle is
  "Claude models", Claude is the name people look for, and Anthropic's letter A would read as a
  different service next to it. The alternative, Anthropic's own A-mark, is one line in
  `AIChoice.logo` and one more file here.
- **Codex has its own mark** (the cloud with a prompt), which LobeHub offers in black and in a
  gradient on a white tile. The black one is used: the other brings a white square of its own that
  shows in dark mode. No OpenAI page we could read offers a Codex file, so its source is LobeHub's
  drawing of the Codex app icon.
- **xAI shows xAI's mark**, not the Grok swirl (`grok.svg`), because the row is called xAI.
- **OpenRouter is shown in black or white.** Its brand page offers Grape and Volt for colour
  (Volt, LobeHub's `openrouter-color`, is for dark backgrounds only) and Ink and Cloud for black and
  white, so the one file covers both appearances.

### Brand rules checked, and what is not verified

The marks are not altered, recoloured, stretched or framed: the app draws them at their own
proportions, centred on a neutral plate (white; dark navy in dark mode) with the plate's own
margin as the clear space, at 66 % of the plate's size. The plate is the app's tile, not a frame on
the mark.

- **Anthropic** ([trademark guidelines](https://www.anthropic.com/legal/trademark-guidelines)): no
  alteration of colour, font or proportions; reasonable clear space; backgrounds that don't hurt
  legibility; no implication of sponsorship or endorsement. The page also says use is limited to
  what Anthropic permits and that it supplies the logo images itself. Not asked: the founder may
  want to write to marketing@anthropic.com before a public release.
- **Mistral** ([brand page](https://mistral.ai/brand)): gradient version preferred; don't recolour,
  stretch, rotate, frame, use old or unofficial versions, or put it on a coloured background. Its
  downloads are PNG only, so the vector is LobeHub's, which carries the same colours.
- **OpenRouter** ([brand assets](https://openrouter.ai/brand)): "Please don't stretch, recolor, or
  remix the marks." Glyph in Grape, Volt, Ink or Cloud.
- **xAI** ([brand guidelines](https://x.ai/legal/brand-guidelines)) and **OpenAI**
  ([brand page](https://openai.com/brand/)): both refused the page fetch (HTTP 403), so their rules
  are known only from search summaries: use only to refer accurately to the service, no implied
  endorsement, no altering, clear space. Not read in full.
- **Google (Gemini), Groq, DeepSeek, Ollama, LM Studio:** no usable brand page found. Groq's old style
  guide lists orange `#F55036` as its primary colour for accents; LobeHub has only a one-colour
  Groq mark, so it is shown black or white and nobody has confirmed whether Groq draws it in orange.

## How the app uses them

`swift scripts/provider-logos.swift` turns each SVG into `logos/<name>.pdf`: a 24 × 24 pt vector
page. The script writes the PDF itself (paths, colours, gradients with their transparency as soft
masks) and cannot write a bitmap; it exists because macOS's own SVG renderer bends Claude's and
Codex's marks, loses LM Studio's 30 % bars and flattens Gemini's gradients. A feature it doesn't
know stops it. The app bundle copies `logos/` to `Contents/Resources/ProviderLogos/`.

`ProviderLogo` loads them. `-color` files are drawn as they are. The others are template images,
tinted pure black on light and pure white on dark (`Theme.logoInk`), the black or white the owners
ask for; the navy of the app's ink colour would be a recolouring. A dev build finds them with
`SIDEFOLK_RESOURCES=<repo>/Resources`; without it the tiles fall back to monograms and symbols.

To update: fetch the files of one exact newer version from the URL above into `lobehub-icons/`,
run the script, look at `swift run SidefolkApp --ui-snapshots`, and change the version here and in
`THIRD_PARTY_NOTICES.md`.
