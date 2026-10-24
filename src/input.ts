import * as THREE from "three";
import type { Familiar } from "./familiar";

type Sample = { x: number; y: number; t: number };

const DRAG_SLOP = 4;
const DOUBLE_CLICK_MS = 320;
const MAX_THROW = 2600;

/**
 * Click-through: the overlay ignores the mouse unless the cursor is over a pet's actual
 * surface (a raycast against its skinned mesh) or over a bubble.
 */
export function wireInput(o: {
  familiars: () => Familiar[];
  setInteractive: (on: boolean) => void;
  /** A single click: the pet's status card. Petting never answers anything. */
  onClick: (f: Familiar) => void;
  onDoubleClick: (f: Familiar) => void;
  onMenu: (f: Familiar) => void;
}) {
  const raycaster = new THREE.Raycaster();
  const origin = new THREE.Vector3();
  const down = new THREE.Vector3(0, 0, -1);
  let interactive = false;
  let pressed: { f: Familiar; x: number; y: number; dx: number; dy: number } | null = null;
  let dragging = false;
  let samples: Sample[] = [];
  let lastClick = { f: null as Familiar | null, at: 0 };

  const overPet = (f: Familiar, x: number, y: number) => {
    if (!f.out) return false;
    const world = f.stage.toWorld(x, y);
    // A box around the pet first: the skinned raycast checks every triangle.
    const { position, scale } = f.pet.holder;
    const dy = world.y - position.y;
    if (Math.abs(world.x - position.x) > scale.x || dy < -0.2 * scale.y || dy > 3 * scale.y) return false;
    raycaster.set(origin.set(world.x, world.y, 1000), down);
    return raycaster.intersectObject(f.pet.model.body, false).length > 0;
  };
  const petAt = (x: number, y: number) => o.familiars().find((f) => overPet(f, x, y));

  const refresh = (x: number, y: number) => {
    const want = dragging || !!pressed || o.familiars().some((f) => f.out && f.bubble.contains(x, y)) || !!petAt(x, y);
    if (want === interactive) return;
    interactive = want;
    o.setInteractive(want);
    document.body.classList.toggle("hover", want);
  };

  // The web view's own menu (Reload, Inspect) is no use here; a pet's menu replaces it.
  addEventListener("contextmenu", (event) => {
    event.preventDefault();
    const f = petAt(event.clientX, event.clientY);
    if (f) o.onMenu(f);
  });

  addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || event.ctrlKey) return;
    const f = petAt(event.clientX, event.clientY);
    if (!f) return;
    const world = f.stage.toWorld(event.clientX, event.clientY);
    pressed = { f, x: event.clientX, y: event.clientY, dx: f.mind.x - world.x, dy: f.mind.y - world.y };
    samples = [];
  });

  addEventListener("pointermove", (event) => {
    if (!pressed) return;
    const { f } = pressed;
    if (!dragging && Math.hypot(event.clientX - pressed.x, event.clientY - pressed.y) > DRAG_SLOP) {
      dragging = true;
      f.mind.grab();
    }
    if (!dragging) return;
    const world = f.stage.toWorld(event.clientX, event.clientY);
    f.mind.hold(world.x + pressed.dx, world.y + pressed.dy);
    samples.push({ ...world, t: performance.now() });
    samples = samples.filter((s) => performance.now() - s.t < 90);
  });

  addEventListener("pointerup", (event) => {
    if (pressed && dragging) {
      const first = samples[0];
      const last = samples[samples.length - 1];
      const seconds = first && last ? (last.t - first.t) / 1000 : 0;
      const clamp = (v: number) => Math.max(-MAX_THROW, Math.min(MAX_THROW, v));
      pressed.f.mind.release(
        seconds > 0.01 ? clamp((last.x - first.x) / seconds) : 0,
        seconds > 0.01 ? clamp((last.y - first.y) / seconds) : 0,
      );
    } else if (pressed) {
      const now = performance.now();
      if (lastClick.f === pressed.f && now - lastClick.at < DOUBLE_CLICK_MS) o.onDoubleClick(pressed.f);
      else {
        pressed.f.mind.poke();
        o.onClick(pressed.f);
      }
      lastClick = { f: pressed.f, at: now };
    }
    pressed = null;
    dragging = false;
    refresh(event.clientX, event.clientY);
  });

  return { refresh };
}
