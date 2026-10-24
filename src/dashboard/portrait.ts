import * as THREE from "three";
import { loadModel } from "../pet/model";
import { normalizeLook } from "../pet/look";
import { HEIGHT, Pet } from "../pet/pet";
import type { ClipName } from "../pet/clips";
import type { Look } from "./api";

// Pet portraits for the Sidefolk window, drawn from the same models and looks as the desktop:
// still pictures for lists (rendered once per look, then cached) and small live previews for
// the appearance editor (idle and "needs you"), which run only while they are on screen.

type Frame = "bust" | "full";

function scene() {
  const s = new THREE.Scene();
  s.add(new THREE.AmbientLight(0xffffff, 1.5));
  const key = new THREE.DirectionalLight(0xfff3e6, 2.2);
  key.position.set(-0.6, 1, 1);
  const rim = new THREE.DirectionalLight(0xdfe8ff, 0.7);
  rim.position.set(1, 0.4, -0.6);
  s.add(key, rim);
  return s;
}

function camera(frame: Frame) {
  // World units are overlay pixels; the pet stands HEIGHT tall with its feet at 0.
  const span = frame === "bust" ? HEIGHT * 0.78 : HEIGHT * 1.22;
  const middle = frame === "bust" ? HEIGHT * 0.64 : HEIGHT * 0.56;
  const c = new THREE.OrthographicCamera(-span / 2, span / 2, middle + span / 2, middle - span / 2, 1, 2000);
  c.position.z = 1000;
  return c;
}

let shared: THREE.WebGLRenderer | null = null;
const pictures = new Map<string, Promise<string>>();
/** Finished portraits, so a redrawn list shows them at once instead of blinking. */
const ready = new Map<string, string>();
const keyOf = (look: Look, frame: Frame) => `${frame}:${look.species}:${look.palette}:${look.accessory}:${look.style ?? "soft"}`;

/** A still portrait as an image URL, idle pose, transparent background. */
export function portrait(look: Look, frame: Frame = "bust"): Promise<string> {
  const key = keyOf(look, frame);
  let picture = pictures.get(key);
  if (!picture) {
    picture = (async () => {
      const pet = new Pet(await loadModel(normalizeLook(look)));
      const s = scene();
      s.add(pet.holder);
      pet.update(0.6, null, 0, "open");
      shared ??= new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true, powerPreference: "low-power" });
      shared.setPixelRatio(2);
      shared.setSize(128, 128);
      shared.setClearColor(0x000000, 0);
      shared.render(s, camera(frame));
      const url = shared.domElement.toDataURL("image/png");
      dispose(s);
      ready.set(key, url);
      return url;
    })();
    picture.catch(() => pictures.delete(key));
    pictures.set(key, picture);
  }
  return picture;
}

/** An <img> that fills in when its portrait is ready. */
export function portraitImage(look: Look, alt: string, className = "portrait", frame: Frame = "bust") {
  const img = document.createElement("img");
  img.className = className;
  img.alt = alt;
  img.decoding = "async";
  const done = ready.get(keyOf(look, frame));
  if (done) {
    img.src = done;
    return img;
  }
  void portrait(look, frame)
    .then((url) => (img.src = url))
    .catch(() => img.classList.add("missing"));
  return img;
}

function dispose(object: THREE.Object3D) {
  object.traverse((o) => {
    if (!(o instanceof THREE.Mesh)) return;
    o.geometry.dispose();
    for (const m of Array.isArray(o.material) ? o.material : [o.material]) m.dispose();
  });
}

const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches || document.documentElement.classList.contains("reduce-motion");

/** A small animated preview of one clip. Call `stop()` when it leaves the screen. */
export class LivePreview {
  private readonly renderer: THREE.WebGLRenderer;
  private readonly scene = scene();
  private readonly camera = camera("full");
  private pet: Pet | null = null;
  private timer = 0;
  private last = 0;
  private version = 0;

  constructor(
    readonly canvas: HTMLCanvasElement,
    private readonly clip: ClipName,
  ) {
    this.renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, powerPreference: "low-power" });
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    this.renderer.setSize(canvas.clientWidth || 160, canvas.clientHeight || 180, false);
    this.renderer.setClearColor(0x000000, 0);
  }

  async show(look: Look) {
    const version = ++this.version;
    const next = new Pet(await loadModel(normalizeLook(look)));
    if (version !== this.version) return;
    if (this.pet) {
      this.scene.remove(this.pet.holder);
      dispose(this.pet.holder);
    }
    this.pet = next;
    next.play(this.clip, 0);
    this.scene.add(next.holder);
    this.draw(0.4);
    if (!this.timer && !reducedMotion()) this.loop();
  }

  private draw(dt: number) {
    if (!this.pet) return;
    this.pet.update(dt, null, 0, "open");
    this.renderer.render(this.scene, this.camera);
  }

  // 15 frames a second is plenty for a thumbnail and keeps the window cheap.
  private loop = () => {
    const now = performance.now();
    this.draw(this.last ? Math.min(0.2, (now - this.last) / 1000) : 0);
    this.last = now;
    this.timer = window.setTimeout(this.loop, 66);
  };

  stop() {
    clearTimeout(this.timer);
    this.timer = 0;
    dispose(this.scene);
    this.renderer.dispose();
    this.renderer.forceContextLoss();
  }
}
