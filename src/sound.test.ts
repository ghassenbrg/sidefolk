import { describe, expect, it } from "vitest";
import { syllables, voiceFor } from "./sound";

describe("voices", () => {
  it("gives species their own register and names a small nudge", () => {
    expect(voiceFor("cat", "Pip").pitch).toBeGreaterThan(voiceFor("fox", "Pip").pitch);
    expect(voiceFor("bunny", "Pip").pitch).not.toBe(voiceFor("bunny", "Mochi").pitch);
    expect(voiceFor("custom:x.glb", "Pip").pitch).toBeGreaterThan(0);
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
