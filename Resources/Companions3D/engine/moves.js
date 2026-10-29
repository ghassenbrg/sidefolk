// Mochi's moves, authored like an animator's blocking: anticipation, action, overshoot, settle.
// Each move writes deltas into a pose `P` (degrees, model axes) at time `t` seconds:
//   x = pitch (+ tips forward, toward the viewer), y = yaw (+ turns to Mochi's left),
//   z = roll (+ tilts the top toward Mochi's right). Arms: `raise(side)` lifts, `fwd(side)` swings
//   forward. Ears, scarf tag, tail and body squash also get springs on top, so they follow through.
import { curve, win, smooth, easeOutBack, noise } from './motion.js';

const S = { L: 1, R: -1 };
export const add = (P, bone, x = 0, y = 0, z = 0) => {
  const b = P.b[bone] || (P.b[bone] = [0, 0, 0]);
  b[0] += x; b[1] += y; b[2] += z;
};
const raise = (P, s, deg) => add(P, 'arm' + s, 0, 0, S[s] * deg);
const fwd = (P, s, deg) => add(P, 'arm' + s, 0, -S[s] * deg, 0);
const handBend = (P, s, deg) => add(P, 'hand' + s, 0, 0, S[s] * deg);
const ear = (P, s, pitch, splay = 0) => { // splay + leans the ear outward
  add(P, `ear${s}1`, pitch * 0.35, 0, -S[s] * splay * 0.5);
  add(P, `ear${s}2`, pitch * 0.35, 0, -S[s] * splay * 0.3);
  add(P, `ear${s}3`, pitch * 0.3, 0, -S[s] * splay * 0.2);
};
const ears = (P, pitch, splay = 0) => { ear(P, 'L', pitch, splay); ear(P, 'R', pitch, splay); };
const lean = (P, pitch, roll = 0) => { add(P, 'hips', pitch * 0.3, 0, roll * 0.3); add(P, 'spine', pitch * 0.35, 0, roll * 0.35); add(P, 'chest', pitch * 0.35, 0, roll * 0.35); };
const face = (P, f) => Object.assign(P.face, f);
const hopY = (t, t0, t1, h) => (t > t0 && t < t1) ? 4 * h * ((t - t0) / (t1 - t0)) * (1 - (t - t0) / (t1 - t0)) : 0;

const HAPPY = { mood: 'happy' };

