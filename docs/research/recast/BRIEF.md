# File conversion for Sidefolk: decision brief

> The pictures this names are kept out of the repository, in `sandbox/formatic-research/` on the founder's Mac. The icon is in `icon/` here.

2026-11-03. Name: **Formatic**, with its icon, approved by the founder (section 7). It replaces the working name Recast. This is analysis, not an approved design. Nothing
is implemented. The earlier work in `Sandbox Luna/File Converter Extension` was not used, at the founder's request.

## 1. Recommendation

Build a Mac-native converter on Apple's own frameworks. Do not port Filee's engines or its donut. Take Filee's
knowledge and small pieces of its MIT code, and make Sidefolk's companion the way in.

- **Why people would use it:** drop a file on the companion, pick what you need, and get the result beside the original.
- **Its own identity:** three things Filee can't easily copy, in section 3.
- **The cost:** the extension is the smaller job. Most of the work is general app abilities: of six gaps, one is mostly solved on main, one is partly solved and four are open (section 5).
- **The first version:** no third-party conversion engine, so no licence obligations beyond notices for any code we port.
  FFmpeg is a later, separate decision.

## 2. What Filee teaches

Demand is real: 20,774 stars since 2026-09-29 (GitHub API, today). Its idea is that no window opens, and the formats
appear where you already are. The Mac field is crowded, though (Morpholder, a FileConverter menu bar app, Convertible,
FileShift, others). A long format list won't set us apart, and Filee's 270 formats aren't the thing to chase.

**Worth copying**

| What | Where in Filee | Why |
|---|---|---|
| Only show formats that fit the file | Formats and routes | The core of "easy" |
| Routes with several steps | `Filee.Core/Conversion/RoutePlanner.cs`, 258 lines | New engines unlock routes without other code changing |
| Refusing rather than producing a broken file | `docs/ENGINES.md`, complex scripts | Its renderer breaks Arabic and Indic text, so it refuses. Sidefolk ships in Arabic, so we need this rule |
| Its record of real-world edge cases | `CHANGELOG.md`, `docs/ENGINES.md`, tests | Test ideas to reuse: aliases, sidecar files, animated images |

**Not worth copying**

- **The donut.** It needs a global input hook and macOS Accessibility (`Filee.Platform.MacOS`, SharpHook). An extension
  can now draw its own framed surfaces (D99), but not a menu that follows the cursor across other apps. Sidefolk already has what the donut works hard to create: a target that is always
  on screen.
- **The engine downloader.** A converter that holds `network` loses section 3's strongest point.
- **The long tail** (HWP is 14,846 of its 72,996 engine lines; CAD, geospatial, e-books). Add only on real demand.

## 3. Where its identity comes from

These come from what the product does, not from decoration.

1. **The companion is the converter's front door.** Nothing to open, no shortcut to hold, no Accessibility grant.
2. **Outcomes first, formats second.** People want "small enough to email", "opens on any PC" or "keeps transparency"
   more often than they want "JPEG 2000". The first choices are outcomes for that file, and every format is one step away.
   It also works in words, with no AI: "make this smaller", "turn this into a PDF" (commands, D50).
3. **It tells you what changed, and it can prove the privacy.**
   - *Before:* a plain line such as "Transparent areas become white."
   - *After:* a receipt such as "1.1 MB, 74% smaller, beside the original", with Open, Show and Undo.
   - *Privacy:* with no `network` in the manifest, the sandbox blocks the internet, and the install sheet lists no internet access.
     Filee can only promise that.

Other agents get this too: Claude Code can convert through MCP, under Guard and the audit trail.

## 4. Interaction model

| Option | Verdict |
|---|---|
| **A. Drop on the companion, answer in the Sidecard, Home page for history and defaults** | **Recommended.** Uses what makes Sidefolk different |
| B. Home page as a workspace with a drop zone | Conventional, and means opening a window first. Pages can't accept a drop today; Noor's `file` button would give a picker |
| C. Filee's donut, rebuilt in the app | A second drag gesture to learn, needs Accessibility, and duplicates the companion |

The flow in A, as words rather than a mockup:

1. Drag `trip.heic` onto the companion. It reacts (the hop exists today).
2. The Sidecard shows the file and its size, up to three outcomes for this file, and "Other format…". Nothing is pre-selected and Return doesn't
   choose, because choosing is what grants the read (T43, confirmed by Noor). Each choice carries its one-line consequence if it has one.
