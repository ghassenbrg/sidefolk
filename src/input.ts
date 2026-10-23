import * as THREE from "three";
import type { Bubble } from "./bubble";
import type { Mind } from "./mind";
import type { Pet } from "./pet/pet";
import type { Stage } from "./stage";

type Sample = { x: number; y: number; t: number };

const DRAG_SLOP = 4;
const DOUBLE_CLICK_MS = 320;
const MAX_THROW = 2600;

/**
 * Click-through: the overlay ignores the mouse unless the cursor is over the pet's
 * actual surface (a raycast against the skinned mesh) or over the bubble.
 */
export function wireInput(o: {
  stage: Stage;
  pet: Pet;
  mind: Mind;
  bubble: Bubble;
  setInteractive: (on: boolean) => void;
}) {
  const raycaster = new THREE.Raycaster();
  const origin = new THREE.Vector3();
  const down = new THREE.Vector3(0, 0, -1);
  let interactive = false;
  let pressed: { x: number; y: number; dx: number; dy: number } | null = null;
  let dragging = false;
  let samples: Sample[] = [];
  let lastClick = 0;

  const overPet = (x: number, y: number) => {
    const world = o.stage.toWorld(x, y);
    raycaster.set(origin.set(world.x, world.y, 1000), down);
    return raycaster.intersectObject(o.pet.rig.body, false).length > 0;
  };

  const refresh = (x: number, y: number) => {
    const want = dragging || !!pressed || o.bubble.contains(x, y) || overPet(x, y);
    if (want === interactive) return;
    interactive = want;
    o.setInteractive(want);
    document.body.classList.toggle("hover", want);
  };

  addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || !overPet(event.clientX, event.clientY)) return;
    const world = o.stage.toWorld(event.clientX, event.clientY);
    pressed = { x: event.clientX, y: event.clientY, dx: o.mind.x - world.x, dy: o.mind.y - world.y };
    samples = [];
  });

  addEventListener("pointermove", (event) => {
    if (!pressed) return;
    if (!dragging && Math.hypot(event.clientX - pressed.x, event.clientY - pressed.y) > DRAG_SLOP) {
      dragging = true;
      o.mind.grab();
    }
    if (!dragging) return;
    const world = o.stage.toWorld(event.clientX, event.clientY);
    o.mind.hold(world.x + pressed.dx, world.y + pressed.dy);
    samples.push({ ...world, t: performance.now() });
    samples = samples.filter((s) => performance.now() - s.t < 90);
  });

  addEventListener("pointerup", (event) => {
    if (dragging) {
      const first = samples[0];
      const last = samples[samples.length - 1];
      const seconds = first && last ? (last.t - first.t) / 1000 : 0;
      const clamp = (v: number) => Math.max(-MAX_THROW, Math.min(MAX_THROW, v));
      o.mind.release(
        seconds > 0.01 ? clamp((last.x - first.x) / seconds) : 0,
        seconds > 0.01 ? clamp((last.y - first.y) / seconds) : 0,
      );
    } else if (pressed) {
      const now = performance.now();
      if (now - lastClick < DOUBLE_CLICK_MS) o.bubble.prompt();
      else o.mind.poke();
      lastClick = now;
    }
    pressed = null;
    dragging = false;
    refresh(event.clientX, event.clientY);
  });

  return { refresh };
}
