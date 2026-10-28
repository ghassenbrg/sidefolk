# The extension library: a plan to review (2026-10-28)

The founder asked how people could browse a library of extensions, search it by category, and install or
remove what they want, while Sidefolk still ships a good set inside the app. This is the plan: where the code
lives, what a download is, how the app finds and trusts it, what the person sees, and the order to build it.
Nothing here is built. The ideas themselves are in [extension-ideas.md](extension-ideas.md) (70 of them, now
with a category each).

## Decisions for the founder

1. **A second public repository, `sidefolk-extensions`, for the library** (official and community extensions
   in one place, Raycast-style), separate from the app. *Recommended.* The name is yours.
2. **Its licence: MIT**, for the extensions and the Kit they're built on, whatever the app's licence becomes
   ([licence.md](licence.md)). *Recommended:* contributors need to know their code stays open; the app can stay FSL.
3. **Who may submit at first:** official extensions only, for the first release of the library; community
   pull requests from the second phase, once the review checklist has been used on our own. *Recommended.*
4. **Two secrets for the new repository** (only you can add them):
   - the Developer ID certificate and notary credentials the app's Release workflow already uses;
   - a new Ed25519 key that signs the library's index.
5. **Updates:** extensions update by themselves when the new version asks for nothing more. A version that
   wants more waits for the person's click. *Recommended.*
6. **Reviewed community extensions' tool descriptions reach the model**, as the built-ins' do (D39), because a
   reviewer read them as prompts and the index pins them. *Recommended*, with a security sign-off. (D24 keeps
   unreviewed ones out.)
7. **The first library set:** which approved ideas go in it (see "The bundled set and the library").
8. **Where the index lives:** GitHub Pages of the new repository now; your own domain once the name and domain
   are settled (CHECKLIST items 9 and 10). *Recommended.*
9. **Shipping on with instant commands:** an extension whose everyday tools work by instant commands (D50) and
   show the model one or two tools at most may ship on. A command-only tool costs no tokens. *Recommended:*
   add Little Log, Holidays & Days Off, Daily Delight and Gadget Batteries on, if approved.

## Summary

- **Two homes.**
  - The app repository keeps the app and, for now, the 13 built-ins.
  - A new public `sidefolk-extensions` repository (MIT) holds the Kit and every library extension, official and
    community, each in its own folder, added by pull request and reviewed.
  - Later the built-ins move there too, and the app pins one reviewed revision of it.
- **A download is a signed program.** Our CI builds every library extension from reviewed source:
  - it builds one universal program (Apple silicon and Intel);
  - it signs it with Sidefolk's Developer ID under the identifier `dev.sidefolk.ext.<id>`;
  - it notarizes it with Apple;
  - it publishes a `.zip` with its `.sha256` on GitHub Releases.

  No unsigned program comes from the library. Folders installed by hand stay as they are today, and Gatekeeper
  judges their programs.
- **Instant or smart, the author's choice** (D50). An extension's tools can carry whole-sentence commands with
  typed slots that run at once with no AI ("flip a coin", "a cup of flour in grams"), be seen by the model, or
  both. A command-only tool costs no tokens. The index shows which tools work instantly, Browse can filter by
  it, review checks the patterns, and authors get advice on when to choose which (section 8).
- **One signed index** (`index.json` plus its signature) lists everything: categories, tags, permissions,
  sizes, versions, checksums and a withdrawn list. The app fetches it with an ETag, sends nothing about the
  person, caches it, and checks its signature, serial number and expiry before believing a word.
- **In the app**, "Browse" sits beside "Installed" in Settings › Extensions.
  - It has categories, search, a "Works instantly" filter and a detail page per extension.
  - Install goes through the same preview sheet as today, after the download's checksum and signature are checked.
  - Uninstall asks about the extension's data.
  - The AI may say "there's an extension for that" with a button. Only the person's click installs.
- **Trust** comes in tiers:
  - Built in.
  - Official.
  - Community, reviewed and built by us.
  - Local, unreviewed.
  - MCP servers, unsandboxed.

  The sandbox doesn't change. A withdrawn version is switched off everywhere at the next index fetch.
- **Build order:**
  - Phase 1 is the smallest real library: the repository, its CI, the signed index, Browse, install, update,
    uninstall and the withdrawn list, launched with 8–10 official extensions, so Browse is never an empty shop.
  - Phase 2: AI suggestions and community submissions.
  - Phase 3: the built-ins move into the library repository.
  - Later: partner-signed extensions and loading tools on demand.

## 1. Where extensions live

### How others do it

