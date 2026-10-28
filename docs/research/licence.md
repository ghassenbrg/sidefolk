# Choosing a licence (for the founder, 2026-10-28)

Today LICENSE reserves every right (D17) while the repository is public: people can read the code but may
not build, use, change or contribute to it. That was meant to last until this choice is made. It is the
founder's call, with a lawyer before the public launch (docs/launch/CHECKLIST.md, item 1).

## What "stealing" can mean, and what stops each

| Worry | What stops it |
|---|---|
| Someone renames the app and sells it, or ships a look-alike called Sidefolk | **The brand**, not the code licence: the name, the logo and the companions (their names and art) kept out of the code licence and protected as trademarks and copyright |
| Someone puts the code inside a closed product | Copyleft (GPL) or a source-available licence (FSL, BUSL, PolyForm) |
| Someone sells or hosts a competing copy | Only a source-available licence (FSL, BUSL, PolyForm Shield). GPL lets anyone sell copies as long as they share the source |

## The options

| Licence | "Open source" (OSI)? | Can others sell a copy? | Closed forks? | Notes |
|---|---|---|---|---|
| MIT / Apache-2.0 | Yes | Yes | Yes | Most adoption, no protection beyond the brand |
| GPL-3.0 | Yes | Yes, with the source | No | Real open source. The Mac App Store is effectively closed to GPL apps (VLC was pulled in 2011); a Developer ID DMG, as Sidefolk ships, is fine |
| **FSL-1.1-ALv2** (Fair Source) | No: "source available" | Not for two years | Not for two years | Any use except a competing commercial product or service; each release becomes Apache-2.0 two years after it ships. Sentry made it in 2023; Liquibase and others use it |
| BUSL-1.1 | No | Not until a change date (up to 4 years) | No | Like FSL with more knobs and a longer wait |
| PolyForm Noncommercial / Shield | No | No (Noncommercial: nobody commercial at all) | No | Noncommercial also stops companies using it at work |
| All rights reserved (today) | No | No | No | Nobody may build it or contribute; or make the repository private and ship only the app |

## Recommendation

**FSL-1.1-ALv2 for the code, the brand kept apart, and a CLA for outside contributions.**
- Anyone can read it, build it, use it at home and at work, fix it and send changes. Nobody can sell or host
  a competing Sidefolk for two years after each release. After that each release becomes Apache-2.0, so the
  promise to open it up is real, just delayed. The founder can still sell Sidefolk, or a paid edition: a
  licence binds others, not the copyright holder.
- Say "source available" or "Fair Source" in public, never "open source": FSL isn't OSI-approved, and the
  open-source crowd will call that out.
- If being open source matters more than stopping a paid clone (community, packaging by others), choose
  **GPL-3.0 plus the brand protection** below instead.

## What to do with either choice

1. LICENSE: the licence text with the licensor's name (individual or company, CHECKLIST item 9), the README's
   licence section, and the GitHub licence field (SPDX `FSL-1.1-ALv2` or `GPL-3.0-only`).
2. A TRADEMARKS.md: "Sidefolk", the logo, and the companions' names and art aren't covered by the code
   licence; forks rename and draw their own. Register the name where it will sell (lawyer).
3. Contributions: a Contributor License Agreement (for example CLA Assistant on GitHub), so the founder can
   relicense or sell commercial licences later. A sign-off (DCO) alone doesn't give that right.
4. Third parties: GRDB, KeyboardShortcuts and LobeHub Icons are MIT and fit every option; THIRD_PARTY_NOTICES.md
   stays bundled.
5. The app's own terms of use (CHECKLIST item 8) are separate from the source licence and still needed.

Sources: [SPDX: FSL-1.1-ALv2](https://spdx.org/licenses/FSL-1.1-ALv2.html),
[Sentry: introducing the FSL](https://blog.sentry.io/introducing-the-functional-source-license-freedom-without-free-riding/),
[Liquibase on the FSL](https://www.liquibase.com/blog/liquibase-community-for-the-future-fsl),
[LibrePlanet: Apple and GPLv3](https://libreplanet.org/wiki/Apple).
