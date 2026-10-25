// The two companions (docs/V1.md F-24; the founder keeps both, 25 October 2026): Pip the bunny
// and Spark the robot, as pre-rendered 3D clay frames in public/crew/<id>/3d/<pose>.webp, cut
// from art/crew/<id>/3d by scripts/make_sprites.py. Pip is the default (creative-design/PIP.md).

/** `light`: where the status light sits: beside Pip's right ear (frame pixels), on Spark's antenna
 * tip, which moves from pose to pose. */
export type Character = { id: "pip" | "spark"; name: string; kind: string; light: { x: number; y: number } | "antenna" };

export const CHARACTERS: Character[] = [
  { id: "pip", name: "Pip", kind: "Bunny", light: { x: 290, y: 78 } },
  { id: "spark", name: "Spark", kind: "Robot", light: "antenna" },
];

/** A stored look, or Pip for anything else (older installs may name a removed character). */
export const lookOf = (id: string | null | undefined): Character["id"] => (id === "spark" ? "spark" : "pip");

/** Where a companion's frames are, relative to the page. */
export const framesDir = (id: string | null | undefined) => `crew/${lookOf(id)}/3d`;

export const character = (id: string | null | undefined) => CHARACTERS.find((c) => c.id === lookOf(id))!;

/** A picture of the companion for the window. */
export const picture = (id?: string | null, pose = "idle") => `/${framesDir(id)}/${pose}.webp`;