| Store | Where the code lives | Who builds it | Review | What it gets right | What it gets wrong |
|---|---|---|---|---|---|
| **Raycast** | One public monorepo, `raycast/extensions`; each extension a folder | Raycast's store pipeline, from the merged source | Every new extension and every update is a pull request, reviewed by Raycast's community managers (first contact within a week); all source is open | One place to read every line; updates are reviewed too; authors don't host anything | A busy repository; review is the bottleneck; duplicates are refused, so the first author "owns" an idea |
| **Obsidian** | Each plugin in its author's own repository; one index file lists them (`community-plugins.json`) | The author; files come from the author's GitHub release | Automatic and human review at first submission; later releases aren't reviewed by the team | Easy to publish; scales with little staff | An update can change anything after review; plugins run with full rights |
| **Zed** | A registry repository, `zed-industries/extensions`, with each extension as a git submodule and an `extensions.toml` index | Zed's CI, which compiles to WebAssembly and packages | Pull request to add or bump a version; a licence check in CI (MIT, Apache and a few others) | Updates pass through a reviewed pull request; WebAssembly runs sandboxed without per-binary signing | Submodules are awkward; WebAssembly limits what an extension can do |
| **VS Code** | Authors publish packages to Microsoft's Marketplace | The author | Malware scans, publisher verification by domain, signing by the Marketplace, a block list that uninstalls bad extensions | Signed packages, scanning, remote removal | Extensions run with full rights; 2025 research showed the "verified" badge only proves a domain; malicious extensions keep turning up |
| **Alfred** | Authors' own files; the Gallery is curated | The author | Human review that a workflow works, isn't a duplicate, carries all its code and doesn't download more | Small and curated, so quality is high | Slow to grow; no sandbox |
| **Homebrew** | `homebrew-core` (reviewed pull requests) and anyone's own "tap" repository | BrewTestBot builds "bottles" in CI for core | Every core change is a pull request; taps are unreviewed | Reproducible builds by CI; taps let anyone publish without asking | Taps are trust-on-first-use; a tap can run anything at install |

### What fits Sidefolk

Our extensions are **native programs** (D39), so a download is code, and macOS wants code signed and notarized.
That rules out Obsidian's model (authors hosting their own binaries) for anything we list. It points to
Raycast's and Homebrew-core's: reviewed source, built and signed by our CI.

**Recommendation: a separate public monorepo, `sidefolk-extensions`, for every library extension, official and
community, with the Kit in it.**

- **CI time.** The app's CI builds 13 extension programs today. Seventy more would add many minutes to every
  app pull request. In their own repository, CI builds only the folders a pull request touches.
- **Versions of their own.** An extension fix ships the same day, without an app release. The app and an
  extension only share the stdio protocol (JSON-RPC, MCP-shaped) and the manifest's `"sidefolk": ">=x.y"`, so
  they needn't move together.
- **Contributors.** Outsiders can send an extension without touching, or signing a CLA for, the app's code.
- **Review.** One place, one checklist. `CODEOWNERS` gives each extension's author review rights on their
  folder; only Sidefolk's maintainers can merge.
- **Licences.** The library repository can be MIT while the app's licence is still open (FSL is recommended in
  licence.md). Mixing both in one repository confuses contributors.
- **The Kit.** It moves into the library repository as a small Swift package product (MIT). The app depends on
  one pinned revision of it (`Package.resolved`, reviewed bumps; T23 already says so).

**Alternatives weighed:**
- *Everything in the app's `extensions/` folder.* It's simplest today, but CI slows, every fix needs an app
  release, and community contributions fall under the app's licence.
- *Official in the app repository, community in a second one.* That means two pipelines and two review
  habits, and an extension that changes hands has to move. Raycast keeps its own extensions in the same public
  repository as everyone's; so should we.
- *Each author's own repository plus an index (Obsidian, Zed's submodules).* Updates either skip review
  (Obsidian) or need submodule bumps (Zed), and we'd still have to build and sign their code.

**Where the 13 built-ins go.** They stay in the app repository for phase 1: they work, they're tested by the
app's CI and they're signed inside the app. In phase 3 their source moves to the library repository. The app
then builds its bundled set from one pinned library revision, so all extension code has one home and one review.

## 2. What a downloadable extension is

- **Built only from reviewed source.** A pull request carries Swift source on the Kit, a manifest, an icon and
  tests. It never carries a binary.
- **Its commands come with it.** Per tool, the manifest says:
  - which whole sentences run it instantly, with typed slots (a number, a unit, a place, a date, a file, a
    name);
  - whether the model sees the tool at all (D50).

  These are part of what is reviewed, pinned at install (like tool descriptions, T14), shown on the install
  preview, and listed in the index. A command still runs through `ToolExecutor`: Guard, approvals and audit
  apply as if the AI had called it, so a risky tool still asks. Core intents win over any extension's
  commands; when two extensions match the same sentence, it goes to the AI.
