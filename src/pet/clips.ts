// Clip names the hero model must provide. The clips themselves are authored in
// art/blender/build_hero.py and exported into public/models/hero.glb.

export const CLIPS = [
  "idle",
  "walk",
  "sit",
  "sleep",
  "wave",
  "think",
  "read",
  "work",
  "celebrate",
  "alert",
  "sad",
  "dangle",
  "fall",
] as const;
export type ClipName = (typeof CLIPS)[number];
