import * as THREE from "three";
import type { BoneName } from "./model";

// How a pet looks: a palette that recolors the hero's vertex-color regions, and one
// accessory. Every look keeps the hero's skeleton and clips, so every animation works.

/** Bodies built by art/blender/build_hero.py; all share the skeleton, clips and palette colors. */
export const SPECIES = {
  bunny: { label: "Bunny", url: "models/hero.glb" },
  cat: { label: "Cat", url: "models/cat.glb" },
  fox: { label: "Fox", url: "models/fox.glb" },
  sheep: { label: "Sheep", url: "models/sheep.glb" },
  turtle: { label: "Turtle", url: "models/turtle.glb" },
  robot: { label: "Robot", url: "models/robot.glb" },
  raccoon: { label: "Raccoon", url: "models/raccoon.glb" },
  squid: { label: "Squid", url: "models/squid.glb" },
  crt: { label: "CRT bot", url: "models/crt.glb" },
  courier: { label: "Courier", url: "models/courier.glb" },
  archivist: { label: "Archivist", url: "models/archivist.glb" },
  dragon: { label: "Dragon", url: "models/dragon.glb" },
  // The Studio Collection's quiet bodies.
  penguin: { label: "Penguin", url: "models/penguin.glb" },
  capsule: { label: "Capsule", url: "models/capsule.glb" },
  owl: { label: "Owl", url: "models/owl.glb" },
  bird: { label: "Bird", url: "models/bird.glb" },
  orbit: { label: "Quiet robot", url: "models/orbit.glb" },
  vale: { label: "Curled fox", url: "models/vale.glb" },
} as const;
export type SpeciesName = keyof typeof SPECIES;
export const SPECIES_NAMES = Object.keys(SPECIES) as SpeciesName[];
/** Imported models are stored by the app and named "custom:<file>". */
export const CUSTOM = "custom:";

/** Coats. `cream` (muzzle, belly) is a lighter body unless the design names it. */
export const PALETTES: Record<string, { label: string; body: string; points: string; scarf: string; cream?: string }> = {
  snow: { label: "Snow", body: "#f2e4d2", points: "#4a3f4f", scarf: "#6fcfb4" },
  // The starter crew's designed coats: Byte the charcoal cat, Patch the terracotta fox.
  charcoal: { label: "Charcoal", body: "#3d404b", points: "#1e2027", scarf: "#6fcfb4", cream: "#efe5d3" },
  terracotta: { label: "Terracotta", body: "#c87658", points: "#3a2a2a", scarf: "#6fcfb4", cream: "#f7ecdc" },
  // Loom's wool (the design board's lavender) around a charcoal face.
  lavender: { label: "Lavender", body: "#c9b8ea", points: "#3d3943", scarf: "#6fcfb4", cream: "#f1ebf8" },
  // The rest of the roster's designed coats.
  moss: { label: "Moss", body: "#9fc28a", points: "#56724a", scarf: "#6fcfb4", cream: "#efe7c6" },
  stone: { label: "Stone", body: "#9b968f", points: "#2e2a2c", scarf: "#6fcfb4", cream: "#f1ebe1" },
  indigo: { label: "Indigo", body: "#353d60", points: "#1f2438", scarf: "#6fcfb4", cream: "#f4efe6" },
  navy: { label: "Navy", body: "#ece3d3", points: "#26304d", scarf: "#6fcfb4", cream: "#fbf7ef" },
  plum: { label: "Plum", body: "#efe7da", points: "#4a2f52", scarf: "#6fcfb4", cream: "#fbf7ef" },
  mint: { label: "Mint", body: "#86cbb0", points: "#2f4f4b", scarf: "#6fcfb4", cream: "#f3ecd2" },
  slate: { label: "Slate", body: "#6f7a88", points: "#3b414b", scarf: "#6fcfb4", cream: "#efe8da" },
  sand: { label: "Sand", body: "#e8dcc3", points: "#3d4048", scarf: "#6fcfb4", cream: "#f8f2e4" },
  cocoa: { label: "Cocoa", body: "#c9966c", points: "#4a2f25", scarf: "#f0b043" },
  midnight: { label: "Midnight", body: "#646a82", points: "#25222f", scarf: "#f27a72" },
  peach: { label: "Peach", body: "#f8c9ab", points: "#8a4f3d", scarf: "#6eaaea" },
  sage: { label: "Sage", body: "#cbdab8", points: "#4c5a3c", scarf: "#b383dc" },
  honey: { label: "Honey", body: "#f3d070", points: "#6b4a1f", scarf: "#4fb6a8" },
  ember: { label: "Ember", body: "#ec8c4f", points: "#3b2b2d", scarf: "#5fb8d8" },
};
export const PALETTE_NAMES = ["snow", "charcoal", "terracotta", "lavender", "moss", "stone", "indigo", "navy", "plum", "mint", "slate", "sand", "cocoa", "midnight", "peach", "sage", "honey", "ember"] as const;
export type PaletteName = (typeof PALETTE_NAMES)[number];

