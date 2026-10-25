# Ines — creative direction audit

25 October 2026. Independent conclusion; no other council reports read.

**Vote: A — everyday reminders and dated notes, with optional AI. Release verdict: a focused private beta, after the signal and identity corrections below; the evidence does not support a broad companion-assistant launch.**

Sidefolk has a credible visual home: a quiet Mac utility with a small, approachable creature beside it. The current art is good enough to ship into a beta. Another character generation round would solve the wrong problem. What needs work is the relationship between the creature's behavior, its identity in the window, and the work it claims to represent. A charming face should make an interruption easier to understand, rather than supply a reason to interrupt.

## What I inspected

I read AGENTS.md, STATUS, DECISIONS, LEARNINGS, especially Decision 38, the approved [review specification](../../creative-design/review-2026-10-24/README.md), and all five final boards. I inspected the current WebKit light/dark contact sheets covering 26 main views, the overlay/request/Spark captures, the ten built-in idle designs in both styles, selected Pip/Spark/Rune pose sets, and original Pip/Spark/Rune references. I inspected `pip.ts`, `mind.ts`, `familiar.ts`, `roster.ts`, `recolor.ts`, and the relevant dashboard rendering.

The browser evidence is under `output/audit-2026-10-25/webkit/`. My derived asset comparisons are `output/playwright/ines-creative-crew.png` and `ines-creative-poses.png`. The crew comparison uses 210 × 190 frame canvases, corresponding to the renderer's medium standing height of 150 CSS px; the pose overview is smaller for comparison. These are static images. I did not observe continuous animation, listen to sound, capture the native desktop, or measure performance. Temporal polish and native wallpaper behavior remain unverified.

## Keep the approved identity and its restraint

Pip's charcoal ear tips, cream body, dot face and mint scarf survive reduction well. Spark's black visor and large eyes also read immediately at desktop size. The references are recognizably preserved; the current sprites retain the important silhouette and palette decisions. The bunny's minimal face leaves room for a user to project personality without demanding attention. The alert's orange exclamation card and the sleep pose change the outer shape enough to be more useful than a tiny facial change.

Keep the current logo exactly unchanged. The production mark is a reliable compact identifier in the window and status cards. The latest character approval explicitly supersedes the earlier body-B art, so the cream bunny's difference from the old black-bunny boards is an approved evolution, not a design regression. Preserve the approved artwork and lack of white outline.

The crew also forms a coherent family. Shared mint, cream and charcoal unite substantially different silhouettes; the tan capybara and brown otter add warmth without breaking it. The flatter 2D drawings preserve the same recognizable features. “3D” is a rendered look, not a promise of a live model; the Settings description already says “Soft 3D renders or flat 2D drawings.” Keep that language. Returning to live 3D would add production work without an established user benefit.

The current main window honors much of the approved direction: everyday navigation comes first, the companion stays small, themes are consistent, and the utility is allowed to look like a utility. Dark mode remains restrained rather than turning into a neon pet dashboard. The three-step first-use image is particularly coherent: meet one bunny, make one real reminder. Keep that sequence and the absence of a home-screen character collection.

## Rework the signal grammar before adding personality

The strongest creative defect is a factual one. `mind.ts:197–203` occasionally chooses `think` as an autonomous idle activity, while `pip.ts:49–55` gives that pose the same blue status light used for actual thinking. A user learning the signals cannot distinguish “my companion has an idle mannerism” from “my agent is thinking.” Reserve the status signal for actual work; an idle thought can retain an idle signal. This can be corrected without replacing art.

Similarly, `pip.ts:37–38` uses the same laptop frames for reading and working. That is acceptable as a coarse “busy” gesture, but it cannot demonstrate the richer claim that the pet acts out each kind of agent activity. Do not market every tool event as visibly distinct. The window's words must remain authoritative. A future behavior pass should prioritize a few dependable categories—available, occupied, needs you, finished—over a larger catalogue of weak distinctions.

