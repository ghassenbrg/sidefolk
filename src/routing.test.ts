import { describe, expect, it } from "vitest";
import type { PetRecord } from "./familiar";
import { DEFAULT_LOOK } from "./pet/look";
import { findPet, nextName, nextPalette, resolve } from "./routing";

const pet = (id: string, name: string, bindings: PetRecord["bindings"]): PetRecord => ({ id, name, look: DEFAULT_LOOK, bindings });
const crew = [
  pet("a", "Pip", [{ kind: "project", key: "/Users/me/git/api" }]),
  pet("b", "Mochi", [{ kind: "agent", key: "codex" }]),
  pet("c", "Nori", [{ kind: "session", key: "claude:s1" }]),
];

describe("resolve", () => {
  it("prefers session, then project, then agent", () => {
    expect(resolve(crew, { source: "claude", session: "s1", project: "/Users/me/git/api" })).toBe("c");
    expect(resolve(crew, { source: "codex", session: "t", project: "/Users/me/git/api" })).toBe("a");
    expect(resolve(crew, { source: "codex", session: "t", project: "/Users/me/git/web" })).toBe("b");
  });
  it("falls back to the main pet", () => {
    expect(resolve(crew, { source: "claude", session: "s2", project: "/Users/me/git/web" })).toBeNull();
    expect(resolve(crew, { source: "claude", session: "s2", project: "" })).toBeNull();
  });
});

describe("names and palettes", () => {
  it("picks unused names", () => {
    expect(nextName([])).toBe("Pip");
    expect(nextName(["pip", "Mochi"])).toBe("Biscuit");
  });
  it("picks the least used palette", () => {
    expect(nextPalette(["snow"])).not.toBe("snow");
  });
});

describe("findPet", () => {
  it("matches names, project folders and prefixes", () => {
    expect(findPet(crew, "pip")?.id).toBe("a");
    expect(findPet(crew, "the api pet")?.id).toBe("a");
    expect(findPet(crew, "Moc")?.id).toBe("b");
    expect(findPet(crew, "x")).toBeUndefined();
  });
});
