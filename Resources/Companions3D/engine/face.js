// A companion's face, from its character's `face` settings. Two kinds:
//  - ink: glossy 3D eyes with shader eyelids, and a painted layer (nose, mouth, blush, brows,
//    closed-eye arcs, tears) on a decal cut from the head itself, so it bends with it.
//  - screen: everything glows on a dark visor (Spark): eyes, lids and mouth are light, painted.
// Model units, three.js axes: x = the character's left, y up, z toward the viewer.
import * as THREE from 'three';

const CANVAS = 1024;

export class Face {
  constructor(cfg) {
    this.cfg = cfg;
    const { R, span, cx = 0, cz = 0, cy = 0 } = cfg.unwrap;
    this.R = R; this.span = span; this.cx = cx; this.cz = cz; this.cy = cy;
    this.unit = CANVAS / (2 * span);
    this.L = cfg.layout;
    this.C = { ink: '#16285e', brow: null, mouth: '#8c1f33', mouthDeep: '#5e1424', tongue: '#ff7a86', lip: '#3a1630', blush: '255,140,160', ...cfg.colors };
  }

  // Cylindrical unwrap around the head's vertical axis: arc length keeps features undistorted on
  // the sides of the face (blush), where a flat projection would stretch them.
  arc(x, z) { return Math.atan2(x - this.cx, z - this.cz) * this.R; }
  px(s) { return (s + this.span) / (2 * this.span) * CANVAS; }
  py(y) { return (1 - (y - this.cy + this.span) / (2 * this.span)) * CANVAS; }
  /** Canvas point of a face feature at (x, y) on the front of the head (x measured from its middle). */
  at(x, y) { return [this.px(Math.atan2(x, this.R) * this.R), this.py(y)]; }

