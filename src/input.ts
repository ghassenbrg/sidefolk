import type { Familiar } from "./familiar";

type Sample = { x: number; y: number; t: number };

const DRAG_SLOP = 4;
const MAX_THROW = 2600;

/**
 * Click-through: the overlay ignores the mouse unless the cursor is over the companion itself
 * (its frame's opaque pixels) or over its card.
 */
export function wireInput(o: {
  familiars: () => Familiar[];
  setInteractive: (on: boolean) => void;
  /** A click, left or right, on a companion: the one place to talk to it. It never answers anything. */
  onClick: (f: Familiar) => void;
}) {
  let interactive = false;
  let pressed: { f: Familiar; x: number; y: number; dx: number; dy: number } | null = null;
  let dragging = false;
  let samples: Sample[] = [];

  const overPet = (f: Familiar, x: number, y: number) => f.contains(x, y);
  // Topmost first: companions added later are drawn over Pip, whose frame is wide.
  const petAt = (x: number, y: number) => [...o.familiars()].reverse().find((f) => overPet(f, x, y));

  const refresh = (x: number, y: number) => {
    const want = dragging || !!pressed || o.familiars().some((f) => f.bubble.contains(x, y)) || !!petAt(x, y);
    if (want === interactive) return;
    interactive = want;
    o.setInteractive(want);
    document.body.classList.toggle("hover", want);
  };

  // The web view's own menu (Reload, Inspect) is no use here; a right click opens the field too.
  addEventListener("contextmenu", (event) => {
    event.preventDefault();
    const f = petAt(event.clientX, event.clientY);
    if (f) o.onClick(f);
  });

  addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || event.ctrlKey) return;
    const f = petAt(event.clientX, event.clientY);
    if (!f) return;
    const world = f.bounds.toWorld(event.clientX, event.clientY);
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
    const world = f.bounds.toWorld(event.clientX, event.clientY);
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
      pressed.f.mind.poke();
      o.onClick(pressed.f);
    }
    pressed = null;
    dragging = false;
    refresh(event.clientX, event.clientY);
  });

  return { refresh };
}
