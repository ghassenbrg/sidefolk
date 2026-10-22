export const petSpecies = [
  "bunny",
  "cat",
  "fox",
  "bear",
  "frog",
  "ghost",
] as const;
export const petCatalog = [
  {
    id: "bunny",
    name: "Moonbun",
    tag: "A soft little optimist",
    color: "#c2b5f5",
  },
  {
    id: "cat",
    name: "Miso",
    tag: "Curious about everything",
    color: "#f6c477",
  },
  { id: "fox", name: "Ember", tag: "Small paws, big ideas", color: "#ed9f78" },
  {
    id: "bear",
    name: "Pebble",
    tag: "Your calm in the chaos",
    color: "#bba292",
  },
  { id: "frog", name: "Fern", tag: "One hop ahead", color: "#a8cf98" },
  {
    id: "ghost",
    name: "Boo",
    tag: "Friendly background presence",
    color: "#b7d9eb",
  },
] as const;
export type PetSpecies = (typeof petSpecies)[number];
