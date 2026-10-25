// Pip, the one companion in v1 (docs/V1.md F-24/F-25, creative-design/PIP.md): pre-rendered 3D
// clay frames in public/crew/pip/3d/<pose>.webp, cut from art/crew/pip/3d by
// scripts/make_sprites.py. Spark's frames stay in public/crew/spark for v1.2 (F-19).

/** Where Pip's frames are, relative to the page. */
export const PIP_FRAMES = "crew/pip/3d";

/** A picture of Pip for the window. */
export const picture = (pose = "idle") => `/${PIP_FRAMES}/${pose}.webp`;
