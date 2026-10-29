// Mochi: a white plush bunny, navy ear tips, pink inner ears, a turquoise knitted scarf with a
// hanging tag, a pompom tail. Rig: mochi-3d/blender/rig.py.
import { bodyMaterial } from '../engine/materials.js';
import { Spring } from '../engine/motion.js';
import { add } from '../engine/moves.js';

const ear = (s, side) => ({ bones: [`ear${s}1`, `ear${s}2`, `ear${s}3`], side, twitch: true });

export default {
  id: 'mochi',
  name: 'Mochi',
  model: 'mochi.glb',
  floor: 0.952,
  pivot: [0, 0.5, 0],
  frame: { sidefolk: 2.3 },

  material: (body) => bodyMaterial(body, {
    surface: `
      // Ears: outside the head's ellipsoid, above the brow.
      float rr = length(vec3(p.x / 0.44, (p.z + 0.005) / 0.42, (p.y + 0.03) / 0.36));
      float earM = smoothstep(0.98, 1.06, rr) * smoothstep(0.10, 0.17, p.y);
      float sx = p.x >= 0.0 ? 1.0 : -1.0;
      vec2 a = vec2(0.15 * sx, 0.22), ab = vec2(0.335 * sx, 0.94) - a;
      float t = dot(p.xy - a, ab) / dot(ab, ab);
      float pd = length((p.xy - a) - ab * t);
      // The navy tip: a rounded cap, its edge dipping toward the ear's sides.
      float cut = 0.60 - 3.2 * pd * pd;
      float navy = earM * smoothstep(cut - 0.01, cut + 0.01, t);
      float turq = smoothstep(0.07, 0.18, min(s.g - s.r, s.b - s.r));
      float pink = earM * smoothstep(0.03, 0.08, s.r - s.g) * (1.0 - navy);
      c = vec3(0.93, 0.925, 0.92);
      c = mix(c, tex * vec3(0.97, 1.03, 1.03), turq);
      c = mix(c, mix(tex, vec3(1.0, 0.62, 0.68), 0.35), pink);
      c = mix(c, vec3(0.010, 0.030, 0.19), navy);
      float plushH = tri(uPlush, p, nR, 6.5);
      float knitH = tri(uKnit, p * vec3(1.0, 1.25, 1.0), nR, 4.2);
      bumpH = mix(plushH * 0.26, knitH, turq) * 0.012;
      // Knit grooves sit in shade; the pile catches a little light on its tips.
      c *= mix(0.985 + 0.03 * plushH, 0.72 + 0.4 * knitH, turq);
      rough = mix(0.8, 0.93, turq);
      // White velvet sheen would wash the navy tips out to lavender: tint it down there.
      sheenTint = mix(vec3(1.0), vec3(0.12, 0.16, 0.35), navy);
      inner = 1.0 - 0.6 * navy;
      // Light glowing through the thin ears, warm and pink at the inner ear.
      glow = earM * (1.0 - navy) * mix(vec3(0.05, 0.035, 0.035), vec3(0.11, 0.045, 0.06), pink);`,
  }),

  face: {
    kind: 'ink',
    unwrap: { R: 0.42, span: 0.36 },
    // The front of the head between brow and scarf (ears start higher, the scarf lower).
    region: (x, y, z) => z > 0.08 && y > -0.3 && y < 0.26,
    // Nose and mouth keep a clear gap: the mouth never reaches up to the nose.
    layout: {
      eye: { x: 0.2, y: -0.052, w: 0.148, h: 0.194, depth: 0.036 },
      nose: { y: -0.116, w: 0.044, h: 0.027 },
      mouth: { y: -0.168 },
      blush: { x: 0.3, y: -0.142, w: 0.105, h: 0.062 },
    },
  },

  chains: [ear('L', 1), ear('R', -1)],
  pick: { head: { r: 0.43, at: [0, -0.04, 0] }, body: { r: 0.31, at: [0, -0.62, 0] }, tips: ['earL2', 'earR2'] },

  /** A fluffy pompom: a sphere with soft lumps, on the tail bone so it can wag and jiggle. */
  extras(c, THREE) {
    const geo = new THREE.SphereGeometry(0.078, 64, 48);
    const p = geo.attributes.position, v = new THREE.Vector3();
    for (let i = 0; i < p.count; i++) {
      v.fromBufferAttribute(p, i);
      const d = v.clone().normalize();
      const lump = 1 + 0.07 * Math.sin(d.x * 17 + d.y * 5) * Math.sin(d.y * 15 + d.z * 7) + 0.04 * Math.sin(d.z * 23 + d.x * 11);
      v.multiplyScalar(lump); p.setXYZ(i, v.x, v.y, v.z);
    }
    geo.computeVertexNormals();
    const mat = new THREE.MeshPhysicalMaterial({ color: 0xf4f3f2, roughness: 1, sheen: 1, sheenRoughness: 0.35, sheenColor: 0xffffff, emissive: 0x141312 });
    const tail = c.tailMesh = new THREE.Mesh(geo, mat);
    tail.castShadow = true;
    const bone = c.bones.tail;
    bone.add(tail);
    tail.position.copy(bone.worldToLocal(new THREE.Vector3(0, -0.705, -0.265)));
    c.tailS = { x: new Spring(0, 140, 7), z: new Spring(0, 140, 7), s: new Spring(1, 260, 9) };
  },

  /** The pompom jiggles on landings and wags when happy. */
  dynamics(c, dt, P, { lin, a, happy }) {
    const T = c.tailS;
    T.x.kick((-lin.y * 90 - a.x * 0.3) * dt); T.z.kick((lin.x * 90 - a.z * 0.3) * dt);
    add(P, 'tail', T.x.step(0, dt), 0, T.z.step(Math.sin(c.time * 14) * 14 * happy, dt));
    const ts = T.s.step(1, dt); T.s.kick(-lin.y * 0.6 * dt);
    c.tailMesh.scale.set(1 / Math.sqrt(ts), ts, 1 / Math.sqrt(ts));
  },

  // Relaxed: arms down from the modelled A-pose, a hint of forward lean, feet slightly turned out.
  stand(t, P) {
    add(P, 'armL', 0, -8, -24); add(P, 'armR', 0, 8, 24);
    add(P, 'handL', 0, 0, -6); add(P, 'handR', 0, 0, 6);
    add(P, 'chest', 2); add(P, 'thighL', 0, 6, 0); add(P, 'thighR', 0, -6, 0);
  },
};