3. The companion's light shows work. Anything long shows progress and a Stop button.
4. A whisper gives the receipt and Open, Show and Undo. Undo moves the new file to the Trash. The original is never touched.

The Home page holds recent results and defaults, and it is optional. It isn't where the work happens. Several files
behave the same way, with one choice for the group and a combined receipt.

## 5. What the platform can't do yet

Checked against `origin/main` (`d14e5f57`) and the unmerged `team/noor` and `team/sideflow-host` branches, since the local
`main` checkout is behind them. Each gap is a general ability any extension could use, as D98 requires: the app holds
no code naming an extension. Items 1 and 2 were measured (section 8). The others were read in the code and docs.

| # | Gap | State today | Needed |
|---|---|---|---|
| 1 | Video export fails in the sandbox | **Open.** `media` only: error -12903. Adding `com.apple.coremedia.videoencoder` alone: `fmt?`. Adding `com.apple.audio.AudioComponentRegistrar` as well: works. On main the encoder opens only under `screen`, and the audio service isn't opened at all | Open both under `media`, or a new permission. `screen` is the wrong thing to ask for |
| 2 | Half a core for 60 s kills the extension; so does 512 MB | **Open.** `ExtensionProcess.swift:22-25`, section 8 | Pace work to fit, and decide whether heavy work gets an allowance |
| 3 | 300 s per call, no progress | **Open.** Still 300 s on `team/sideflow-host`, and no progress messages in the Kit. Sideflow's flows chain calls but don't lengthen one. At the rate measured, one call covers about 36 minutes of footage, and a 2-hour film takes about 17 minutes | Long tasks: a handle, progress, Stop. Possible stopgap, untested: Miraya's clone into the data folder, with the page showing progress through Sideflow's `steps` part |
| 4 | Offering conversions on a drop | **Mostly solved on main.** `drops` declares kinds and name patterns, and a file goes under a `paths` argument (D100). But offers come after Sidefolk's own choices, at most three, and only the first dropped file is used (`CompanionWindowController.swift:942`) | Several files per drop, and a way for a file-type offer to lead the card. Check how the card reads before asking |
| 5 | Saving beside the original | **Open.** A drop or Noor's `file` button gives a read of one file for that call. `"write"` still means a folder the person shared | A grant to create new files beside the given files and overwrite nothing. Tighter than folder write, with fewer prompts |
| 6 | Result surface | **Partly.** D99 surfaces could draw the receipt, and `sidefolk/activity.add` gives a History row. Launch Services stays closed (D63), so nothing can Open, Show or drag out the result | A general file result action drawn by Sidefolk: Open, Show, Undo, drag out |

No session owns any of these six today (coordinator, 2026-11-03). Because each is general host work for every extension,
they are separate options below, not one package. Each needs its own decision and goes to the coordinator before it is
built. Only D140 to D143 are reserved for this work, so six abilities means grouping them or asking for more numbers.

**Options, in the order I'd do them**

| Order | Option (gap) | Without it | Review |
|---|---|---|---|
| A | Create new files beside a dropped file (5) | Output needs a shared folder, with the prompts that brings. I haven't confirmed a drop can name its output folder today, so this may block the drop flow | **Guard and `SECURITY.md`.** A sandbox grant would widen it. [The proposal](PLATFORM-PROPOSAL.md) has Sidefolk place the file instead: no new sandbox rule, but a new host capability that needs independent review |
| B | Several files per drop, and an offer that leads the card (4) | One file at a time, with offers after Sidefolk's own | Normal. Note that `paths` allows at most 4 per tool, which a batch would exceed |
| C | File result action: Open, Show, Undo, drag out (6) | The receipt is words only, with no way to act on the file from it | Normal, though Open and Show touch what D63 keeps closed to extensions |
| D | Encoder and audio service access (1) | No video re-encoding. Audio conversion may need the audio service too; not tested | **Guard and `SECURITY.md`: it widens the sandbox** |
| E | Long tasks with progress and Stop (3) | A length limit on video, about 36 minutes of footage per call at the measured rate | Normal |
| F | An allowance for heavy work (2) | Pace the work to half a core, so large HEIC batches run slowly. Only FFmpeg truly needs it | Needs its own decision, since it relaxes a safety limit (SECURITY T15, T17) |

A, B and C make the core flow. D adds video. E and F can wait until real use shows they're needed.