/** One-shot moves. `dur` seconds; the engine fades each in and out around it. */
export const ACTIONS = {
  wave: {
    dur: 2.7,
    fn(t, P) {
      // Short arms vanish behind that big head when raised straight up, so (like the reference
      // render) the arm comes up *and forward*: the paw rises beside the cheek, in front of it.
      const up = curve([[0, -8], [0.22, -14], [0.52, 106], [0.64, 98], [2.05, 100], [2.5, 0], [2.7, 0]], t);
      const front = win(t, 0.15, 0.5, 2.05, 2.55);
      raise(P, 'R', up);
      fwd(P, 'R', 48 * front);
      add(P, 'armR', -25 * front);
      const w = win(t, 0.5, 0.65, 1.95, 2.15);
      handBend(P, 'R', Math.sin((t - 0.5) * Math.PI * 2 * 1.9) * 32 * w - 20 * front);
      raise(P, 'R', Math.sin((t - 0.5) * Math.PI * 2 * 1.9 - 0.6) * 9 * w);
      // The body answers: a lean away to balance, the head tilts toward the waving hand.
      lean(P, curve([[0, 0], [0.25, 3], [0.6, -2], [2.2, -2], [2.7, 0]], t), -5 * win(t, 0.3, 0.6, 2.0, 2.5));
      add(P, 'head', 0, 6 * win(t, 0.4, 0.8, 2.0, 2.5), 12 * win(t, 0.4, 0.8, 2.0, 2.5) + Math.sin(t * 6) * 2.5 * w);
      raise(P, 'L', 6 * w);
      ear(P, 'R', -6 * w, 8 * w); ear(P, 'L', 4 * w, 4 * w);
      P.squash *= 1 + 0.02 * Math.sin(t * Math.PI * 2 * 1.9) * w;
      if (t > 0.35 && t < 2.3) face(P, { mood: 'excited', wink: 0 });
    },
  },

  bow: {
    dur: 2.6,
    fn(t, P) {
      // Hands meet over the tummy, a small lift, then a deep bend from the hips that the head
      // finishes; held for a breath, then up with a little overshoot.
      // With a head this big, a polite bow is shallow: deeper and we'd only see the top of it.
      const bend = curve([[0, 0], [0.35, -4], [0.95, 36], [1.55, 38], [2.15, -4], [2.45, 1], [2.6, 0]], t);
      add(P, 'hips', bend * 0.4); add(P, 'spine', bend * 0.3); add(P, 'chest', bend * 0.2);
      add(P, 'head', bend * 0.3);
      const hands = win(t, 0.1, 0.5, 2.0, 2.45);
      for (const s of ['L', 'R']) { fwd(P, s, 55 * hands); raise(P, s, -22 * hands); handBend(P, s, -12 * hands); }
      ears(P, 22 * win(t, 0.6, 1.0, 1.6, 2.1));
      add(P, 'thighL', -bend * 0.08); add(P, 'thighR', -bend * 0.08);
      P.look *= 1 - win(t, 0.3, 0.8, 1.8, 2.3);
      if (t > 0.7 && t < 1.9) face(P, { mood: 'content' });
      else face(P, { mood: 'smile' });
    },
  },

  hop: {
    dur: 1.25,
    fn(t, P) {
      const crouch = curve([[0, 0], [0.24, 1], [0.32, -0.3], [0.78, -0.2], [0.86, 1], [1.05, -0.1], [1.25, 0]], t);
      P.root.py += hopY(t, 0.3, 0.84, 0.3) - 0.025 * Math.max(0, crouch);
      P.squash *= 1 - 0.13 * crouch;
      add(P, 'thighL', -16 * Math.max(0, crouch)); add(P, 'thighR', -16 * Math.max(0, crouch));
      add(P, 'footL', 16 * Math.max(0, crouch)); add(P, 'footR', 16 * Math.max(0, crouch));
      lean(P, 8 * Math.max(0, crouch));
      const air = win(t, 0.28, 0.4, 0.7, 0.84);
      for (const s of ['L', 'R']) raise(P, s, -14 * Math.max(0, crouch) + 48 * air);
      add(P, 'thighL', -22 * air); add(P, 'thighR', -22 * air);
      add(P, 'head', -6 * air);
      face(P, t > 0.25 && t < 0.95 ? { mood: 'excited' } : {});
    },
  },

  jump: {
    dur: 1.6,
    fn(t, P) {
      const crouch = curve([[0, 0], [0.32, 1], [0.4, -0.4], [1.12, -0.2], [1.2, 1.1], [1.42, -0.1], [1.6, 0]], t);
      P.root.py += hopY(t, 0.38, 1.18, 0.55) - 0.03 * Math.max(0, crouch);
      P.squash *= 1 - 0.15 * crouch;
      for (const s of ['L', 'R']) {
        add(P, 'thigh' + s, -20 * Math.max(0, crouch) - 30 * win(t, 0.45, 0.6, 0.95, 1.12));
        add(P, 'foot' + s, 20 * Math.max(0, crouch));
        raise(P, s, -18 * Math.max(0, crouch) + 92 * win(t, 0.38, 0.55, 1.0, 1.2)); fwd(P, s, 25 * win(t, 0.38, 0.55, 1.0, 1.2));
      }
      lean(P, 10 * Math.max(0, crouch) - 6 * win(t, 0.4, 0.6, 1.0, 1.15));
      face(P, t > 0.36 && t < 1.3 ? { mood: 'laugh' } : { mood: 'excited' });
    },
  },

  cheer: {
    dur: 3.0,
    fn(t, P, fx) {
      const beat = (t - 0.2) * 2.2;
      const on = win(t, 0, 0.25, 2.6, 3.0);
      const pump = (0.5 + 0.5 * Math.sin(beat * Math.PI * 2)) * on;
      for (const s of ['L', 'R']) { raise(P, s, (78 + 28 * pump) * on); handBend(P, s, 18 * pump); fwd(P, s, 22 * on); }
      P.root.py += Math.abs(Math.sin(beat * Math.PI)) * 0.09 * on;
      P.squash *= 1 + 0.05 * Math.sin(beat * Math.PI * 2) * on;
      add(P, 'head', -8 * on, 0, Math.sin(beat * Math.PI) * 8 * on);
      lean(P, -4 * on);
      ears(P, -6 * on, 10 * pump);
      face(P, { mood: 'laugh' });
      fx.at(0.4, 'sparkle'); fx.at(1.3, 'sparkle'); fx.at(2.0, 'star');
    },
  },

  dance: {
    dur: 6.4, loopable: true,
    fn(t, P, fx) {
      const bpm = 112, b = t * bpm / 60;           // beats
      const on = win(t, 0, 0.4, 6.0, 6.4);
      const bounce = Math.pow(Math.abs(Math.sin(b * Math.PI)), 1.5);
      P.root.py += bounce * 0.045 * on;
      P.squash *= 1 - 0.05 * (1 - bounce) * on;
      const sway = Math.sin(b * Math.PI / 2);      // side to side every two beats
      add(P, 'hips', 0, sway * 10 * on, sway * 9 * on);
      add(P, 'spine', 0, 0, -sway * 6 * on);
      add(P, 'chest', 0, -sway * 6 * on, -sway * 5 * on);
      add(P, 'head', 4 * bounce * on, sway * 8 * on, Math.sin(b * Math.PI / 2 + 0.8) * 12 * on);
      // Arms: alternate punches up, a twirl every second bar.
      const bar = Math.floor(b / 4) % 2;
      for (const s of ['L', 'R']) {
        const ph = s === 'L' ? 0 : Math.PI;
        const a = bar ? 60 + 55 * (0.5 + 0.5 * Math.sin(b * Math.PI + ph)) : 30 + 35 * Math.sin(b * Math.PI / 2 + ph);
        raise(P, s, a * on); fwd(P, s, 20 * on); handBend(P, s, 20 * Math.sin(b * Math.PI + ph) * on);
        add(P, 'thigh' + s, -14 * Math.max(0, Math.sin(b * Math.PI / 2 + ph)) * on);
      }
      ears(P, 0, 8 * sway * on);
      face(P, { mood: (b % 8) > 6 ? 'laugh' : 'excited' });
      for (let k = 1; k < 6; k += 1.5) fx.at(k, 'note');
    },
  },

  nod: {
    dur: 1.3,
    fn(t, P) {
      add(P, 'head', curve([[0, 0], [0.18, 16], [0.42, -3], [0.62, 13], [0.88, -2], [1.1, 1], [1.3, 0]], t));
      add(P, 'chest', curve([[0, 0], [0.2, 3], [0.65, 2.5], [1.3, 0]], t));
      face(P, { mood: 'smile' });
    },
  },

  shake: {
    dur: 1.4,
    fn(t, P) {
      add(P, 'head', 4 * win(t, 0, 0.2, 1.1, 1.4), Math.sin(t * Math.PI * 2 * 2.4) * 22 * win(t, 0, 0.1, 0.8, 1.4), 0);
      add(P, 'chest', 0, Math.sin(t * Math.PI * 2 * 2.4 - 0.5) * 5 * win(t, 0, 0.1, 0.8, 1.4), 0);
      face(P, { mood: 'pout' });
    },
  },

  giggle: {
    dur: 1.9,
    fn(t, P) {
      const on = win(t, 0, 0.15, 1.5, 1.9);
      const shake = Math.sin(t * Math.PI * 2 * 7) * on;
      add(P, 'chest', 3 * on + shake * 2, 0, shake * 3);
      add(P, 'head', 8 * on, 0, 10 * on + shake * 2);
      for (const s of ['L', 'R']) { fwd(P, s, 60 * on); raise(P, s, 35 * on); handBend(P, s, 30 * on); }
      P.root.py += Math.abs(shake) * 0.01;
      ears(P, 4 * on, 6 * on);
      face(P, { mood: 'giggle' });
    },
  },

  flip: {
    dur: 1.8,
    fn(t, P) {
      const crouch = curve([[0, 0], [0.3, 1], [0.38, -0.4], [1.3, -0.3], [1.4, 1.1], [1.62, -0.1], [1.8, 0]], t);
      P.root.py += hopY(t, 0.36, 1.38, 0.75) - 0.03 * Math.max(0, crouch);
      P.squash *= 1 - 0.14 * crouch;
      const spin = smooth((t - 0.45) / 0.8);
      P.root.rx -= 360 * spin;              // a backflip
      for (const s of ['L', 'R']) {
        add(P, 'thigh' + s, -60 * win(t, 0.45, 0.6, 1.1, 1.3)); add(P, 'foot' + s, 30 * win(t, 0.45, 0.6, 1.1, 1.3));
        raise(P, s, 90 * win(t, 0.36, 0.5, 1.1, 1.35) - 15 * Math.max(0, crouch));
      }
      face(P, { mood: t < 1.35 ? 'excited' : 'laugh' });
    },
  },

  lookAround: {
    dur: 3.4,
    fn(t, P) {
      const yaw = curve([[0, 0], [0.5, -38], [1.3, -36], [1.8, 34], [2.6, 32], [3.1, 0], [3.4, 0]], t);
      add(P, 'head', 0, yaw, -yaw * 0.12);
      add(P, 'chest', 0, yaw * 0.2, 0);
      P.gaze = [yaw / 40 * 0.9, 0.1];
      P.look *= 0.2;
      ear(P, yaw > 0 ? 'L' : 'R', -8 * Math.abs(yaw) / 38, 6);
      face(P, { mood: 'curious' });
    },
  },

  think: {
    dur: 4.0, loopable: true,
    fn(t, P, fx) {
      const on = win(t, 0, 0.6, 3.5, 4.0);
      fwd(P, 'R', 72 * on); raise(P, 'R', 48 * on); handBend(P, 'R', 40 * on);
      raise(P, 'L', -10 * on); fwd(P, 'L', 30 * on);
      add(P, 'head', -10 * on, 10 * on, -12 * on + noise(t, 3) * 3);
      lean(P, 0, 3 * on);
      ear(P, 'L', 0, 10 * on); ear(P, 'R', 10 * on, -4 * on);
      P.gaze = [0.55, 0.65];
      P.look *= 0.15;
      face(P, { mood: 'thinking' });
      fx.at(1.0, 'dots');
    },
  },

  shy: {
    dur: 3.0,
    fn(t, P) {
      const on = win(t, 0, 0.5, 2.5, 3.0);
      for (const s of ['L', 'R']) { fwd(P, s, 52 * on); raise(P, s, -26 * on); handBend(P, s, -20 * on); }
      add(P, 'head', 14 * on, -12 * on, 12 * on);
      lean(P, 4 * on, Math.sin(t * 2.4) * 4 * on);
      ears(P, 28 * on, -6 * on);
      P.gaze = [-0.6, -0.5]; P.look *= 1 - on;
      face(P, { mood: 'shy' });
    },
  },

  yawn: {
    dur: 3.4,
    fn(t, P) {
      const st = win(t, 0.2, 1.0, 2.2, 3.0);
      for (const s of ['L', 'R']) { raise(P, s, 98 * st); fwd(P, s, 28 * st); handBend(P, s, 25 * st); }
      lean(P, -10 * st);
      add(P, 'head', -14 * st);
      P.squash *= 1 + 0.06 * st;
      ears(P, -10 * st, -8 * st);
      face(P, t > 0.3 && t < 2.6 ? { mood: 'yawn' } : { mood: 'sleepy' });
    },
  },

  love: {
    dur: 3.0,
    fn(t, P, fx) {
      const on = win(t, 0, 0.45, 2.5, 3.0);
      for (const s of ['L', 'R']) { fwd(P, s, 70 * on); raise(P, s, 85 * on); handBend(P, s, 40 * on); }
      add(P, 'head', 4 * on, 0, Math.sin(t * 3.4) * 10 * on);
      lean(P, 0, Math.sin(t * 3.4) * 5 * on);
      ears(P, 6 * on, -8 * on);
      face(P, { mood: 'love' });
      fx.at(0.5, 'heart'); fx.at(1.3, 'heart'); fx.at(2.0, 'heart');
    },
  },

  surprised: {
    dur: 1.6,
    fn(t, P, fx) {
      const jolt = curve([[0, 0], [0.08, 1], [0.35, 0.7], [1.2, 0.5], [1.6, 0]], t);
      P.root.py += hopY(t, 0.02, 0.32, 0.07);
      P.squash *= 1 + 0.08 * curve([[0, 0], [0.06, 1], [0.2, -0.4], [0.4, 0.1], [0.6, 0]], t);
      for (const s of ['L', 'R']) raise(P, s, 40 * jolt);
      lean(P, -6 * jolt); add(P, 'head', -8 * jolt);
      ears(P, -10 * jolt, -8 * jolt);
      face(P, { mood: 'surprised' });
      fx.at(0.05, 'bang');
    },
  },

  sad: {
    dur: 3.4,
    fn(t, P) {
      const on = win(t, 0, 0.8, 2.8, 3.4);
      lean(P, 10 * on); add(P, 'head', 16 * on, 0, 6 * on);
      for (const s of ['L', 'R']) { raise(P, s, -28 * on); fwd(P, s, 12 * on); }
      ears(P, 36 * on, 22 * on);
      P.squash *= 1 - 0.03 * on;
      P.look *= 1 - 0.7 * on;
      face(P, { mood: 'sad' });
    },
  },

  angry: {
    dur: 2.2,
    fn(t, P) {
      const on = win(t, 0, 0.2, 1.8, 2.2);
      const stomp = curve([[0, 0], [0.35, 1], [0.5, -0.3], [0.62, 0], [1.0, 1], [1.12, -0.3], [1.25, 0]], t);
      add(P, 'thighL', -30 * Math.max(0, stomp)); add(P, 'footL', 10 * Math.max(0, stomp));
      P.squash *= 1 + 0.05 * Math.min(0, stomp) * 2;
      for (const s of ['L', 'R']) { raise(P, s, -30 * on); fwd(P, s, -12 * on); handBend(P, s, -10 * on); }
      add(P, 'head', 6 * on);
      ears(P, -30 * on, 6 * on);
      face(P, { mood: 'angry' });
    },
  },

  dizzy: {
    dur: 3.0,
    fn(t, P, fx) {
      const on = win(t, 0, 0.3, 2.4, 3.0);
      const a = t * Math.PI * 2 * 0.9;
      add(P, 'head', Math.sin(a) * 10 * on, 0, Math.cos(a) * 12 * on);
      lean(P, Math.sin(a + 1) * 5 * on, Math.cos(a + 1) * 6 * on);
      ears(P, 0, Math.sin(a * 2) * 10 * on);
      face(P, { mood: 'dizzy' });
      fx.at(0.3, 'star'); fx.at(1.2, 'star');
    },
  },

  wince: {
    dur: 1.1,
    fn(t, P) {
      const on = curve([[0, 0], [0.08, 1], [0.6, 0.8], [1.1, 0]], t);
      P.squash *= 1 - 0.07 * on;
      add(P, 'head', 10 * on, 0, 6 * on);
      for (const s of ['L', 'R']) { raise(P, s, 25 * on); fwd(P, s, 40 * on); }
      ears(P, 20 * on, -10 * on);
      face(P, { mood: 'wince' });
    },
  },

  sniff: {
    dur: 1.8,
    fn(t, P) {
      const on = win(t, 0, 0.2, 1.4, 1.8);
      const pulse = Math.max(0, Math.sin(t * Math.PI * 2 * 3.2));
      add(P, 'head', (6 + 3 * pulse) * on, 0, 5 * on);
      lean(P, 5 * on);
      ears(P, -6 * on);
      face(P, { mood: 'curious', noseTwitch: pulse * on });
    },
  },

  boop: {
    dur: 1.0,
    fn(t, P) {
      const hit = curve([[0, 0], [0.06, 1], [0.2, -0.5], [0.38, 0.2], [0.55, 0], [1.0, 0]], t);
      P.squash *= 1 - 0.1 * hit;
      add(P, 'head', -10 * Math.max(0, hit), 0, 0);
      ears(P, -12 * hit);
      face(P, { mood: t < 0.7 ? 'giggle' : 'happy' });
    },
  },

  stretch: {
    dur: 3.0,
    fn(t, P) {
      const st = win(t, 0.1, 0.9, 1.8, 2.7);
      for (const s of ['L', 'R']) { raise(P, s, 100 * st); fwd(P, s, 22 * st); handBend(P, s, 25 * st); }
      add(P, 'chest', -8 * st, 0, Math.sin(t * 2) * 6 * st); add(P, 'head', -8 * st);
      P.squash *= 1 + 0.08 * st;
      face(P, { mood: 'content' });
    },
  },

  celebrate: { dur: 3.0, fn(t, P, fx) { ACTIONS.cheer.fn(t, P, fx); P.root.ry += 360 * smooth((t - 0.9) / 1.1); } },

  scratch: {
    dur: 2.4,
    fn(t, P) {
      // A paw up to the back of the head, a few scratches, a sheepish smile.
      const on = win(t, 0, 0.35, 1.9, 2.4);
      fwd(P, 'L', 35 * on); raise(P, 'L', 92 * on); handBend(P, 'L', 30 * on + Math.sin(t * 22) * 12 * win(t, 0.4, 0.5, 1.6, 1.8));
      add(P, 'head', 6 * on, -8 * on, -12 * on);
      ear(P, 'L', -10 * on, 8 * on);
      face(P, { mood: 'oops' });
    },
  },

  sneeze: {
    dur: 2.0,
    fn(t, P, fx) {
      // "A… a…" head back, eyes squeezing, then "choo!": a snap forward, squash, ears flung.
      const build = curve([[0, 0], [0.3, 0.4], [0.7, 0.6], [0.95, 1], [1.02, -1.2], [1.25, -0.6], [1.6, 0], [2.0, 0]], t);
      add(P, 'head', -14 * build); lean(P, -6 * build);
      P.squash *= 1 + 0.05 * build;
      ears(P, 12 * Math.min(0, build), -8 * build);
      face(P, t < 0.95 ? { mood: 'wince', mouthOpen: 0.3 * build, mouthRound: 1, giddy: 0 } : t < 1.4 ? { mood: 'wince' } : { mood: 'oops' });
      fx.at(1.0, 'sweat');
    },
  },

  breathe: {
    dur: 11.5,
    fn(t, P) {
      // One slow breath with the person: in for four seconds, hold one, out for six.
      const b = curve([[0, 0], [0.4, 0], [4.4, 1], [5.4, 1], [11.0, 0], [11.5, 0]], t);
      add(P, 'chest', -6 * b); add(P, 'head', -4 * b);
      for (const s of ['L', 'R']) { raise(P, s, 10 * b); fwd(P, s, -6 * b); }
      ears(P, -6 * b, -4 * b);
      P.squash *= 1 + 0.035 * b;
      face(P, { mood: 'content' });
    },
  },

  peek: {
    dur: 2.6,
    fn(t, P) {
      const on = win(t, 0, 0.4, 2.0, 2.6);
      lean(P, 6 * on, 14 * on); add(P, 'head', 4 * on, 0, 10 * on);
      ear(P, 'L', -10 * on, 10 * on);
      P.gaze = [0.8, -0.1]; P.look *= 1 - on;
      face(P, { mood: 'curious' });
    },
  },
};

