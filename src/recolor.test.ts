import { describe, expect, it } from "vitest";
import { shiftMint } from "./recolor";

describe("shiftMint", () => {
  it("turns mint and leaves fur, cream and charcoal as they are", () => {
    // Mint #6FCFB4, otter brown, cream, charcoal.
    const data = new Uint8ClampedArray([111, 207, 180, 255, 139, 90, 60, 255, 255, 252, 247, 255, 39, 42, 51, 255]);
    const before = [...data];
    shiftMint(data, 172);
    expect([...data.slice(0, 3)]).not.toEqual(before.slice(0, 3));
    // Rose: red is now the strongest channel.
    expect(data[0]).toBeGreaterThan(data[1]);
    expect([...data.slice(4)]).toEqual(before.slice(4));
  });
  it("does nothing for Pip's own mint", () => {
    const data = new Uint8ClampedArray([111, 207, 180, 255]);
    shiftMint(data, 0);
    expect([...data]).toEqual([111, 207, 180, 255]);
  });
});
