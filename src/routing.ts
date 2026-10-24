import type { PetRecord } from "./familiar";
import { PALETTE_NAMES, SPECIES_NAMES, type Look, type PaletteName, type StyleName } from "./pet/look";

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

type Character = { name: string; look: Look };
const character = (name: string, species: string, palette: PaletteName, style: StyleName = "soft", accessory: Look["accessory"] = "none"): Character => ({
  name,
  look: { species, palette, accessory, style },
});

/**
 * The roster from creative-design/CHARACTERS.md and PROFESSIONAL-COLLECTION.md, each with its
 * designed body, coat and first art family. Names stay with their designs.
 */
export const ROSTER: Record<string, Character> = Object.fromEntries(
  [
    character("Byte", "cat", "charcoal", "soft", "glasses"),
    character("Patch", "fox", "terracotta"),
    character("Loom", "sheep", "lavender"),
    character("Moss", "turtle", "moss"),
    character("Relay", "robot", "snow"),
    character("Stack", "raccoon", "stone", "ink"),
    character("Nib", "squid", "indigo", "ink"),
    character("Pico", "crt", "snow", "ink"),
    character("Sora", "courier", "navy", "anime"),
    character("Yuna", "archivist", "plum", "anime"),
    character("Kite", "dragon", "mint", "anime"),
    character("Slate", "penguin", "charcoal"),
    character("Dot", "capsule", "snow"),
    character("Calder", "owl", "slate"),
    character("Finch", "bird", "sand"),
    character("Orbit", "orbit", "snow"),
    character("Vale", "vale", "terracotta"),
  ].map((c) => [c.name, c]),
);

/**
 * Who comes next, by comfort style: Friendly follows the Starter Studio crew (Byte, Patch,
 * Loom), Professional the Workday crew (Finch, Calder, Orbit), Minimal the Quiet Desk (Slate,
 * Finch, Orbit). The rest of the roster follows, then plain names.
 */
export const ORDER: Record<string, string[]> = {
  friendly: ["Byte", "Patch", "Loom", "Moss", "Relay", "Stack", "Nib", "Pico", "Kite", "Sora", "Yuna", "Finch", "Calder", "Orbit", "Vale", "Slate", "Dot"],
  professional: ["Finch", "Calder", "Orbit", "Vale", "Slate", "Dot", "Byte", "Patch", "Loom", "Moss", "Relay", "Stack", "Nib", "Pico", "Kite", "Sora", "Yuna"],
  minimal: ["Slate", "Finch", "Orbit", "Dot", "Calder", "Vale", "Byte", "Patch", "Loom", "Moss", "Relay", "Stack", "Nib", "Pico", "Kite", "Sora", "Yuna"],
};
const NAMES = ["Mochi", "Biscuit", "Clover", "Pebble", "Juniper", "Toffee", "Nori", "Sprout", "Maple", "Basil", "Waffle"];

/** A plain name nobody in the crew has yet (after the roster is used up). */
export function nextName(taken: readonly string[]): string {
  const used = new Set(taken.map((n) => n.toLowerCase()));
  const free = NAMES.find((n) => !used.has(n.toLowerCase()));
  if (free) return free;
  for (let i = 2; ; i++) {
    const name = `${NAMES[taken.length % NAMES.length]} ${i}`;
    if (!used.has(name.toLowerCase())) return name;
  }
}

const leastUsed = <T extends string>(options: readonly T[], used: readonly string[]) =>
  [...options].sort((a, b) => used.filter((u) => u === a).length - used.filter((u) => u === b).length)[0];

/** The next companion's name and look, following the comfort style's crew. */
export function nextCompanion(crew: readonly PetRecord[], comfort = "friendly"): Character {
  const taken = crew.map((p) => p.name.toLowerCase());
  const name = (ORDER[comfort] ?? ORDER.friendly).find((n) => !taken.includes(n.toLowerCase()));
  if (name) return ROSTER[name];
  return {
    name: nextName(crew.map((p) => p.name)),
    look: {
      species: leastUsed(SPECIES_NAMES, crew.map((p) => p.look.species)),
      palette: leastUsed<PaletteName>(PALETTE_NAMES, crew.map((p) => p.look.palette)),
      accessory: "none",
      style: "soft",
    },
  };
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
