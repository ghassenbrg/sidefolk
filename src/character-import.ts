// Turns a picture someone made into a companion: the filled-in template (16 poses in a 4×4
// grid, public/character-template.png) or a single picture. All on this Mac, with a canvas: the
// background goes (transparent pixels, or whatever color the corners are), each pose is found
// in its box, every frame gets the same scale with the feet on one line, and a thin ivory
// outline like Pip's. Mirrors scripts/make_sprites.py, which makes the built-in characters.

export const POSES = ["idle", "blink", "listen", "think", "work1", "work2", "alert", "sad", "note", "write1", "write2", "done", "wave", "sit", "sleep", "dangle"] as const;
export type Pose = (typeof POSES)[number];

/** What a missing pose borrows, first match wins; code still adds breathing, hops and the light. */
export const FALLBACK: Record<Pose, Pose[]> = {
  idle: [],
  blink: ["idle"],
  listen: ["idle"],
  think: ["idle"],
  work1: ["work2", "idle"],
  work2: ["work1", "idle"],
  alert: ["wave", "idle"],
  sad: ["idle"],
  note: ["idle"],
  write1: ["write2", "note", "idle"],
  write2: ["write1", "note", "idle"],
  done: ["wave", "idle"],
  wave: ["done", "idle"],
  sit: ["idle"],
  sleep: ["sit", "idle"],
  dangle: ["idle"],
};

/** The frame each pose shows, given the poses a character has. */
export function resolvePose(have: ReadonlySet<string>, pose: Pose): Pose {
  if (have.has(pose)) return pose;
  return FALLBACK[pose].find((p) => have.has(p)) ?? "idle";
}

// The frames' canvas, as in make_sprites.py: a standing figure is 300 px tall, feet at y 366.
const CANVAS_W = 420;
const CANVAS_H = 380;
const STANDING = 300;
const BASELINE = 366;
const OUTLINE = 5;
// The template's boxes: 400 px, of which the top 352 are for drawing.
const TEMPLATE_DRAW = 352 / 400;
/** Fewer opaque pixels than this in a box means it was left empty. */
const MIN_PIXELS = 400;

export type Imported = { frames: Partial<Record<Pose, string>>; missing: Pose[]; warnings: string[] };

type Box = { x0: number; y0: number; x1: number; y1: number; count: number };

/** Opacity 0–255 per pixel: the picture's own transparency, or distance from the corners' color. */
export function alphaOf(data: Uint8ClampedArray, width: number, height: number): Uint8ClampedArray {
  const alpha = new Uint8ClampedArray(width * height);
  const at = (x: number, y: number) => (y * width + x) * 4;
  const corners = [at(0, 0), at(width - 1, 0), at(0, height - 1), at(width - 1, height - 1)];
  if (corners.some((i) => data[i + 3] < 250)) {
    for (let i = 0; i < alpha.length; i++) alpha[i] = data[i * 4 + 3];
    return alpha;
  }
  const bg = [0, 1, 2].map((c) => corners.map((i) => data[i + c]).sort((a, b) => a - b)[1]);
  const distance = new Float32Array(width * height);
  for (let i = 0; i < distance.length; i++) distance[i] = Math.hypot(data[i * 4] - bg[0], data[i * 4 + 1] - bg[1], data[i * 4 + 2] - bg[2]);
  // Only background reachable from the edges goes: a white belly inside a dark outline stays.
  const outside = new Uint8Array(width * height);
  const queue: number[] = [];
  const visit = (i: number) => {
    if (!outside[i] && distance[i] < 90) {
      outside[i] = 1;
      queue.push(i);
    }
  };
  for (let x = 0; x < width; x++) visit(x), visit((height - 1) * width + x);
  for (let y = 0; y < height; y++) visit(y * width), visit(y * width + width - 1);
  while (queue.length) {
    const i = queue.pop()!;
    const x = i % width;
    if (x > 0) visit(i - 1);
    if (x < width - 1) visit(i + 1);
    if (i >= width) visit(i - width);
    if (i < width * (height - 1)) visit(i + width);
  }
  // Soft edge between 40 and 90, so the template's pale guides and antialiasing fade out.
  for (let i = 0; i < alpha.length; i++) alpha[i] = outside[i] ? Math.max(0, Math.min(255, ((distance[i] - 40) / 50) * 255)) : 255;
  return alpha;
}

function boxOf(alpha: Uint8ClampedArray, width: number, x0: number, y0: number, x1: number, y1: number): Box | null {
  let box: Box | null = null;
  for (let y = y0; y < y1; y++)
    for (let x = x0; x < x1; x++) {
      if (alpha[y * width + x] < 128) continue;
      box ??= { x0: x, y0: y, x1: x, y1: y, count: 0 };
      box.x0 = Math.min(box.x0, x);
      box.x1 = Math.max(box.x1, x);
      box.y0 = Math.min(box.y0, y);
      box.y1 = Math.max(box.y1, y);
      box.count++;
    }
  return box && box.count >= MIN_PIXELS ? box : null;
}

/** The middle of the feet: the bottom tenth of the figure, so a raised arm doesn't shift it. */
function feetCenter(alpha: Uint8ClampedArray, width: number, box: Box) {
  const top = box.y1 - Math.max(2, Math.round((box.y1 - box.y0) * 0.1));
  let sum = 0;
  let n = 0;
  for (let y = top; y <= box.y1; y++)
    for (let x = box.x0; x <= box.x1; x++)
      if (alpha[y * width + x] >= 128) {
        sum += x;
        n++;
      }
  return n ? sum / n : (box.x0 + box.x1) / 2;
}

