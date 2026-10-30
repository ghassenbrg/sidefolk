# Your own companions, community companions, and a place to get them

A brainstorm for the founder (2026-10-30), not a decision. Two asks: anyone can add a companion of their own,
or one someone else made (an extension could bring one); and Sidefolk ships only a few companions built in and
downloads the rest, so nobody carries models they never use.

*Update (2026-10-30): step 2 is built ahead of step 1 (D55).* The gallery lives in `sidefolk-addons` with Sidefolk's
own companions (Ember, Kiko, Nimbo, Folio) and nine extensions. Packs and the catalog are signed with the Developer
ID rather than a new Ed25519 key. Our 3D characters still carry code, so community 3D companions wait for step 1.

## Where things stand

- **2D, made by you (D43):** a folder with `species.json` and SVG parts in `<home>/companions/` or inside an
  extension, read strictly as data, checked to draw inside the window, listed under "Made by you". This already
  works, and it is the model to follow: nothing in a companion runs.
- **3D (D51):** each companion is a `characters/<id>.js` file plus a `.glb` model inside the app. The JS holds
  numbers (floor, frame, face layout, chains, poses) but also code (a GLSL `surface`, `stand()`, postures,
  each one's own trick). That is fine for companions we write; a pack from a stranger can't carry code.
- **Size:** `Resources/Companions3D` is 28 MB of the 43 MB DMG. Ember, Kiko, Nimbo and Folio are about 18 MB of
  that (models 2.7–5.7 MB each).

## 1. One format: a companion pack is data

A `.sfcompanion` (a zipped folder), the same for 2D and 3D, for ours and everyone's:

| File | What |
|---|---|
| `companion.json` | id (reverse DNS, `com.someone.otter`), name, author, version, licence, minimum Sidefolk, `looks: ["3d", "2d"]` |
| `model.glb` | 3D: rigged with our bone names (`hips spine chest head`, `arm.L` …, chains such as `ear.L.1`) |
| `character.json` | 3D as numbers: floor, pivot, frame, marks, shadow, face layout and colours, chains, how it stands, which shared postures, fidgets and moments it uses |
| `species.json`, `parts/` | 2D, as today |
| `portrait.png`, `preview.webp` | Settings still, a short loop for the gallery |

What replaces the code in today's character files:
- **Materials from presets** (plush, fur, plastic, paper, metal, glass visor) with tunable numbers, instead of
  GLSL. Our six already fall into these.
- **Postures and moments from the shared library** (sit, lie, sleep, doze, twirl, peek…) with a few numbers each.
  A pack can choose `sleep: "doze"` as Ember now does. Signature tricks such as Mochi's bunny hops stay for
  built-ins, unless we later add a keyframe format (poses at times, as data).
- **Our own six move to this format first**, so the format is proven before anyone else uses it.

## 2. Checking a pack

`sidefolk companion validate <folder>` runs the same checks the app runs before loading a pack (like `sidefolk ext
validate`):
- GLB at most 8 MB, about 100k triangles, 2K textures, no scripts or external URLs in it;
- the bones it needs, weights that sum to one, and a face region the face decal can find;
- it stays inside the window in every posture and move (rendered off screen, like `--check-companion` for 2D);
- portrait present, licence named, names and texts within limits.

## 3. Making one

- **For creators (soonest):** publish the pipeline we already use, the `sidefolk-3d-character` skill and
  `companions-3d/` (sheet → Meshy → Blender rig → character file), as a template repository with
  `sidefolk companion pack`. An agent such as Claude Code or Codex can follow it end to end, as it did for Folio.
- **For everyone, in Sidefolk (later):** "Make a companion": describe it or drop a drawing → a reference sheet
  (image generation) → a model (Meshy, on the person's own key, about 40 credits) → rigged from a **body
  template** (biped, floater, four-legged, blob), placing template bones on the model and computing weights the
  way `rigkit.py` does (by position, in code, without Blender on their Mac) → a face editor where they drag eyes,
  mouth and blush onto the portrait. Rigging is the hard part; templates keep it reliable. 2D data companions can
  come first, since they need no model.

## 4. Getting them: a gallery

Settings › Companion gains **Get more**: a gallery read from a signed catalog, with the same trust as updates (D46):
- **Catalog:** a static JSON file on GitHub (id, name, author, licence, size, version, SHA-256, preview, download
  address, review state), signed with an Ed25519 key whose public half is in the app. A link on a web page never
  installs anything.
- **Download on demand** to `<home>/companions/<id>/<version>/`: check size and SHA-256 against the catalog,
  validate, then it shows like any companion. Remove frees the space. Updates come with the app's daily look.
- **Built in:** Mochi (2D and 3D), Spark (2D and 3D), the robot and the folks: the app still works offline on
  first launch. **In the gallery:** Ember, Kiko, Nimbo, Folio and every community pack. That makes the app about
  18 MB smaller, and each extra companion costs only the person who picks it.
- **Extensions:** an extension's manifest can list companion packs (2D already works); they go through the same
  validation and show the extension's trust level (docs/research/extensions-catalog.md).

## 5. Community: trust and safety

- Packs are data, so the risk is content, not code: size limits, validation, and a person looking at each one.
- **Submitting:** a pull request to a public `sidefolk-companions` repository. CI validates the pack and renders a
  contact sheet (every feeling, move and posture) into the PR; we review it (quality, and no characters that
  belong to someone else), merge it, and the catalog updates.
- **After publishing:** a "Report" link per companion, and a withdrawn list in the catalog that turns a pack
  off with a notice (the person's choice falls back to Mochi).
- **Licences:** CC0 or CC BY, or the author's own terms shown before download. Paid companions are a later
  question (link out to the creator).

## 6. Where it lives: repositories

- **`sidefolk` (this repository) keeps** what changes with the app: the pack formats (`companion.json`,
  `character.json`, the extension manifest), the loader, `sidefolk companion validate` and `sidefolk ext validate`,
  the gallery in Settings, the built-in companions and the bundled extensions. A format change edits the loader,
  the validator and our own characters in one commit, tested together.
- **`sidefolk-addons` (one public repository, made with D55) holds** every add-on, Sidefolk's own and later the
  community's: `companions/` and `extensions/`, the signed catalog, and CI that builds and tests each pull request
  (the contact sheet comes with community packs). Built packs are published on its `gallery` release, and only
  sources stay in git (plain git for now, about 19 MB; Git LFS if it grows). Ember, Kiko, Nimbo and Folio are
  there, as the example packs.
- **Why it's apart from the app:**
  - Strangers' pull requests stay away from the repository that builds and signs the app.
  - The catalog updates without an app release.
  - `sidefolk/.git` is already 2.8 GB, mostly models and reference images.
  - Packs carry their own licences (CC0, CC BY).
- **Why it's one repository and not two:**
  - Companions and extensions share the signed catalog, release hosting and review process.
  - Their different trust is handled by separate CI jobs per folder and `CODEOWNERS`.
  - Extensions can split out later if they ever need their own reviewers.
- **`sidefolk-companion-template` (step 3)** is a GitHub template repository with the creator kit (the skill,
  the pipeline and `sidefolk companion pack`), so a creator can click "Use this template".
- **Nothing is created before it is needed:** step 1 happens entirely in this repository.

## 7. In what order

1. **Format:** `character.json` and material presets; our six converted; packs load from `<home>/companions/`
   (3D "Made by you"); `sidefolk companion validate`. Small, and it proves the format.
2. **Gallery:** the signed catalog, download, remove and update; Ember, Kiko, Nimbo and Folio move out of the
   app.
3. **Creator kit:** the template repository, `sidefolk companion pack`, the community repository with CI review.
4. **Make a companion in Sidefolk:** body templates, the face editor, and image generation and Meshy on the
   person's own keys.

## Questions for the founder

- Host packs on GitHub Releases (free, the same trust as updates) or on our own CDN (faster, costs money)?
- Should the four new companions move to the gallery now (smaller app) or stay built in until step 2 ships?
- How high is the review bar: anything that validates, or only packs that meet our art bar (a "Featured" row
  and an "All" tab)?
- Paid companions ever, or free only?
