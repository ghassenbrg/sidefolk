// A worker's color: every crew character wears the same mint accent (scarf, lights, hoodie,
// leaves), so turning only mint pixels to the worker's hue recolors the accent and leaves fur,
// faces and outlines as drawn. A CSS hue-rotate on the whole picture turned brown otters blue.

/** Mint's hue (#6FCFB4 is 163°) and how far from it a pixel still counts as mint, in degrees. */
const MINT = 163;
const RANGE = 28;
/** Below this saturation a pixel is ivory, cream or charcoal, never accent. */
const MIN_SATURATION = 0.22;

/** Turns the mint pixels of RGBA `data` by `hue` degrees, in place. */
export function shiftMint(data: Uint8ClampedArray, hue: number) {
  if (!hue) return;
  for (let i = 0; i < data.length; i += 4) {
    if (!data[i + 3]) continue;
    const r = data[i] / 255;
    const g = data[i + 1] / 255;
    const b = data[i + 2] / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    const d = max - min;
    if (!d) continue;
    const s = d / (1 - Math.abs(2 * l - 1));
    if (s < MIN_SATURATION) continue;
    let h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
    const off = Math.abs(((h - MINT + 540) % 360) - 180);
    if (off > RANGE) continue;
    // Pixels at the edge of the range turn a little less, so anti-aliased edges blend.
    const turn = hue * Math.min(1, (RANGE - off) / 8);
    const [nr, ng, nb] = hsl((h + turn + 360) % 360, s, l);
    data[i] = nr;
    data[i + 1] = ng;
    data[i + 2] = nb;
  }
}

function hsl(h: number, s: number, l: number): [number, number, number] {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

/** A decoded image with its mint turned by `hue`, as a data URL. */
export function recolored(img: HTMLImageElement, hue: number): string {
  const canvas = document.createElement("canvas");
  canvas.width = img.naturalWidth;
  canvas.height = img.naturalHeight;
  const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(img, 0, 0);
  const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height);
  shiftMint(pixels.data, hue);
  ctx.putImageData(pixels, 0, 0);
  return canvas.toDataURL("image/png");
}
