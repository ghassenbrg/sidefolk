// Ember: a chibi red fox on its hind legs: orange fur, cream muzzle and chest, dark brown paws,
// ear tips and brows, big amber eyes and a big fluffy tail. Rig: blender/rig_ember.py.
import { bodyMaterial } from '../engine/materials.js';
import { add, raise, lean, face } from '../engine/moves.js';
import { win, smooth } from '../engine/motion.js';

const ear = (s, side) => ({ bones: [`ear${s}1`, `ear${s}2`], side, twitch: true, k: [190, 135], d: [11, 7.5], limit: [40, 35] });

export default {
  id: 'ember',
  name: 'Ember',
  model: 'ember.glb',
  floor: 0.952,
  pivot: [0, 0.5, 0],
  frame: { sidefolk: 2.3 },
  marks: [0.45, 0.65, 0.15],
  blob: [1.3, 0.85],

  // Dense short fur: a stronger pile than Mochi's plush, warm sheen, light through the ears.
  material: (body) => bodyMaterial(body, {
    params: { sheenRoughness: 0.42, roughness: 0.86 },
    surface: `
      float lum = dot(s, vec3(0.3, 0.55, 0.15));
      float cream = smoothstep(0.62, 0.74, min(s.g, s.b) / max(s.r, 0.01)) * smoothstep(0.6, 0.75, lum);
      float darkF = 1.0 - smoothstep(0.26, 0.4, lum);
      float earM = smoothstep(0.56, 0.64, p.y) * step(0.12, abs(p.x));
      float pink = earM * smoothstep(0.03, 0.09, s.b - s.g) * (1.0 - darkF);
      c = tex * vec3(1.04, 0.98, 0.95);
      c = mix(c, vec3(0.97, 0.92, 0.85), cream * 0.55);
      float fur = tri(uPlush, p, nR, 5.2);
      bumpH = fur * 0.011 * (1.0 - 0.4 * darkF);
      c *= 0.97 + 0.05 * fur;
      rough = 0.86;
      // The sheen takes the fur's own colour: warm, never a grey film over the orange.
      sheenTint = mix(vec3(1.0), clamp(s * 1.35, 0.0, 1.0), 0.7 * (1.0 - cream));
      inner = 1.0 - 0.7 * darkF;
      glow = earM * (1.0 - darkF) * mix(vec3(0.05, 0.025, 0.012), vec3(0.1, 0.04, 0.045), pink);`,
  }),

  face: {
    kind: 'ink',
    unwrap: { R: 0.42, span: 0.4, cz: 0.12, cy: 0.15 },
    region: (x, y, z) => z > 0.2 && y > -0.15 && y < 0.52,
    colors: { ink: '#2b1a12', brow: '#4a2a1a', blush: '255,120,110', lip: '#3a1a12' },
    iris: { deep: [0.025, 0.008, 0.002], rim: [0.32, 0.13, 0.025], glow: [0.95, 0.5, 0.12], glowAmt: 0.55, pupil: 0.38 },
    layout: {
      eye: { x: 0.172, y: 0.268, w: 0.162, h: 0.19, depth: 0.042 },
      nose: { y: 0.118, w: 0.074, h: 0.05, shape: 'fox', color: '#2a1913' },
      mouth: { y: 0.04, scale: 0.85 },
      brow: { base: 0.95, y: 0.41, len: 0.105, width: 15, arch: 10, tilt: -0.06 },
      blush: { x: 0.29, y: 0.14, w: 0.09, h: 0.055, alpha: 0.32 },
    },
  },

  // Its own moment: chasing its own tail round and round, a little dizzy after.
  actions: {
    tailChase: {
      dur: 3.4,
      fn(t, P, fx) {
        fx.at(2.6, 'sweat');
        P.root.ry -= 720 * smooth((t - 0.3) / 2.2);
        const on = win(t, 0.2, 0.5, 2.3, 2.8);
        add(P, 'head', 8 * on, -55 * on, 0); add(P, 'chest', 6 * on, -20 * on, 0);
        P.root.py += 0.03 * Math.abs(Math.sin(t * 9)) * on;
        lean(P, 8 * on);
        for (const s of ['L', 'R']) raise(P, s, 25 * on);
        P.look *= 1 - on;
        face(P, { mood: t < 2.6 ? 'excited' : t < 3.1 ? 'dizzy' : 'giggle' });
      },
    },
  },
  moments: ['tailChase'],

  chains: [
    ear('L', 1), ear('R', -1),
    { bones: ['tail1', 'tail2', 'tail3'], side: -1, k: [80, 62, 48], d: [8, 6.5, 5], gain: 0.55, breeze: 0.7, wag: 9, limit: [35, 35], seed: 5 },
  ],
  pick: { head: { r: 0.5, at: [0, 0.27, 0.1] }, body: { r: 0.3, at: [0, -0.48, 0] }, tips: ['earL2', 'earR2'] },
  fidgets: ['lookAround', 'earTwitch', 'earTwitch', 'tilt', 'sniff', 'smile', 'stretch', 'hop', 'blinkDouble', 'giggle'],

  // The model stands in a T: arms come down to the sides, paws a little forward.
  stand(t, P) {
    add(P, 'armL', 0, -14, -62); add(P, 'armR', 0, 14, 62);
    add(P, 'handL', 0, 0, -10); add(P, 'handR', 0, 0, 10);
    add(P, 'chest', 2); add(P, 'thighL', 0, 6, 0); add(P, 'thighR', 0, -6, 0);
  },
};
