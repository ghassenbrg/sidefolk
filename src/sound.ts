// The pets' voices, made on the fly with Web Audio: no sound files. When a bubble shows text
// the pet "babbles" a few soft syllables (pitch and rhythm follow the words, like animal
// chatter in games); reactions get small cues. With "Speak out loud" on, macOS reads the
// words instead (see `speaker`).

export type Voice = { pitch: number; wave: OscillatorType };
export type Cue = "poke" | "wave" | "celebrate" | "sad" | "alert" | "done" | "fail";

const BASE: Record<string, number> = { bunny: 640, cat: 720, fox: 560 };

/** A pet's voice: its species sets the register, its name nudges it so two cats differ. */
export function voiceFor(species: string, name: string): Voice {
  let hash = 0;
  for (const c of name) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  const nudge = 1 + ((hash % 17) - 8) / 100;
  return { pitch: (BASE[species] ?? 600) * nudge, wave: species === "fox" ? "sawtooth" : "triangle" };
}

/** The syllables a line babbles: one per word-ish chunk, a pitch step per vowel, at most 14. */
export function syllables(text: string): number[] {
  const steps: number[] = [];
  for (const word of text.toLowerCase().match(/[a-z0-9]+|[?!]/g) ?? []) {
    if (word === "?" || word === "!") {
      // A question ends rising, an exclamation jumps.
      if (steps.length) steps[steps.length - 1] += word === "?" ? 4 : 3;
      continue;
    }
    for (let i = 0; i < Math.max(1, Math.round(word.length / 3)); i++) {
      const c = word.charCodeAt(Math.min(word.length - 1, i * 3));
      steps.push((c % 7) - 3);
    }
  }
  return steps.slice(0, 14);
}

class Sound {
  enabled = true;
  /** 0..1 */
  volume = 0.6;
  /** Set when "Speak out loud" is on: reads the text instead of babbling it. */
  speaker: ((text: string, voice: Voice) => void) | null = null;
  private ctx: AudioContext | null = null;
  private out: GainNode | null = null;
  private busyUntil = 0;

  private context(): { ctx: AudioContext; out: GainNode } | null {
    if (!this.enabled || this.volume <= 0) return null;
    try {
      if (!this.ctx) {
        this.ctx = new AudioContext();
        this.out = this.ctx.createGain();
        // Soft and warm: no harsh edges from the oscillators.
        const filter = this.ctx.createBiquadFilter();
        filter.type = "lowpass";
        filter.frequency.value = 2400;
        this.out.connect(filter).connect(this.ctx.destination);
      }
      if (this.ctx.state === "suspended") void this.ctx.resume();
      this.out!.gain.value = 0.18 * this.volume;
      return { ctx: this.ctx, out: this.out! };
    } catch {
      return null;
    }
  }

  /** Call from a click: some web views only allow audio after the user did something. */
  unlock() {
    void this.context();
  }

  private blip(at: number, freq: number, length: number, wave: OscillatorType, glide = 1.04, level = 1) {
    const audio = this.context();
    if (!audio) return;
    const { ctx, out } = audio;
    const osc = ctx.createOscillator();
    const env = ctx.createGain();
    osc.type = wave;
    osc.frequency.setValueAtTime(freq, at);
    osc.frequency.exponentialRampToValueAtTime(freq * glide, at + length);
    env.gain.setValueAtTime(0, at);
    env.gain.linearRampToValueAtTime(level, at + 0.012);
    env.gain.exponentialRampToValueAtTime(0.001, at + length);
    osc.connect(env).connect(out);
    osc.start(at);
    osc.stop(at + length + 0.02);
  }

  /** A pet says something: babble, or read it aloud when speech is on. */
  say(text: string, voice: Voice) {
    if (!this.enabled) return;
    if (this.speaker) return this.speaker(text, voice);
    const audio = this.context();
    if (!audio) return;
    // Don't talk over the previous line.
    const start = Math.max(audio.ctx.currentTime + 0.02, this.busyUntil);
    const steps = syllables(text);
    steps.forEach((step, i) => {
      const freq = voice.pitch * Math.pow(2, step / 12);
      this.blip(start + i * 0.085, freq, 0.07, voice.wave, step > 2 ? 1.12 : 0.97, 0.8);
    });
    this.busyUntil = start + steps.length * 0.085;
  }

  cue(cue: Cue, voice: Voice) {
    const audio = this.context();
    if (!audio) return;
    const t = audio.ctx.currentTime + 0.01;
    const p = voice.pitch;
    const notes: Record<Cue, [number, number, number][]> = {
      // [delay, pitch multiple, length]
      poke: [[0, 1.5, 0.08]],
      wave: [[0, 1, 0.07], [0.08, 1.33, 0.1]],
      celebrate: [[0, 1, 0.08], [0.09, 1.26, 0.08], [0.18, 1.5, 0.08], [0.27, 2, 0.16]],
      sad: [[0, 1.2, 0.14], [0.15, 0.9, 0.22]],
      alert: [[0, 1.5, 0.07], [0.1, 1.5, 0.07]],
      done: [[0, 1.26, 0.08], [0.09, 1.68, 0.14]],
      fail: [[0, 0.8, 0.18]],
    };
    for (const [delay, multiple, length] of notes[cue]) this.blip(t + delay, p * multiple, length, voice.wave, cue === "sad" ? 0.94 : 1.03);
  }
}

export const sound = new Sound();
