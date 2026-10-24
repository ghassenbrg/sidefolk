// The built-in crew: ten characters from the user's reference photos (art/crew/refs), each in
// two styles, "3d" (soft clay renders) and "2d" (flat drawings of the same design). Their
// frames are public/crew/<id>/<style>/<pose>.webp, cut by scripts/make_sprites.py. A companion's
// look is one of these ids, or the id of a character someone made (Settings → Characters).

export type Style = "3d" | "2d";

export type Member = { id: string; name: string; kind: string };

export const ROSTER: Member[] = [
  { id: "spark", name: "Spark", kind: "Robot" },
  { id: "pip", name: "Pip", kind: "Bunny" },
  { id: "pebble", name: "Pebble", kind: "Penguin" },
  { id: "capy", name: "Capy", kind: "Capybara" },
  { id: "nova", name: "Nova", kind: "Alien" },
  { id: "lumi", name: "Lumi", kind: "Cloud spirit" },
  { id: "pixel", name: "Pixel", kind: "Cat" },
  { id: "otis", name: "Otis", kind: "Otter" },
  { id: "rune", name: "Rune", kind: "Owl" },
  { id: "sprout", name: "Sprout", kind: "Tiny plant creature" },
];

/** Your companion's look when none is chosen, and a new Spark worker's. */
export const MAIN_LOOK = "pip";
export const WORKER_LOOK = "spark";

export const member = (id: string | undefined) => ROSTER.find((m) => m.id === id);

/** Where a crew member's frames are, relative to the page. */
export const framesDir = (id: string, style: Style) => `crew/${id}/${style}`;

/** A picture of your companion for the window; a made character shows as Pip there. */
export const picture = (look: string | undefined, style: Style = "3d", pose = "idle") => `/${framesDir(member(look) ? look! : MAIN_LOOK, style)}/${pose}.webp`;
