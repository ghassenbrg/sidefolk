// Little floating marks around Mochi's head: zZz, ?, !, hearts, notes, sparkles, stars, sweat.
import * as THREE from 'three';
import { easeOutBack, clamp } from './motion.js';

const INK = '#1e3a8a';
const DRAW = {
  z: (c) => text(c, 'z', INK, 150),
  question: (c) => text(c, '?', INK, 170),
  bang: (c) => text(c, '!', '#ff5a6e', 180),
  dots: (c) => { c.fillStyle = INK; for (let i = 0; i < 3; i++) { c.beginPath(); c.arc(70 + i * 58, 128, 17, 0, 7); c.fill(); } },
  heart: (c) => {
    c.fillStyle = '#ff6b8b';
    c.beginPath(); c.moveTo(128, 205);
    c.bezierCurveTo(30, 140, 40, 50, 128, 85); c.bezierCurveTo(216, 50, 226, 140, 128, 205); c.fill();
    c.fillStyle = 'rgba(255,255,255,.6)'; c.beginPath(); c.ellipse(90, 100, 18, 12, -0.6, 0, 7); c.fill();
  },
  note: (c) => text(c, '♪', '#14b8c4', 170),
  sparkle: (c) => star4(c, '#2ed4d9'),
  star: (c) => star4(c, '#ffc93c'),
  sweat: (c) => {
    c.fillStyle = '#8fd8ff';
    c.beginPath(); c.moveTo(128, 40); c.quadraticCurveTo(200, 150, 128, 200); c.quadraticCurveTo(56, 150, 128, 40); c.fill();
    c.fillStyle = 'rgba(255,255,255,.7)'; c.beginPath(); c.ellipse(108, 150, 12, 20, 0.3, 0, 7); c.fill();
  },
};
function text(c, s, color, size) {
  c.font = `800 ${size}px ui-rounded, "SF Pro Rounded", system-ui, sans-serif`;
  c.textAlign = 'center'; c.textBaseline = 'middle';
  c.lineWidth = 14; c.strokeStyle = 'rgba(255,255,255,.9)'; c.strokeText(s, 128, 134);
  c.fillStyle = color; c.fillText(s, 128, 134);
}
function star4(c, color) {
  c.fillStyle = color; c.beginPath();
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4 - Math.PI / 2, r = i % 2 ? 26 : 100;
    c.lineTo(128 + Math.cos(a) * r, 128 + Math.sin(a) * r);
  }
  c.fill();
}

export class Marks {
  constructor(parent) {
    this.parent = parent; this.live = []; this.tex = {};
  }
  texture(kind) {
    if (this.tex[kind]) return this.tex[kind];
    const cv = document.createElement('canvas'); cv.width = cv.height = 256;
    DRAW[kind](cv.getContext('2d'));
    const t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace;
    return (this.tex[kind] = t);
  }
  /** Spawns a mark at `origin` (world), drifting up and out on `side` (+1 right, −1 left). */
  emit(kind, origin, side = 1) {
    if (kind === 'zzz') { [0, 0.45, 0.9].forEach((d, i) => this.emit2('z', origin, side, d, 0.7 + i * 0.25)); return; }
    this.emit2(kind === 'think' ? 'dots' : kind, origin, side, 0, 1);
  }
  emit2(kind, origin, side, delay, size) {
    if (!DRAW[kind]) return;
    const mat = new THREE.SpriteMaterial({ map: this.texture(kind), transparent: true, depthWrite: false, opacity: 0 });
    const s = new THREE.Sprite(mat);
    s.renderOrder = 10;
    this.parent.add(s);
    this.live.push({ s, kind, origin: origin.clone(), side, t: -delay, life: kind === 'dots' ? 2.2 : 1.9, size, seed: Math.random() * 6 });
  }
  update(dt) {
    for (const m of this.live) {
      m.t += dt;
      const u = clamp(m.t / m.life);
      const pop = easeOutBack(clamp(m.t / 0.35));
      const rise = m.kind === 'sweat' ? -0.12 * u : 0.36 * (1 - Math.pow(1 - u, 2));
      const drift = m.kind === 'sweat' ? 0 : m.side * (0.1 * u + Math.sin(m.t * 3 + m.seed) * 0.025);
      m.s.position.set(m.origin.x + drift, m.origin.y + rise, m.origin.z);
      const sc = 0.13 * m.size * pop * (m.kind === 'heart' ? 1 + Math.sin(m.t * 10) * 0.06 : 1);
      m.s.scale.set(sc, sc, sc);
      m.s.material.rotation = m.kind === 'sparkle' || m.kind === 'star' ? m.t * 1.5 : Math.sin(m.t * 2 + m.seed) * 0.15;
      m.s.material.opacity = m.t < 0 ? 0 : clamp(m.t / 0.15) * (1 - clamp((u - 0.6) / 0.4));
    }
    this.live = this.live.filter((m) => {
      if (m.t < m.life) return true;
      this.parent.remove(m.s); m.s.material.dispose(); return false;
    });
  }
}
