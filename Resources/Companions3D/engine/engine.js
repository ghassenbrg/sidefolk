// Sidefolk 3D companions: a living character on a skinned Meshy model. One engine; each
// character (characters/*.js) brings its model, material, face, springy parts and a few poses.
//
// Every frame builds one pose from layers, then lets physics finish it:
//   posture (stand / sit / lie / sleep, blended by springs)
//   + idle life (breath, weight shifts, micro head motion)
//   + activity loop (Sidefolk's state: listening, thinking, working…)
//   + one-shot moves (wave, bow, hop, dance…, faded in and out)
//   + look-at (eyes lead, head follows, chest a little)
//   → springs: ears, antennae, tails, scarf tag, squash & stretch
// The face is separate (face.js), driven by mood + moves + blinking + speech.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { Spring, damp, clamp, lerp, smooth, noise, rand, pick } from './motion.js';
import { ACTIONS, LOOPS, POSTURES, MOMENTS_3D, add } from './moves.js';
import { moodFace } from './moods.js';
import { Face, buildEye } from './face.js';
import { Marks } from './marks.js';

const D2R = Math.PI / 180;
// Bones that pass through follow-through springs (the posed core, head and limbs).
const FOLLOW = { hips: [320, 30], spine: [260, 25], chest: [220, 21], head: [165, 15.5],
  armL: [150, 14], armR: [150, 14], handL: [115, 10.5], handR: [115, 10.5] };

const STATES = {
  idle: { loop: 'idle' }, listening: { loop: 'listening' }, hearing: { loop: 'hearing' },
  thinking: { loop: 'thinking' }, working: { loop: 'working' }, waiting: { loop: 'waiting' },
  success: { loop: 'success', mood: 'happy' }, error: { loop: 'error' },
  alert: { loop: 'alert' }, dragging: { loop: 'dragging' },
  celebrating: { loop: 'celebrating' }, sleeping: { loop: 'idle', posture: 'sleep' },
};

/**
 * How big a reaction is, by liveliness: Minimal (the economical setting) keeps only what tells
 * you something; Balanced adds a little joy; Lively plays the whole scene. One place to tune.
 * Each entry is a move, or moves played one after another. Every move starting is also announced
 * (`'move'` event), the hook for sound effects later.
 */
const REACTIONS = {
  success: { minimal: 'nod', balanced: 'hop', lively: ['cheer', 'twirl'] },          // something finished
  alert: { minimal: 'surprised', balanced: 'attention', lively: ['surprised', 'attention'] }, // a reminder, news
  error: { minimal: null, balanced: 'scratch', lively: ['wince', 'scratch'] },
  petted: { minimal: null, balanced: 'giggle', lively: 'thanks' },                     // after a long stroke
};

export class Companion {
  constructor(canvas, character, opts = {}) {
    this.C = character;
    this.opts = { interactive: true, liveliness: 'balanced', shadow: true, ...opts };
    this.canvas = canvas;
    this.time = 0;
    this.mood = 'neutral';
    this.posture = 'stand';
    this.loopName = 'idle';
    this.state = 'idle';
    this.actions = [];
    this.listeners = {};
    this.paused = false;
    this.pivot = new THREE.Vector3(...(character.pivot || [0, 0.5, 0]));
    this.initRenderer();
  }

  // ───────────────────────────── setup ─────────────────────────────

