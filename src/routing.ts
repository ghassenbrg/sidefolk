import type { PetRecord } from "./familiar";
import { PALETTE_NAMES, type PaletteName } from "./pet/look";

/** What an agent event or question says about where it came from. */
export type Origin = { source: string; session: string; project: string };

/**
 * The pet that speaks for an origin: the most specific binding wins (a session, then a
 * project, then an agent). `null` means the main pet.
 */
export function resolve(pets: readonly PetRecord[], origin: Origin): string | null {
  const session = `${origin.source}:${origin.session}`;
  const order = [
    (p: PetRecord) => p.bindings.some((b) => b.kind === "session" && b.key === session),
    (p: PetRecord) => !!origin.project && p.bindings.some((b) => b.kind === "project" && b.key === origin.project),
    (p: PetRecord) => p.bindings.some((b) => b.kind === "agent" && b.key === origin.source),
  ];
  for (const matches of order) {
    const pet = pets.find(matches);
    if (pet) return pet.id;
  }
  return null;
}

const NAMES = ["Pip", "Mochi", "Biscuit", "Clover", "Pebble", "Juniper", "Toffee", "Nori", "Sprout", "Maple", "Basil", "Waffle"];

/** A friendly name nobody in the crew has yet. */
export function nextName(taken: readonly string[]): string {
  const used = new Set(taken.map((n) => n.toLowerCase()));
  const free = NAMES.find((n) => !used.has(n.toLowerCase()));
  if (free) return free;
  for (let i = 2; ; i++) {
    const name = `${NAMES[taken.length % NAMES.length]} ${i}`;
    if (!used.has(name.toLowerCase())) return name;
  }
}

/** The palette used least so far, so pets are easy to tell apart. */
export function nextPalette(used: readonly PaletteName[]): PaletteName {
  const count = (p: PaletteName) => used.filter((u) => u === p).length;
  return [...PALETTE_NAMES].sort((a, b) => count(a) - count(b))[0];
}

/** Finds a pet by its name or its project's folder name, ignoring case. */
export function findPet(pets: readonly PetRecord[], words: string): PetRecord | undefined {
  const want = words.trim().toLowerCase().replace(/^the\s+/, "").replace(/\s+pet$/, "");
  const folderOf = (p: PetRecord) => {
    const project = p.bindings.find((b) => b.kind === "project")?.key ?? "";
    return project.split("/").filter(Boolean).pop()?.toLowerCase() ?? "";
  };
  return (
    pets.find((p) => p.name.toLowerCase() === want) ??
    pets.find((p) => folderOf(p) === want) ??
    pets.find((p) => p.name.toLowerCase().startsWith(want) && want.length >= 2)
  );
}
