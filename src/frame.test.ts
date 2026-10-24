import { describe, expect, it } from "vitest";
import { needed, shouldMove } from "./frame";

describe("overlay window size", () => {
  it("covers the companions with a margin, kept on the work area", () => {
    expect(needed([{ x: 1000, y: 700, width: 120, height: 110 }], 1440, 875)).toEqual({ x: 928, y: 628, width: 264, height: 247 });
    expect(needed([{ x: 10, y: 20, width: 50, height: 50 }, { x: 1400, y: 800, width: 100, height: 100 }], 1440, 875)).toEqual({ x: 0, y: 0, width: 1440, height: 875 });
  });

  it("is the whole work area with nothing to show", () => {
    expect(needed([], 1440, 875)).toEqual({ x: 0, y: 0, width: 1440, height: 875 });
  });

  it("moves when something would be cut off or the window is far too big, not for small changes", () => {
    const current = { x: 900, y: 600, width: 300, height: 275 };
    expect(shouldMove(current, { x: 910, y: 610, width: 280, height: 265 })).toBe(false);
    expect(shouldMove(current, { x: 880, y: 610, width: 280, height: 265 })).toBe(true);
    expect(shouldMove(current, { x: 900, y: 300, width: 300, height: 575 })).toBe(true);
    expect(shouldMove({ x: 0, y: 0, width: 1440, height: 875 }, { x: 900, y: 600, width: 300, height: 275 })).toBe(true);
  });
});
