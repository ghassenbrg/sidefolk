import { describe, expect, it } from "vitest";
import { syllables, voiceFor } from "./sound";

describe("voices", () => {
  it("nudges the register by name", () => {
    expect(voiceFor("Pip").pitch).not.toBe(voiceFor("Mochi").pitch);
    expect(voiceFor("Pip").pitch).toBeGreaterThan(500);
  });
  it("babbles a few syllables per line, rising on questions", () => {
    const plain = syllables("Run a command");
    const asked = syllables("Run a command?");
    expect(plain.length).toBeGreaterThan(1);
    expect(asked[asked.length - 1]).toBe(plain[plain.length - 1] + 4);
    expect(syllables("word ".repeat(40)).length).toBe(14);
    expect(syllables("")).toEqual([]);
  });
});
