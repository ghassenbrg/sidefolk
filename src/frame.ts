// The overlay window covers only the companions, not the whole screen: with "Hide from screen
// recordings" on, macOS blanks the window's area in Mission Control's previews and screen shares,
// and a small window is cheaper to composite. The page still lays everything out in screen
// coordinates (the display's work area); the body is shifted by the window's origin so it
// shows the right part, and pointer positions (relative to the window) get the origin back.

export type Rect = { x: number; y: number; width: number; height: number };

/** The work area, and the part of it the window covers, in CSS pixels; set by `place`. */
export const area = { width: 0, height: 0, frame: { x: 0, y: 0, width: 0, height: 0 } as Rect };

/** Room around the companions, so a hop, a bubble growing a line or a short drag stay inside. */
const MARGIN = 72;
/** A window this much bigger than it needs to be on some side shrinks. */
const SLACK = 3 * MARGIN;

/** Window coordinates (pointer events, getBoundingClientRect) to screen coordinates. */
export const toScreen = (x: number, y: number) => ({ x: x + area.frame.x, y: y + area.frame.y });

/** Lays the page out for the window at `frame` of a work area `width` × `height`. */
export function place(width: number, height: number, frame: Rect = { x: 0, y: 0, width, height }) {
  Object.assign(area, { width, height, frame });
  const body = document.body.style;
  body.width = `${width}px`;
  body.height = `${height}px`;
  body.transform = frame.x || frame.y ? `translate(${-frame.x}px, ${-frame.y}px)` : "";
}

/** The window the elements need: their union plus a margin, kept on the work area. */
export function needed(rects: Rect[], width: number, height: number): Rect {
  if (!rects.length) return { x: 0, y: 0, width, height };
  const x0 = Math.max(0, Math.floor(Math.min(...rects.map((r) => r.x)) - MARGIN));
  const y0 = Math.max(0, Math.floor(Math.min(...rects.map((r) => r.y)) - MARGIN));
  const x1 = Math.min(width, Math.ceil(Math.max(...rects.map((r) => r.x + r.width)) + MARGIN));
  const y1 = Math.min(height, Math.ceil(Math.max(...rects.map((r) => r.y + r.height)) + MARGIN));
  return { x: x0, y: y0, width: Math.max(1, x1 - x0), height: Math.max(1, y1 - y0) };
}

/** Whether the window at `current` should change to fit `want`: it cuts something off, or is far too big. */
export function shouldMove(current: Rect, want: Rect) {
  const cuts = want.x < current.x || want.y < current.y || want.x + want.width > current.x + current.width || want.y + want.height > current.y + current.height;
  const loose =
    want.x - current.x > SLACK ||
    want.y - current.y > SLACK ||
    current.x + current.width - (want.x + want.width) > SLACK ||
    current.y + current.height - (want.y + want.height) > SLACK;
  return cuts || loose;
}
