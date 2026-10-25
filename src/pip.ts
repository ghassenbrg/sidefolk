// A companion's body, from generated art (art/crew, cut by scripts/make_sprites.py): one image
// per pose, all on the same canvas with the feet on one baseline.
// Code adds the life: breathing, blinks, a short hop, squash when landing, a slight sway, and the
// status light, drawn here so its colors are exact and it pulses only when it needs you.

import { recolored } from "./recolor";

export type ClipName =
  | "idle"
  | "listen"
  | "sit"
  | "sleep"
  | "wave"
  | "puzzled"
  | "think"
  | "read"
  | "work"
  | "celebrate"
  | "alert"
  | "sad"
  | "note"
  | "write"
  | "dangle"
  | "fall";

const FRAMES = ["idle", "blink", "listen", "think", "work1", "work2", "alert", "sad", "note", "write1", "write2", "done", "wave", "sit", "sleep", "dangle"] as const;
type Frame = (typeof FRAMES)[number];

/** The frames a clip shows; more than one alternate (typing, writing). */
const CLIP_FRAMES: Record<ClipName, Frame[]> = {
  idle: ["idle"],
  listen: ["listen"],
  sit: ["sit"],
  sleep: ["sleep"],
  wave: ["wave"],
  // The approved listen frame already has the folded ear; a separate clip gives it a clear
  // puzzled meaning without changing Pip’s frozen artwork.
  puzzled: ["listen"],
  think: ["think"],
  read: ["work1", "work2"],
  work: ["work1", "work2"],
  celebrate: ["done"],
  alert: ["alert"],
  sad: ["sad"],
  note: ["note"],
  write: ["write1", "write2"],
  dangle: ["dangle"],
  fall: ["dangle"],
};

type Light = "idle" | "think" | "work" | "alert" | "done" | "sad" | "sleep";
const CLIP_LIGHT: Record<ClipName, Light> = {
  idle: "idle",
  listen: "think",
  sit: "idle",
  sleep: "sleep",
  wave: "idle",
  puzzled: "idle",
  think: "think",
  read: "work",
  work: "work",
  celebrate: "done",
  alert: "alert",
  sad: "sad",
  note: "alert",
  write: "work",
  dangle: "idle",
  fall: "idle",
};
/** The runtime status palette from the design system. */
const LIGHT: Record<Light, string> = {
  idle: "#6fcfb4",
  think: "#8cc6ff",
  work: "#ffb547",
  alert: "#ff7a2e",
  done: "#6fe3b4",
  sad: "#9d90b8",
  sleep: "#c9d6d1",
};

/** Frame canvas size, in frame pixels (scripts/make_sprites.py). */
export const VIEW_W = 420;
export const VIEW_H = 380;
/** Where the feet stand, and how tall a standing Pip is, in frame pixels. */
export const FEET = 366;
export const DRAWN = 300;
/** On-screen height of a standing Pip at size "medium", in CSS pixels. */
export const HEIGHT = 150;
/** Hit-test masks are kept at a quarter of the frame size. */
const MASK = 4;

const spring = (from: number, to: number, rate: number, dt: number) => from + (to - from) * (1 - Math.exp(-rate * dt));

export class PipView {
  readonly el: HTMLDivElement;
  private readonly body: HTMLDivElement;
  private readonly images = new Map<Frame, HTMLImageElement>();
  private readonly masks = new Map<Frame, Uint8Array>();
  /** The top of each frame (an antenna's tip), in frame pixels. */
  private readonly tips = new Map<Frame, { x: number; y: number }>();
  private readonly light: HTMLDivElement;
  private current: ClipName = "idle";
  private shown: Frame = "idle";
  private clipTime = 0;
  private time = 0;
  private blinkIn = 2.5;
  private blinking = 0;
  private squashAmount = 0;
  private hop = 0;
  private sway = 0;
  private lightColor = "";
  private fade: { from: Frame; outgoing: Animation; incoming: Animation } | null = null;
  /** Reduce motion: no breathing, swaying, hops or pulses. */
  still = false;
  activeAgent = false;

