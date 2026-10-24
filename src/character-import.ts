// Turns pictures someone made into a companion, all on this Mac with a canvas. Any of these work,
// and mix: one picture per pose named after it (idle.png, wave.png…); pose sheets in any grid,
// read left to right, top to bottom (the template, the crew's 4×2 sheets on chroma green, two
// sheets one after the other, an exported .sidefolk.png); or one standing picture. The background
// goes (transparent pixels, or whatever color the corners are), each pose is found by the empty
// space around it, every frame gets the same scale with the feet on one line, and a thin ivory
// outline like the crew's. Mirrors scripts/make_sprites.py, which makes the built-in characters.

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

// The frames' canvas, as in make_sprites.py: a standing figure is 300 px tall (at most 260 wide),
// feet at y 366.
const CANVAS_W = 420;
const CANVAS_H = 380;
const STANDING = 300;
const WIDEST = 260;
const BASELINE = 366;
const OUTLINE = 5;
// The template's boxes: 400 px, of which the top 352 are for drawing (for the export).
const TEMPLATE_DRAW = 352 / 400;
/** Fewer opaque pixels than this is a speck, not a pose. */
const MIN_PIXELS = 400;

export type Imported = { frames: Partial<Record<Pose, string>>; missing: Pose[]; warnings: string[] };
/** A picture to import and its file name, which may name its pose. */
export type Source = { image: HTMLImageElement; name: string };

export type Box = { x0: number; y0: number; x1: number; y1: number; count: number };

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

/** Runs of non-empty entries in a projection, split where at least `gap` are empty. */
function spans(profile: number[], gap: number, size: number): [number, number][] {
  const out: [number, number][] = [];
  let start = -1;
  let empty = 0;
  for (let i = 0; i <= profile.length + gap; i++) {
    if (i < profile.length && profile[i]) {
      if (start < 0) start = i;
      empty = 0;
    } else if (start >= 0 && ++empty > gap) {
      const end = i - empty + 1;
      if (end - start >= size) out.push([start, end]);
      start = -1;
      empty = 0;
    }
  }
  return out;
}

/**
 * The poses in a picture, left to right and top to bottom: rows of figures split by empty rows,
 * figures split by empty columns. Labels and specks (much shorter than the tallest figure) drop.
 */
export function findFigures(alpha: Uint8ClampedArray, width: number, height: number): Box[] {
  const solid = (x: number, y: number) => alpha[y * width + x] >= 128;
  const rows = Array.from({ length: height }, (_, y) => {
    for (let x = 0; x < width; x++) if (solid(x, y)) return 1;
    return 0;
  });
  const boxes: Box[] = [];
  for (const [top, bottom] of spans(rows, Math.max(4, Math.round(height * 0.012)), Math.max(8, Math.round(height * 0.03)))) {
    const cols = Array.from({ length: width }, (_, x) => {
      for (let y = top; y < bottom; y++) if (solid(x, y)) return 1;
      return 0;
    });
    for (const [left, right] of spans(cols, Math.max(4, Math.round(width * 0.006)), Math.max(8, Math.round(width * 0.02)))) {
      let box: Box | null = null;
      for (let y = top; y < bottom; y++)
        for (let x = left; x < right; x++) {
          if (!solid(x, y)) continue;
          box ??= { x0: x, y0: y, x1: x, y1: y, count: 0 };
          box.x0 = Math.min(box.x0, x);
          box.x1 = Math.max(box.x1, x);
          box.y0 = Math.min(box.y0, y);
          box.y1 = Math.max(box.y1, y);
          box.count++;
        }
      if (box && box.count >= MIN_PIXELS) boxes.push(box);
    }
  }
  const tallest = Math.max(0, ...boxes.map((b) => b.y1 - b.y0));
  return boxes.filter((b) => b.y1 - b.y0 >= tallest * 0.3);
}

/**
 * Each figure's cell in reading order, and how many cells the picture has. A square picture is the
 * 4×4 template, read by position so an empty box stays empty; any other picture is read by rows of
 * figures, as many columns as its fullest row.
 */
