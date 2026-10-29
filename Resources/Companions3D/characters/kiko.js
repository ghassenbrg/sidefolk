// Kiko: a chibi kid astronaut: warm brown skin, fluffy dark curls, a padded mustard spacesuit with
// a copper neck ring, plum gloves, knee pads, boots and backpack. Rig: blender/rig_kiko.py.
import { bodyMaterial } from '../engine/materials.js';
import { add } from '../engine/moves.js';

export default {
  id: 'kiko',
  name: 'Kiko',
  model: 'kiko.glb',
  floor: 0.952,
  pivot: [0, 0.45, 0],
  frame: { sidefolk: 2.3 },
  marks: [0.45, 0.62, 0.1],

  material: (body) => bodyMaterial(body, {
    params: { sheen: 0.5, sheenRoughness: 0.6, roughness: 0.7, clearcoat: 0.4, clearcoatRoughness: 0.3 },
    surface: `
      float lum = dot(s, vec3(0.3, 0.55, 0.15));
      // Skin: warm, saturated, light; around the face, ears, neck.
      float skin = smoothstep(0.08, 0.16, s.r - s.g) * smoothstep(0.02, 0.08, s.g - s.b) * smoothstep(0.42, 0.52, lum) * step(0.05, p.y);
      float hair = (1.0 - smoothstep(0.24, 0.36, lum)) * step(0.3, p.y);
      float suit = smoothstep(0.1, 0.2, s.g - s.b) * smoothstep(0.55, 0.65, lum) * (1.0 - skin);
      float plum = smoothstep(0.02, 0.08, s.b - s.g) * (1.0 - smoothstep(0.45, 0.6, lum));
      float copper = smoothstep(0.12, 0.22, s.r - s.b) * smoothstep(0.5, 0.65, s.r) * (1.0 - skin) * (1.0 - suit);
      // Meshy's colours came out pale: the suit goes back to mustard, the skin to warm brown.
      c = tex;
      c = mix(c, tex * vec3(1.02, 0.86, 0.52), suit);
      c = mix(c, tex * vec3(0.86, 0.68, 0.54), skin);
      float pad = tri(uPlush, p, nR, 7.0);
      bumpH = suit * pad * 0.006 + hair * tri(uPlush, p, nR, 12.0) * 0.003;
      rough = mix(0.82, 0.55, skin);
      rough = mix(rough, 0.5, hair);
      rough = mix(rough, 0.6, plum);
      rough = mix(rough, 0.28, copper);
      clear = copper + 0.4 * plum + 0.25 * skin;
      sheenTint = mix(vec3(0.0), vec3(1.0, 0.92, 0.75), suit) + hair * vec3(0.45, 0.32, 0.25);
      // Skin lets a little warm light through, so cheeks never look like painted plastic.
      inner = 0.6 + 0.6 * skin;
      glow = skin * vec3(0.045, 0.018, 0.01);`,
  }),

  face: {
    kind: 'ink',
    unwrap: { R: 0.34, span: 0.38, cy: 0.32 },
    region: (x, y, z) => z > 0.12 && y > 0.12 && y < 0.6,
    colors: { ink: '#2a1810', brow: '#33200f', blush: '240,110,100', lip: '#4a1f18', mouth: '#7a2a2a' },
    iris: { deep: [0.02, 0.008, 0.003], rim: [0.24, 0.11, 0.035], glow: [0.62, 0.33, 0.12], glowAmt: 0.4, pupil: 0.36 },
    layout: {
      eye: { x: 0.138, y: 0.335, w: 0.124, h: 0.162, depth: 0.036 },
      nose: { y: 0.258, w: 0.05, h: 0.03, shape: 'button', color: '#9a5a3a' },
      mouth: { y: 0.192, scale: 0.8 },
      brow: { base: 1, y: 0.44, len: 0.095, width: 12, arch: 8, tilt: -0.04 },
      blush: { x: 0.215, y: 0.245, w: 0.08, h: 0.05, alpha: 0.34 },
    },
  },

  chains: [],
  pick: { head: { r: 0.45, at: [0, 0.48, 0] }, body: { r: 0.3, at: [0, -0.4, 0] } },
  fidgets: ['lookAround', 'tilt', 'smile', 'stretch', 'hop', 'blinkDouble', 'giggle', 'scratch'],

  // Arms relaxed down from the modelled A-pose.
  stand(t, P) {
    add(P, 'armL', 0, -14, -40); add(P, 'armR', 0, 14, 40);
    add(P, 'handL', 0, -10, -4); add(P, 'handR', 0, 10, 4);
    add(P, 'thighL', 0, 5, 0); add(P, 'thighR', 0, -5, 0);
  },
};
