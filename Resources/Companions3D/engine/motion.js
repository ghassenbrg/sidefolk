// Small motion toolkit: springs for follow-through, curves for authored moves, smooth noise.

/** A damped spring on one number: `stiffness` pulls to the target, `damping` < 2√k overshoots. */
export class Spring {
  constructor(value = 0, stiffness = 120, damping = 14) {
    this.x = value; this.v = 0; this.k = stiffness; this.d = damping;
  }
  step(target, dt) {
    // Semi-implicit Euler in small slices stays stable at low frame rates.
    const n = Math.max(1, Math.ceil(dt / (1 / 240)));
    const h = dt / n;
    for (let i = 0; i < n; i++) {
      this.v += (this.k * (target - this.x) - this.d * this.v) * h;
      this.x += this.v * h;
    }
    // A bad input must never poison the pose for good.
    if (!Number.isFinite(this.x) || !Number.isFinite(this.v)) { this.x = target; this.v = 0; }
    return this.x;
  }
  kick(dv) { if (Number.isFinite(dv)) this.v += dv; }
}

/** Frame-rate independent exponential approach. */
export const damp = (a, b, rate, dt) => b + (a - b) * Math.exp(-rate * dt);

export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, t) => a + (b - a) * t;
export const smooth = (t) => { t = clamp(t); return t * t * (3 - 2 * t); };
export const easeInOut = (t) => { t = clamp(t); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; };
export const easeOutBack = (t, s = 1.7) => { t = clamp(t) - 1; return 1 + t * t * ((s + 1) * t + s); };

/** 0 → 1 over [a, b], held, then 1 → 0 over [c, d]: a window that fades a move in and out. */
export const win = (t, a, b, c, d) => smooth((t - a) / (b - a)) * (1 - smooth((t - c) / (d - c)));

/**
 * Catmull-Rom through keys [[time, value], ...] (value: number or array). Gives flowing,
 * pose-to-pose motion without stopping dead at each key; times outside hold the ends.
 */
export function curve(keys, t) {
  if (t <= keys[0][0]) return keys[0][1];
  const last = keys[keys.length - 1];
  if (t >= last[0]) return last[1];
  let i = 0;
  while (t > keys[i + 1][0]) i++;
  const p0 = keys[Math.max(0, i - 1)][1], p1 = keys[i][1], p2 = keys[i + 1][1], p3 = keys[Math.min(keys.length - 1, i + 2)][1];
  const u = (t - keys[i][0]) / (keys[i + 1][0] - keys[i][0]);
  const cr = (a, b, c, d) => 0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (-a + 3 * b - 3 * c + d) * u * u * u);
  if (Array.isArray(p1)) return p1.map((_, j) => cr(p0[j], p1[j], p2[j], p3[j]));
  return cr(p0, p1, p2, p3);
}

/** Smooth value noise in [-1, 1]: layered sines with incommensurate rates (cheap, organic). */
export function noise(t, seed = 0) {
  return (Math.sin(t * 1.13 + seed * 7.1) * 0.5 + Math.sin(t * 2.31 + seed * 3.7) * 0.3 + Math.sin(t * 0.47 + seed * 1.3) * 0.2);
}

export const rand = (a, b) => a + Math.random() * (b - a);
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