/** Repeating activities for Sidefolk's states (on top of a posture and idle life). */
export const LOOPS = {
  idle: (t, P) => {},

  listening: (t, P) => {
    add(P, 'head', 4, 0, 9 + noise(t * 0.7, 2) * 3);
    lean(P, 3);
    ears(P, -8, -6);
    if ((t % 5.5) < 1) add(P, 'head', Math.sin((t % 5.5) * Math.PI * 2) * 6);
    P.face.mood = 'attentive';
  },

  hearing: (t, P) => {
    // Ears straight up, a paw cupped by the head, eyes wide: "I'm listening!"
    ears(P, -14, -14);
    fwd(P, 'L', 40); raise(P, 'L', 105); handBend(P, 'L', 35);
    add(P, 'head', 0, 6, -10);
    P.face.mood = 'attentive';
  },

  thinking: (t, P, fx) => ACTIONS.think.fn(0.6 + (t % 2.9), P, fx),

  working: (t, P, fx) => {
    // Typing on an invisible keyboard: paws tapping in turn, head down and focused.
    for (const s of ['L', 'R']) {
      fwd(P, s, 62); raise(P, s, -18);
      const tap = Math.max(0, Math.sin(t * Math.PI * 2 * 3.4 + (s === 'L' ? 0 : 2.2)));
      handBend(P, s, -14 * tap); raise(P, s, -6 * tap);
    }
    add(P, 'head', 14 + Math.sin(t * 1.3) * 2, Math.sin(t * 0.5) * 6, 0);
    lean(P, 6);
    P.gaze = [Math.sin(t * 0.9) * 0.35, -0.65];
    P.look *= 0.1;
    P.face.mood = 'focused';
    if (t % 6 > 5.6) add(P, 'head', -6);
  },

  waiting: (t, P) => {
    const tap = Math.max(0, Math.sin(t * Math.PI * 2 * 1.6));
    add(P, 'footR', -16 * tap);
    add(P, 'hips', 0, 0, Math.sin(t * 0.8) * 3);
    for (const s of ['L', 'R']) { fwd(P, s, -20); raise(P, s, -24); }   // paws behind its back
    add(P, 'head', 0, Math.sin(t * 0.45) * 20, Math.sin(t * 0.3) * 5);
    P.face.mood = 'smile';
  },

  alert: (t, P) => {
    ears(P, -16, -10);
    add(P, 'head', -4, Math.sin(t * 2.2) * 10, 0);
    for (const s of ['L', 'R']) raise(P, s, 20);
    P.face.mood = 'surprised';
  },

  dragging: (t, P) => {
    // Held up: legs dangle and paddle, arms flail a little, ears stream.
    for (const s of ['L', 'R']) {
      const ph = s === 'L' ? 0 : Math.PI;
      add(P, 'thigh' + s, Math.sin(t * 5 + ph) * 25);
      add(P, 'foot' + s, Math.sin(t * 5 + ph + 0.6) * 15);
      raise(P, s, 55 + Math.sin(t * 6 + ph) * 25);
    }
    P.root.rz += Math.sin(t * 2.4) * 6;
    ears(P, 10, 12);
    P.face.mood = 'excited';
  },

  celebrating: (t, P, fx) => ACTIONS.dance.fn(0.5 + (t % 5.4), P, fx),

  error: (t, P, fx) => {
    add(P, 'head', 8, Math.sin(t * 0.8) * 5, 10);
    for (const s of ['L', 'R']) { raise(P, s, -24); fwd(P, s, 20); }
    fwd(P, 'R', 50); raise(P, 'R', 85); handBend(P, 'R', 35);   // paw scratching the back of the head
    add(P, 'handR', 0, 0, Math.sin(t * 9) * 10);
    ears(P, 30, 18);
    P.face.mood = 'oops';
    fx.at(0.3, 'sweat');
  },

  success: (t, P) => {
    add(P, 'head', -4, 0, Math.sin(t * 2) * 6);
    for (const s of ['L', 'R']) raise(P, s, 10);
    P.face.mood = 'happy';
  },
};

