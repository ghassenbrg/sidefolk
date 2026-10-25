import { describe, expect, it } from "vitest";
import { fitsCard } from "./companion";

describe("permission cards", () => {
  it("offer Allow only for an operation that fits whole on the card", () => {
    expect(fitsCard("npm test")).toBe(true);
    expect(fitsCard(`echo ${"x".repeat(700)}; rm -rf build`)).toBe(false);
    expect(fitsCard(Array.from({ length: 13 }, (_, i) => `line ${i}`).join("\n"))).toBe(false);
  });
});
