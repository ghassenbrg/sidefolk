# Third-party logos

The logos Settings › AI and Settings › Agents show beside each AI service (D36). They are not
Sidefolk's brand.

## Source and licence

- **Project:** [Simple Icons](https://simpleicons.org/), npm package `simple-icons`, version
  **16.35.0** (published 2026-10-11).
- **Fetched from:** `https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/<slug>.svg`, on
  2026-10-26. The SVGs in `simple-icons/` are those files, unchanged.
- **Licence:** Simple Icons releases its icons under
  [CC0 1.0 Universal](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md). None
  of the icons below carries an icon-specific licence in that version's data file
  (`data/simple-icons.json`).
- **Trademarks:** each logo is a trademark of its owner. Sidefolk uses them only to identify the
  service an option connects to, never as its own mark, and claims no affiliation or endorsement.
  CC0 covers the drawings' copyright, not the owners' trademark rights.

| Service in Sidefolk | Slug | Title in Simple Icons | Its source |
|---|---|---|---|
| Anthropic (API key) | `anthropic` | Anthropic | https://www.anthropic.com |
| Claude Code (plan, and Settings › Agents) | `claudecode` | Claude Code | https://code.claude.com |
| Google Gemini | `googlegemini` | Google Gemini | https://gemini.google.com |
| Mistral | `mistralai` | Mistral AI | https://chat.mistral.ai |
| DeepSeek | `deepseek` | DeepSeek | https://www.deepseek.com |
| OpenRouter | `openrouter` | OpenRouter | https://openrouter.ai |
| Ollama | `ollama` | Ollama | https://github.com/ollama/ollama/issues/2152#issuecomment-1905286922 |
| LM Studio | `lmstudio` | LM Studio | https://files.lmstudio.ai/lmstudio_icon2.svg |

Not in Simple Icons 16.35.0, so shown as a monogram or SF Symbol instead (never a drawing of
their logo): **OpenAI** (and so **Codex**), **Groq** and **xAI**. Check a later version before
adding one, and record it here.

## How the app uses them

`swift scripts/provider-logos.swift` turns each SVG into `logos/<slug>.pdf`: a 24 × 24 pt vector
page, drawn by macOS's own SVG renderer, one black shape. The app bundle copies `logos/` to
`Contents/Resources/ProviderLogos/`; `ProviderLogo` loads them as template images, so they take the
ink colour in light and dark, monochrome, never the brand colours. A dev build finds them with
`SIDEFOLK_RESOURCES=<repo>/Resources`; without it the tiles fall back to monograms and symbols.
