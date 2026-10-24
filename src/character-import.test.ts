import { describe, expect, it } from "vitest";
import { alphaOf, resolvePose } from "./character-import";

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