/** Whole-body postures: where the body rests. Blended by springs, so changes are gradual. */
export const POSTURES = {
  stand: () => {},

  sit: (t, P) => {
    P.root.py -= 0.13;
    for (const s of ['L', 'R']) {
      add(P, 'thigh' + s, -84, 0, -S[s] * 8);
      add(P, 'foot' + s, 52);
      raise(P, s, -22); fwd(P, s, 34); handBend(P, s, -10);
    }
    add(P, 'hips', -6); add(P, 'spine', 2); add(P, 'chest', 2); add(P, 'head', 2);
  },

  // Lying on its side facing you (the sheet's "Lie Down (Side)"): from the front the whole body
  // reads, where lying on the tummy would hide it behind the head. Head lifted to watch you,
  // a foot swinging lazily.
  lie: (t, P) => {
    Object.assign(P.root, { rz: P.root.rz + 90, py: P.root.py - 0.17, px: P.root.px + 0.32 });
    add(P, 'head', 0, 0, -32);
    add(P, 'chest', 0, 0, -6);
    for (const s of ['L', 'R']) {
      add(P, 'arm' + s, 0, -S[s] * 60, S[s] * -20);
      add(P, 'thigh' + s, -50, 0, 0); add(P, 'foot' + s, 35);
    }
    add(P, 'thighL', 14 * Math.sin(t * 1.3), 0, 0); add(P, 'footL', 18 * Math.sin(t * 1.3 - 0.7));
    for (const s of ['L', 'R']) for (const i of [1, 2, 3]) add(P, `ear${s}${i}`, 0, 0, 14);
  },

  // Asleep curled on its side, cheek on the floor, paws tucked under its chin, ears spilled out.
  sleep: (t, P) => {
    Object.assign(P.root, { rz: P.root.rz + 90, py: P.root.py - 0.18, px: P.root.px + 0.32 });
    add(P, 'head', 6, 0, -12);
    add(P, 'chest', 6, 0, -4); add(P, 'spine', 6);
    for (const s of ['L', 'R']) {
      add(P, 'arm' + s, 0, -S[s] * 72, 0); handBend(P, s, -20);
      add(P, 'thigh' + s, -62, 0, 0); add(P, 'foot' + s, 40);
    }
    for (const s of ['L', 'R']) for (const i of [1, 2, 3]) add(P, `ear${s}${i}`, 4, 0, 18 + (s === 'L' ? 6 : 0));
    const br = Math.sin(t * Math.PI * 2 * 0.2);
    add(P, 'chest', br * 3); add(P, 'head', -br * 1.5); P.squash *= 1 + br * 0.014;
  },
};

export { HAPPY };