  initRenderer() {
    const r = this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, alpha: true, antialias: true, premultipliedAlpha: true, preserveDrawingBuffer: !!this.opts.capture });
    r.setPixelRatio(Math.min(window.devicePixelRatio, this.opts.maxPixelRatio || 2));
    r.setClearColor(0x000000, 0);
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.NeutralToneMapping;
    r.toneMappingExposure = 1.0;
    r.shadowMap.enabled = this.opts.shadow;
    r.shadowMap.type = THREE.PCFSoftShadowMap;

    const scene = this.scene = new THREE.Scene();
    const pm = new THREE.PMREMGenerator(r);
    scene.environment = pm.fromScene(new RoomEnvironment(), 0.035).texture;
    // Animated-film light: a big soft wrap of environment light, a gentle key, a cool rim; low
    // contrast, so surfaces read soft and bright rather than plastic.
    scene.environmentIntensity = this.C.light?.env ?? 1.05;

    this.camera = new THREE.PerspectiveCamera(20, 1, 0.1, 50);
    this.frame(this.opts.frame || 'full');

    // Key light high and in front: the shadow pools under the character instead of streaking
    // sideways across the desktop.
    const key = new THREE.DirectionalLight(0xfff2e6, this.C.light?.key ?? 1.75);
    key.position.set(-0.9, 4.2, 2.6);
    key.castShadow = true;
    key.shadow.mapSize.setScalar(this.opts.shadowSize || 1024);
    Object.assign(key.shadow.camera, { left: -1.6, right: 1.6, top: 2.4, bottom: -0.6, near: 0.5, far: 10 });
    key.shadow.bias = -0.0004; key.shadow.normalBias = 0.025; key.shadow.radius = 5;
    scene.add(key);
    const rim = new THREE.DirectionalLight(0xdfeeff, this.C.light?.rim ?? 1.6);
    rim.position.set(1.8, 2.2, -3);
    scene.add(rim);
    scene.add(new THREE.HemisphereLight(0xf4f7ff, 0xf7ece2, 0.7));

    // Ground: a shadow catcher plus a soft contact blob, invisible otherwise (transparent window).
    if (this.opts.shadow) {
      const ground = new THREE.Mesh(new THREE.PlaneGeometry(6, 6), new THREE.ShadowMaterial({ opacity: 0.13 }));
      ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true;
      scene.add(ground);
    }
    const blobCv = document.createElement('canvas'); blobCv.width = blobCv.height = 128;
    const bc = blobCv.getContext('2d'); const g = bc.createRadialGradient(64, 64, 0, 64, 64, 64);
    const a = this.opts.shadow ? 1 : 1.3;   // alone, the contact shadow carries the grounding
    g.addColorStop(0, `rgba(20,30,60,${0.34 * a})`); g.addColorStop(0.5, `rgba(20,30,60,${0.14 * a})`); g.addColorStop(1, 'rgba(20,30,60,0)');
    bc.fillStyle = g; bc.fillRect(0, 0, 128, 128);
    const [bw, bd] = this.C.blob || [1.1, 0.75];
    this.blob = new THREE.Mesh(new THREE.PlaneGeometry(bw, bd), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(blobCv), transparent: true, depthWrite: false }));
    this.blob.rotation.x = -Math.PI / 2; this.blob.position.y = 0.002;
    scene.add(this.blob);

    this.marks = new Marks(scene);
  }

  /** Camera framing: 'full' leaves headroom for jumps; 'tight' is for a small desktop window;
   *  'sidefolk' matches the 2D rig's canvas (feet 10% above the bottom, centred), so Sidefolk's
   *  hit testing and bubble anchors line up with what is drawn. */
  frame(kind) {
    const c = this.camera;
    const F = this.C.frame || {};
    if (kind === 'sidefolk') {
      const h = F.sidefolk ?? 2.3, dist = h / (2 * Math.tan(c.fov * D2R / 2));
      c.position.set(0, 0.4 * h, dist);
      c.lookAt(0, 0.4 * h, 0);
      return;
    }
    const h = kind === 'tight' ? (F.tight ?? 2.35) : (F.full ?? 2.75);
    const y = kind === 'tight' ? (F.tightY ?? 0.98) : (F.fullY ?? 1.08);
    const dist = h / (2 * Math.tan(c.fov * D2R / 2));
    c.position.set(0, y + 0.03, dist);
    c.lookAt(0, y, 0);
  }

  async load(url = new URL(`../assets/${this.C.model}`, import.meta.url).href) {
    const gltf = await new GLTFLoader().loadAsync(url);
    const model = this.model = gltf.scene;
    model.traverse((o) => { if (o.isSkinnedMesh) this.body = o; });
    const body = this.body;
    body.castShadow = true; body.receiveShadow = true; body.frustumCulled = false;

    // Wrappers, outside in: squash (at the feet) › mover (whole-body turn about the pivot) › offset.
    this.root = new THREE.Group();
    this.squashG = new THREE.Group();
    this.mover = new THREE.Group();
    this.offset = new THREE.Group();
    this.root.add(this.squashG); this.squashG.add(this.mover); this.mover.add(this.offset); this.offset.add(model);
    this.scene.add(this.root);
    this.root.updateMatrixWorld(true);

    // Bones and their rest frames in model space (everything is still at identity here).
    this.bones = {};
    body.skeleton.bones.forEach((b) => { this.bones[b.name.replace(/[.\s]/g, '')] = b; });
    this.rest = {};
    for (const [n, b] of Object.entries(this.bones)) {
      if (n === 'root' || n === 'face') continue;
      const w = b.getWorldQuaternion(new THREE.Quaternion());
      this.rest[n] = { q: b.quaternion.clone(), w, wi: w.clone().invert() };
    }

    body.material = this.C.material(body);
    this.buildFace();
    this.C.extras?.(this, THREE);
    this.buildPicking();

    // Feet on the floor.
    this.offset.position.set(0, this.C.floor, 0).sub(this.pivot);
    this.mover.position.copy(this.pivot);
    this.initDynamics();
    this.setMood('neutral');
    if (this.opts.interactive) this.bindPointer();
    this.resize();
    // One frame now: a window WebKit throttles (behind others, not yet shown) gets no animation
    // frames, and would otherwise stay empty until it does.
    this.update(1 / 60);
    this.renderer.render(this.scene, this.camera);
    this.start();
    this.emit('ready');
  }

  buildFace() {
    const F = this.C.face;
    this.face3 = new Face(F);
    this.body.parent.add(this.face3.buildDecal(this.body));
    this.eyes = [];
    // A screen paints its eyes, and a likeness keeps the model's own (painted lids only).
    if (F.kind === 'screen' || !F.layout.eye) { this.faceKey = ''; return; }

    // Eyes: found on the head's surface by ray, then carried by the surface itself: three skinned
    // vertices around each eye give its place and turn every frame. (Carried by the head bone, an
    // eye slid behind a face that mostly follows the body, as Nimbo's and Folio's do.)
    const body = this.body, pos = body.geometry.attributes.position;
    const probe = new THREE.Mesh(body.geometry);
    probe.matrixWorld.copy(body.matrixWorld);
    const ray = new THREE.Raycaster();
    const bodyWQ = body.getWorldQuaternion(new THREE.Quaternion());
    const nearest = (p) => {
      let best = 0, bd = Infinity;
      for (let i = 0; i < pos.count; i++) {
        const dx = pos.getX(i) - p.x, dy = pos.getY(i) - p.y, dz = pos.getZ(i) - p.z, d = dx * dx + dy * dy + dz * dz;
        if (d < bd) { bd = d; best = i; }
      }
      return best;
    };
    const E = F.layout.eye;
    for (const side of [1, -1]) {
      ray.set(new THREE.Vector3(side * E.x, E.y, 3), new THREE.Vector3(0, 0, -1));
      const hit = ray.intersectObject(probe)[0];
      const n = hit.face.normal.clone().transformDirection(body.matrixWorld);
      n.add(new THREE.Vector3(0, 0, F.eyeForward ?? 0.9)).normalize();           // keep them looking ahead
      const zx = n, xx = new THREE.Vector3(0, 1, 0).cross(zx).normalize(), yx = zx.clone().cross(xx);
      const q = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(xx, yx, zx));
      const eye = buildEye(side, E, F.iris);
      body.add(eye.group);
      const at = body.worldToLocal(hit.point.clone().addScaledVector(n, -E.depth * (E.sink ?? 0.42)));
      const surface = body.worldToLocal(hit.point.clone());
      const anchor = [surface, surface.clone().add(new THREE.Vector3(0.06, 0, 0)), surface.clone().add(new THREE.Vector3(0, 0.06, 0))].map(nearest);
      const rest = this.anchorFrame(anchor);
      eye.anchor = {
        verts: anchor,
        offset: at.sub(rest.p).applyQuaternion(rest.q.clone().invert()),
        turn: rest.q.clone().invert().multiply(bodyWQ.clone().invert().multiply(q)),
      };
      this.eyes.push(eye);
    }
    this.placeEyes();
    this.faceKey = '';
  }

  /** Where three skinned vertices are now, as a point and a turn (body space). */
  anchorFrame(verts) {
    const [p0, p1, p2] = verts.map((i) => this.body.getVertexPosition(i, new THREE.Vector3()));
    const x = p1.sub(p0).normalize(), z = x.clone().cross(p2.sub(p0)).normalize(), y = z.clone().cross(x);
    return { p: p0, q: new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(x, y, z)) };
  }

  placeEyes() {
    for (const e of this.eyes) {
      const { p, q } = this.anchorFrame(e.anchor.verts);
      e.group.position.copy(e.anchor.offset).applyQuaternion(q).add(p);
      e.group.quaternion.copy(q).multiply(e.anchor.turn);
    }
  }

  buildPicking() {
    const inv = new THREE.MeshBasicMaterial({ visible: false });
    const P = this.C.pick;
    const sphere = (r, boneName, at) => {
      const m = new THREE.Mesh(new THREE.SphereGeometry(r, 16, 12), inv);
      const b = this.bones[boneName];
      b.add(m); if (at) m.position.copy(b.worldToLocal(new THREE.Vector3(...at)));
      return m;
    };
    this.pickHead = sphere(P.head.r, 'head', P.head.at);
    this.pickBody = sphere(P.body.r, P.body.bone || 'spine', P.body.at);
    this.pickEars = (P.tips || []).filter((n) => this.bones[n]).map((n) => sphere(P.tipR ?? 0.16, n));
  }

  initDynamics() {
    const S = (k, d) => new Spring(0, k, d);
    // Springy chains (ears, antennae, tails): every segment swings on two axes.
    this.chains = (this.C.chains || []).filter((c) => c.bones.every((b) => this.bones[b])).map((c) => ({
      ...c,
      segs: c.bones.map((_, i) => {
        const k = c.k?.[i] ?? 150 - i * 35, d = c.d?.[i] ?? 9 - i * 1.6;
        return { x: S(k, d), z: S(k, d) };
      }),
    }));
    this.scarfS = { x: S(55, 5.5), z: S(55, 5.5) };
    this.squashS = new Spring(1, 340, 15);
    this.postureW = { stand: new Spring(1, 7, 5.3), sit: S(7, 5.3), lie: S(7, 5.3), sleep: S(5, 4.5) };
    this.loopW = { idle: { w: new Spring(1, 9, 6), t: 0 } };
    this.look = { yaw: S(55, 12), pitch: S(55, 12), target: null, idleT: 0, idleGoal: new THREE.Vector2() };
    this.gaze = new THREE.Vector2(); this.saccade = new THREE.Vector2(); this.nextSaccade = 0;
    this.blink = { next: rand(1.5, 4), t: -1, double: false };
    this.face = moodFace('neutral'); this.face.lidL = 0; this.face.lidR = 0; this.face.time = 0;
    this.prevHeadQ = new THREE.Quaternion(); this.prevW = new THREE.Vector3(); this.angAcc = new THREE.Vector3();
    this.prevHeadP = new THREE.Vector3(); this.headV = new THREE.Vector3(); this.headA = new THREE.Vector3();
    this.speech = null; this.voice = 0;
    this.nextFidget = rand(5, 9);
    this.pet = { active: false, w: new Spring(0, 12, 7), x: 0 };
  }

  // ───────────────────────────── public API ─────────────────────────────

  on(ev, fn) { (this.listeners[ev] ||= []).push(fn); }
  emit(ev, data) { (this.listeners[ev] || []).forEach((f) => f(data)); }

  setMood(name) { this.mood = name; this.moodFace = moodFace(name); }

  /** The one-shot moves this character has (the shared set and its own, minus what its body can't do). */
  get moves() { return [...Object.keys(ACTIONS), ...Object.keys(this.C.actions || {})].filter((n) => !(this.C.skip || []).includes(n)); }

  /** A one-shot move by name (wave, bow, hop, jump, cheer, dance, nod, shake, giggle, flip…). */
  play(name) {
    const clip = this.C.actions?.[name] || ACTIONS[name];
    if (!clip || (this.C.skip || []).includes(name)) return false;
    for (const a of this.actions) a.fading ??= a.t;
    this.actions.push({ name, clip, t: 0 });
    this.queue = [];
    this.nextFidget = this.time + rand(8, 14);
    if (name === 'flip' || name === 'jump' || name === 'surprised') this.forceBlink();
    this.emit('move', name);
    return true;
  }

  /** Plays moves one after another, each starting as the last one settles. */
  playSequence(names) {
    const [first, ...rest] = names.filter((n) => this.C.actions?.[n] || ACTIONS[n]);
    if (!first) return false;
    this.play(first);
    this.queue = rest;
    return true;
  }

  /** The reaction to `event` (REACTIONS) at the current liveliness. */
  react(event) {
    // One event, one reaction: Sidefolk may report it twice (a state and a cue).
    if (this.reacted?.event === event && this.time - this.reacted.at < 1.5) return false;
    this.reacted = { event, at: this.time };
    const level = this.opts.liveliness === 'still' ? 'minimal' : this.opts.liveliness;
    const r = REACTIONS[event]?.[level] ?? REACTIONS[event]?.balanced;
    if (!r) return false;
    return this.playSequence(Array.isArray(r) ? r : [r]);
  }

  /** Sidefolk's states (idle, listening, hearing, thinking, working, waiting, success, error,
   *  alert, dragging, celebrating, sleeping). */
  setState(name) {
    const s = STATES[name] || STATES.idle;
    this.state = name;
    this.setLoop(s.loop);
    if (s.mood) this.setMood(s.mood); else if (['happy', 'asleep'].includes(this.mood)) this.setMood('neutral');
    // Sitting and lying down are for idling: any other state stands up (the host's posture is reset
    // the same way and sends no cue for it), so an alert never arrives lying down with open eyes.
    this.setPosture(s.posture || (name === 'idle' && this.posture !== 'sleep' ? this.posture : 'stand'));
    if (REACTIONS[name]) this.react(name);
  }

  setLoop(name) {
    if (!LOOPS[name]) return;
    this.loopName = name;
    if (!this.loopW[name]) this.loopW[name] = { w: new Spring(0, 9, 6), t: 0 };
  }

  setPosture(name) {
    if (!POSTURES[name]) return;
    if (name === this.posture) return;
    this.posture = name;
    if (name === 'sleep') this.setMood('asleep');
    else if (this.mood === 'asleep') this.setMood('neutral');
  }

  /** Talks `text`: a mouth timeline from its syllables, with head beats and brows on ? and !. */
  say(text) {
    const segs = []; let t = 0.05;
    for (const word of text.split(/(\s+|[,.!?;:…]+)/)) {
      if (!word) continue;
      if (/^\s+$/.test(word)) { t += 0.05; continue; }
      if (/^[,.!?;:…]+$/.test(word)) { t += /[,;:]/.test(word) ? 0.18 : 0.32; continue; }
      const syl = word.toLowerCase().match(/[aeiouyàâéèêëîïôöùûüœ]+|[^aeiouy]+$/g) || [word];
      for (const s of syl) {
        const d = rand(0.1, 0.16);
        segs.push({ t0: t, t1: t + d, open: rand(0.45, 0.9), round: /[ou]/.test(s) ? 0.8 : 0 });
        t += d + 0.015;
      }
    }
    this.speech = { segs, t: 0, end: t + 0.1, ask: /\?\s*$/.test(text), exclaim: /!/.test(text) };
    this.emit('speaking', true);
    return t;
  }

  /** Live voice level 0…1 (from real audio); overrides the text timeline while it is non-zero. */
  talk(level) { this.voice = clamp(level ?? 0); }

  /** Look at a point given in normalized window coords (−1…1, y up); null returns to idle gazing. */
  lookAt(nx, ny) {
    if (nx == null) { this.look.target = null; return; }
    const v = new THREE.Vector3(nx, ny, 0.5).unproject(this.camera);
    const dir = v.sub(this.camera.position).normalize();
    const t = (1.4 - this.camera.position.z) / dir.z;
    this.look.target = this.camera.position.clone().addScaledVector(dir, t);
    this.look.lastSeen = this.time;
  }

  /** Stops for good and frees the GPU: the page swaps in another character. */
  dispose() {
    this.paused = true;
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    this.canvas.remove();
  }

  pause(p = true) { const was = this.paused; this.paused = p; if (was && !p) { this.last = performance.now(); this.loop(); } }

  /** Advances `seconds` at a fixed 60 fps and renders: for tests and frame captures. */
  step(seconds) {
    for (let i = 0; i < Math.round(seconds * 60); i++) this.update(1 / 60);
    this.renderer.render(this.scene, this.camera);
  }

  // ───────────────────────────── frame ─────────────────────────────

  start() { this.last = performance.now(); this.loop(); }

  loop() {
    if (this.paused) return;
    requestAnimationFrame(() => this.loop());
    const now = performance.now();
    const elapsed = (now - this.last) / 1000;
    if (elapsed < 1e-4) return;     // two frames at one timestamp: nothing to integrate
    // Only breathing and blinking: fewer frames do (`idleFps`); anything moving gets `maxFps`.
    // Compared before the step is clamped: a clamped step can never reach a slow frame's time.
    const cap = this.calm && this.opts.idleFps ? this.opts.idleFps : this.opts.maxFps;
    if (cap && elapsed < 1 / cap - 0.002) return;
    this.last = now;
    const dt = Math.min(0.05, elapsed);
    this.update(dt);
    // The shadow is a second pass: every other frame is enough to follow the body.
    if (this.opts.shadowEvery) {
      this.renderer.shadowMap.autoUpdate = false;
      this.renderer.shadowMap.needsUpdate = (this.frameNo = (this.frameNo || 0) + 1) % this.opts.shadowEvery === 1;
    }
    this.renderer.render(this.scene, this.camera);
  }

  resize() {
    const w = this.canvas.clientWidth || window.innerWidth, h = this.canvas.clientHeight || window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  update(dt) {
    this.time += dt;
    const t = this.time;
    const P = this.layer();
    const faceLayers = [];
    const postures = { ...POSTURES, stand: this.C.stand || (() => {}), ...this.C.postures };

    // Posture: weighted blend of every posture's pose.
    for (const [name, s] of Object.entries(this.postureW)) {
      const w = clamp(s.step(name === this.posture ? 1 : 0, dt), 0, 1.05);
      if (w < 0.001) continue;
      const L = this.layer();
      postures[name](t, L);
      this.mix(P, L, w);
    }
    const lying = clamp(this.postureW.lie.x + this.postureW.sleep.x);
    const sleeping = clamp(this.postureW.sleep.x);

    // Idle life: breathing and drifting weight, quieter when lying down.
    {
      const br = Math.sin(t * Math.PI * 2 * 0.27);
      add(P, 'chest', -1.4 * br); add(P, 'head', 0.8 * br);
      add(P, 'armL', 0, 0, 1.8 * br); add(P, 'armR', 0, 0, -1.8 * br);
      P.squash *= 1 + 0.009 * br;
      const live = 1 - 0.7 * lying;
      add(P, 'hips', 0, noise(t * 0.3, 1) * 3 * live, noise(t * 0.22, 2) * 2.5 * live);
      add(P, 'spine', 0, 0, -noise(t * 0.22, 2) * 1.5 * live);
      add(P, 'head', noise(t * 0.4, 4) * 2 * live, noise(t * 0.33, 5) * 4 * live, noise(t * 0.27, 6) * 3.5 * live);
      this.C.life?.(t, P, live);
    }

    // Activity loops (state), crossfaded.
    for (const [name, L0] of Object.entries(this.loopW)) {
      const w = clamp(L0.w.step(name === this.loopName ? 1 : 0, dt));
      if (w < 0.002 && name !== this.loopName) { if (name !== 'idle') delete this.loopW[name]; continue; }
      const prev = L0.t; L0.t += dt;
      const L = this.layer();
      LOOPS[name](L0.t, L, this.fx(prev, L0.t, w));
      this.mix(P, L, w * (1 - 0.85 * lying));
      if (L.face.mood || Object.keys(L.face).length) faceLayers.push([L.face, w]);
      if (L.gaze) P.gaze = L.gaze;
    }

    // Petting: a bliss that deepens the longer it lasts. First a smile and a lean into the hand;
    // then eyes shut, ears smoothed back, the body melting and swaying, a happy wag; at the end
    // a sigh, and (Balanced, Lively) a thank-you.
    {
      const pet = this.pet;
      if (pet.active) pet.t = (pet.t || 0) + dt;
      const w = pet.w.step(pet.active ? 1 : 0, dt);
      if (w > 0.002) {
        const deep = smooth((pet.t || 0) / 1.6);
        const sway = Math.sin(t * 2.2) * (2 + 6 * deep);
        const L = this.layer();
        // Leaning into the hand: toward the stroke, or to one side when Sidefolk doesn't say.
        const side = pet.x || 0.8;
        add(L, 'head', 6 + 6 * deep, side * 12, -side * (12 + 16 * deep) + sway);
        add(L, 'chest', 3 + 3 * deep, 0, -side * (4 + 6 * deep) + sway * 0.4);
        L.root.rz -= side * 4 * deep;
        for (const s of ['L', 'R']) {
          add(L, `ear${s}1`, -14 - 10 * deep); add(L, `ear${s}2`, -12 - 8 * deep); add(L, `ear${s}3`, -8 - 6 * deep);
          add(L, 'arm' + s, 0, (s === 'L' ? -1 : 1) * 20 * deep, (s === 'L' ? -1 : 1) * -8 * deep);   // paws curl in
        }
        L.squash = 1 - 0.02 - 0.07 * deep;
        if (deep > 0.9 && pet.active && (pet.hearts ?? 0) < this.time) { pet.hearts = this.time + 2.6; this.markAtHead('heart'); }
        L.face = deep < 0.35 ? { mood: 'smile', blush: 1.2 } : deep < 0.95 ? { mood: 'content', blush: 1.5 } : { mood: 'love', blush: 1.7, shy: 0.6 };
        this.mix(P, L, w);
        faceLayers.push([L.face, w]);
      }
      if (!pet.active && pet.t) {
        // Let go: a contented sigh, then a thank-you after a real stroke.
        if (pet.t > 1.2) this.react('petted');
        else this.flash = { mood: 'happy', until: this.time + 1.4 };
        pet.t = 0;
      }
    }

    // One-shot moves.
    for (const a of this.actions) {
      const prev = a.t; a.t += dt;
      const fadeIn = smooth(a.t / 0.16);
      const fadeOut = 1 - smooth((a.t - (a.clip.dur - 0.32)) / 0.32);
      const killed = a.fading != null ? 1 - smooth((a.t - a.fading) / 0.22) : 1;
      const w = fadeIn * fadeOut * killed * (1 - 0.6 * lying);
      const L = this.layer();
      a.clip.fn(Math.min(a.t, a.clip.dur), L, this.fx(prev, a.t, w));
      this.mix(P, L, w);
      if (Object.keys(L.face).length) faceLayers.push([L.face, w]);
      if (L.gaze && w > 0.5) P.gaze = L.gaze;
      a.w = w;
    }
    this.actions = this.actions.filter((a) => a.t < a.clip.dur && !(a.fading != null && a.t - a.fading > 0.25));
    // A sequence's next move starts as the last one settles, so they flow into each other.
    if (this.queue?.length && this.actions.every((a) => a.t > a.clip.dur - 0.35)) {
      const [next, ...rest] = this.queue;
      this.play(next);
      this.queue = rest;
    }
    const busy = this.actions.length > 0;

    // Speech: head beats on stressed syllables, ears perk, brows rise on questions.
    const speechOpen = this.speechStep(dt, P);

    // Things it does on its own when nothing else is happening: small fidgets, and in Balanced
    // and Lively the moments only a 3D body can have (turning round, twirling, its own tricks).
    // 'still' (Reduce Motion) starts nothing.
    const live = this.opts.liveliness;
    if (live !== 'still' && !busy && this.loopName === 'idle' && this.posture === 'stand' && !this.speech && !this.pet.active && t > this.nextFidget) {
      const gap = { minimal: [20, 40], balanced: [9, 18], lively: [4, 9] }[live] || [9, 18];
      this.nextFidget = t + rand(...gap);
      const moment = { balanced: 0.3, lively: 0.5 }[live] || 0;
      const pool = Math.random() < moment
        ? [...MOMENTS_3D, ...(this.C.moments || []), ...(this.C.moments || [])].filter((n) => !(this.C.skip || []).includes(n))
        : this.C.fidgets || ['lookAround', 'earTwitch', 'earTwitch', 'tilt', 'sniff', 'smile', 'stretch', 'hop', 'blinkDouble', 'giggle'];
      this.fidget(pick(pool));
    }
    if (sleeping > 0.8 && (t % 3.2) < dt) this.markAtHead('zzz');

    // Look-at: an idle drifting gaze when nobody is moving the pointer.
    this.lookStep(dt, P);

    // ── apply bones ──
    // Limbs that are part of the body (Nimbo's puffs) move less, so they never tear away from it.
    const ls = this.C.limbScale;
    if (ls) for (const n of ['armL', 'armR', 'handL', 'handR']) if (P.b[n]) P.b[n] = P.b[n].map((v) => v * ls);
    this.dynamics(dt, P, lying);
    this.followThrough(dt, P);
    // A body with no neck (Iris, one block) turns as a whole: `turnWhole` of the head's and chest's
    // yaw goes to the whole body, which a looking-round would otherwise wring like a towel.
    const tw = this.C.turnWhole;
    if (tw) for (const n of ['head', 'chest', 'spine']) if (P.b[n]) { P.root.ry += P.b[n][1] * tw; P.b[n][1] *= 1 - tw; }
    for (const [n, r] of Object.entries(this.rest)) {
      const e = P.b[n];
      const bone = this.bones[n];
      if (!e) { bone.quaternion.copy(r.q); continue; }
      const qm = new THREE.Quaternion().setFromEuler(new THREE.Euler(e[0] * D2R, e[1] * D2R, e[2] * D2R, 'YXZ'));
      bone.quaternion.copy(r.q).multiply(r.wi.clone().multiply(qm).multiply(r.w));
    }
    const R = P.root;
    // A small window has little headroom: jumps stay lower there (the ears would leave it).
    if (R.py > 0 && this.opts.hopScale) R.py *= this.opts.hopScale;
    // Floating characters hover above their shadow, bobbing.
    const hover = this.C.hover ? this.C.hover(t, lying) : 0;
    this.mover.position.set(this.pivot.x + R.px, this.pivot.y + R.py + hover, this.pivot.z + R.pz);
    this.mover.rotation.set(R.rx * D2R, R.ry * D2R, R.rz * D2R, 'YXZ');
    const sq = this.squashS.step(P.squash, dt);
    this.squashG.scale.set(1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq));
    const air = clamp((R.py + hover) / 0.6);
    this.blob.scale.setScalar(1 - 0.55 * air + 0.25 * lying);
    this.blob.material.opacity = 1 - 0.7 * air;

    this.root.updateMatrixWorld(true);
    this.placeEyes();
    this.measureHead(dt);
    // Calm: only breathing, blinking and slow glances, which read fine at the idle frame rate.
    this.calm = !busy && !this.speech && this.voice < 0.01 && this.loopName === 'idle' && this.pet.w.x < 0.01
      && Math.abs(this.look.yaw.v) < 40 && this.headA.length() < 2
      && Object.entries(this.postureW).every(([n, s]) => Math.abs(s.x - (n === this.posture ? 1 : 0)) < 0.01);

    // ── face ──
    this.faceStep(dt, faceLayers, P, speechOpen);
    this.marks.update(dt);
  }

  layer() { return { b: {}, root: { px: 0, py: 0, pz: 0, rx: 0, ry: 0, rz: 0 }, squash: 1, look: 1, face: {}, gaze: null }; }

  /** Adds layer L into P scaled by w (squash and look multiply toward their layer values). */
  mix(P, L, w) {
    for (const [n, v] of Object.entries(L.b)) add(P, n, v[0] * w, v[1] * w, v[2] * w);
    for (const k of Object.keys(P.root)) P.root[k] += L.root[k] * w;
    P.squash *= lerp(1, L.squash, w);
    P.look *= lerp(1, L.look, w);
  }

  fx(prev, now, w) {
    return { at: (t0, kind) => { if (w > 0.4 && prev < t0 && now >= t0) this.markAtHead(kind); } };
  }

  markAtHead(kind) {
    // In Sidefolk the 2D view draws the effects over the 3D character: ask it ('mark' event).
    if (this.opts.marks === false) { this.emit('mark', kind); return; }
    const p = new THREE.Vector3();
    this.bones.head.getWorldPosition(p);
    const side = kind === 'sweat' ? -1 : 1;
    const [mx, my, mz] = this.C.marks || [0.42, 0.62, 0.15];
    const off = kind === 'sweat' ? new THREE.Vector3(-mx, my * 0.35, mz + 0.05) : new THREE.Vector3(mx, my, mz);
    this.marks.emit(kind, p.add(off), side);
  }

  fidget(kind) {
    const t = this.time;
    switch (kind) {
      case 'earTwitch': {
        const twitchy = this.chains.filter((c) => c.twitch);
        const c = twitchy.length ? pick(twitchy) : null;
        if (c) { const last = c.segs.length - 1; c.segs[last].x.kick(rand(-260, -160)); c.segs[Math.max(0, last - 1)].z.kick(rand(-120, 120)); }
        break;
      }
      case 'blinkDouble': this.forceBlink(true); break;
      case 'tilt': this.tilt = { t0: t, dir: pick([1, -1]) }; break;
      case 'smile': this.flash = { mood: pick(['smile', 'happy', 'wink']), until: t + 1.6 }; break;
      default: this.play(kind);
    }
  }

  speechStep(dt, P) {
    let open = 0;
    if (this.speech) {
      const sp = this.speech; sp.t += dt;
      const seg = sp.segs.find((s) => sp.t >= s.t0 && sp.t < s.t1);
      if (seg) {
        const u = (sp.t - seg.t0) / (seg.t1 - seg.t0);
        open = seg.open * Math.sin(u * Math.PI);
        this.speechRound = seg.round;
        add(P, 'head', -2.5 * Math.sin(u * Math.PI) * seg.open, 0, 0);
      }
      const on = win01(sp.t, sp.end);
      add(P, 'head', 0, Math.sin(sp.t * 1.7) * 4 * on, Math.sin(sp.t * 1.1) * 4 * on + (sp.ask ? 8 * on : 0));
      add(P, 'chest', 0, Math.sin(sp.t * 1.3) * 2 * on, 0);
      for (const s of ['L', 'R']) add(P, `ear${s}2`, -4 * on);
      if (sp.t > sp.end) { this.speech = null; this.emit('speaking', false); }
    }
    if (this.voice > 0.01) open = Math.max(open, this.voice);
    return open;
  }

  lookStep(dt, P) {
    const L = this.look;
    const head = new THREE.Vector3(); this.bones.head.getWorldPosition(head);
    head.y += 0.1;
    let tgt = L.target;
    if (!tgt || this.time - (L.lastSeen ?? -99) > 6) {
      // Wandering attention: settle on a spot, sometimes the viewer, sometimes off to a side.
      if (this.time > L.idleT) {
        L.idleT = this.time + rand(1.8, 4.5);
        L.idleGoal.set(Math.random() < 0.45 ? 0 : rand(-0.9, 0.9), Math.random() < 0.5 ? 0 : rand(-0.4, 0.5));
      }
      tgt = this.camera.position.clone().add(new THREE.Vector3(L.idleGoal.x * 2.5, L.idleGoal.y * 1.6, 0));
    }
    const d = tgt.clone().sub(head);
    const yaw = clamp(Math.atan2(d.x, d.z) / D2R, -50, 50);
    const pitch = clamp(Math.atan2(-d.y, Math.hypot(d.x, d.z)) / D2R, -24, 30);
    const k = P.look;
    const hy = L.yaw.step(yaw * k, dt), hp = L.pitch.step(pitch * k, dt);
    add(P, 'head', hp * 0.8, hy * 0.78, 0);
    add(P, 'chest', hp * 0.15, hy * 0.2, 0);
    // Eyes lead the head: they point where the head is still turning to.
    let gx = clamp((yaw * k - hy * 0.98) / 22 + yaw * k / 140, -1, 1);
    let gy = clamp(-(pitch * k - hp * 0.95) / 18 - pitch * k / 120, -1, 1);
    if (P.gaze) { gx = P.gaze[0]; gy = P.gaze[1]; }
    if (this.time > this.nextSaccade) {
      this.nextSaccade = this.time + rand(0.5, 2.2);
      this.saccade.set(rand(-0.12, 0.12), rand(-0.08, 0.08));
      if (Math.abs(gx - this.gaze.x) > 0.5 && Math.random() < 0.5) this.forceBlink();
    }
    this.gaze.x = damp(this.gaze.x, gx + this.saccade.x, 26, dt);
    this.gaze.y = damp(this.gaze.y, gy + this.saccade.y, 26, dt);
  }

  /** Secondary motion: chains, scarf tag, tail and squash follow what the body really did. */
  dynamics(dt, P, lying) {
    const a = this.angAcc, lin = this.headA;
    const happy = ['happy', 'excited', 'laugh', 'giggle', 'love', 'content'].includes(this.face.curMood) ? 1 : 0;
    for (const c of this.chains) {
      const sx = c.side ?? 1, n = c.segs.length;
      const gain = c.gain ?? 1, breeze = c.breeze ?? 1;
      c.segs.forEach((seg, i) => {
        const g = (n === 1 ? 1 : [0.55, 1, 1.45, 1.7][i]) * gain;
        seg.x.kick((-a.x * 0.55 - lin.z * 40 - Math.abs(lin.y) * 22 - lin.y * 18) * g * dt);
        seg.z.kick((-a.z * 0.55 + lin.x * 40 + sx * lin.y * 26) * g * dt);
        // A tail wags when happy and sways a little on its own.
        const wag = c.wag ? (Math.sin(this.time * 12 - i * 0.9) * c.wag * happy + noise(this.time * 0.6, 7 + i) * c.wag * 0.35) * (i + 1) / n : 0;
        seg.x.step(0, dt); seg.z.step(wag, dt);
        const lim = c.limit || [55, 45];
        seg.x.x = clamp(seg.x.x, -lim[0], lim[0]); seg.z.x = clamp(seg.z.x, -lim[1], lim[1]);
        // A breeze that never quite stops: ears are alive even at rest.
        const br = noise(this.time * 0.8 + i * 0.4, sx * 3 + (c.seed ?? 0)) * (1.5 + i) * breeze;
        add(P, c.bones[i], seg.x.x + br, 0, seg.z.x + br * 0.4 * sx);
      });
    }
    // Head-tilt fidget.
    if (this.tilt) {
      const u = (this.time - this.tilt.t0) / 2.2;
      if (u > 1) this.tilt = null;
      else {
        const e = Math.sin(clamp(u) * Math.PI);
        add(P, 'head', 0, 0, this.tilt.dir * 16 * e);
        add(P, `ear${this.tilt.dir > 0 ? 'R' : 'L'}2`, 0, 0, this.tilt.dir * 8 * e);
      }
    }
    // Scarf tag hangs with gravity and swings with the chest.
    if (this.rest.scarf) {
      const bend = (n) => (P.b[n] ? P.b[n][0] : 0);
      const roll = (n) => (P.b[n] ? P.b[n][2] : 0);
      const pitchSum = bend('hips') + bend('spine') + bend('chest') + P.root.rx * (1 - lying);
      const rollSum = roll('hips') + roll('spine') + roll('chest') + P.root.rz;
      this.scarfS.x.kick((-a.x * 0.3 - lin.z * 60) * dt); this.scarfS.z.kick((-a.z * 0.3 + lin.x * 60) * dt);
      const sxp = this.scarfS.x.step(clamp(-pitchSum, -75, 3), dt);
      const szp = this.scarfS.z.step(clamp(-rollSum * 0.8, -40, 40), dt);
      add(P, 'scarf', clamp(sxp, -80, 4), 0, szp);
    }
    this.C.dynamics?.(this, dt, P, { lin, a, happy, lying });
  }

  /**
   * Overlapping action: the authored pose is where each part *wants* to be; slightly underdamped
   * springs get it there, so the torso leads, the head and arms trail and settle with a little
   * overshoot, and no move stops dead like a puppet's. Stiffer near the core, looser at the ends.
   */
  followThrough(dt, P) {
    const O = this.overlap ||= {};
    for (const [n, [k, d]] of Object.entries(FOLLOW)) {
      if (!this.rest[n]) continue;
      const target = P.b[n] || [0, 0, 0];
      const s = O[n] ||= [0, 1, 2].map((i) => new Spring(target[i], k, d));
      P.b[n] = target.map((v, i) => s[i].step(v, dt));
    }
    // The whole body turns with weight too (lying down, flips, sways); height stays exact so
    // hops and landings keep their timing.
    const R = P.root;
    const rs = O.root ||= { rx: new Spring(R.rx, 140, 19), ry: new Spring(R.ry, 140, 19), rz: new Spring(R.rz, 140, 19),
      px: new Spring(R.px, 160, 22), pz: new Spring(R.pz, 160, 22) };
    for (const k of ['rx', 'ry', 'rz', 'px', 'pz']) R[k] = rs[k].step(R[k], dt);
  }

  measureHead(dt) {
    const q = this.bones.head.getWorldQuaternion(new THREE.Quaternion());
    const dq = q.clone().multiply(this.prevHeadQ.clone().invert());
    if (dq.w < 0) { dq.x *= -1; dq.y *= -1; dq.z *= -1; dq.w *= -1; }
    const cw = clamp(dq.w, -1, 1);
    const ang = 2 * Math.acos(cw);
    const s = Math.sqrt(Math.max(0, 1 - cw * cw));
    const wNow = s > 1e-5 ? new THREE.Vector3(dq.x / s, dq.y / s, dq.z / s).multiplyScalar(ang / D2R / dt) : new THREE.Vector3();
    const acc = wNow.clone().sub(this.prevW).divideScalar(dt);
    this.angAcc.lerp(acc.clampLength(0, 9000), 0.5);
    this.prevW.copy(wNow); this.prevHeadQ.copy(q);
    const p = this.bones.head.getWorldPosition(new THREE.Vector3());
    const v = p.clone().sub(this.prevHeadP).divideScalar(dt);
    const la = v.clone().sub(this.headV).divideScalar(dt);
    this.headA.lerp(la.clampLength(0, 60), 0.5);
    this.headV.copy(v); this.prevHeadP.copy(p);
    for (const vec of [this.angAcc, this.prevW, this.headA, this.headV]) {
      if (!Number.isFinite(vec.x + vec.y + vec.z)) vec.set(0, 0, 0);
    }
  }

  forceBlink(double = false) { if (this.blink.t < 0) { this.blink.t = 0; this.blink.double = double; } }

  faceStep(dt, layers, P, speechOpen) {
    // Target: mood, a passing smile, then each move's face on top by its weight.
    let target = { ...(this.flash && this.time < this.flash.until ? moodFace(this.flash.mood) : this.moodFace) };
    let curMood = this.flash && this.time < this.flash.until ? this.flash.mood : this.mood;
    for (const [lf, w] of layers) {
      const lt = { ...(lf.mood ? moodFace(lf.mood) : target), ...lf };
      for (const k of Object.keys(target)) {
        if (typeof lt[k] !== 'number') continue;
        // Eyes are either open or shut for a feeling: half-blended lids read as smug, so they
        // switch with the stronger layer (and still animate, smoothed below).
        target[k] = SNAP.has(k) ? (w > 0.5 ? lt[k] : target[k]) : lerp(target[k], lt[k], w);
      }
      if (w > 0.5 && lf.mood) curMood = lf.mood;
    }
    if (this.speech || this.voice > 0.01) {
      target.mouthOpen = Math.max(target.mouthOpen * 0.4, speechOpen);
      target.mouthRound = lerp(target.mouthRound, this.speechRound || 0, 0.6);
      target.lid = Math.min(target.lid, 0.5);
      if (this.speech?.ask) target.browRaise = Math.max(target.browRaise, 0.5);
    }
    const f = this.face;
    f.curMood = curMood;
    for (const k of Object.keys(target)) {
      const rate = k === 'mouthOpen' ? 28 : k.startsWith('lid') || k === 'winkL' || k === 'winkR' ? 16 : 10;
      f[k] = damp(f[k] ?? target[k], target[k], rate, dt);
    }
    f.time = this.time;

    // Blinks: 2.5–6 s apart, sometimes double, quick to close and slower to open.
    const B = this.blink;
    let blink = 0;
    if (B.t < 0 && this.time > B.next) { B.t = 0; B.double = Math.random() < 0.18; }
    if (B.t >= 0) {
      B.t += dt;
      const len = B.double ? 0.42 : 0.19;
      const u = B.t;
      blink = B.double ? Math.max(blinkCurve(u), blinkCurve(u - 0.22)) : blinkCurve(u);
      if (B.t > len) { B.t = -1; B.next = this.time + rand(2.4, 6); }
    }
    f.lidL = clamp(Math.max(f.lid, f.winkL, blink));
    f.lidR = clamp(Math.max(f.lid, f.winkR, blink));
    f.gazeX = this.gaze.x; f.gazeY = this.gaze.y;

    for (const e of this.eyes) {
      const lid = e.side > 0 ? f.lidL : f.lidR;
      e.uniforms.uLid.value.set(lid, f.lidSlant, f.lidBottom, f.lidBottomSlant);
      e.uniforms.uGaze.value.set(this.gaze.x, this.gaze.y);
      // `face.twinkle: false`: no idle twinkle (a thin cross over a dark iris or a lens), only real sparkles.
      e.uniforms.uSparkle.value = this.C.face.twinkle === false && f.sparkle < 0.5 ? 0 : clamp(f.sparkle);
      const open = f.eyeOpen;
      e.mesh.scale.set(1 + (open - 1) * 0.55, open, 1);
      e.mesh.position.set(this.gaze.x * 0.012, this.gaze.y * 0.008, 0);
      e.mesh.visible = lid < 0.985 && f.dizzy < 0.5;
    }

    // Repaint the decal only when what it shows changed.
    const key = this.face3.key(f);
    if (key !== this.faceKey) {
      this.faceKey = key;
      this.face3.paint(f, this.eyes);
    }
  }

  // ───────────────────────────── pointer ─────────────────────────────

  bindPointer() {
    const el = this.canvas;
    const ray = new THREE.Raycaster();
    const ndc = (e) => {
      const r = el.getBoundingClientRect();
      return new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    };
    const hit = (e) => {
      ray.setFromCamera(ndc(e), this.camera);
      const h = ray.intersectObjects([this.pickHead, this.pickBody, ...this.pickEars], false)[0];
      if (!h) return null;
      return h.object === this.pickHead ? 'head' : h.object === this.pickBody ? 'body' : 'ear';
    };
    let down = null, clicks = [];
    window.addEventListener('pointermove', (e) => {
      const n = ndc(e); this.lookAt(n.x, n.y);
      if (down) {
        const d = Math.hypot(e.clientX - down.x, e.clientY - down.y);
        if (d > 14 && (down.part === 'head' || down.part === 'ear')) {
          this.pet.active = true;
          this.pet.x = clamp((e.clientX - down.x) / 80, -1, 1);
        }
      }
      el.style.cursor = hit(e) ? 'pointer' : 'default';
    });
    el.addEventListener('pointerdown', (e) => {
      const part = hit(e);
      if (!part) return;
      down = { x: e.clientX, y: e.clientY, part, t: this.time };
    });
    window.addEventListener('pointerup', () => {
      if (!down) return;
      const petted = this.pet.active;
      this.pet.active = false;
      if (petted) this.emit('petted');
      else {
        clicks = clicks.filter((c) => this.time - c < 2).concat(this.time);
        if (clicks.length >= 5) { clicks = []; this.play('dizzy'); }
        else if (down.part === 'ear') { this.fidget('earTwitch'); this.play('boop'); }
        else if (down.part === 'head') this.play('boop');
        else this.play('giggle');
        this.emit('clicked', down.part);
      }
      down = null;
    });
    el.addEventListener('dblclick', () => this.play('hop'));
    window.addEventListener('resize', () => this.resize());
  }
}

const SNAP = new Set(['lid', 'happyEyes', 'giddy', 'winkL', 'winkR', 'dizzy']);
const blinkCurve = (u) => (u < 0 ? 0 : u < 0.07 ? smooth(u / 0.07) : u < 0.1 ? 1 : 1 - smooth((u - 0.1) / 0.09));
const win01 = (t, end) => smooth(t / 0.2) * (1 - smooth((t - end + 0.25) / 0.25));