  /**
   * `folder` holds the frames in public/ (roster.ts); `hue` turns the mint accent to a worker's
   * color (recolor.ts); `lightAt` is the status light's place in frame pixels, or "antenna" for
   * the top of each frame (Spark's antenna moves with its pose).
   */
  constructor(
    folder: string,
    private readonly hue = 0,
    label = "Companion",
    private readonly lightAt: { x: number; y: number } | "antenna" = { x: 290, y: 78 },
  ) {
    this.el = document.createElement("div");
    this.el.className = "pip";
    this.el.setAttribute("role", "img");
    this.el.setAttribute("aria-label", label);
    this.body = document.createElement("div");
    this.body.className = "pip-body";
    for (const name of FRAMES) {
      const img = new Image();
      img.src = `${folder}/${name}.webp`;
      img.alt = "";
      img.draggable = false;
      img.hidden = name !== "idle";
      this.images.set(name, img);
      this.body.append(img);
    }
    this.light = document.createElement("div");
    this.light.className = "pip-light";
    this.body.append(this.light);
    this.el.append(this.body);
  }

  /** Resolves once every frame is decoded; the hit-test masks are built then (a cached image can
   * fire "load" before it can be drawn, which gave empty masks). */
  ready() {
    return Promise.all(
      [...this.images].map(async ([name, img]) => {
        try {
          await img.decode();
          // Only the drawing's mint takes the worker's color; the status light keeps its own.
          if (this.hue) {
            img.src = recolored(img, this.hue);
            await img.decode();
          }
          const m = mask(img);
          this.masks.set(name, m);
          this.tips.set(name, tip(m));
        } catch {
          // A missing frame stays hidden; hit tests treat it as solid.
        }
      }),
    );
  }

  get clip(): ClipName {
    return this.current;
  }

  play(name: ClipName) {
    if (name === this.current) return;
    this.current = name;
    this.clipTime = 0;
  }

  /** Pip doesn't walk; it always faces you. Kept for the behavior code. */
  face(_direction: number) {}

  squash(amount: number) {
    this.squashAmount = Math.max(this.squashAmount, amount);
  }

  /** @param gaze the cursor relative to Pip's face, in CSS pixels (or null): Pip leans toward it a touch. */
  update(dt: number, gaze: { x: number; y: number } | null) {
    this.time += dt;
    this.clipTime += dt;
    const frames = CLIP_FRAMES[this.current];
    let frame = frames[Math.floor(this.clipTime / 0.32) % frames.length];
    // Blinks in the idle pose.
    this.blinkIn -= dt;
    if (this.blinkIn <= 0) {
      this.blinking = 0.14;
      this.blinkIn = 2.5 + Math.random() * 4;
    }
    this.blinking = Math.max(0, this.blinking - dt);
    if (frame === "idle" && this.blinking > 0) frame = "blink";
    if (this.still && this.fade) {
      this.fade.outgoing.cancel();
      this.fade.incoming.cancel();
      this.images.get(this.fade.from)!.hidden = true;
      this.fade = null;
    }
    if (frame !== this.shown) {
      this.fade?.outgoing.cancel();
      this.fade?.incoming.cancel();
      const previous = this.shown;
      const before = this.images.get(previous)!;
      const next = this.images.get(frame)!;
      for (const [name, image] of this.images) image.hidden = name !== frame && name !== previous;
      this.shown = frame;
      // Blinks stay crisp; only real pose changes fade. Reduced motion changes immediately.
      if (this.still || previous === "blink" || frame === "blink") {
        before.hidden = true;
        this.fade = null;
      } else {
        const duration = Number.parseFloat(getComputedStyle(this.el).getPropertyValue("--motion-control")) || 0;
        const outgoing = before.animate([{ opacity: 1 }, { opacity: 0 }], { duration });
        const incoming = next.animate([{ opacity: 0 }, { opacity: 1 }], { duration });
        void incoming.finished.catch(() => {});
        this.fade = { from: previous, outgoing, incoming };
        void outgoing.finished.then(() => { if (this.shown !== previous) before.hidden = true; }).catch(() => {});
      }
    }

    const still = this.still;
    this.squashAmount = spring(this.squashAmount, 0, 9, dt);
    // One short hop when celebrating or saying hello (under 1.2 s).
    const hopping = (this.current === "celebrate" || this.current === "wave") && !still && this.clipTime < 1.1;
    this.hop = hopping ? Math.abs(Math.sin(this.clipTime * Math.PI * 1.8)) * 10 * (1 - this.clipTime / 1.1) : spring(this.hop, 0, 12, dt);
    const lean = gaze && !still ? Math.max(-1, Math.min(1, gaze.x / 400)) * 2 : 0;
    const swayTarget = still ? 0 : this.current === "listen" ? 3 + lean : this.current === "puzzled" ? 5 : this.current === "think" ? -2.5 : this.current === "wave" ? Math.sin(this.clipTime * 6) * 2 : lean;
    this.sway = spring(this.sway, swayTarget, 5, dt);
    const breath = still || this.current === "dangle" ? 0 : Math.sin(this.time * 2.2) * 0.012;
    const sy = 1 - this.squashAmount + breath;
    const sx = 1 + this.squashAmount * 0.6 - breath * 0.5;
    this.body.style.transform = `translateY(${(-this.hop).toFixed(2)}%) rotate(${this.sway.toFixed(2)}deg) scale(${sx.toFixed(3)}, ${sy.toFixed(3)})`;

    // The status light: exact color, a gentle bob, a pulse only when it needs you.
    this.light.hidden = !this.activeAgent && ["idle", "sit", "listen", "puzzled", "think", "wave"].includes(this.current);
    const light = CLIP_LIGHT[this.current];
    const color = LIGHT[light];
    if (color !== this.lightColor) {
      this.lightColor = color;
      this.light.style.setProperty("--light", color);
    }
    const bob = still ? 0 : Math.sin(this.time * 1.7) * 1.2;
    const pulse = light === "alert" && !still ? 0.5 + 0.5 * Math.sin(this.time * 4) : 0;
    const at = this.lightAt === "antenna" ? (this.tips.get(this.shown) ?? { x: 224, y: 78 }) : this.lightAt;
    const top = this.lightAt !== "antenna" && (this.current === "sleep" || this.current === "sad") ? at.y + 60 : at.y;
    this.light.style.left = `${(at.x / VIEW_W) * 100}%`;
    this.light.style.top = `${((top + bob * 4) / VIEW_H) * 100}%`;
    this.light.style.setProperty("--pulse", pulse.toFixed(2));
    this.light.style.opacity = light === "sleep" ? "0.6" : "1";
  }