**Conditions from the coordinator's check (2026-11-03).** D140 to D143 and the order A, B, C, D have no conflict with Noor, Sideflow, dev ideas or the themes session.

- **A (D140):** Noor's `pickedFile` is on `team/noor` (`111a9bdc`), not on main yet. It lands after dev ideas' Notebook overview, and A must be based on `origin/main` after that. `ToolExecutor.execute`'s signature is shared with Sideflow. Read Noor's T43 and Sideflow's T44 first. The grant covers only files created beside the dropped file, never overwritten, behind Guard, `ToolExecutor` and the audit trail. Plan for several rounds of independent security review; Sideflow's took three.
- **B (D141):** a new kind of argument, a list of files granted one by one, not a higher `paths` cap. Details and questions for Sideflow and Noor are in [the proposal](PLATFORM-PROPOSAL.md). Read against their branches but not yet reviewed by them.
- **C (D142):** Open and Show touch what D63 keeps closed, so they needed the founder's explicit words, now given (section 9). The action is drawn by Sidefolk, not the extension. Open is drawn only for images, audio, video, PDF, plain text and CSV, and refuses links or any path but the created file. Show only reveals the file in Finder. Don't reuse Noor's action names (`go`, `copy`, `file`, `allow`, `settings`) or Sideflow's reserved names (`steps`, `tree`, `bar`, `nav`, `notice`, `ticks`, `companion`, `workspace`).
- **D (D143):** independent security review, and measure under the real host's rules before claiming it works. Section 8's result came from a hand-built copy.
- **Implementation:** still needs the founder's explicit go. The coordinator then needs the branch, the exact files and the base commit.

**Pieces to build on, which don't cover these options themselves**

- **Noor's `file` page action** (D105, `pickedFile` on `ToolExecutor.execute`, `team/noor`): a read of one picked file for one call. It gives the Home page a picker. It doesn't cover several files or creating new ones, but it is the pattern options A and B would extend.
- **Sideflow's flow steps and job runner** (`team/sideflow-host`): timeouts and cancel, not long tasks with progress and Stop. Its `steps` part can display a batch.
- **Watch folders, as Filee has them:** possibly a flow built by the person from this extension's tools, one file at a time. Lists in plans always ask on a card (Sideflow's review). Not tried.

## 6. Scope, reuse and licences

**Measured on this Mac (macOS 27). Sidefolk's floor is macOS 15, so re-check newer formats such as AVIF writing there.**

| Kind | With Apple's frameworks alone | Missing |
|---|---|---|
| Images | Reads 62 types, including WebP, AVIF, JPEG XL, RAW, PSD. Writes JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP, ICO, ICNS, PDF | **WebP writing** |
| Video | MOV and MP4 in; MP4 and MOV out with H.264, HEVC or ProRes, on the hardware encoder | WebM read failed here. MKV and AVI not tested, and not in Apple's usual list |
| Audio | Encodes AAC, ALAC, FLAC, Opus, PCM; decodes MP3 too | **MP3 writing** |
| PDF | Pictures to and from PDF, merge, split, text; OCR with Vision (Filee uses it on Mac too). Not tested here | Strong compression |
| Documents | `textutil` lists doc, docx, odt, rtf, html, txt | Layout fidelity. Don't promise Office-quality PDFs. Not tested here |
| Data, subtitles | Our own code, porting Filee's | |
| Archives | Apple's `bsdtar` wrote 7z, zip, tar, iso, xar here. Reading RAR and others not tested | |

**Using Filee's code.** Its own code is MIT, but it is C# on .NET, so it can't be linked into a Swift extension.
Reuse means reading and porting, keeping Filee's copyright and MIT notice in `licenses/` (`build.py` already packs that
folder). MIT doesn't cover every file: `Fonts/Cff/CubicToQuadratic.cs` follows Apache-2.0 fontTools, and the HWPX code adapts
`pypandoc-hwpx`. Check a file's origin before porting it. Good candidates: `RoutePlanner`, `FormatRegistry`,
`CompanionFiles`, `PageRange`, `Data/` (2,554 lines), `Subtitles/` (1,929 lines).

Running Filee's .NET command-line tool as a bundled engine would be a poor fit: another runtime, Magick.NET's bundled LGPL
libraries, and the 512 MB cap. I didn't measure its size.

**Engines**, per Filee's `THIRD-PARTY-NOTICES.md` and ffmpeg.org/legal:

