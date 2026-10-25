# Ines — creative director, character-driven products

## 1. Seat & method
I own the soul: character, voice, animation, delight, brand. I looked at every overlay-*.png and several window shots, the approved concept sheets (creative-design/v2), the 10 reference photos, the brand SVGs, CHARACTERS.md, DESIGN-SYSTEM.md and decisions 36–38. I composited all 16 frames of Pip, Spark and Capy (3D and 2D) at the real 150 px height (pip.ts:83) on light, dark and blue wallpapers, plus a lineup of all ten idles (scratchpad/council/ines-shots/*.png). I also read the companion's copy and the motion code in pip.ts and mind.ts.

## 2. First 30 seconds
The clay bunny is honestly cute. It's well crafted and consistent, and I'd screenshot it. Then I opened Settings → Companion and found a blind-box shelf of ten equal toys with the robot in the first tile (full-settings-companion.png). Then Pip spoke, and it sounded like a log line: "Claude stopped with a problem in api: rate_limit. Open it from Sidefolk." (overlay-failed.png). The body is there but nobody lives in it yet. Pip has a look and no self.

## 3. Scores
- **Clarity of purpose: 4.** Three products share one bunny: a pet, a life assistant and an agent cockpit. The character can't tell you which one it is.
- **Ease of use: 5.** The overlay is calm and every card can be closed. But Pip fails the phrases people actually say, and he sits there looking content while he fails.
- **Visual quality: 7.** The assets are charming and the mint accent works across the whole set. Dark wallpapers break it (problem 5), and the 2D style adds nothing.
- **Usefulness to me: 5.** I'd keep Pip for the "needs you" card and the reminders. I wouldn't keep the ten characters, the terminal or the TTS voice.
- **Trust & safety: 6.** The permission card is sober and clear (overlay-permission.png). But Pip offers to run "make coffee" in my terminal (overlay-make-coffee-reply.png) and repeats raw errors.
- **Release readiness: 3.** The character design isn't frozen, and a fourth art pipeline is staged in git right now (art/blender/film-duo/).

## 4. Top problems, ranked
1. **Blocker: Pip's identity has changed four times in three days, and the shipped Pip isn't the brand.**
   - The logo is a charcoal bunny with a mint signal dot (art/brand/pip-signal.svg, fill #272A33).
   - The approved Pip was the charcoal body B (PLAN-V2 §4, creative-design/v2/pip-body-b.png). Decision 38 replaced it hours later with an ivory clay bunny with charcoal ear tips (art/crew/refs/pip.jpg).
   - The pipelines so far: procedural Blender (v0.1), then 2D body B, then generated pose sheets, and now the staged Blender "film" rigs (art/blender/film-duo/README.md).
   - **Fix:** freeze the character (section 6). The ivory clay Pip is the stronger asset, so keep it. Redraw the app icon as Pip's real head (ivory, charcoal ear tips, mint dot). Keep the charcoal silhouette only as the mono mark. The dark-mode sidebar already shows an ivory head that reads as Pip (dark-home.png), which is evidence this works.
2. **Major: it's a catalog, not a character.**
   - The picker shows ten equal tiles, and Spark comes before Pip.
   - Each character's personality is one noun ("Bunny", "Cloud spirit"). CHARACTERS.md writes personalities for 12 characters (Byte, Patch, Loom…) that no longer exist. No personality is written down anywhere for the current Pip.
   - The 2D style is a trace of the 3D one, and at 150 px the two are nearly the same (ines-shots/lineup-2d.png vs lineup-3d.png). That doubles the art cost for no new identity.
   - **Fix:** ship Pip plus Spark only, in one style.
3. **Major: Pip's voice sounds like system messages, and errors leak through.** Examples:
   - The fallback reply lists features instead of reacting: "I can set reminders, run commands and open your work sessions…" (companion.ts:402).
   - "Spark looks after api now (sky)." (overlay-spark.png).
   - "OK, today 12:13 AM: stretch" (overlay-reminder-saved.png).
   - Morning, welcome-back and weekly briefings are bullet dumps: "api · Claude finished: …" (away.ts:28).
   - Raw `String(e)` goes straight into the bubble (companion.ts:387, 397).
   - The only line with personality is "A quiet week on my side." (main.ts:352).
   - **Fix:** the voice rules below, and an error-to-plain-language table.
4. **Major: the acting doesn't match the moment.**
   - Pip sits relaxed while proposing a shell command (overlay-make-coffee-reply.png) and while saying he doesn't understand you (overlay-casual-reply.png).
   - A "confused" moment, which a parser that misses often needs most, has no pose.
   - The face is two dots in 12 of 16 frames. Only done, blink and sleep change the expression.
   - **Fix:** add a puzzled pose (head tilt, one ear folded; the concept sheet already has it as "think"). Map every bubble type to a pose.
5. **Major: dark wallpapers erase the ears.**
   - Pip's charcoal ear tips, and the 2D outline, disappear on dark backgrounds, so the bunny loses its bunny-ness (ines-shots/pip-dark-zoom.png, pip-2d.png). Nova, Pebble, Rune and Pixel lose their whole body.
   - The outline was removed on 24 Oct (commit d59e76a), yet the importer still offers "Light outline (keeps it visible on dark wallpapers)" (light-characters.png).
   - **Fix:** add a soft warm rim light or 1.5 px ivory edge that switches on automatically from wallpaper luminance, or lighten the ear tips to warm grey.
6. **Major: the animation is stiff between poses.**
   - The code adds real life, and it's good: breathing, blinks every 2.5–6.5 s, a hop, sway, squash, a cursor-near wave, sit then sleep after 2 min, drag/dangle/throw (pip.ts:184-209, mind.ts:174-205).
   - But poses hard-cut, and the work and write loops are 2-frame flipbooks at about 3 fps (pip.ts:185, 0.32 s).
   - The concept's "glances at cursor" and "ears that lag" can't be done with whole-body frames.
   - **Fix:** for Pip only, add 6 micro-frames: look left, look right, ear twitch, head tilt, anticipation crouch, hold-up-note. Fund it from dropping the 2D style.
7. **Major: Pip delivers agents' news but has no stance as messenger.** The design system has the right rule: report the real state, don't claim reasoning (DESIGN-SYSTEM.md:66). But nothing gives Pip a stance. **Fix:** make Pip the messenger, never the AI (section 6).
8. **Minor: "Spark" is both a character name and a role.** A robot named Spark can be your companion, while a Spark worker can be a capybara (art/crew/README.md). **Fix:** a Spark is always the robot, recoloured per project.
9. **Minor: spoken TTS in a generic macOS voice** (full-settings-sound.png) breaks the character. The soft oscillator blips (sound.ts) are the right voice. **Fix:** cut TTS and give Pip a sound signature.
10. **Minor: the make-your-own importer** asks users to paste a prompt into an image AI (light-characters.png). That brings back the zoo, dilutes the brand and adds likeness/IP risk. The provenance of the reference photos also needs confirming (inferred).

## 5. Feature verdicts
| Feature | Verdict | Why |
|---|---|---|
| Pip desktop companion | KEEP | It's the product's soul and the one thing nobody else has |
| Talking by typing (local parser) | REWORK | Every miss should get a puzzled pose and an in-character suggestion of the nearest thing |
| Tell bar in window | KEEP | Same brain; label it with the companion's name |
| Reminders | KEEP | "Holds up the note" is Pip's best ritual |
| Notes & notebooks | KEEP | The writing pose sells it; keep the feature simple |
| AI "Draft a summary" | LATER | Not core to the character |
| Quick commands (run in terminal) | REWORK | Developer mode only; offering "make coffee" makes Pip look foolish |
| Saved actions | LATER | Power-user feature, no character payoff |
| Open app/folder/URL | KEEP | Cheap and useful |
| Watching Claude Code/Codex sessions | KEEP | Unique acting material |
| Permission requests on companion | KEEP | The signature moment: Pip raises the "!" card |
| Per-session full access | REWORK | Move it to the window and keep the bubble sober (I defer to the safety seats) |
| Start sessions | LATER | Window feature, not a character feature |
| Open/continue session | KEEP | Needed for "needs you" to pay off |
| Sparks | REWORK | Always the robot, recoloured, at most 3; Pip and Spark are a good duo |
| Terminal inside Sidefolk | CUT | Off-brand and duplicates the Terminal app |
| Calendar heads-up | LATER | Fold into the greeting once it's solid |
| Morning brief | REWORK | One warm greeting, three lines, in voice |
| Weekly wins | REWORK | The best emotional moment in the app; make it a celebration, not a list |
| Ten characters + 3D/2D styles | CUT | Pip and Spark in 3D clay only |
| Make-your-own character import | CUT | LATER at best, after Pip is loved |
| Accent colors | KEEP | Scarf colour: personal without losing identity |
| Sounds & spoken voice | REWORK | Keep the blips, cut TTS |
| Setup guide | REWORK | Let Pip host it: arrive, wave, ask for one reminder |
| Settings (9 categories) | REWORK | About 4; Companion becomes name, scarf colour, size, motion |
| CLI `sidefolk here` | LATER | Fine for developers, not v1 identity |
| MCP tools for agents | KEEP | Agents speak through Pip, in Pip's voice rules |
| Dock app + window | KEEP | A home for everything Pip holds |

## 6. What v1 should be
**One sentence:** for people who work at a Mac all day, alongside AI agents or not, Pip is a small clay bunny who keeps your reminders and notes and taps you when Claude or Codex needs you.

**Character bible (lock this down):**
- **Who Pip is.** A quiet desk-mate and messenger, not an AI. Pip *holds things for you* (notes, reminders, agents' questions) and *brings them to you* at the right moment. Three traits: attentive (the ears turn toward you), earnest (holds things up with both paws), unbothered (sits, naps, never nags). Pip is male or neutral; pick one and stay with it. Spark is Pip's coworker: a little robot, one per project, recoloured. No other species in v1.
- **The look, frozen.** Ivory clay body, charcoal ear tips, mint scarf, status dot at the right ear (pip.ts:86). Any change needs a 150 px test on light, mid and dark wallpapers, a written reason and a one-week cooldown. No new art pipeline. Stop the film-duo Blender work for the app.
- **The ears carry the emotion.** Up means attention. Twitch means "heard you". One folded means puzzled. Both down means sad or asleep.
- **State map.** idle, listen (you type), think, work (agent busy), alert (needs you), done (only for real success), sad (an agent failed, never when *you* do something wrong), note/write, wave, sit, sleep, dangle. Add **puzzled**.
- **Voice rules.**
  1. One short sentence of 12 words or fewer, then the buttons.
  2. "I" for Pip's own acts ("Got it. I'll tap you at 9."). Name the agent for theirs ("Claude wants to run a command in api.").
  3. No raw errors. "rate_limit" becomes "Claude hit its usage limit in api."
  4. No guilt, no urgency theatre, no emoji. Exclamation marks only on done.
  5. When Pip doesn't understand, own it and offer the nearest thing: "Hmm, not sure. A reminder at 5 pm to call mom?"
  6. On permission cards the personality lives in the pose; the copy stays plain.
  7. A recurring phrase family: "Got it." / "Noted." / "Here if you need me."
- **The delight moments that matter, in order:**
  1. The first hop-and-wave, plus one reminder created during setup.
  2. Writing, then holding up the note when it fires.
  3. Raising the "!" card for a permission request.
  4. A cheer and hop on real completion.
  5. Pick up, dangle, toss (the shareable moment).
  6. Falls asleep while you're away, wakes with a wave and one line about what happened.
  7. Reading back your week on Friday.
  8. An ear twitch when poked.

**5 must-haves:**
1. The frozen Pip and Spark.
2. The voice rules applied to every string, plus an error translation table.
3. Puzzled and micro-frames for Pip, with pose mapped to every bubble.
4. Dark-wallpaper legibility.
5. The 8 delight moments, polished and timed (celebrations under 1.2 s, per DESIGN-SYSTEM.md:64).

**5 must-cuts:**
1. The other 8 characters.
2. The 2D style.
3. The character importer.
4. Spoken TTS.
5. The in-app terminal.

**Vote: EVOLVE.** The character runtime is right: pre-rendered frames plus code-driven life and physics, cheap on CPU, with a good drag/throw feel. What's wrong is scope, voice and a design that won't stop moving. Those are fixed by cutting and writing, not by a restart.

## 7. The one thing
If Pip tilted his head when he didn't understand me, and held up my note with both paws when it was time, I'd keep him on my desktop for years. I'd uninstall the moment the bunny says "rate_limit". When the character talks like a stack trace, it's a widget, not a friend.