/**
 * Art styles (creative-design/CHARACTERS.md, "Style families"): one character, three ways to
 * draw it. Styles are renderer looks on the same model, so every style keeps the name,
 * project, animations, status light and click area. src/pet/model.ts draws them.
 */
export const STYLES = {
  soft: { label: "Soft 3D" },
  ink: { label: "Ink & Geek" },
  anime: { label: "Pocket Anime" },
} as const;
export type StyleName = keyof typeof STYLES;
export const STYLE_NAMES = Object.keys(STYLES) as StyleName[];

export const ACCESSORIES = {
  none: "Nothing",
  glasses: "Glasses",
  headphones: "Headphones",
  flower: "Flower",
  beanie: "Beanie",
} as const;
export type AccessoryName = keyof typeof ACCESSORIES;
export const ACCESSORY_NAMES = Object.keys(ACCESSORIES) as AccessoryName[];

/** Looks saved before styles existed have no `style`; they read as Soft 3D. */
export type Look = { species: string; palette: PaletteName; accessory: AccessoryName; style: StyleName };
export const DEFAULT_LOOK: Look = { species: "bunny", palette: "snow", accessory: "none", style: "soft" };

/** Accepts anything (stored files, agent text) and returns a valid look. */
export function normalizeLook(value: unknown): Look {
  const v = (value ?? {}) as Partial<Record<keyof Look, unknown>>;
  return {
    species:
      typeof v.species === "string" && (SPECIES_NAMES.includes(v.species as SpeciesName) || /^custom:[\w.-]+\.glb$/.test(v.species))
        ? v.species
        : DEFAULT_LOOK.species,
    palette: PALETTE_NAMES.includes(v.palette as PaletteName) ? (v.palette as PaletteName) : DEFAULT_LOOK.palette,
    accessory: ACCESSORY_NAMES.includes(v.accessory as AccessoryName)
      ? (v.accessory as AccessoryName)
      : DEFAULT_LOOK.accessory,
    style: STYLE_NAMES.includes(v.style as StyleName) ? (v.style as StyleName) : DEFAULT_LOOK.style,
  };
}

// Regions of the hero's vertex colors (linear RGB, as exported by art/blender/build_hero.py).
const REGIONS = {
  body: [0.88, 0.776, 0.644],
  points: [0.068, 0.05, 0.078],
  scarf: [0.159, 0.624, 0.456],
  cream: [1, 0.956, 0.896],
  scarfDetail: [0.105, 0.479, 0.342],
} as const;
type Region = keyof typeof REGIONS;

const linear = (hex: string) => new THREE.Color(hex);
const near = (r: number, g: number, b: number, c: readonly number[]) =>
  Math.abs(r - c[0]) + Math.abs(g - c[1]) + Math.abs(b - c[2]) < 0.03;

/** Colors per region for a palette; cream and the scarf's darker detail follow from the rest. */
export function regionColors(palette: PaletteName): Record<Region, THREE.Color> {
  const p = PALETTES[palette];
  const body = linear(p.body);
  const scarf = linear(p.scarf);
  return {
    body,
    points: linear(p.points),
    scarf,
    cream: p.cream ? linear(p.cream) : body.clone().lerp(new THREE.Color(1, 1, 1), 0.6),
    scarfDetail: scarf.clone().multiplyScalar(0.68),
  };
}

