# Package verification

Checked 24 October 2026.

- 18 unique character IDs; six professional characters; 18 roster cards in the lookbook.
- 11 final PNG assets exist and decode as PNG headers with expected dimensions. The selected Pip Signal logo is 1254 × 1254 on ivory. The paired Studio board and eight other presentation boards are 1536 × 1024; the earlier Side by Side transparent lockup is 1983 × 793.
- All static HTML file links, fragment anchors and Markdown file links resolve. HTML element nesting and duplicate IDs checked in both pages.
- Both JSON prompt sets parse and refer to existing final assets. The selected reference is copied into the package, so it does not depend on the original temporary clipboard location.
- JavaScript syntax checked for both the lookbook and app prototype.
- App prototype logic exercised in a simulated DOM: navigation, request allow/decline, duplicate-decision guard, appearance and comfort presets, reminder add/complete, escaped reminder text, settings, onboarding back/next, connection explanation and reset.

## Palette measurements

Calculated text/background contrast ratios for the specified token pairs:

| Pair | Ratio |
|---|---|
| Charcoal on ivory | 12.94:1 |
| Muted text on ivory | 5.10:1 |
| Ivory on dark surface | 13.31:1 |
| Muted text on dark surface | 8.34:1 |
| Charcoal on mint | 7.68:1 |
| Light focus against ivory | 6.21:1 |
| Dark focus against dark surface | 10.33:1 |
| Light control boundary against light surface | 4.37:1 |
| Dark control boundary against dark surface | 5.74:1 |

These calculations do not certify the finished UI. Generated boards sometimes use incidental colors and typography; implementation should follow the written tokens.

## Limits

Generated artwork was inspected as images. The HTML prototypes were not screenshot-tested or validated in native Tauri; the repository disallows agent screen capture. Interaction checks use a simulated DOM, not a real browser or screen reader. Native layout, keyboard focus, zoom, assistive technology and desktop behavior still need hand review. The prototype uses memory only and never calls an agent, executes a command or schedules a real notification.

The selected logo still needs a vector production pass. The unused transparency experiment has visible haze and is labelled as a draft. Character art is not a rig, GLB or animation atlas. Existing app tests were not rerun because this change adds only local design artifacts and a standalone prototype.