- **Built by CI, after merge:**
  - **Build:** `swift build -c release --arch arm64 --arch x86_64 --product ext-<folder>`, giving one universal
    program of about 250 KB (built-ins measure 236–304 KB on Apple silicon today).
  - **Sign:** `codesign --options runtime --timestamp --identifier dev.sidefolk.ext.<id>` with Sidefolk's
    Developer ID, using the retrying `sign()` from release.sh.
  - **Notarize:** with `notarytool`, as a zip. A bare program can't be stapled, so Apple's check happens online,
    when the app verifies it at install, and the app is online then anyway.
- **The package:** `<folder>-<version>.zip` (made with `ditto -c -k --keepParent`). It holds the extension's
  folder: `sidefolk-extension.json`, `icon.pdf` or `icon.png`, `bin/ext-<folder>` and any data files. Beside it
  sits `<folder>-<version>.zip.sha256`.
- **The minimum versions:** the manifest's `"sidefolk": ">=0.2"` gives the oldest app that can run it. The
  index adds `macos` and `archs`.
- **Hosting:** GitHub Releases of the library repository, one release per extension version, tagged
  `<folder>@<version>`. It's free, sits behind a CDN, and has the same hosts the updater already accepts
  (`github.com`, `*.githubusercontent.com`, T31).