/** Rewrites a geometry's vertex colors in place. Colors outside the known regions stay. */
export function recolor(geometry: THREE.BufferGeometry, palette: PaletteName) {
  if (palette === "snow") return;
  const colors = geometry.getAttribute("color") as THREE.BufferAttribute | undefined;
  if (!colors) return;
  const target = regionColors(palette);
  for (let i = 0; i < colors.count; i++) {
    const [r, g, b] = [colors.getX(i), colors.getY(i), colors.getZ(i)];
    for (const region of Object.keys(REGIONS) as Region[]) {
      if (!near(r, g, b, REGIONS[region])) continue;
      const c = target[region];
      colors.setXYZ(i, c.r, c.g, c.b);
      break;
    }
  }
  colors.needsUpdate = true;
}

/**
 * Accessory meshes in bone-local space (bones point up with identity rest rotation, so
 * x is right, y up, z toward the viewer). Positions were fitted in the browser preview.
 */
export function accessory(
  name: AccessoryName,
  outline: number,
  toon: (color: string) => THREE.Material = (color) => new THREE.MeshToonMaterial({ color }),
): { bone: BoneName; object: THREE.Object3D } | null {
  const ink = new THREE.MeshBasicMaterial({ color: outline });
  const group = new THREE.Group();
  switch (name) {
    case "glasses": {
      // Byte's round mint glasses; the bridge stays dark so the frame reads at small sizes.
      const mint = new THREE.MeshBasicMaterial({ color: "#6fcfb4" });
      for (const side of [-1, 1]) {
        const ring = new THREE.Mesh(new THREE.TorusGeometry(0.15, 0.032, 8, 28), mint);
        ring.position.set(side * 0.25, 0.47, 0.6);
        ring.rotation.y = side * 0.32;
        group.add(ring);
      }
      const bridge = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 0.2, 6), ink);
      bridge.rotation.z = Math.PI / 2;
      bridge.position.set(0, 0.5, 0.66);
      group.add(bridge);
      return { bone: "head", object: group };
    }
    case "headphones": {
      const band = new THREE.Mesh(new THREE.TorusGeometry(0.62, 0.05, 8, 32, Math.PI), toon("#3d3a4a"));
      band.position.set(0, 0.42, 0.12);
      group.add(band);
      for (const side of [-1, 1]) {
        const cup = new THREE.Mesh(new THREE.CylinderGeometry(0.19, 0.19, 0.14, 20), toon("#f27a72"));
        cup.rotation.z = Math.PI / 2;
        cup.position.set(side * 0.62, 0.38, 0.12);
        group.add(cup);
      }
      return { bone: "head", object: group };
    }
    case "flower": {
      const petal = toon("#ffd1dc");
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        const p = new THREE.Mesh(new THREE.SphereGeometry(0.075, 10, 8), petal);
        p.position.set(Math.cos(a) * 0.09, Math.sin(a) * 0.09, 0);
        p.scale.z = 0.5;
        group.add(p);
      }
      const middle = new THREE.Mesh(new THREE.SphereGeometry(0.06, 10, 8), toon("#ffc94a"));
      middle.position.z = 0.03;
      group.add(middle);
      group.position.set(0.34, 0.94, 0.2);
      group.scale.setScalar(1.5);
      return { bone: "head", object: group };
    }
    case "beanie": {
      const crown = new THREE.Mesh(
        new THREE.SphereGeometry(0.42, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2),
        toon("#5a7bd8"),
      );
      crown.scale.y = 0.62;
      const pom = new THREE.Mesh(new THREE.SphereGeometry(0.1, 12, 10), toon("#f4f1ea"));
      pom.position.y = 0.28;
      group.add(crown, pom);
      group.position.set(0, 0.98, 0.04);
      group.rotation.x = -0.12;
      return { bone: "head", object: group };
    }
    case "none":
      return null;
  }
}