  /** Whether a screen point (client coordinates) is on Pip itself, using the frame's transparency. */
  contains(x: number, y: number) {
    const r = this.el.getBoundingClientRect();
    if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false;
    const m = this.masks.get(this.shown);
    if (!m) return true;
    const mx = Math.floor(((x - r.left) / r.width) * (VIEW_W / MASK));
    const my = Math.floor(((y - r.top) / r.height) * (VIEW_H / MASK));
    // A little slack around the outline: a near-miss still counts as touching Pip.
    for (let dy = -1; dy <= 1; dy++)
      for (let dx = -1; dx <= 1; dx++) {
        const px = mx + dx;
        const py = my + dy;
        if (px >= 0 && py >= 0 && px < VIEW_W / MASK && py < VIEW_H / MASK && m[py * (VIEW_W / MASK) + px]) return true;
      }
    return false;
  }
}

/** A small opaque/transparent map of a frame, for hit testing. */
/** The middle of the frame's topmost part (an antenna's ball), in frame pixels. */
function tip(m: Uint8Array): { x: number; y: number } {
  const w = VIEW_W / MASK;
  const top = Math.floor(m.indexOf(1) / w);
  if (top < 0) return { x: 224, y: 78 };
  const xs: number[] = [];
  for (let y = top; y < top + 5; y++) for (let x = 0; x < w; x++) if (m[y * w + x]) xs.push(x);
  return { x: ((Math.min(...xs) + Math.max(...xs) + 1) / 2) * MASK, y: top * MASK + 12 };
}

function mask(img: HTMLImageElement): Uint8Array {
  const w = VIEW_W / MASK;
  const h = VIEW_H / MASK;
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(img, 0, 0, w, h);
  const data = ctx.getImageData(0, 0, w, h).data;
  const out = new Uint8Array(w * h);
  for (let i = 0; i < out.length; i++) out[i] = data[i * 4 + 3] > 96 ? 1 : 0;
  return out;
}
