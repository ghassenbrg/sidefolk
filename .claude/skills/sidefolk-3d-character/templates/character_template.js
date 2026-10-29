// <Name>: <one line from the sheet: body, colours, materials, face>.
// Sheet: companions-3d/references/<id>-sheet.png. Rig: blender/rig_<id>.py.
//
// Template from the sidefolk-3d-character skill. Coordinates are three.js model units: x = its
// left, y up, z toward the viewer (Blender z is y here, Blender -y is z). Replace every number
// with what you measured on the model and the sheet; drop what this body doesn't have.
import { bodyMaterial } from '../engine/materials.js';
import { add } from '../engine/moves.js';

const ear = (s, side) => ({ bones: [`ear${s}1`, `ear${s}2`], side, twitch: true, k: [190, 135], d: [11, 7.5], limit: [40, 35] });

export default {
  id: 'name',
  name: 'Name',
  model: 'name.glb',
  floor: 0.952,                 // how far the soles sit below the model's origin
  pivot: [0, 0.5, 0],           // whole-body turns (lying down, flips) happen about here
  frame: { sidefolk: 2.3 },     // model units the app's window shows from floor to top (with margin)
  marks: [0.45, 0.6, 0.15],     // where zZz, ?, ! appear, from the head
  blob: [1.2, 0.8],             // contact shadow size

  // Classify Meshy's texture into clean colour zones; keep relief subtle.
  material: (body) => bodyMaterial(body, {
    params: { sheenRoughness: 0.5, roughness: 0.82 },
    surface: `
      float lum = dot(s, vec3(0.3, 0.55, 0.15));
      float dark = 1.0 - smoothstep(0.26, 0.4, lum);
      c = tex;
      float fine = tri(uPlush, p, nR, 6.0);
      bumpH = fine * 0.008;
      rough = 0.82;
      inner = 1.0 - 0.6 * dark;`,
  }),

  face: {
    kind: 'ink',
    // R: distance from the head's vertical axis to the face (a flat face: a far axis, R 2, cz -1.8).
    unwrap: { R: 0.42, span: 0.4, cz: 0.1, cy: 0.2 },
    region: (x, y, z) => z > 0.2 && y > -0.1 && y < 0.55,
    colors: { ink: '#2b1a12', brow: '#3a2418', blush: '255,130,140' },
    iris: { deep: [0.02, 0.01, 0.005], rim: [0.25, 0.12, 0.04], glow: [0.7, 0.4, 0.15], glowAmt: 0.4, pupil: 0.36 },
    layout: {
      eye: { x: 0.17, y: 0.27, w: 0.15, h: 0.18, depth: 0.04 },
      nose: { y: 0.12, w: 0.06, h: 0.04 },           // shape: 'fox' | 'button' | (bean)
      mouth: { y: 0.04, scale: 0.9 },                  // always below the nose, with a gap
      brow: { base: 0, y: 0.41, len: 0.1, width: 12, arch: 10 },   // base 1: always shown
      blush: { x: 0.29, y: 0.14, w: 0.09, h: 0.055, alpha: 0.35 },
    },
  },

  chains: [ear('L', 1), ear('R', -1)],
  pick: { head: { r: 0.5, at: [0, 0.27, 0.1] }, body: { r: 0.3, at: [0, -0.48, 0] }, tips: ['earL2', 'earR2'] },
  fidgets: ['lookAround', 'earTwitch', 'tilt', 'smile', 'stretch', 'hop', 'blinkDouble', 'giggle'],

  // From the modelled A-pose to relaxed: arms down to the sides.
  stand(t, P) {
    add(P, 'armL', 0, -10, -40); add(P, 'armR', 0, 10, 40);
    add(P, 'thighL', 0, 5, 0); add(P, 'thighR', 0, -5, 0);
  },
};
