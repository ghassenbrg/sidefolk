// Folio, "the folded little wish": an origami character of thick coral paper with crimson inner
// folds, a cream corner folded over its roof, two paper fins and two folded feet; big dark eyes.
// Its body is card: it bends a little, as a whole. Sheet: companions-3d/references/folio-sheet.png.
// Rig: rig_folio.py.
import { bodyMaterial } from '../engine/materials.js';
import { add, POSTURES, raise, face } from '../engine/moves.js';
import { win } from '../engine/motion.js';

export default {
  id: 'folio',
  name: 'Folio',
  model: 'folio.glb',
  floor: 0.837,
  pivot: [0, 0.5, 0],
  frame: { sidefolk: 2.3, fullY: 1.0, tightY: 0.92 },
  marks: [0.55, 0.55, 0.12],
  blob: [1.4, 0.7],
  skip: ['sniff'],

  // Paper: matte, a fine fibre, a little light through it; folds shade only softly (the thin body
  // bakes very dark occlusion, so it counts for little).
  material: (body) => bodyMaterial(body, {
    params: { sheen: 0.35, sheenRoughness: 0.75, roughness: 0.9 },
    ao: [0.8, 0.75, 0.95],
    surface: `
      float lum = dot(s, vec3(0.3, 0.55, 0.15));
      float crimson = smoothstep(0.22, 0.34, s.r - s.g) * (1.0 - smoothstep(0.5, 0.62, lum));
      c = tex * vec3(1.04, 1.0, 0.98);
      c = mix(c, tex * vec3(0.95, 0.85, 0.88), crimson);
      float fibre = tri(uPlush, p, nR, 10.0);
      bumpH = fibre * 0.0035;
      c *= 0.98 + 0.04 * fibre;
      rough = 0.9;
      sheenTint = vec3(1.0, 0.92, 0.88);
      inner = 0.75;
      glow = c * vec3(0.03, 0.018, 0.015) * (1.0 - crimson);`,
  }),

  face: {
    kind: 'ink',
    // The face is a flat sheet: a far-off axis makes the unwrap nearly a plain projection.
    unwrap: { R: 2.0, span: 0.6, cz: -1.8, cy: -0.1 },
    region: (x, y, z) => z > 0.1 && Math.abs(x) < 0.62 && y > -0.55 && y < 0.35,
    colors: { ink: '#2c1a14', brow: '#3a221a', blush: '230,90,90', lip: '#5a1a22', mouth: '#9a2a36' },
    iris: { deep: [0.01, 0.005, 0.004], rim: [0.07, 0.035, 0.025], glow: [0.32, 0.15, 0.09], glowAmt: 0.18 },
    eyeForward: 1.6,
    layout: {
      eye: { x: 0.3, y: -0.01, w: 0.24, h: 0.3, depth: 0.05, sink: 0.25 },
      mouth: { y: -0.2, scale: 1.3 },
      brow: { base: 0, y: 0.17, len: 0.12, width: 10, arch: 8 },
      blush: { x: 0.44, y: -0.15, w: 0.12, h: 0.07, alpha: 0.35 },
    },
  },

  // Its own moment: flaps its paper fins and floats up like a sheet in a draught, then lands.
  actions: {
    flutter: {
      dur: 3.0,
      fn(t, P, fx) {
        fx.at(0.6, 'sparkle');
        const on = win(t, 0.1, 0.4, 2.2, 2.7);
        const flap = Math.sin(t * Math.PI * 2 * 3.2) * on;
        for (const s of ['L', 'R']) raise(P, s, 30 * on + 35 * flap);
        P.root.py += 0.2 * win(t, 0.3, 1.0, 1.8, 2.6);
        P.root.rz += 8 * Math.sin(t * 2.4) * on; P.root.rx -= 6 * on;
        P.squash *= 1 - 0.07 * win(t, 2.5, 2.6, 2.65, 2.85);
        face(P, { mood: 'excited' });
      },
    },
  },
  moments: ['flutter'],

  chains: [],
  pick: { head: { r: 0.5, at: [0, 0.25, 0] }, body: { r: 0.45, at: [0, -0.3, 0], bone: 'spine' } },
  fidgets: ['lookAround', 'tilt', 'smile', 'stretch', 'hop', 'blinkDouble', 'giggle', 'tilt'],

  // A flat card on its side would show only an edge: Folio rests sitting, leaning back to lie
  // and nodding forward to sleep.
  postures: {
    lie: (t, P) => { POSTURES.sit(t, P); P.root.rx -= 16; add(P, 'head', -6, 0, -6); add(P, 'armL', 0, 0, 20); add(P, 'armR', 0, 0, -20); },
    sleep: (t, P) => {
      POSTURES.sit(t, P); P.root.rz += 6;
      const br = Math.sin(t * Math.PI * 2 * 0.2);
      add(P, 'head', 12 + br * 2, 0, -8); add(P, 'chest', 6 + br * 2); P.squash *= 1 + br * 0.01;
    },
  },

  // Fins a little lower than modelled; feet slightly turned out.
  stand(t, P) {
    add(P, 'armL', 0, 0, -8); add(P, 'armR', 0, 0, 8);
    add(P, 'thighL', 0, 5, 0); add(P, 'thighR', 0, -5, 0);
  },
};
