# Pip: character bible (v1, frozen)

Contract: [docs/V1.md §8](../docs/V1.md). Changes need the change process in V1 §13.

**Pip and Spark are always in the app** (founder, 25 October 2026). Pip is the default and the
character this bible describes. Spark is the clay robot: the same poses, voice rules and "never"
list apply, its status light sits on its antenna tip, and the user picks either one in Settings →
Companion.

## Who Pip is

Pip is a quiet desk-mate and messenger, **not an AI**. Pip holds things for you: your reminders,
your notes, your agents' questions. Pip brings them to you at the right moment and remembers what
got done.

Traits: **attentive, earnest, unbothered.**

Pip speaks in the first person. Agents are always named for their own work: "Claude finished in
api", never "I finished".

## Look

- The ivory clay bunny with charcoal ear tips and a mint scarf: `public/crew/pip/3d/*.webp`, cut
  from `art/crew/pip/3d`.
- One style only: pre-rendered 3D clay frames.
- The status dot sits by the right ear.
- The logo (charcoal Pip Signal) is unchanged. Wherever Pip *speaks*, the ivory character
  appears, not the glyph.
- Must read at 150 px on light, mid and dark wallpapers. On dark wallpapers a warm rim keeps the
  ears visible.

## Ears are the grammar

| Ears | Meaning |
|---|---|
| Up | Attention |
| Twitch | Heard you |
| One folded | Puzzled |
| Both down | Asleep or sad |

## Pose map

| State | When | Notes |
|---|---|---|
| idle | Nothing happening | Breathing, blinks; no activity light |
| listen | You are typing | |
| work | An agent is busy (real events only) | Work colour only here |
| alert | A request or question needs you | "!" card |
| done | Real success only | Under 1.2 s |
| sad | An agent failed | Never because *you* did something |
| puzzled | Pip didn't understand | New in v1 |
| write | A note was saved | |
| hold-up | A reminder fires | Pip holds the note |
| wave, sit, sleep, dangle | Greeting, resting, away, being dragged | |

Allowed additions in v1, and nothing else:
- the puzzled pose
- up to six micro-frames: look left, look right, ear twitch, tilt, anticipation crouch, hold up
  note
- cross-fades between poses

## Voice

1. One sentence of 12 words or fewer, then the buttons.
2. "I" for Pip's acts; name the agent for theirs.
3. No raw errors. Every error goes through `src/voice.ts`: `rate_limit` becomes "Claude hit its
   usage limit in api."
4. No guilt, no urgency theatre, no emoji. "!" only on done.
5. When Pip misses something, it owns the miss and offers the nearest thing: "I saved that to
   your Log. Make it a reminder?"
6. Permission cards are plain; the personality lives in the pose.
7. Recurring phrases: "Got it." · "Noted." · "Here if you need me."

## Pip never

- nags twice
- walks around the desktop
- celebrates something that didn't succeed
- shows an activity light while idle
- claims an agent's work as its own

## Moments that matter, in order

1. First hop and wave, plus one real reminder made in setup.
2. Writing a note, then holding it up when it's time.
3. The "!" card for a permission request.
4. A short cheer on real completion.
5. Pick up, dangle, toss.
6. Sleeping while you're away, then waking with a wave.
7. Your week on Friday.
8. An ear twitch when poked.
