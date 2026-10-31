// Spark: a little ivory robot with a dark glass visor (its face is light on the glass), aqua
// headphones and a springy antenna with an aqua ball. Rig: blender/rig_spark.py.
import { bodyMaterial } from '../engine/materials.js';
import { damp, curve, win } from '../engine/motion.js';
import { add, raise, fwd, face, POSTURES } from '../engine/moves.js';

export default {
  id: 'spark',
  name: 'Spark',
  model: 'spark.glb',
  floor: 0.952,
  pivot: [0, 0.5, 0],
  frame: { sidefolk: 2.3 },
  marks: [0.5, 0.55, 0.15],

  // Soft-touch ivory plastic, a glossy glass visor, aqua and navy parts; no fabric sheen.
  material: (body) => bodyMaterial(body, {
    params: { sheen: 0, clearcoat: 0.7, clearcoatRoughness: 0.18, roughness: 0.42 },
    ao: [0.5, 0.35, 0.85],
    uniforms: { uPulse: { value: 0 } },
    surface: `
      float lum = dot(s, vec3(0.3, 0.55, 0.15));
      float aqua = smoothstep(0.12, 0.22, min(s.g - s.r, s.b - s.r)) * smoothstep(0.45, 0.6, s.g);
      float dark = (1.0 - smoothstep(0.32, 0.45, lum)) * (1.0 - aqua);
      // The visor is the dark glass on the front of the head; other dark parts are navy joints.
      float visor = dark * smoothstep(-0.12, -0.06, p.y) * smoothstep(0.18, 0.24, p.z);
      vec3 ivory = vec3(0.93, 0.915, 0.88);
      c = ivory * (0.97 + 0.03 * lum);
      c = mix(c, vec3(0.07, 0.62, 0.62), aqua);
      c = mix(c, vec3(0.022, 0.035, 0.11), dark);
      c = mix(c, vec3(0.008, 0.012, 0.035), visor);
      rough = mix(mix(0.4, 0.3, aqua), 0.5, dark * (1.0 - visor));
      // Dark smoked glass: a soft, dim sheen of the room, not a mirror with a lamp in it.
      rough = mix(rough, 0.32, visor);
      clear = mix(0.6, 1.0, aqua) * (1.0 - 0.6 * visor);
      spec = 1.0 - 0.75 * visor;
      // A faint grain on the plastic so it isn't a CG-perfect surface.
      bumpH = tri(uPlush, p, nR, 9.0) * 0.0012 * (1.0 - visor);
      inner = 0.55 * (1.0 - dark);
      // The visor glows a deep blue from inside; the headphone rings and the antenna ball glow
      // aqua, brighter while Spark listens or thinks.
      glow = visor * vec3(0.004, 0.012, 0.03) + aqua * vec3(0.02, 0.2, 0.2) * (0.25 + uPulse);`,
  }),

  face: {
    kind: 'screen',
    glow: '64,236,228',
    unwrap: { R: 0.34, span: 0.36, cy: 0.17 },
    region: (x, y, z) => z > 0.2 && Math.abs(x) < 0.37 && y > -0.09 && y < 0.43,
    lift: 0.004,
    layout: {
      eye: { x: 0.13, y: 0.195, w: 0.1, h: 0.158 },
      mouth: { y: 0.06 },
    },
  },

  // Its own moment: a slow scan of the room, antenna boinging, headphones bright.
  actions: {
    scan: {
      dur: 3.6,
      fn(t, P, fx) {
        fx.at(0.3, 'dots');
        const on = win(t, 0, 0.4, 3.0, 3.6);
        const sweep = curve([[0, 0], [0.8, -45], [1.8, 45], [2.8, 0], [3.6, 0]], t);
        add(P, 'head', -4 * on, sweep * on, 0); add(P, 'chest', 0, sweep * 0.25 * on, 0);
        const boing = Math.sin(t * 16) * Math.exp(-t * 1.1) * 26;
        add(P, 'antenna1', boing * 0.4, 0, boing * 0.3); add(P, 'antenna2', boing, 0, boing * 0.6);
        P.look *= 1 - on;
        P.gaze = [sweep / 50, 0];
        face(P, { mood: 'attentive' });
      },
    },
  },
  moments: ['scan'],

  chains: [{ bones: ['antenna1', 'antenna2'], side: 1, k: [130, 95], d: [6.5, 4.6], gain: 1.5, breeze: 0.5, twitch: true, limit: [40, 40] }],
  pick: { head: { r: 0.5, at: [0, 0.17, 0] }, body: { r: 0.27, at: [0, -0.46, 0] }, tips: ['antenna2'], tipR: 0.12 },
  fidgets: ['lookAround', 'earTwitch', 'earTwitch', 'tilt', 'smile', 'stretch', 'hop', 'blinkDouble', 'giggle'],
  skip: ['sniff', 'sneeze'],

  // Headphones and antenna light up while Spark pays attention. Asleep it is on standby: the face
  // dims to a faint glow and the headphone rings go dark but for a slow pulse.
  dynamics(c, dt) {
    const busy = ['listening', 'hearing', 'thinking', 'working'].includes(c.loopName);
    const standby = c.postureW.sleep.x;
    const slow = 0.5 + 0.5 * Math.sin(c.time * Math.PI * 2 * 0.2);
    const target = busy ? 0.55 + 0.35 * Math.sin(c.time * (c.loopName === 'thinking' ? 5 : 3)) : -0.22 * standby * (1 - 0.4 * slow);
    const u = c.body.material.userData.u.uPulse;
    u.value = damp(u.value, target, 6, dt);
    c.faceDecal ||= c.body.parent.getObjectByName('FaceDecal');
    c.faceDecal.material.color.setScalar(1 - standby * (0.62 - 0.12 * slow));
  },

  postures: {
    // Kicked back: sitting with its legs out, leaning back on its hands, the visor tipped to you.
    // (On its side, the shared lie of old, the big helmet stayed upright over a sideways body.)
    lie: (t, P, C) => {
      C.stand(t, P);
      P.root.py -= 0.16; P.root.rx -= 36; P.root.pz += 0.03;
      for (const [s, d] of [['L', 1], ['R', -1]]) {
        add(P, 'thigh' + s, -54, 0, -d * 8);
        raise(P, s, -12); fwd(P, s, -70);
      }
      add(P, 'head', 22, 0, 10); add(P, 'chest', 6);
      add(P, 'footL', 0, 0, 10 * Math.sin(t * 1.3));
    },
    // Standby: sitting, slumped a little, head bowed, arms limp, antenna drooping; the face dims
    // (dynamics) and breathes no more than a slow pulse.
    sleep: (t, P, C) => {
      POSTURES.sit(t, P, C);
      for (const s of ['L', 'R']) { raise(P, s, -4); fwd(P, s, -18); }
      add(P, 'spine', 6); add(P, 'chest', 6); add(P, 'head', 14, 0, 6);
      add(P, 'antenna1', 26); add(P, 'antenna2', 20);
      P.look *= 0.2;
    },
  },

  // Arms relaxed down from the modelled A-pose.
  stand(t, P) {
    add(P, 'armL', 0, -6, -18); add(P, 'armR', 0, 6, 18);
    add(P, 'handL', 0, 0, -6); add(P, 'handR', 0, 0, 6);
    add(P, 'thighL', 0, 4, 0); add(P, 'thighR', 0, -4, 0);
  },
};
