import { describe as group, expect, it } from "vitest";
import { describe } from "./describe";

group("describe", () => {
  it("reads species, color and accessory", () => {
    expect(describe("a sleepy black cat with a red bandana and glasses")).toEqual({ species: "cat", palette: "midnight", accessory: "glasses" });
    expect(describe("Ginger fox who loves music")).toEqual({ species: "fox", palette: "ember", accessory: "headphones" });
    expect(describe("chocolate bunny")).toEqual({ species: "bunny", palette: "cocoa" });
    expect(describe("a fox, orange with a white tip")).toEqual({ species: "fox", palette: "ember" });
  });
  it("leaves out what it cannot tell", () => {
    expect(describe("something cute")).toEqual({});
  });
});