| Engine | Licence | Position |
|---|---|---|
| Apple frameworks, `bsdtar`, `textutil` | Part of macOS | **Use.** Nothing to ship, and Apple's encoders avoid us shipping H.264/HEVC codecs ourselves |
| libwebp | BSD (my knowledge; Filee lists it only as a Magick.NET delegate) | Good first addition for WebP |
| PDFium, Tesseract, whisper.cpp | BSD/Apache, Apache-2.0, MIT | Allowed. Not needed at first (Vision does OCR) |
| FFmpeg, **LGPL build** | LGPL-2.1+ | Possible, with duties below |
| 7-Zip | LGPL plus an unRAR restriction | Not needed, `bsdtar` covers the start |
| LibreOffice | MPL-2.0 | About 298 MB download, over the 200 MB pack limit. Skip |
| **Filee's FFmpeg** (gyan build, x264, x265) | **GPL-3.0+** | **Do not ship** |
| **Homebrew's ffmpeg on this Mac** | **GPL** (`--enable-gpl`, measured) | **Do not copy into a pack** |
| **Pandoc, calibre, H2Orestart** | **GPL** | **Do not ship** |
| **Ghostscript** | **AGPL-3.0** | **Do not ship** |

Sidefolk is proprietary (D17, `LICENSE`), which is why the GPL and AGPL rows are closed unless the founder decides otherwise.

**If FFmpeg comes later**, it is the only way to get WebM, MKV, AVI and MP3 together. FFmpeg's checklist requires: no
`--enable-gpl` or `--enable-nonfree`; dynamic linking (`lib/` is already supported, D69); the matching source, your
changes and configure options, hosted on the same server as the binary; credit on download pages, in About and the EULA;
and an EULA that doesn't forbid reverse engineering (today's `LICENSE` is silent on this but restrictive, so it needs a look).
FFmpeg also warns that commercial products may owe patent fees. **Have a lawyer review this before shipping; this
brief isn't legal advice.** FFmpeg also hits gap 2: its software paths ran at 0.7 to 4.6 cores here (section 8).

**Suggested order**

1. Options A, B and C, then the extension with images, PDF, data and archives, and audio if it works without option D.
2. Option D for MOV/MP4 and any audio that needs it, then option E for long video. Add documents only as far as testing supports them.
3. WebP through libwebp.
4. A separate decision on FFmpeg, as its own gallery pack and with no network either.

## 7. Name and icon

**Name: Formatic, approved by the founder on 2026-11-03.** The founder rejected the earlier options and asked for a much better name.

