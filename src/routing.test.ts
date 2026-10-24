import { describe, expect, it } from "vitest";
import type { PetRecord } from "./familiar";
import { DEFAULT_LOOK } from "./pet/look";
import { PALETTE_NAMES, SPECIES_NAMES } from "./pet/look";
import { findPet, nextCompanion, nextName, ORDER, resolve, ROSTER } from "./routing";

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

describe("next companion", () => {
  const pet = (name: string, species = "bunny", palette = "snow") =>
    ({ id: name, name, look: { species, palette, accessory: "none", style: "soft" }, bindings: [] }) as PetRecord;
  it("starts with the comfort style's crew and its designed looks", () => {
    expect(nextCompanion([pet("Pip")])).toEqual({ name: "Byte", look: { species: "cat", palette: "charcoal", accessory: "glasses", style: "soft" } });
    expect(nextCompanion([pet("Pip"), pet("byte")]).name).toBe("Patch");
    expect(nextCompanion([pet("Pip"), pet("Byte"), pet("Patch")]).look.species).toBe("sheep");
    expect(nextCompanion([pet("Slate")], "professional").name).toBe("Finch");
    expect(nextCompanion([pet("Dot")], "minimal").name).toBe("Slate");
  });
  it("keeps each character's first art family", () => {
    expect(ROSTER.Stack.look.style).toBe("ink");
    expect(ROSTER.Kite.look.style).toBe("anime");
  });
  it("then picks plain names and the least used body and coat", () => {
    const all = Object.values(ROSTER).map((c) => pet(c.name, c.look.species, c.look.palette));
    const next = nextCompanion([pet("Pip"), ...all]);
    expect(next.name).toBe("Mochi");
    expect(ORDER.friendly.length).toBe(Object.keys(ROSTER).length);
    expect(nextName(["Mochi"])).toBe("Biscuit");
  });
  it("names every roster body and coat that exists", () => {
    for (const c of Object.values(ROSTER)) {
      expect(SPECIES_NAMES).toContain(c.look.species);
      expect(PALETTE_NAMES).toContain(c.look.palette);
    }
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
