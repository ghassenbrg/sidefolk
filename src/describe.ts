import type { AccessoryName, Look, PaletteName, SpeciesName } from "./pet/look";

// "Describe your pet": words in a description map to kit settings on this machine. A photo
// goes to an agent only when the user picks one (see `describe_photo` in the desktop app).

const SPECIES_WORDS: [RegExp, SpeciesName][] = [
  [/\b(cat|kitty|kitten|feline)s?\b/, "cat"],
  [/\b(fox|foxes|vixen|kit fox)\b/, "fox"],
  [/\b(bunny|bunnies|rabbit|hare)s?\b/, "bunny"],
];

const PALETTE_WORDS: [RegExp, PaletteName][] = [
  [/\b(orange|ginger|red|rust|copper|ember)\b/, "ember"],
  [/\b(black|dark|gr[ae]y|charcoal|slate|midnight|navy|blue)\b/, "midnight"],
  [/\b(brown|chocolate|cocoa|coffee|tan|caramel)\b/, "cocoa"],
  [/\b(pink|peach|rose|salmon)\b/, "peach"],
  [/\b(green|sage|mint|olive)\b/, "sage"],
  [/\b(yellow|gold|golden|honey|blond|blonde)\b/, "honey"],
  [/\b(white|cream|ivory|snow|light)\b/, "snow"],
];

const ACCESSORY_WORDS: [RegExp, AccessoryName][] = [
  [/\b(glasses|specs|spectacles|nerdy)\b/, "glasses"],
  [/\b(headphones?|headset|music|dj)\b/, "headphones"],
  [/\b(flower|flowers|blossom|daisy)\b/, "flower"],
  [/\b(beanie|hat|toque|woolly)\b/, "beanie"],
];

/** Every match of every pattern, with where it ends. */
function matches<T>(text: string, table: [RegExp, T][]) {
  return table
    .flatMap(([re, value]) => [...text.matchAll(new RegExp(re.source, "g"))].map((m) => ({ value, at: m.index, end: m.index + m[0].length })))
    .sort((a, b) => a.at - b.at);
}

/** The settings a description mentions; anything not mentioned is left out. */
export function describe(text: string): Partial<Look> {
  const t = text.toLowerCase();
  const look: Partial<Look> = {};
  const animal = matches(t, SPECIES_WORDS)[0];
  const colors = matches(t, PALETTE_WORDS);
  // "a black cat with a red bandana": the color right before the animal is its coat.
  const coat = animal ? colors.filter((c) => c.end <= animal.at).pop() : undefined;
  const species = animal?.value;
  const palette = (coat ?? colors[0])?.value;
  const accessory = matches(t, ACCESSORY_WORDS)[0]?.value;
  if (species) look.species = species;
  if (palette) look.palette = palette;
  if (accessory) look.accessory = accessory;
  return look;
}
