// Nimbo: a floating lavender cloud with a warm glow in its face, a golden star clip and two little
// cloud puffs for hands. It never touches the ground: it hovers and bobs above its shadow, and
// sits, lies and sleeps as a cloud does (settling lower, tipping, drifting). Rig: rig_nimbo.py.
import { bodyMaterial } from '../engine/materials.js';
import { add } from '../engine/moves.js';

export default {
  id: 'nimbo',
  name: 'Nimbo',
  model: 'nimbo.glb',
  floor: 0.831,
  pivot: [0, 0.6, 0],
  frame: { sidefolk: 2.3, full: 2.75, fullY: 1.0, tightY: 0.95 },
  marks: [0.6, 0.6, 0.15],
  blob: [1.7, 0.95],
  skip: ['sniff', 'scratch'],

  material: (body) => bodyMaterial(body, {
    params: { sheenRoughness: 0.32, roughness: 0.92 },
    surface: `
      float gold = smoothstep(0.12, 0.22, s.r - s.b) * smoothstep(0.05, 0.12, s.g - s.b) * step(0.3, p.y);
      float peach = smoothstep(0.0, 0.06, s.r - s.b) * (1.0 - gold);
      c = mix(tex * vec3(0.98, 0.98, 1.03), vec3(0.95, 0.72, 0.28), gold);
      float puff = tri(uPlush, p, nR, 6.0);
      bumpH = puff * 0.014 * (1.0 - gold);
      rough = mix(0.92, 0.25, gold);
      clear = gold;
      sheenTint = mix(vec3(1.0, 0.97, 1.0), vec3(0.0), gold);
      inner = 1.2 * (1.0 - gold);
      // The warm light in its middle, and a soft lavender glow all over: a cloud lit from within.
      glow = peach * vec3(0.09, 0.055, 0.03) + (1.0 - gold) * vec3(0.012, 0.01, 0.022) + gold * vec3(0.05, 0.035, 0.0);`,
  }),

  face: {
    kind: 'ink',
    unwrap: { R: 0.62, span: 0.42, cy: 0.04 },
    region: (x, y, z) => z > 0.32 && y > -0.34 && y < 0.44,
    lift: 0.004,
    colors: { ink: '#3a2a66', brow: '#6a58a0', blush: '255,130,160', lip: '#5a2040' },
    iris: { deep: [0.02, 0.006, 0.04], rim: [0.16, 0.07, 0.28], glow: [0.5, 0.32, 0.9], glowAmt: 0.5, pupil: 0.34 },
    eyeForward: 1.4,
    layout: {
      eye: { x: 0.2, y: 0.07, w: 0.19, h: 0.235, depth: 0.05, sink: 0.3 },
      mouth: { y: -0.125, scale: 1.45 },
      brow: { base: 0.85, y: 0.25, len: 0.1, width: 10, arch: 12, tilt: 0.12 },
      blush: { x: 0.33, y: -0.08, w: 0.12, h: 0.07, alpha: 0.45 },
    },
  },

  chains: [],
  pick: { head: { r: 0.72, at: [0, 0.05, 0] }, body: { r: 0.5, at: [0, -0.45, 0], bone: 'spine' }, tips: ['handL', 'handR'], tipR: 0.2 },
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