export function gridCells(figures: Box[], width: number, height: number): { cell: number[]; size: number } {
  const center = (b: Box) => [(b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2];
  if (figures.length > 1 && Math.abs(width / height - 1) < 0.05) {
    const at = (v: number, total: number) => Math.min(3, Math.floor((v / total) * 4));
    return { cell: figures.map((b) => at(center(b)[1], height) * 4 + at(center(b)[0], width)), size: 16 };
  }
  // findFigures returns rows top to bottom; a figure starting below the previous one's bottom begins a row.
  const rows: number[] = [];
  let row = 0;
  figures.forEach((b, i) => {
    if (i && b.y0 > figures[i - 1].y1) row++;
    rows.push(row);
  });
  const columns = Math.max(1, ...Array.from({ length: row + 1 }, (_, r) => rows.filter((x) => x === r).length));
  const cell = figures.map((b, i) => rows[i] * columns + Math.min(columns - 1, Math.floor((center(b)[0] / width) * columns)));
  return { cell, size: (row + 1) * columns };
}

/** A pose named by a file name: "idle.png", "03-listen.webp", "Bun wave.png". */
export function poseOfName(name: string): Pose | null {
  const words = name.toLowerCase().replace(/\.[a-z0-9]+$/, "").split(/[^a-z0-9]+/);
  return POSES.find((p) => words.includes(p)) ?? null;
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

type Cut = { canvas: HTMLCanvasElement; alpha: Uint8ClampedArray; width: number };

/** The picture with its background gone, and its opacity. */
function cutOut(image: HTMLImageElement): Cut {
  const { naturalWidth: width, naturalHeight: height } = image;
  const source = document.createElement("canvas");
  source.width = width;
  source.height = height;
  const ctx = source.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(image, 0, 0);
  const pixels = ctx.getImageData(0, 0, width, height);
  const alpha = alphaOf(pixels.data, width, height);
  const keyed = new ImageData(new Uint8ClampedArray(pixels.data), width, height);
  despill(keyed.data, alpha);
  for (let i = 0; i < alpha.length; i++) keyed.data[i * 4 + 3] = Math.min(keyed.data[i * 4 + 3], alpha[i]);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  canvas.getContext("2d")!.putImageData(keyed, 0, 0);
  return { canvas, alpha, width };
}

/**
 * Edge pixels keep a tint of a chroma backdrop (green, blue); where a pixel is partly transparent,
 * its dominant channel is capped at the other two, as make_sprites.py does.
 */
export function despill(data: Uint8ClampedArray, alpha: Uint8ClampedArray) {
  for (let i = 0; i < alpha.length; i++) {
    if (alpha[i] >= 250 || alpha[i] === 0) continue;
    const [r, g, b] = [data[i * 4], data[i * 4 + 1], data[i * 4 + 2]];
    if (g > r + 60 && g > b + 60) data[i * 4 + 1] = Math.max(r, b);
    else if (b > r + 60 && b > g + 60) data[i * 4 + 2] = Math.max(r, g);
  }
}

/**
 * Reads the pictures (see the top of this file). Resolves to data URLs per pose found, the poses
 * still missing (they borrow, see FALLBACK), and plain-language warnings.
 */
export async function importCharacter(sources: Source[], outline = true): Promise<Imported> {
  const warnings: string[] = [];
  const found: [Pose, Cut, Box][] = [];
  // Unnamed pictures' figures by grid cell, each picture after the last one's cells.
  const queue: [number, Cut, Box][] = [];
  let offset = 0;
  for (const { image, name } of sources) {
    const cut = cutOut(image);
    const figures = findFigures(cut.alpha, cut.width, image.naturalHeight);
    const named = sources.length > 1 ? poseOfName(name) : null;
    if (named && figures.length) {
      found.push([named, cut, figures.reduce((a, b) => (b.count > a.count ? b : a))]);
      continue;
    }
    const cells = gridCells(figures, cut.width, image.naturalHeight);
    figures.forEach((box, i) => queue.push([offset + cells.cell[i], cut, box]));
    offset += cells.size;
  }
  // They fill the poses in the template's order, skipping the ones named; an empty cell stays a gap.
  const open = POSES.filter((p) => !found.some(([pose]) => pose === p));
  const extra = queue.filter(([cell]) => !open[cell]).length;
  for (const [cell, cut, box] of queue) if (open[cell]) found.push([open[cell], cut, box]);
  if (extra) warnings.push(`There were ${extra} more figures than poses; the extra ones are left out.`);

  const idle = found.find(([pose]) => pose === "idle");
  if (!idle) return { frames: {}, missing: [...POSES], warnings: ["I couldn't find a standing figure for idle. Try a picture with a plain or transparent background, or name one file idle.png."] };
  const [, , ib] = idle;
  const scale = Math.min(STANDING / (ib.y1 - ib.y0 + 1), WIDEST / (ib.x1 - ib.x0 + 1));
  const frames: Partial<Record<Pose, string>> = {};
  for (const [pose, { canvas: cut, alpha, width }, box] of found) {
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
    s.imageSmoothingQuality = "high";
    s.drawImage(cut, box.x0, box.y0, box.x1 - box.x0 + 1, box.y1 - box.y0 + 1, fx, fy, w, h);
    s.globalCompositeOperation = "source-in";
    s.fillStyle = "#fffcf7";
    s.fillRect(0, 0, CANVAS_W, CANVAS_H);
    const f = frame.getContext("2d")!;
    f.imageSmoothingQuality = "high";
    if (outline) for (let a = 0; a < 16; a++) f.drawImage(silhouette, Math.cos((a / 16) * Math.PI * 2) * OUTLINE, Math.sin((a / 16) * Math.PI * 2) * OUTLINE);
    f.drawImage(cut, box.x0, box.y0, box.x1 - box.x0 + 1, box.y1 - box.y0 + 1, fx, fy, w, h);
    frames[pose] = frame.toDataURL("image/png");
  }
  const missing = POSES.filter((p) => !frames[p]);
  if (missing.length && missing.length < POSES.length - 1) warnings.unshift(`${missing.length} of 16 poses are missing; they borrow from others (${missing.slice(0, 4).join(", ")}${missing.length > 4 ? "…" : ""}). It works, just with less variety.`);
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
