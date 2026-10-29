// Nimbo: a floating lavender cloud with a warm glow in its face, a golden star clip and two little
// cloud puffs for hands. It never touches the ground: it hovers and bobs above its shadow, and
// sits, lies and sleeps as a cloud does (settling lower, tipping, drifting). Shaped after the
// founder's sheet (companions-3d/references/nimbo-sheet-v2.webp): a wide cloud, the face low in it.
// Rig: rig_nimbo.py.
import { bodyMaterial } from '../engine/materials.js';
import { add, face } from '../engine/moves.js';
import { win, smooth } from '../engine/motion.js';

export default {
  id: 'nimbo',
  name: 'Nimbo',
  model: 'nimbo.glb',
  floor: 0.671,
  pivot: [0, 0.45, 0],
  limbScale: 0.45,
  frame: { sidefolk: 2.3, full: 2.75, fullY: 0.9, tightY: 0.85 },
  marks: [0.6, 0.5, 0.15],
  blob: [1.8, 0.8],
  skip: ['sniff', 'scratch'],

  material: (body) => bodyMaterial(body, {
    params: { sheenRoughness: 0.32, roughness: 0.92 },
    surface: `
      float gold = smoothstep(0.12, 0.22, s.r - s.b) * smoothstep(0.05, 0.12, s.g - s.b) * step(0.3, p.y);
      float peach = smoothstep(0.0, 0.08, s.r - s.b) * (1.0 - gold);
      // The sheet's colours: a clear lavender, warm cream-peach in the face, a golden star.
      vec3 lav = tex * vec3(0.93, 0.92, 1.05);
      c = mix(lav, tex * vec3(1.04, 0.97, 0.9), peach);
      c = mix(c, vec3(0.95, 0.72, 0.28), gold);
      float puff = tri(uPlush, p, nR, 6.0);
      bumpH = puff * 0.006 * (1.0 - gold);
      rough = mix(0.92, 0.25, gold);
      clear = gold;
      sheenTint = mix(vec3(1.0, 0.97, 1.0), vec3(0.0), gold);
      inner = 1.2 * (1.0 - gold);
      // The warm light in its middle, and a soft lavender glow all over: a cloud lit from within.
      glow = peach * vec3(0.11, 0.07, 0.035) + (1.0 - gold) * vec3(0.012, 0.01, 0.024) + gold * vec3(0.05, 0.035, 0.0);`,
  }),

  face: {
    kind: 'ink',
    // The front of the cloud is nearly flat: a wide unwrap.
    unwrap: { R: 0.9, span: 0.45, cy: -0.15 },
    region: (x, y, z) => z > 0.2 && Math.abs(x) < 0.62 && y > -0.52 && y < 0.25,
    lift: 0.004,
    colors: { ink: '#3a2a66', brow: '#6a58a0', blush: '255,130,160', lip: '#5a2040' },
    iris: { deep: [0.02, 0.006, 0.04], rim: [0.16, 0.07, 0.28], glow: [0.5, 0.32, 0.9], glowAmt: 0.5, pupil: 0.34 },
    eyeForward: 1.4,
    layout: {
      eye: { x: 0.26, y: -0.12, w: 0.17, h: 0.23, depth: 0.05, sink: 0.3 },
      mouth: { y: -0.3, scale: 1.6 },
      brow: { base: 0.85, y: 0.03, len: 0.1, width: 10, arch: 14, tilt: 0.15 },
      blush: { x: 0.38, y: -0.25, w: 0.11, h: 0.065, alpha: 0.45 },
    },
  },

  // Its own moment: a barrel roll in the air, a puff of joy.
  actions: {
    barrelRoll: {
      dur: 2.8,
      fn(t, P) {
        const roll = 360 * smooth((t - 0.5) / 1.5);
        P.root.rz -= roll;
        P.root.py += 0.18 * win(t, 0.2, 0.7, 1.9, 2.5);
        P.squash *= 1 + 0.05 * Math.sin(t * 6) * win(t, 0.3, 0.5, 2.1, 2.4);
        face(P, { mood: t > 0.6 && t < 2.0 ? 'laugh' : 'happy' });
      },
    },
  },
  moments: ['barrelRoll'],

  chains: [],
  pick: { head: { r: 0.62, at: [0, 0, 0] }, body: { r: 0.45, at: [0, -0.35, 0], bone: 'spine' }, tips: ['handL', 'handR'], tipR: 0.17 },
  fidgets: ['lookAround', 'tilt', 'smile', 'stretch', 'hop', 'blinkDouble', 'giggle', 'tilt'],

  /** Hovering: a slow bob and a little drift; lower and stiller when resting. */
  hover(t, lying) {
    return 0.14 - 0.08 * lying + (0.035 - 0.02 * lying) * Math.sin(t * 1.55) + 0.01 * Math.sin(t * 0.61 + 1);
  },
  life(t, P, live) {
    // A cloud breathes by swelling, and its puffs drift on their own.
    P.squash *= 1 + 0.012 * Math.sin(t * 1.55 + 0.6) * live;
    add(P, 'handL', 0, 0, Math.sin(t * 1.3) * 5 * live); add(P, 'handR', 0, 0, Math.sin(t * 1.1 + 2) * 5 * live);
    P.root.rz += Math.sin(t * 0.5) * 2 * live;
  },

  postures: {
    // Settles lower, a little squashed, puffs resting in front.
    sit: (t, P) => { P.root.py -= 0.07; P.squash *= 0.95; add(P, 'head', 4); },
    // Tips over a little, like a cloud resting its cheek on the air.
    lie: (t, P) => { P.root.rz += 18; P.root.py -= 0.04; add(P, 'head', 0, 0, -8); P.squash *= 0.96; },
    sleep: (t, P) => {
      P.root.rz += 14; P.root.py -= 0.06; add(P, 'head', 6, 0, -10);
      const br = Math.sin(t * Math.PI * 2 * 0.2);
      P.squash *= 0.94 + br * 0.02;
    },
  },
};