The implementation has ingredients for life: timed blinks, slight cursor lean, restrained breathing, short greeting/completion hops, sitting and sleeping. The code limits greeting proximity reactions with a 40-second cooldown and does not make the creature stroll across the desktop. Those are good decisions for daily use. But most actions are single paintings, with work/write alternating two paintings every 0.32 seconds (`pip.ts`). This is a pose-based performance with procedural movement, and its believability depends on frame registration and timing. Source inspection establishes intent, not whether it feels alive for an hour. Require a native hand check at small/medium sizes for abrupt switches, repetitive typing, greeting frequency and reduced motion before making a motion-quality claim.

The same motion recipe serves every species. That is a sensible baseline, but a cloud, robot and bunny should eventually differ in timing and attitude. Use existing assets first: a deliberate robot pause, a quieter Sprout response, or a softer cloud settling cadence. The named roles in `art/crew/README.md` currently describe appearance and positioning more than demonstrated behavioral capabilities. Avoid implying that selecting Rune grants expertise or Otis grants a different toolset.

## Make ownership readable across surfaces

The desktop Spark screenshot has a promising distinction: the robot wears a project-colored accent and a project badge, while Pip is the personal companion. Recoloring only mint preserves the character's skin/fur and is a strong implementation choice. The status orb remains a separate signal. Keep this separation; project ownership and urgency are different information.

However, the orb is anchored to one fixed coordinate, “beside the right ear,” for every character and pose (`pip.ts:85–86, 222–224`). Several designs have antennas, halos or leaves there. The Spark capture visibly contains both a decorative antenna dot and a status dot. This is manageable, but it makes the status language harder to discover. Check every species at actual size, and position the runtime signal consistently outside the silhouette rather than assuming bunny anatomy. Per-character anchors are a smaller intervention than rebuilding the assets.

Custom-character continuity is a concrete weakness: `roster.ts:32–33` falls back to Pip for a made character's window picture, and the chooser uses an initial for made characters. The desktop can therefore be “my character” while the window becomes someone else's bunny. Use the imported idle thumbnail for these identity surfaces. Keep the logo separate and unchanged. This is more valuable personalization than adding accessories.

## Restore hierarchy where implementation became dense

The real screenshots retain the boards' overall layout, but several useful simplifications have weakened. The approved Reminders view suggests a completion control, title/time and disclosure to details. The current rows expose Open, Snooze, Edit, Delete and Mark complete together. Repeated verbs compete with the reminder itself and make a calm list resemble a management console. Retain completion and one obvious details action; place the less frequent actions in details or a labelled menu.

The actual notebook toolbar similarly foregrounds Copy as Markdown, Show in Finder and Draft a summary above the entries. The board made dated writing primary and AI secondary. Restore that emphasis: reading and adding a note should dominate; export and optional summarization can remain available with less weight. These are hierarchy corrections within approved scope.

The permission overlay is legible, and exact command/folder information is a strength. Yet “Allow everything from this session” sits directly below the one-time choice, in the same friendly card. The creature should convey “there is a decision waiting,” never reassurance that running it is safe. Visually separate the persistent-access decision and explain its scope in the deliberate review step. No extra angry character or alarming palette is needed.

## Release discipline

**Keep:** current logo and approved crew; both art styles; quiet themes; small sidebar companion; personal Pip/project Spark distinction; explicit status words; the real two-minute reminder introduction.

**Rework first:** idle-versus-work signaling, imported-character thumbnails, row/toolbar hierarchy, and persistent-access emphasis. Validate native motion and backgrounds through the repo's permitted hand-check workflow. A narrow beta should include people who leave the companion visible during ordinary work, not just people excited by the art.

**Defer:** more species, accessories, live 3D, elaborate autonomous antics, and broad assistant positioning. Ten characters already provide ample choice. The next investment should demonstrate that users keep Sidefolk because it helps them remember or capture something, not because they enjoy choosing a pet once.

A is the most coherent current promise: a small companion that helps with small commitments. B, developer-first, has a more specialized signal-monitoring benefit, but would require stronger multi-session and workload legibility than the current visual grammar supplies. C dilutes both. For A's beta, watch whether people voluntarily use reminders/dated capture in week two and whether the companion earns its screen space. If the only retained use is agent monitoring, choose B on that evidence. Do not use charm to disguise an undecided product.