- **What the app checks, in order** (the updater's pattern, T31):
  1. Size and SHA-256 against the signed index.
  2. Unzip into a staging folder with today's installer rules: no links, no setuid bits, no special files,
     nothing outside the folder.
  3. The program's signature must meet a requirement built from **the running app's own signature**: anchored
     at Apple, a Developer ID leaf, the same Team ID, the identifier `dev.sidefolk.ext.<id>`, and notarized.
     It's checked strictly, across both architectures.
  4. The manifest must be valid, and its permissions must equal what the index says. If they differ, the
     install is refused: the index or the package has been tampered with.
  5. Then the normal install preview opens. On the person's click, the folder is installed and pinned as
     today, with a new origin, `library`.
- **Quarantine:** Sidefolk marks everything it writes (`LSFileQuarantineEnabled`), and Gatekeeper held unmarked-
  signature programs at `_dyld_start` (D39's addendum). A library program drops its mark **after** the checks
  above, as built-ins and the updater do: Sidefolk has made Gatekeeper's judgement itself, against a stricter
  requirement.

**Community extensions we didn't build:**
- *Refused from the library* (recommended): the library lists only what our CI built from reviewed source.
- *Install from Folder stays* for developers. Scripts (`sh`, Python, Node) run as today. A program the
  developer compiled on their own Mac isn't quarantined, so it runs. A downloaded unsigned program keeps its
  mark, and macOS refuses it; the sheet says why.
- *Partners* (phase 4): a company with its own Developer ID signs and notarizes its package; the index pins
  that company's Team ID; we still review it. Labelled "By <company>, reviewed by Sidefolk".
- *Built from source on the person's Mac*: it needs Xcode or the Command Line Tools, which most people don't
  have. Rejected, except as a developer option later.
- *WebAssembly* (Zed's way): community code in a portable sandboxed format, with no signing per program.
  Attractive at a larger scale, but it's a new runtime to embed and a new Kit. Revisit if review can't keep up.

## 3. The catalog index

One file lists the whole library: `index.json`, with its signature in `index.json.sig`.

```json
{
  "format": 1,
  "serial": 42,
  "generated": "2026-11-10T09:00:00Z",
  "expires": "2026-12-10T09:00:00Z",
  "categories": [{ "id": "home-family", "title": "Home & Family", "symbol": "house" }],
  "featured": ["dev.sidefolk.plant-pal", "dev.sidefolk.little-log"],
  "extensions": [{
    "id": "dev.sidefolk.plant-pal",
    "name": "Plant Pal",
    "summary": "Your plants, when you last watered each, and a note when one is thirsty.",
    "category": "home-family",
    "tags": ["plants", "home", "reminders"],
    "audience": ["everyone"],
    "author": { "name": "Sidefolk", "github": "sidefolk" },
    "trust": "official",
    "license": "MIT",
    "source": "https://github.com/<owner>/sidefolk-extensions/tree/main/plant-pal",
    "icon": { "url": "https://…/plant-pal@1.1.0/icon.png", "sha256": "…" },
    "examples": ["Who needs water today?", "I watered the fern."],
    "data_sources": [],
    "version": {
      "version": "1.1.0", "released": "2026-11-09", "notes": "Cacti need less water in winter.",
      "sidefolk": ">=0.2", "macos": ">=15.0", "archs": ["arm64", "x86_64"],
      "url": "https://github.com/<owner>/sidefolk-extensions/releases/download/plant-pal@1.1.0/plant-pal-1.1.0.zip",
      "size": 251904, "sha256": "…",
      "team_id": "2XQJWQBD4W",
      "permissions": { "network": false, "files": { "read": [], "write": [] }, "exec": [], "media": false },
      "tools": [
        { "name": "watered", "title": "Mark a plant watered", "risk": "low", "hash": "…",
          "model": false, "commands": ["I watered the {plant}", "watered the {plant}"] },
        { "name": "thirsty_today", "title": "Plants that need water", "risk": "low", "hash": "…",
          "model": true, "commands": ["who needs water today", "which plants are thirsty"] },
        { "name": "add_plant", "title": "Add a plant", "risk": "low", "hash": "…", "model": true, "commands": [] }
      ],
      "works": "both",
      "model_tokens": 190,
      "watchers": [{ "name": "plants_thirsty", "title": "Plants thirsty" }]
    }
  }],
  "withdrawn": [{ "id": "dev.sidefolk.example", "versions": ["1.0.0"], "reason": "It sent more than it said.", "action": "disable" }]
}
```

- **Instant or AI, per tool.**
  - `model` says whether the model sees the tool.
  - `commands` lists its instant sentences, as the manifest gives them; the reviewer sees exactly these.
  - `works` sums the extension up as `instant` (every tool is command-only), `both` or `ai`, for the badge and
    the filter.
  - `model_tokens` is CI's measure of what switching it on adds to every request (zero for `instant`), so the
    detail page can say "Adds about 190 words' worth to each request" honestly.
- **Only the latest version** is listed per extension. The app never offers a lower version than the one
  installed (no downgrades), except a reinstall the person asks for.
- **About the size:** roughly 2 KB an entry, so 70 extensions come to about 140 KB, or about 25 KB compressed.
- **Signed with Ed25519.** CI signs it with a key kept in the library repository's secrets. The public keys
  are compiled into the app: a current one and a spare, for rotating.
  - `serial` only goes up, so the app refuses an index older than the one it has.
  - `expires` (30 days) stops someone replaying an old index forever to hide a withdrawal: a "freeze" attack.
  - The signature covers the bytes as published.
- **Hosting:** GitHub Pages of the library repository now (it serves ETags and HTTPS), and the founder's own
  domain later. The URL is fixed in the app; its redirects must stay on that host.
- **Fetching:**
  - **When:** when the person opens Browse; once a day while any library extension is installed (for updates
    and withdrawals); and at the AI's request, only from the cache (below).
  - **How:** `If-None-Match` with the last ETag, an ephemeral session with no cookies or credentials, and a
    15-second timeout.
  - **What it sends:** only `User-Agent: Sidefolk/<version>`. Never what's installed or who's asking.
  - **Downloads** do tell GitHub that this address fetched that package, as any download does. The privacy
    page says so.
- **Offline:** the last good index and its signature are kept in Application Support. Browse shows it with "As
  of 3 November". Installing needs the internet.
- **Where it sits with D47's rules:** this is the app's own request, like the updater (T31), not the AI's
  tool, so D47's card rules don't apply to it. Settings › Extensions › Library gets one switch, "Check the
  library for updates" (on), next to the updater's.
- **Icons and screenshots** are fetched only while Browse is open, checked against their hashes, cached, and
  only PNG (never SVG: T13).

**Alternatives weighed:**
- *No index signature, trusting HTTPS and the packages' code signatures.* A stolen GitHub account could still
  delete a withdrawal or point at an older, vulnerable version. The signature is cheap.
- *Signing the index with the Developer ID certificate* (CMS). It needs no new secret, but it uses a
  code-signing identity for data, which Apple's terms don't clearly allow.
- *TUF* (The Update Framework): the thorough answer to every repository attack, and too much machinery for one
  index file. Its key ideas are borrowed: a serial, an expiry and key rotation.

## 4. In the app

Settings › Extensions already has "Installed", with search and All / On / Off (`ExtensionListQuery`,
`ExtensionsSettingsView`). Beside it:

- **Browse** (shown only once the index has entries: no empty shop).
  - **The top:** search and a category list (section 7), with Featured on top.
  - **The search** reuses `ExtensionListQuery`'s folding and every-word rule over each entry's name, summary,
    tags, category, tool titles, commands, examples and author. An index entry becomes an
    `ExtensionListEntry` like an installed row. A filter shows All / Not installed / Installed, plus a
    **Works instantly** filter for extensions with instant commands.
  - **Rows** look like Installed's one-line rows: icon, name, summary, and a trust chip ("Official", or "By
    <author>, reviewed") plus Install or Installed. Rows also carry a small **Instant** chip (a bolt) when some
    tools need no AI.
- **A detail page** for each extension: what it does, examples to try, its tools and watchers by title, what it
  may do (the same plain lines `PermissionSummary` gives today), where its data comes from and on what terms,
  size, version, what's new, the author, the source link and the licence.
  - "**Say it, no AI needed:**" lists the instant sentences.
  - "**For the AI:**" names the tools the model sees and the cost of switching it on ("about 190 tokens a
    request", or "nothing" for a command-only extension).
  - Installed's rows show the same two lines under Details.
- **Install…** downloads, checks (section 2), then opens the **existing install preview sheet**, which already
  shows permissions, warnings and the sandbox, and arms after 800 ms. Nothing installs without that click. The
  new extension's tools are offered from the person's next request, as today.
- **Updates:**
  - *Ask for nothing more:* with "Update extensions automatically" on (default), a version that asks for no
    more permissions installs by itself, with a quiet line in Activity. Changed tool descriptions are still
    held until approved (T14).
  - *Ask for more:* the person sees the preview with the difference, and the old version keeps running until
    they choose.
  - *Manual:* "Update" appears on the row and in Browse.
- **Uninstall:**
  - It frees the program (about 250 KB) and, if the person chooses, its data. The sheet asks: "Also delete
    what Plant Pal kept (12 KB)?", with Delete chosen.
  - Keeping it means a reinstall finds it again; today's uninstall deletes the data folder, so that becomes a
    choice.
  - Space is honestly small for most extensions. Data (word lists, rules books) can be a few MB, and the size
    is shown.
- **Built-ins** can't be removed: their files are inside the signed app. They can be switched off, which takes
  their tools away from the model, and "Clear its data" empties what they kept.
- **The withdrawn list:** at the next index fetch, a withdrawn version is switched off with a notice giving the
  reason ("Withdrawn by Sidefolk: …"). Its data is kept, and the person may uninstall it. A withdrawn version
  can't be installed or switched back on.
- **What the AI may do:**
  - A tool `extensions.find(query)` searches the **cached** index only (no network from the AI) and returns
    names and summaries as **untrusted** text.
  - The AI can then show a card: "There's an extension for that: Plant Pal (Official). Look at it…". The
    button opens the detail page.
  - The AI never installs, enables or updates on its own. The tool refuses other agents and routines, as the
    builder tools do (D39).
  - Today's "switched off in Settings" line for built-ins stays as it is.
- **Install from a file:** dropping a downloaded `.zip` from the library on Settings goes through the same
  checks against the cached index, for people who download in a browser. *Phase 2.*

## 5. Trust and security

| Tier | Who | Built by | Sandbox | Descriptions reach the model | Label |
|---|---|---|---|---|---|
| Built in | Sidefolk, inside the app | The app's release | Yes | Yes (D39) | "Comes with Sidefolk" |
| Official | Sidefolk, in the library | Library CI | Yes | Yes | "Official" |
| Community | Anyone, reviewed by Sidefolk | Library CI | Yes | Yes, once reviewed (decision 6) | "By <author>, reviewed by Sidefolk" |
| Partner (phase 4) | A company with its own Developer ID, reviewed | The company | Yes | Yes, once reviewed | "By <company>, reviewed by Sidefolk" |
| Local | A folder, or a draft Sidefolk wrote | Whoever | Yes | No (D24) | "Not reviewed" / "Written for you" |
| MCP server | A command the person added | — | **No** | No | "Runs with your full permissions" |

- **The sandbox stays as it is.** Review adds to it and never replaces it: a reviewed extension still gets
  only what its manifest asks for, and the install sheet still says it in plain words.
- **What a reviewer checks** (a checklist in the library's CONTRIBUTING):
  1. **Least privilege.** The internet only when needed. Folders named per call, never fixed ones without a
     reason. A minimal `exec` list, never "can run anything". `media` only for picture code.
  2. **All the code, read.** It's Swift on the Kit, usually a few hundred lines. No obfuscation, no binaries or
     generated blobs, no `dlopen`, no Apple Events, no spawning programs outside `exec`.
  3. **Dependencies.** The Kit, plus Swift packages on an allow-list, pinned in `Package.resolved`. No build
     plugins and no binary targets (T23).
  4. **Network honesty.** It reaches only the hosts its README names. This gets enforceable once the per-host
     allow-list exists.
  5. **Descriptions read as prompts.** No instructions to the model ("always call this first"), no claims
     beyond what it does, risk levels that are true. These words will reach the model.
  6. **Commands.**
     - Whole sentences with typed slots, never catch-alls ("{text}" alone, "help", "stop", "next", a bare
       number).
     - Nothing that takes a core intent's sentences.
     - No collisions with popular library extensions. CI lists overlaps against core and the whole index on the
       pull request.
     - 2–6 phrasings per tool, the ones people say.
     - Tools that send data out, write or delete get commands only when Guard's card still asks.
     - A command result reads well with no AI wording around it.
  7. **Data sources.** Their terms allow an app like Sidefolk (commercial use if Sidefolk is paid), and
     attribution is shown where it's required (extension-ideas.md lists the doubtful ones).
  8. **Privacy note.** It's accurate: what leaves the Mac, and to whom.
  9. **Behaviour.** Watchers trigger on change, not on level. Results are small. Times stay within limits.
     Tests pass in the sandbox, including each command's sentences.
  10. **Fit.** Not a duplicate of a built-in or core feature. A clear name, an icon, two or more examples.
  11. **Licence.** MIT (or Apache 2.0), in the folder.
- **Pinning:** library programs must carry our Team ID and the identifier `dev.sidefolk.ext.<id>`. The
  requirement is built from the running app's signature, never from the download. The index's public keys
  are compiled in.
- **Withdrawal:** a signed `withdrawn` list in the index, enforced at every fetch. The 30-day expiry means a
  person who blocks the index can't keep a bad version alive for long without the app noticing: an index that
  can't be refreshed after it expires shows a warning on library extensions.
- **Supply-chain risks and their answers:**
  - *A contributor's account is stolen and pushes a bad update.* Every update is a pull request a Sidefolk
    maintainer reviews. Authors can't merge. CI builds only merged commits.
  - *A maintainer's account is stolen.* The organisation requires two-factor sign-in. `main` is protected.
    Releases run in a protected GitHub environment that needs a second approval, once there are two
    maintainers. The index key and Developer ID never leave CI secrets.
  - *A malicious pull request tries to steal secrets.* Pull-request workflows get no secrets. Signing runs only
    on `push` to `main`, in its own job. Never `pull_request_target` with the pull request's code.
  - *Dependency poisoning.* An allow-list, pinned versions, reviewed bumps, no plugins.
  - *An index swapped, frozen or rolled back.* The signature, the serial and the expiry.
  - *Typosquatting and look-alikes.* Review, and unique names.
  - *Commands that hijack sentences.* An extension claiming "check my bank" or a core phrase to catch what
    people say. Patterns are reviewed and pinned (a change is held like a changed tool). Core intents always
    win. Collisions go to the AI rather than to either extension.
  - *A data source turning hostile.* Results are already untrusted (T2). The sandbox limits what the program
    can do. The withdrawal list exists for the rest.
  - *A stolen Developer ID key.* It threatens every Developer ID app; Apple's revocation answers it, as for
    the updater (T31).

## 6. The bundled set and the library

**What decides.** Inside the app goes what most people want on day one and what the app's own promise leans
on. Everything else goes to the library.
- Bundling costs almost no space: about 250 KB per program, 3.3 MB for all 13 today.
- The real costs of bundling are tied releases and one more thing to test with every app release.
- The cost that matters to people is **tokens**, and switching off already removes it: only extensions that
  are on reach the model, and the ones that are off show as one line each.

**Instant commands change "on".** Being on has two costs now, and they're different:
- **Tokens:** only for tools the model sees. A command-only tool costs nothing; a "Both" extension can show the
  model one or two tools and leave the rest to commands.
- **Sentences:** an extension that's on claims its commands' sentences. Core wins and collisions go to the AI,
  but many extensions on means more sentences going to the AI instead of being answered instantly.

So the rule becomes: on by default when the extension is everyday, its model-visible tools are few (about
200 tokens at most), and its commands are distinctive. That allows more on than before:
- Daily Delight and Gadget Batteries cost nothing.
- Little Log and Holidays cost one or two tools each.

It also suggests trimming today's: Calculator, Currency, World Clock and Playtime could answer their everyday
sentences instantly and show the model fewer tools, once D50 lands.

**Recommendation:**

| Group | Extensions | Why |
|---|---|---|
| Inside the app, **on** | World Clock, Weather, System Vitals, Calculator, Currency, Playtime, Images, Git; and, if approved, Little Log (E23), Holidays & Days Off (E4), Daily Delight (E50) and Gadget Batteries (E10) | Everyday questions; few model-visible tools, the rest instant |
| Inside the app, **off** | PDF Tools, QR Codes, Archives, Dev Toolbox, Feeds | Already shipped; one switch away works offline. They move to the library in phase 3, with nothing breaking (below) |
| **Library** | Every other approved idea (extension-ideas.md) | New versions without app releases; people choose |

**How a bundled extension moves to the library without breaking anyone's setup:**
- It keeps its id, so its on/off state, data and pins stay.
- The app's `catalog.json` gains a `"moved"` list naming it. The app no longer reinstalls or replaces it from
  its Resources, and changes the installed record's origin from `bundled` to `library`.
- From then on its updates come from the index, and it can be uninstalled.
- A person who never had it finds it in Browse. A person who switched it off keeps it off.
- Its tool names (`ext.<folder>.<tool>`) don't change, so watchers and approvals that name them keep working.

**Token cost, once more:** a bigger library adds nothing to any request. Only extensions that are on reach
the model. The biggest unlock for more of them on at once is **tools loaded on demand**: the model sees one
line per extension and asks for its tools when a request needs them (extension-ideas.md, "Capabilities").

## 7. Categories

Fourteen categories, each with a SF Symbol for Browse. Every extension, the 13 built-ins included, has one.
extension-ideas.md's summary now has a Category column.

| Category | Built-ins | Ideas |
|---|---|---|
| **Weather & Sky** | Weather | E1 Outside, E2 Sky & Space, E3 Earthquakes |
| **Time & Travel** | World Clock | E4 Holidays & Days Off, E5 Trip Kit, E61 Calendar Peek |
| **Your Mac & Safety** | System Vitals | E6 Is This Link Safe?, E7 Network Doctor, E8 Mac Doctor, E9 Space Finder, E10 Gadget Batteries, E63 Shortcuts Runner |
| **Files & Documents** | PDF Tools, Archives | E40 Doc Converter |
| **Photos & Design** | Images, QR Codes | E43 Color Studio, E45 Photo Sorter, E46 Video & Audio Kit, E70 Photo Memories |
| **Money & Numbers** | Calculator, Currency | E35 Pocket Ledger, E36 Money Math |
| **Work & Business** | — | E37 Time Tracker, E38 Invoice Maker, E39 Spreadsheet Helper, E42 Uptime & Certificates |
| **Home & Family** | — | E11 Kitchen, E12 Food Facts, E13 Pantry, E14 Plant Pal, E15 Upkeep, E16 Chores, E17 Lent & Borrowed, E18 Birthday Book, E19 Baby Log, E64 Smart Home, E65 Parcels |
| **Learning & Kids** | — | E20 Story Keeper, E21 Little Learners, E22 Secret Codes, E28 Curious, E30 Scholar, E31 Flashcards, E34 Student Desk |
| **Reading & Writing** | Feeds | E29 Wordsmith, E32 Bookshelf, E33 Read Later, E41 Writer's Desk, E47 Name Forge |
| **Wellbeing & Focus** | — | E23 Little Log, E24 Habits, E25 Mood Diary, E26 Now & Next, E27 Workout Log, E66 Ambient Sounds |
| **Fun & Games** | Playtime | E48 Word Games, E49 Trivia Night, E50 Daily Delight, E51 Tabletop Companion, E52 Game Deals, E67 Board Games, E68 Companion Care |
| **Music, TV & Sports** | — | E44 Chords & Scales, E53 TV Night, E54 New Music, E62 Music Control, E69 Scores & Markets |
| **Developer Tools** | Git, Dev Toolbox | E55 Ports & Processes, E56 Package Watch, E57 API Poke, E58 Developer Disk Cleanup, E59 SQLite Explorer, E60 GitHub Public |

Tags carry the rest ("offline", "kids", "ADHD", "no account"). Audience is a short fixed list (everyone,
developers, students, parents, creators, small business) that Browse can filter by later.

## 8. Instant, smart, or both: advice for authors

Goes into CONTRIBUTING and `skills/sidefolk-extension/SKILL.md`. The founder's test: flipping a coin or a
small sum shouldn't wait a few seconds for an AI.

**Make a tool instant (commands) when:**
- people say it in a few predictable sentences ("who needs water today?", "AirPods battery", "a cup of flour
  in grams");
- the slots are typed things: a number, a unit, a date, a place, a name, a file the person dropped or named;
- the answer is exact and needs no judgement: a lookup, a conversion, a log entry, a game move;
- speed is the point: games, quick logs at 3 a.m., checks before a meeting.

**Let the model see it (smart) when:**
- the input is free-form: a pasted recipe, an email, a messy CSV, "something calm";
- it needs judgement, a summary, or a choice between options;
- it chains with other tools ("plan my trip": Weather, Currency, Trip Kit);
- it depends on the conversation ("add that to my list", "the second one").

**Choose both** (most tools): commands for the three to six common sentences, and the model for every other
wording. The person gets speed when they say it plainly and help when they don't.

**Keep a tool away from the model** (command-only) when its sentences are predictable and nothing would chain
it: it then costs no tokens at all. Don't, if people will phrase it in many ways, or the AI often needs it.
When unsure, show the model one summary tool and keep the rest instant.

**Never:**
- a catch-all pattern ("{anything}"), a bare word ("stop", "next", "help") or a bare number;
- a sentence a core intent already answers;
- an instant command that sends data out, writes or deletes without Guard's card still asking.

**Write instant results for people, not for a model:** a whole, friendly sentence ("Yes, at 8:12.") and a card
when it helps, since no AI will rephrase them.

**Languages:** commands are in English, like the core parser (D50 may add others). The model-visible path
serves every language, which is one more reason most tools should be "Both".

Each of the 70 ideas now says which of its tools should be instant, smart or both (extension-ideas.md, the
"Works" column and each idea's "Instant or AI" line):
- 62 are both;
- 5 are instant only: Gadget Batteries, Daily Delight, Ambient Sounds, Board Games, Companion Care;
- 3 are AI only: Story Keeper, Spreadsheet Helper, Photo Sorter.

## 9. The plan, in phases

### Phase 0: decide (this document)
The founder's eight decisions, the approved ideas, and the first library set.

### Phase 1: the smallest real library (about 3 weeks)
The library repository (M, about a week):
- `sidefolk-extensions` (MIT): the Kit moved there as a package product; a template extension; CONTRIBUTING
  with the review checklist; `CODEOWNERS`.
- CI on pull requests (no secrets), checking the changed extensions:
  - a build for both architectures, and their tests;
  - the manifest validator (the `sidefolk` command line from a pinned app version);
  - a start in the sandbox with nothing granted, to list the tools;
  - forbidden-API lint, and size and licence checks;
  - a command check: each pattern parses, is no catch-all, and its overlaps with core intents and every other
    extension in the index are listed;
  - a comment for the reviewer with the generated index entry, its plain permission lines, its commands and
    `model_tokens`.
- CI on merge (secrets, protected environment): build, sign, notarize, release `<folder>@<version>` with the
  zip and `.sha256`, regenerate `index.json`, sign it, publish to Pages. A nightly job re-checks every URL and
  hash in the index.

The app (L, about two weeks):
- Index fetch, signature, serial and expiry checks, cache, ETag.
- Download and verification (checksum, unzip rules, the signature requirement from the running app,
  permissions equal to the index).
- The `library` origin.
- Browse (categories, search through `ExtensionListQuery`, detail page), Install through the preview sheet,
  automatic and manual updates, uninstall with the data choice, the withdrawn list.
- Settings switches, tests with fixtures, and no network in tests.
- The app depends on the Kit from the library repository at a pinned revision.

Content (S–M each): 8–10 official extensions from the approved ideas, built and reviewed like any
contribution, so Browse opens full.

*Real, not fake:* Browse appears only when a signed index with entries is there.

### Phase 2: AI suggestions and community (about 2 weeks)
- `extensions.find` and the suggestion card.
- Install from a downloaded `.zip`.
- Example requests and screenshots on detail pages.
- Community pull requests open, with the checklist used on our own extensions first, and a second
  maintainer for releases if possible.

### Phase 3: one home for extension code (about 1 week)
- The 13 built-ins' source moves to the library repository. The app's release builds its bundled set from the
  pinned library revision and signs it inside the app, as today.
- PDF Tools, QR Codes, Archives, Dev Toolbox and Feeds move to the library with the `"moved"` list.
- Platform pieces the library needs most next: secrets for extensions, and the per-host network allow-list
  (it lets review point 4 be enforced, and makes the install sheet say "can reach api.tvmaze.com").

### Phase 4: later
- Partner-signed extensions, with their Team IDs pinned in the index.
- Tools loaded on demand.
- WebAssembly, if review can't keep up.
- Ratings or install counts only if they can be had without tracking people. Until then, a hand-picked
  Featured list.

### Who does what in CI

| Where | When | What | Secrets |
|---|---|---|---|
| Library repository | Every pull request | Build changed extensions, tests, validator, sandbox start, lint, size and licence, command overlaps, index-entry comment | None |
| Library repository | Merge to `main` (protected environment) | Sign, notarize, release, index, signature, Pages | Developer ID certificate and password, notary credentials, index key |
| Library repository | Nightly | Every URL and hash in the published index still matches | None |
| App repository | Every pull request | Index parsing and verification against fixtures; the Kit pin; the bundled set's tests | None |
| App repository | Release | Embeds the index public keys; (phase 3) builds the bundled set from the pinned library revision | As today |
| The founder | Once | Creates the repository, adds the secrets, turns on two-factor and branch protection, names the reviewers | — |

Sources: [Raycast: publish an extension](https://developers.raycast.com/basics/publish-an-extension),
[Raycast: prepare an extension for the Store](https://developers.raycast.com/basics/prepare-an-extension-for-store),
[Obsidian: submit your plugin](https://docs.obsidian.md/Plugins/Releasing/Submit+your+plugin),
[Obsidian community directory](https://obsidian.md/help/community-directory),
[Zed: publishing guide](https://zed.dev/docs/extensions/publishing/publishing-guide.md),
[VS Code: extension runtime security](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security),
[Microsoft: security and trust in the Visual Studio Marketplace](https://developer.microsoft.com/blog/security-and-trust-in-visual-studio-marketplace/),
[OX Security on the "verified" badge](https://www.ox.security/blog/can-you-trust-that-verified-symbol-exploiting-ide-extensions-is-easier-than-it-should-be/),
[Alfred: how to submit a workflow](https://alfred.app/submit/).