  /** The decal: the head's front triangles, lifted a hair off the surface, skinned like the head. */
  buildDecal(body) {
    const g = body.geometry;
    const pos = g.attributes.position, nor = g.attributes.normal;
    const idx = g.index.array;
    const keep = [];
    const region = this.cfg.region;
    const inFace = (i) => {
      const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
      return Math.abs(this.arc(x, z)) < this.span && region(x, y, z);
    };
    for (let t = 0; t < idx.length; t += 3) {
      if (inFace(idx[t]) && inFace(idx[t + 1]) && inFace(idx[t + 2])) keep.push(idx[t], idx[t + 1], idx[t + 2]);
    }
    const map = new Map(); const order = [];
    for (const i of keep) if (!map.has(i)) { map.set(i, order.length); order.push(i); }
    const n = order.length;
    const lift = this.cfg.lift ?? 0.0025;
    const P = new Float32Array(n * 3), N = new Float32Array(n * 3), U = new Float32Array(n * 2);
    const SI = new (g.attributes.skinIndex.array.constructor)(n * 4), SW = new Float32Array(n * 4);
    order.forEach((i, k) => {
      const nx = nor.getX(i), ny = nor.getY(i), nz = nor.getZ(i);
      const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
      P.set([x + nx * lift, y + ny * lift, z + nz * lift], k * 3); N.set([nx, ny, nz], k * 3);
      U.set([(this.arc(x, z) + this.span) / (2 * this.span), (y - this.cy + this.span) / (2 * this.span)], k * 2);
      for (let j = 0; j < 4; j++) {
        SI[k * 4 + j] = g.attributes.skinIndex.getComponent(i, j);
        SW[k * 4 + j] = g.attributes.skinWeight.getComponent(i, j);
      }
    });
    const dg = new THREE.BufferGeometry();
    dg.setAttribute('position', new THREE.BufferAttribute(P, 3));
    dg.setAttribute('normal', new THREE.BufferAttribute(N, 3));
    dg.setAttribute('uv', new THREE.BufferAttribute(U, 2));
    dg.setAttribute('skinIndex', new THREE.BufferAttribute(SI, 4));
    dg.setAttribute('skinWeight', new THREE.BufferAttribute(SW, 4));
    dg.setIndex(keep.map((i) => map.get(i)));

    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = CANVAS;
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    const screen = this.cfg.kind === 'screen';
    // A screen's face is light itself: it glows and isn't shaded by the scene.
    const mat = screen
      ? new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, toneMapped: false, blending: THREE.AdditiveBlending,
        polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 })
      : new THREE.MeshStandardMaterial({ map: tex, transparent: true, depthWrite: false, roughness: 0.55,
        polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
    const decal = new THREE.SkinnedMesh(dg, mat);
    decal.name = 'FaceDecal';
    decal.bind(body.skeleton, body.bindMatrix);
    decal.frustumCulled = false;
    decal.renderOrder = 2;
    this.canvas = canvas; this.tex = tex; this.ctx = canvas.getContext('2d');
    return decal;
  }

  /** Repaints the face for `f` (the engine's face state). */
  paint(f, eyes) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, CANVAS, CANVAS);
    if (this.cfg.kind === 'screen') this.paintScreen(ctx, f);
    else this.paintInk(ctx, f, eyes);
    this.tex.needsUpdate = true;
  }

  /** What changes the painted face: repaint only when this string changes. */
  key(f) {
    const v = [f.blush, f.shy, f.mouthOpen, f.smile, f.mouthWidth, f.mouthRound, f.cat, f.wavy, f.mouthX, f.brow, f.browAngle, f.browRaise,
      f.lidL > 0.8 ? f.lidL : 0, f.lidR > 0.8 ? f.lidR : 0, f.happyEyes, f.giddy, f.tears > 0.05 ? f.time : 0, f.dizzy > 0.05 ? f.time : 0,
      f.noseTwitch, (f.lidL > 0.8 || f.lidR > 0.8) ? f.gazeX : 0];
    // On a screen the eyes are painted too: every blink, glance and lid change repaints.
    if (this.cfg.kind === 'screen') v.push(f.lidL, f.lidR, f.gazeX, f.gazeY, f.eyeOpen, f.lidSlant, f.lidBottom);
    return v.map((x) => x.toFixed(3)).join();
  }

  // ─────────────────────────── ink faces ───────────────────────────

  paintInk(ctx, f, eyes) {
    const L = this.L, C = this.C, u = this.unit;

    // Blush: soft, always a little there, stronger when happy or shy.
    for (const side of [1, -1]) {
      const [cx, cy] = this.at(side * L.blush.x, L.blush.y);
      const rx = L.blush.w * u, ry = L.blush.h * u;
      const a = (L.blush.alpha ?? 0.42) * f.blush;
      if (a > 0.01) {
        const grd = ctx.createRadialGradient(cx, cy, 0, cx, cy, rx);
        grd.addColorStop(0, `rgba(${C.blush},${a})`);
        grd.addColorStop(0.55, `rgba(${C.blush},${a * 0.6})`);
        grd.addColorStop(1, `rgba(${C.blush},0)`);
        ctx.save(); ctx.translate(cx, cy); ctx.scale(1, ry / rx); ctx.translate(-cx, -cy);
        ctx.fillStyle = grd; ctx.beginPath(); ctx.arc(cx, cy, rx, 0, Math.PI * 2); ctx.fill(); ctx.restore();
      }
      if (f.shy > 0.05) { // little embarrassed hatch lines on the cheeks
        ctx.strokeStyle = `rgba(230,90,120,${0.7 * f.shy})`; ctx.lineWidth = 5; ctx.lineCap = 'round';
        for (let k = -1; k <= 1; k++) {
          ctx.beginPath(); ctx.moveTo(cx + k * 22 - 8, cy + 10); ctx.lineTo(cx + k * 22 + 8, cy - 10); ctx.stroke();
        }
      }
    }

    if (L.nose) this.paintNose(ctx, f);
    this.paintMouth(ctx, f);

    // Brows: always there for some characters (`brow.base`), or only for strong feelings.
    const browA = Math.min(1, f.brow + (L.brow?.base ?? 0));
    if (browA > 0.02) {
      const B = L.brow || {};
      for (const side of [1, -1]) {
        const [cx] = this.at(side * (B.x ?? L.eye.x), 0);
        const cy = this.py((B.y ?? L.eye.y + L.eye.h * 0.62) + f.browRaise * 0.02);
        const len = (B.len ?? L.eye.w * 0.75) * u;
        const ang = side * f.browAngle + side * (B.tilt ?? 0); // + = inner ends down (angry), − = up (sad)
        ctx.save(); ctx.translate(cx, cy); ctx.rotate(-ang);
        ctx.globalAlpha = browA;
        ctx.strokeStyle = C.brow || C.ink; ctx.lineWidth = B.width ?? 11; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(-len / 2, 0); ctx.quadraticCurveTo(0, -(B.arch ?? 8), len / 2, 0); ctx.stroke();
        ctx.restore();
      }
    }

    // Closed eyes are drawn where the 3D eyes hide: ^ for happy, a soft ‿ for sleep, > < for giddy.
    for (const e of eyes) {
      const lid = e.side > 0 ? f.lidL : f.lidR;
      const [cx] = this.at(e.side * L.eye.x + f.gazeX * 0.012, 0);
      const cy = this.py(L.eye.y + f.gazeY * 0.01);
      const w = L.eye.w * u * 0.95;
      ctx.strokeStyle = C.ink; ctx.lineCap = 'round';
      if (f.dizzy > 0.05) {
        ctx.globalAlpha = f.dizzy; ctx.lineWidth = 7;
        ctx.beginPath();
        for (let a = 0; a < Math.PI * 5; a += 0.15) {
          const r = (a / (Math.PI * 5)) * w * 0.55;
          const rot = a + f.time * 6 * e.side;
          ctx.lineTo(cx + Math.cos(rot) * r, cy + Math.sin(rot) * r * 1.2);
        }
        ctx.stroke(); ctx.globalAlpha = 1;
        continue;
      }
      const closed = THREE.MathUtils.smoothstep(lid, 0.82, 0.97);
      if (closed < 0.01) continue;
      ctx.globalAlpha = closed; ctx.lineWidth = 11;
      ctx.beginPath();
      if (f.giddy > 0.5) {               // > <
        const d = e.side > 0 ? -1 : 1, h = w * 0.32;
        ctx.moveTo(cx - d * w * 0.3, cy - h); ctx.lineTo(cx + d * w * 0.25, cy); ctx.lineTo(cx - d * w * 0.3, cy + h);
      } else {
        // happy (1) arches up like ^, sleepy (0) curves gently down like ‿.
        const bend = THREE.MathUtils.lerp(16, -30, f.happyEyes);
        ctx.moveTo(cx - w / 2, cy); ctx.quadraticCurveTo(cx, cy + bend * 1.6, cx + w / 2, cy);
      }
      ctx.stroke(); ctx.globalAlpha = 1;
    }

    // Tears for real sadness.
    if (f.tears > 0.05) {
      for (const side of [1, -1]) {
        const [x0] = this.at(side * (L.eye.x + 0.01), 0);
        const cx = x0 + side * 10, cy = this.py(L.eye.y - L.eye.h * 0.45) + 30 * ((f.time * 0.6) % 1);
        ctx.fillStyle = `rgba(120,200,255,${f.tears * 0.9})`;
        ctx.beginPath(); ctx.moveTo(cx, cy - 18); ctx.quadraticCurveTo(cx + 12, cy + 2, cx, cy + 12);
        ctx.quadraticCurveTo(cx - 12, cy + 2, cx, cy - 18); ctx.fill();
      }
    }
  }

  paintNose(ctx, f) {
    const N = this.L.nose, C = this.C, u = this.unit;
    const [cx, y0] = this.at(0, N.y); const cy = y0 + f.noseTwitch * 4;
    const w = N.w * u, h = N.h * u;
    ctx.fillStyle = N.color || C.ink;
    ctx.beginPath();
    if (N.shape === 'button') {          // a tiny soft nub: a shadow under a highlight
      ctx.globalAlpha = 0.5;
      ctx.ellipse(cx, cy, w / 2, h / 2, 0, 0, Math.PI * 2); ctx.fill(); ctx.globalAlpha = 1;
      return;
    }
    if (N.shape === 'fox') {             // a rounded triangle, wider on top
      ctx.moveTo(cx - w / 2, cy - h * 0.35);
      ctx.quadraticCurveTo(cx, cy - h * 0.62, cx + w / 2, cy - h * 0.35);
      ctx.quadraticCurveTo(cx + w * 0.32, cy + h * 0.5, cx, cy + h * 0.5);
      ctx.quadraticCurveTo(cx - w * 0.32, cy + h * 0.5, cx - w / 2, cy - h * 0.35);
    } else ctx.ellipse(cx, cy, w / 2, h / 2, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ctx.beginPath(); ctx.ellipse(cx - w * 0.15, cy - h * 0.18, w * 0.16, h * 0.13, 0, 0, Math.PI * 2); ctx.fill();
  }

  paintMouth(ctx, f) {
    const C = this.C, M = this.L.mouth, u = this.unit;
    const [cx, cy] = this.at(f.mouthX * 0.02, M.y);
    const scale = M.scale ?? 1;
    const open = Math.max(0, f.mouthOpen);
    // Open smiles widen too (a big "D" grin).
    const w = (0.048 + 0.075 * f.mouthWidth) * u * scale * (1 - 0.35 * f.mouthRound) * (1 + 0.3 * Math.min(open, 0.8));
    const smile = f.smile;             // −1 frown … 1 big smile
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const line = (M.line ?? 10) * Math.sqrt(scale);

    if (f.cat > 0.5 && open < 0.1) {   // a little ω mouth
      ctx.strokeStyle = C.ink; ctx.lineWidth = line;
      ctx.beginPath();
      ctx.moveTo(cx - w * 0.6, cy - 4); ctx.quadraticCurveTo(cx - w * 0.3, cy + 16 * scale, cx, cy);
      ctx.quadraticCurveTo(cx + w * 0.3, cy + 16 * scale, cx + w * 0.6, cy - 4); ctx.stroke();
      return;
    }
    if (open < 0.06) {                  // closed: one soft curve
      ctx.strokeStyle = C.ink; ctx.lineWidth = line;
      ctx.beginPath();
      if (f.wavy > 0.3) {               // confused squiggle
        ctx.moveTo(cx - w / 2, cy); ctx.bezierCurveTo(cx - w / 6, cy - 16, cx + w / 6, cy + 16, cx + w / 2, cy);
      } else {
        ctx.moveTo(cx - w / 2, cy - smile * 7 * scale); ctx.quadraticCurveTo(cx, cy + smile * 30 * scale, cx + w / 2, cy - smile * 7 * scale);
      }
      ctx.stroke();
      return;
    }
    // Open: a top edge that follows the smile and a deeper bottom edge; rounder for "o".
    const h = (16 + 104 * open) * scale * (1 + 0.25 * f.mouthRound);
    const top = cy - smile * 6 - h * 0.12 * f.mouthRound;
    const lift = smile * 10 * scale * (1 - f.mouthRound);
    const outline = new Path2D();
    if (f.mouthRound > 0.5) {
      outline.ellipse(cx, cy + h * 0.25, w * 0.42, h * 0.55, 0, 0, Math.PI * 2);
    } else {
      outline.moveTo(cx - w / 2, top - lift);
      outline.quadraticCurveTo(cx, top + smile * 8, cx + w / 2, top - lift);
      outline.bezierCurveTo(cx + w / 2, top + h * 0.95, cx - w / 2, top + h * 0.95, cx - w / 2, top - lift);
      outline.closePath();
    }
    // Inside: deep red, darker toward the throat, a soft tongue resting low; clipped to the mouth.
    ctx.save();
    ctx.clip(outline);
    const g = ctx.createLinearGradient(0, top, 0, top + h);
    g.addColorStop(0, C.mouthDeep); g.addColorStop(1, C.mouth);
    ctx.fillStyle = g; ctx.fill(outline);
    const tg = ctx.createRadialGradient(cx, top + h * 0.95, 0, cx, top + h * 0.95, w * 0.42);
    tg.addColorStop(0, C.tongue); tg.addColorStop(1, '#e8566a');
    ctx.fillStyle = tg;
    ctx.beginPath(); ctx.ellipse(cx, top + h * 0.98, w * 0.34, h * 0.4, 0, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
    // A thin lip line around the mouth itself (never around the tongue).
    ctx.strokeStyle = C.lip; ctx.lineWidth = 4.5 * Math.sqrt(scale);
    ctx.stroke(outline);
  }

  // ─────────────────────────── screen faces ───────────────────────────

  /** Light on a dark visor: soft-edged glowing shapes with a wider halo, like the sheet. */
  paintScreen(ctx, f) {
    const L = this.L, u = this.unit, glow = this.cfg.glow || '57,230,224';
    const light = (draw, width) => {
      // Halo, then core: three passes read as light in the glass without a blur filter.
      for (const [lw, a] of [[width * 3.2, 0.12], [width * 1.8, 0.28], [width, 1]]) {
        ctx.strokeStyle = ctx.fillStyle = `rgba(${glow},${a})`; ctx.lineWidth = lw; draw();
      }
    };
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    for (const side of [1, -1]) {
      const lid = side > 0 ? f.lidL : f.lidR;
      const [cx] = this.at(side * L.eye.x + f.gazeX * 0.03, 0);
      const cy = this.py(L.eye.y + f.gazeY * 0.022);
      const w = L.eye.w * u * (1 + (f.eyeOpen - 1) * 0.5), h = L.eye.h * u * f.eyeOpen;
      if (f.dizzy > 0.05) {
        light(() => { ctx.beginPath(); for (let a = 0; a < Math.PI * 5; a += 0.15) {
          const r = (a / (Math.PI * 5)) * w * 0.6, rot = a + f.time * 6 * side;
          ctx.lineTo(cx + Math.cos(rot) * r, cy + Math.sin(rot) * r * 1.2); } ctx.stroke(); }, 9);
        continue;
      }
      const closed = THREE.MathUtils.smoothstep(lid, 0.82, 0.97);
      if (closed > 0.5) {
        light(() => {
          ctx.beginPath();
          if (f.giddy > 0.5) {
            const d = side > 0 ? -1 : 1, hh = w * 0.4;
            ctx.moveTo(cx - d * w * 0.35, cy - hh); ctx.lineTo(cx + d * w * 0.3, cy); ctx.lineTo(cx - d * w * 0.35, cy + hh);
          } else {
            const bend = THREE.MathUtils.lerp(18, -34, f.happyEyes);
            ctx.moveTo(cx - w * 0.62, cy); ctx.quadraticCurveTo(cx, cy + bend * 1.6, cx + w * 0.62, cy);
          }
          ctx.stroke();
        }, 15);
        continue;
      }
      // An open eye: a tall rounded pill, cut by the lids (top with a slant for moods, bottom
      // pushed up by a smile).
      ctx.save();
      // Open lids sit just outside the halo; shut, they meet in the middle.
      const top = cy - h * 0.8 + h * 1.3 * lid, bot = cy + h * 0.8 - h * 1.3 * f.lidBottom;
      const sl = f.lidSlant * h * 0.5 * side;
      ctx.beginPath();
      ctx.moveTo(cx - w, top + sl); ctx.lineTo(cx + w, top - sl); ctx.lineTo(cx + w, bot); ctx.lineTo(cx - w, bot); ctx.closePath();
      ctx.clip();
      for (const [grow, a] of [[1.5, 0.12], [1.22, 0.3], [1, 1]]) {
        ctx.fillStyle = `rgba(${glow},${a})`;
        ctx.beginPath(); ctx.ellipse(cx, cy, w / 2 * grow, h / 2 * grow, 0, 0, Math.PI * 2); ctx.fill();
      }
      // A brighter core and a glint.
      ctx.fillStyle = 'rgba(220,255,252,0.55)';
      ctx.beginPath(); ctx.ellipse(cx - w * 0.12, cy - h * 0.18, w * 0.16, h * 0.14, 0, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
    }
    // Mouth: a small glowing curve, an "o" or an open smile.
    const [mx, my] = this.at(f.mouthX * 0.03, L.mouth.y);
    const mw = (0.05 + 0.07 * f.mouthWidth) * u * (1 - 0.35 * f.mouthRound);
    const open = Math.max(0, f.mouthOpen);
    if (open > 0.08) {
      const h = (10 + 60 * open) * (1 + 0.2 * f.mouthRound);
      for (const [grow, a] of [[1.4, 0.14], [1.18, 0.3], [1, 0.95]]) {
        ctx.fillStyle = `rgba(${glow},${a})`;
        ctx.beginPath();
        if (f.mouthRound > 0.5) ctx.ellipse(mx, my + h * 0.2, mw * 0.4 * grow, h * 0.5 * grow, 0, 0, Math.PI * 2);
        else {
          ctx.moveTo(mx - mw / 2 * grow, my - f.smile * 4);
          ctx.quadraticCurveTo(mx, my + f.smile * 4, mx + mw / 2 * grow, my - f.smile * 4);
          ctx.bezierCurveTo(mx + mw / 2 * grow, my + h * grow, mx - mw / 2 * grow, my + h * grow, mx - mw / 2 * grow, my - f.smile * 4);
        }
        ctx.fill();
      }
    } else {
      light(() => {
        ctx.beginPath();
        if (f.wavy > 0.3) { ctx.moveTo(mx - mw / 2, my); ctx.bezierCurveTo(mx - mw / 6, my - 14, mx + mw / 6, my + 14, mx + mw / 2, my); }
        else if (f.cat > 0.5) { ctx.moveTo(mx - mw * 0.6, my - 3); ctx.quadraticCurveTo(mx - mw * 0.3, my + 14, mx, my); ctx.quadraticCurveTo(mx + mw * 0.3, my + 14, mx + mw * 0.6, my - 3); }
        else { ctx.moveTo(mx - mw / 2, my - f.smile * 6); ctx.quadraticCurveTo(mx, my + f.smile * 26, mx + mw / 2, my - f.smile * 6); }
        ctx.stroke();
      }, 10);
    }
    if (f.tears > 0.05) {
      for (const side of [1, -1]) {
        const [x] = this.at(side * L.eye.x, 0), y = this.py(L.eye.y - L.eye.h * 0.7) + 24 * ((f.time * 0.6) % 1);
        ctx.fillStyle = `rgba(${glow},${0.8 * f.tears})`;
        ctx.beginPath(); ctx.ellipse(x + side * 18, y, 7, 11, 0, 0, Math.PI * 2); ctx.fill();
      }
    }
  }
}

/**
 * One glossy ink eye: a shallow ellipsoid with an iris gradient, an under-glow and two crisp
 * highlights, all in the shader so eyelids can cut it (lid top/bottom, slanted for moods).
 */
export function buildEye(side, eye, iris = {}) {
  const { w, h, depth } = eye;
  const I = { deep: [0.004, 0.011, 0.045], rim: [0.015, 0.045, 0.16], glow: [0.03, 0.32, 0.7], glowAmt: 0.45, ...iris };
  const v3 = (a) => `vec3(${a.map((x) => x.toFixed(4)).join(',')})`;
  const geo = new THREE.SphereGeometry(1, 48, 32);
  geo.scale(w / 2, h / 2, depth);
  const mat = new THREE.MeshPhysicalMaterial({
    color: 0x0b2d5b, roughness: 0.18, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.04, envMapIntensity: 0.55,
  });
  const u = {
    uLid: { value: new THREE.Vector4(0, 0, 0, 0) },   // top, top slant, bottom, bottom slant
    uGaze: { value: new THREE.Vector2(0, 0) },
    uSparkle: { value: 0 },
    uSide: { value: side },
  };
  mat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, u);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vEye;')
      .replace('#include <begin_vertex>', `#include <begin_vertex>\nvEye = position / vec3(${(w / 2).toFixed(4)}, ${(h / 2).toFixed(4)}, ${depth.toFixed(4)});`);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>
        varying vec3 vEye; uniform vec4 uLid; uniform vec2 uGaze; uniform float uSparkle; uniform float uSide;`)
      .replace('#include <color_fragment>', `#include <color_fragment>
        // Eyelids: cut away above the top lid and below the bottom lid (the head shows behind).
        float topLine = 1.0 - 2.0 * uLid.x + uLid.y * vEye.x * uSide;
        float botLine = -1.0 + 2.0 * uLid.z + uLid.w * vEye.x * uSide;
        if (vEye.y > topLine || vEye.y < botLine) discard;
        vec2 q = vEye.xy - uGaze * 0.35;
        // Iris: deep in the middle, a touch lighter toward the rim, a glow pooling at the bottom.
        vec3 c = mix(${v3(I.deep)}, ${v3(I.rim)}, smoothstep(0.55, 1.0, length(q)));
        float glow = smoothstep(0.35, 0.95, -q.y) * (1.0 - smoothstep(0.8, 1.0, length(q * vec2(1.0, 0.9))));
        c = mix(c, ${v3(I.glow)}, glow * ${I.glowAmt.toFixed(3)});
        ${I.pupil ? `c = mix(c, vec3(0.0), (1.0 - smoothstep(${I.pupil.toFixed(3)}, ${(I.pupil + 0.08).toFixed(3)}, length(q))) * 0.9);` : ''}
        diffuseColor.rgb = c;`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        // Two crisp highlights (they drift a little against the gaze, like a real reflection).
        vec2 h1 = vEye.xy - vec2(0.30 * uSide + 0.0, 0.38) + uGaze * 0.12;
        vec2 h2 = vEye.xy - vec2(-0.32 * uSide, -0.40) + uGaze * 0.12;
        float s1 = 1.0 - smoothstep(0.25, 0.28, length(h1 * vec2(1.0, 0.85)));
        float s2 = 1.0 - smoothstep(0.10, 0.125, length(h2));
        float star = uSparkle * (1.0 - smoothstep(0.02, 0.05, min(abs(h2.x) * abs(h2.y) * 30.0, length(h2) - 0.05)));
        totalEmissiveRadiance += vec3(1.0) * max(max(s1, s2 * 0.9), star) * 1.6;`);
  };
  const mesh = new THREE.Mesh(geo, mat);
  mesh.renderOrder = 3;
  const group = new THREE.Group();
  group.add(mesh);
  return { group, mesh, uniforms: u, side };
}
