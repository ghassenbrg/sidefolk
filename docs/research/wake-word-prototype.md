# Wake word: what a prototype measured (dev ideas, item 14)

A small measurement, with no UI and nothing in the app. It fed synthesised speech and silence, from files in real time, to Apple's on-device
`SpeechTranscriber` on this Mac (macOS 27). **It never opened the microphone**, so the question that could sink the approach is still open.

## Measured

| What | Result |
|---|---|
| Idle cost, 90 s of silence | 0.4 % CPU in the app's process, and about 1.9 % in macOS's speech services (`corespeechd`), so **about 2–3 % all the time**, on battery as this ran. Every hour awake, it never idles |
| Ordinary talk | 0.7 % in the app's process; every word of the room is transcribed, in memory |
| A false wake | None in 20 s of ordinary talk, which is too little to say much |
| The name heard, English | Mochi, Kiko, Nimbo, Iris, Nori right. **Purl → Pearl, Rune → Roon, Ember → Amber.** "Hey Spark" → "J Spark", "Hey Folio" → "K Folio", each with the name right |
| The name heard, other languages | French: Mochi → **Moshi**. Japanese: モチ → **持ち**, a plain word. Spanish, German, Italian, Portuguese, Korean, Chinese: **no model on this Mac** until downloaded. Arabic: **not supported at all** |

The voices were synthesised, on clean audio. A real room and a real voice can only be worse.

## What that means

- **It works by transcribing everything, always.** There's no keyword spotter here: to hear "Mochi", the Mac turns all speech in the room into text. Nothing need leave the Mac or be kept, but that's a heavier promise than "listens for one word", and it should be said plainly in the setting.
- **Names need sounds, not spelling.** Matching text wants a list per name per language (Moshi, 持ち, Pearl). That can be tried for the gallery's names, but a custom word in another language would be a guess, and 持ち means "holding", so ordinary Japanese would wake it.
- **Ten languages aren't there.** Arabic can't, and six need a model downloaded first.
- **Still unknown, and needing the microphone: the mute.** An always-open microphone is what muted spoken replies once (HISTORY, "Spoken replies muted by Siri's listener"). It's the first thing to test, about a minute at the founder's Mac, since the orange dot and a permission prompt would appear. It decides whether any of this can work.

## For the founder

Recommended: **don't build it this way yet.** Run the one-minute microphone test when you're at the Mac. If replies still sound and you still want it: English and French first, as an off-by-default experiment, names from the gallery only, with a clear indicator. A real keyword spotter (a small model on the sound itself) would solve cost, privacy and custom words together, but it's a project of its own, with a model per word.
