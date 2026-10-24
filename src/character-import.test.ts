import { describe, expect, it } from "vitest";
import { alphaOf, despill, findFigures, gridCells, poseOfName, resolvePose, type Box } from "./character-import";

describe("resolvePose", () => {
  it("uses a pose when it's there and borrows sensibly when it isn't", () => {
    expect(resolvePose(new Set(["idle", "alert"]), "alert")).toBe("alert");
    expect(resolvePose(new Set(["idle", "note"]), "write1")).toBe("note");
    expect(resolvePose(new Set(["idle", "sit"]), "sleep")).toBe("sit");
    expect(resolvePose(new Set(["idle"]), "dangle")).toBe("idle");
  });
});

describe("alphaOf", () => {
  // 3×3 picture: white background, one dark pixel in the middle, one pale guide pixel.
  const px = (r: number, g: number, b: number) => [r, g, b, 255];
  const white = px(255, 255, 255);
  const data = new Uint8ClampedArray([...white, ...white, ...white, ...white, ...px(39, 42, 51), ...px(236, 236, 236), ...white, ...white, ...white]);
  it("keys out the corners' color and the template's pale guides", () => {
    const alpha = alphaOf(data, 3, 3);
    expect(alpha[4]).toBe(255);
    expect(alpha[5]).toBe(0);
    expect(alpha[0]).toBe(0);
  });
  it("keeps a picture's own transparency", () => {
    const clear = new Uint8ClampedArray(data);
    clear[3] = 0;
    clear[4 * 4 + 3] = 200;
    expect(alphaOf(clear, 3, 3)[4]).toBe(200);
  });
  it("keeps light areas inside the figure's outline", () => {
    // 5×5: white, a dark ring around one white pixel in the middle.
    const W = [255, 255, 255, 255];
    const D = [39, 42, 51, 255];
    const rows = [
      [W, W, W, W, W],
      [W, D, D, D, W],
      [W, D, W, D, W],
      [W, D, D, D, W],
      [W, W, W, W, W],
    ];
    const alpha = alphaOf(new Uint8ClampedArray(rows.flat(2)), 5, 5);
    expect(alpha[12]).toBe(255);
    expect(alpha[0]).toBe(0);
  });
});

/** An opacity map with solid rectangles [x0, y0, x1, y1) on a clear background. */
function paint(width: number, height: number, rects: number[][]) {
  const alpha = new Uint8ClampedArray(width * height);
  for (const [x0, y0, x1, y1] of rects) for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) alpha[y * width + x] = 255;
  return alpha;
}

describe("findFigures", () => {
  it("finds poses by the space between them, row by row, and drops labels", () => {
    // Two rows of two 30×60 figures, and a short label under the first.
    const alpha = paint(200, 200, [
      [10, 10, 40, 70],
      [110, 10, 140, 70],
      [10, 82, 60, 88],
      [10, 110, 40, 170],
      [110, 120, 140, 170],
    ]);
    const boxes = findFigures(alpha, 200, 200);
    expect(boxes.map((b) => [b.x0, b.y0])).toEqual([
      [10, 10],
      [110, 10],
      [10, 110],
      [110, 120],
    ]);
  });
});

describe("gridCells", () => {
  const box = (x0: number, y0: number, x1: number, y1: number): Box => ({ x0, y0, x1, y1, count: 1000 });
  it("reads the square template by position, so an empty box stays a gap", () => {
    // 4×4 cells of 100 px: figures in cells 0, 2 and 5.
    const cells = gridCells([box(10, 10, 90, 90), box(210, 10, 290, 90), box(110, 110, 190, 190)], 400, 400);
    expect(cells).toEqual({ cell: [0, 2, 5], size: 16 });
  });
  it("reads other sheets by rows and their fullest row's columns", () => {
    const sheet = [box(10, 10, 90, 190), box(210, 10, 290, 190), box(410, 10, 490, 190), box(610, 10, 690, 190), box(10, 210, 90, 390), box(410, 220, 490, 390)];
    expect(gridCells(sheet, 800, 400)).toEqual({ cell: [0, 1, 2, 3, 4, 6], size: 8 });
    expect(gridCells([box(10, 10, 90, 190)], 300, 200)).toEqual({ cell: [0], size: 1 });
  });
});

describe("poseOfName", () => {
  it("finds a pose word in a file name", () => {
    expect(poseOfName("idle.png")).toBe("idle");
    expect(poseOfName("03-listen.webp")).toBe("listen");
    expect(poseOfName("Bun wave.PNG")).toBe("wave");
    expect(poseOfName("sheet-a.png")).toBeNull();
  });
});

describe("despill", () => {
  it("takes a chroma green tint out of edge pixels only", () => {
    const data = new Uint8ClampedArray([120, 230, 110, 255, 120, 230, 110, 255]);
    despill(data, new Uint8ClampedArray([128, 255]));
    expect([...data.slice(0, 3)]).toEqual([120, 120, 110]);
    expect(data[5]).toBe(230);
  });
});