- **Why it works:** "Format" says at once what it's about, and "-matic" says it does the job for you, as in automatic. One word, easy to say, and it sounds like a product rather than a description.
- **In use:** "Drop it on Formatic." "Formatic made it a PDF."
- **Tagline, for full clarity:** "Turn any file into the format you need" (38 characters, under the limit of 60).
- **Id:** keep `dev.sidefolk.convert`, with Formatic as the label. The id is permanent, and the name has already changed once. Tools read well: `ext.convert.file`.
- **Weakness:** "format" can suggest formatting a disk or text, which the tagline and icon answer.
- **Collisions** (web searches only, **not trademark clearance**): no file converter by this name found. The name is used for forms products: a [Formatic iOS app](https://apps.apple.com/ci/app/formatic/id1643318765), a [Statamic kit](https://statamic.com/starter-kits/luckymedia/formatic) and an [npm package](https://npmjs.com/package/formatic). That matters little for a row in Sidefolk's own gallery, but check it before marketing the name on its own.

**Rejected:**

| Name | Why not |
|---|---|
| File Converter | The founder didn't like it. Clear but generic |
| FileMorph | Clear, but several products already use it, including [a paid media converter](https://payhip.com/b/56aXy) and [a Mac tool](https://mac.softpedia.com/get/Utilities/FileMorph.shtml) |
| Format Shift | Two words, and close to [FileShift](https://apps.apple.com/dk/app/fileshift/id6742402471), a file converter |
| Recast | Nobody would guess it's about files |
| Convert, Converter | Could be units or currency, beside Currency in the gallery |
| Turnfile, Filevert, Anyform | No collisions found, but awkward to say or read |

**Icon: [`icon/formatic-icon.png`](icon/formatic-icon.png), approved by the founder on 2026-11-03.** Two glass documents, cobalt and coral, with a bright overlap where one becomes the other. It reads as files even at 28 px and looks current, with Apple's glass style on near-black.

- **Weakness:** two overlapping documents is also the usual "copy" symbol. The change of colour and the glow set it apart, but check it in the real sidebar.
- **Not chosen, kept for reference:** [`icon/formatic-icon-alt-shift.png`](icon/formatic-icon-alt-shift.png), one file cut on a diagonal, white above and lime-to-aqua below. It's more unusual and has no "copy" problem, but it's less rich.
- **For shipping:** [`icon/formatic-icon-512.png`](icon/formatic-icon-512.png) is 250,846 bytes, under the 256 KiB limit for a local install. The gallery expects `icon.pdf`, which is still to do. It's a generated image, not checked for resemblance to existing marks.

## 8. Measurements

A scratch program, not product code: 12-core Apple silicon, macOS 27.0.1, a synthetic 60 s 1080p H.264 clip (89 MB), and
12 MP test images. The sandbox profile was rebuilt by hand from `SandboxProfile.baseRules`, plus `mediaRules` and read/write
rules for the test folder, and run with `sandbox-exec`. **It wasn't run through the real extension host, and the
watchdog itself wasn't triggered.** Kill predictions are worked out from its limits. Synthetic footage flatters
decoding, so expect real files to differ.

| Job | Sandbox | Wall time | Average cores | Against the half-core limit |
|---|---|---|---|---|
| HEVC export, AVFoundation, hardware | media + encoder + audio | 8.3 s | 0.11 | Fine, even for long files |
| Remux, passthrough | media + audio | 3.8 s | not recorded | Output written |
| 40 × HEIC, ImageIO | media | 14.1 s | 3.96 | About 170 at this rate reaches 60 s and would be killed. Paced, about 2.8 s each |
| 20 × PNG | media | 12.7 s | 0.53 | Just over; pace it |
| 40 × JPEG | none needed | 2.4 s | 0.63 | Fine in short batches; pace large ones |
| VP9 decode + hardware encode, ffmpeg | none (15 s clip) | 2.3 s | 0.71 | Would be killed on long files |
| x264 software, ffmpeg | none | 14.8 s | 4.57 | Would be killed past 60 s |

## 9. Decisions needed

1. **The neighbours:** whether Images' `convert_images` retires once this ships. I'd keep PDF Tools and Archives, and
   move conversion here so there's one answer to "convert this".

**Decided (founder, 2026-11-03):**

- Native-first. FFmpeg stays a later, separate decision.
- Platform options A, B and C, then D, in section 5's order. E and F wait for real use.
- A dropped file grants a read for that call on all file drops, not only the new key: the founder's words, "All drops". No shipped extension declares a file drop today.
- The Sidecard flow in `design/README.md`, approved, with a quicker way in to be added (`design/RING.md`).
- The look in `design/README.md`, "Your file sets the colour" with one picture per card, approved.
- Open and Show on the result card: the founder's words, "Allow both", in answer to "May Sidefolk open and show files that an extension just created?" Proposed limits, shown to the founder with the recommendation: Sidefolk draws the buttons, they work only on a file the extension just created and only on the person's click, and extensions still can't open anything themselves. The security review covers Open launching a converted file in its default app.

Proposed decision numbers: A D140, B D141, C D142, D D143, the look on host cards D150, Finder's Send to Sidefolk D151, the ring D152 (the last three undecided, see `design/`). Each option goes to the coordinator before it is built, and A and D need the Guard and `SECURITY.md` review.

Next: the founder's explicit go to build. The ring (D152) also needs the ring test to pass first. Nothing here has been built.

## Sources

- [Filee](https://github.com/KnifeLemon/Filee) at commit `c187f1a`: `LICENSE`, `THIRD-PARTY-NOTICES.md`, `docs/ENGINES.md`, `src/`.
- [FFmpeg license and legal considerations](https://ffmpeg.org/legal.html).
- Sidefolk: `docs/EXTENSIONS.md`, `docs/DECISIONS.md` (D17, D50, D63, D69, D98, D99, D100), and on the branches D125 to D129 and Noor's page actions, `docs/SECURITY.md` T12, and `Sources/SidefolkCore/Extensions/`.
- Other converters and collisions: [Morpholder](https://apps.apple.com/us/app/morpholder/id6759731792), [FileShift](https://apps.apple.com/dk/app/fileshift/id6742402471), [Convertible](https://peerpush.com/p/convertible), [Format Converter](https://apps.apple.com/us/app/-/id1462608568).