/**
 * Reads the picture: `layout` "sheet" is the 16-pose template, "single" one standing figure.
 * Resolves to data URLs per pose found, the poses left empty, and plain-language warnings.
 */
export async function importCharacter(image: HTMLImageElement, layout: "sheet" | "single", outline = true): Promise<Imported> {
  const { naturalWidth: width, naturalHeight: height } = image;
  const source = document.createElement("canvas");
  source.width = width;
  source.height = height;
  const ctx = source.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(image, 0, 0);
  const pixels = ctx.getImageData(0, 0, width, height);
  const alpha = alphaOf(pixels.data, width, height);
  // The picture with its background gone.
  const keyed = new ImageData(new Uint8ClampedArray(pixels.data), width, height);
  for (let i = 0; i < alpha.length; i++) keyed.data[i * 4 + 3] = Math.min(keyed.data[i * 4 + 3], alpha[i]);
  const cut = document.createElement("canvas");
  cut.width = width;
  cut.height = height;
  cut.getContext("2d")!.putImageData(keyed, 0, 0);

  const cells: [Pose, Box | null][] =
    layout === "single"
      ? [["idle", boxOf(alpha, width, 0, 0, width, height)]]
      : POSES.map((pose, i) => {
          const cw = width / 4;
          const ch = height / 4;
          const x0 = Math.round((i % 4) * cw + cw * 0.015);
          const y0 = Math.round(Math.floor(i / 4) * ch + ch * 0.015);
          return [pose, boxOf(alpha, width, x0, y0, Math.round(x0 + cw * 0.97), Math.round(Math.floor(i / 4) * ch + ch * TEMPLATE_DRAW - 2))];
        });

  const idle = cells.find(([pose]) => pose === "idle")?.[1];
  if (!idle) return { frames: {}, missing: [...POSES], warnings: [layout === "sheet" ? "The idle box (top left) is empty. It's the one pose every character needs." : "I couldn't find a figure in this picture. Try one with a plain or transparent background."] };
  const scale = STANDING / (idle.y1 - idle.y0 + 1);
  const frames: Partial<Record<Pose, string>> = {};
  const warnings: string[] = [];
  for (const [pose, box] of cells) {
    if (!box) continue;
    const w = (box.x1 - box.x0 + 1) * scale;
    const h = (box.y1 - box.y0 + 1) * scale;
    if (h > CANVAS_H - 10 || w > CANVAS_W - 10) warnings.push(`${pose} is much bigger than idle, so it's cut off at the edges.`);
    const frame = document.createElement("canvas");
    frame.width = CANVAS_W;
    frame.height = CANVAS_H;
    const fx = CANVAS_W / 2 - (feetCenter(alpha, width, box) - box.x0) * scale;
    const fy = BASELINE - h;
    // Ivory sticker outline: the silhouette drawn around the figure, then the figure on top.
    const silhouette = document.createElement("canvas");
    silhouette.width = CANVAS_W;
    silhouette.height = CANVAS_H;
    const s = silhouette.getContext("2d")!;
    s.drawImage(cut, box.x0, box.y0, box.x1 - box.x0 + 1, box.y1 - box.y0 + 1, fx, fy, w, h);
    s.globalCompositeOperation = "source-in";
    s.fillStyle = "#fffcf7";
    s.fillRect(0, 0, CANVAS_W, CANVAS_H);
    const f = frame.getContext("2d")!;
    if (outline) for (let a = 0; a < 16; a++) f.drawImage(silhouette, Math.cos((a / 16) * Math.PI * 2) * OUTLINE, Math.sin((a / 16) * Math.PI * 2) * OUTLINE);
    f.drawImage(cut, box.x0, box.y0, box.x1 - box.x0 + 1, box.y1 - box.y0 + 1, fx, fy, w, h);
    frames[pose] = frame.toDataURL("image/png");
  }
  const missing = POSES.filter((p) => !frames[p]);
  if (layout === "sheet" && missing.length) warnings.unshift(`${missing.length} of 16 boxes are empty; those poses borrow from others (${missing.slice(0, 4).join(", ")}${missing.length > 4 ? "…" : ""}). It works, just with less variety.`);
  return { frames, missing, warnings };
}

/**
 * A character as one picture in the template's layout, background transparent, so it can be sent
 * to someone and imported as it is ("Bun.sidefolk.png").
 */
export async function exportSheet(frames: Partial<Record<string, string>>): Promise<string> {
  const sheet = document.createElement("canvas");
  sheet.width = 1600;
  sheet.height = 1600;
  const ctx = sheet.getContext("2d")!;
  // Each 420×380 frame fits the box's 352 px drawing area; its feet land near the dashed line.
  const scale = (400 * TEMPLATE_DRAW) / CANVAS_H;
  for (const [i, pose] of POSES.entries()) {
    const src = frames[pose];
    if (!src) continue;
    const image = new Image();
    image.src = src;
    await image.decode();
    const w = CANVAS_W * scale;
    ctx.drawImage(image, (i % 4) * 400 + (400 - w) / 2, Math.floor(i / 4) * 400, w, CANVAS_H * scale);
  }
  return sheet.toDataURL("image/png");
}
