import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";

// Phase 0 placeholder character: a bunny built from primitives, but rigged like a real
// asset (one skinned mesh, a named skeleton, clips that drive bones). Swapping in an
// artist-made glTF later only replaces this file.

export const BONES = [
  "root",
  "hips",
  "chest",
  "head",
  "earL",
  "earR",
  "eyeL",
  "eyeR",
  "armL",
  "armR",
  "legL",
  "legR",
  "tail",
] as const;
export type BoneName = (typeof BONES)[number];

type Vec3 = [number, number, number];

// Bind pose in model space: feet on y = 0, facing +z, about 2.3 units tall.
const JOINTS: Record<BoneName, { parent: BoneName | null; at: Vec3 }> = {
  root: { parent: null, at: [0, 0, 0] },
  hips: { parent: "root", at: [0, 0.36, 0] },
  chest: { parent: "hips", at: [0, 0.38, 0] },
  head: { parent: "chest", at: [0, 1.0, 0] },
  earL: { parent: "head", at: [-0.2, 1.84, 0] },
  earR: { parent: "head", at: [0.2, 1.84, 0] },
  eyeL: { parent: "head", at: [-0.24, 1.47, 0.53] },
  eyeR: { parent: "head", at: [0.24, 1.47, 0.53] },
  armL: { parent: "chest", at: [-0.38, 0.86, 0] },
  armR: { parent: "chest", at: [0.38, 0.86, 0] },
  legL: { parent: "hips", at: [-0.18, 0.3, 0] },
  legR: { parent: "hips", at: [0.18, 0.3, 0] },
  tail: { parent: "hips", at: [0, 0.42, -0.36] },
};

export const PALETTE = {
  coat: 0xf1e4d2,
  cream: 0xfffaf3,
  pink: 0xf3aaa8,
  blush: 0xf7a5a0,
  scarf: 0x6fcfb4,
  ink: 0x2c2733,
  outline: 0x3b3342,
};

type Part = {
  shape: "sphere" | "torus" | "box" | "arc";
  bone: BoneName;
  at: Vec3;
  size: Vec3;
  rot?: Vec3;
  color: number;
  outline?: boolean;
};

const mirrored = (part: Part, left: BoneName, right: BoneName): Part[] => [
  { ...part, bone: left },
  {
    ...part,
    bone: right,
    at: [-part.at[0], part.at[1], part.at[2]],
    rot: part.rot && [part.rot[0], -part.rot[1], -part.rot[2]],
  },
];

const PARTS: Part[] = [
  { shape: "sphere", bone: "chest", at: [0, 0.6, 0], size: [0.46, 0.5, 0.42], color: PALETTE.coat, outline: true },
  { shape: "sphere", bone: "chest", at: [0, 0.55, 0.33], size: [0.28, 0.3, 0.1], color: PALETTE.cream },
  { shape: "torus", bone: "chest", at: [0, 0.98, 0], size: [1, 1, 0.85], rot: [Math.PI / 2, 0, 0], color: PALETTE.scarf, outline: true },
  { shape: "box", bone: "chest", at: [0.2, 0.8, 0.33], size: [0.12, 0.26, 0.05], rot: [0.25, 0, 0.18], color: PALETTE.scarf, outline: true },
  { shape: "sphere", bone: "head", at: [0, 1.42, 0.02], size: [0.66, 0.56, 0.56], color: PALETTE.coat, outline: true },
  { shape: "sphere", bone: "head", at: [0, 1.3, 0.5], size: [0.24, 0.15, 0.12], color: PALETTE.cream },
  { shape: "sphere", bone: "head", at: [0, 1.37, 0.6], size: [0.055, 0.038, 0.03], color: PALETTE.pink },
  { shape: "arc", bone: "head", at: [0, 1.285, 0.612], size: [1, 1, 1], color: PALETTE.ink },
  ...mirrored({ shape: "sphere", bone: "eyeL", at: [-0.24, 1.47, 0.53], size: [0.075, 0.1, 0.05], color: PALETTE.ink }, "eyeL", "eyeR"),
  ...mirrored({ shape: "sphere", bone: "eyeL", at: [-0.255, 1.505, 0.574], size: [0.026, 0.03, 0.012], color: 0xffffff }, "eyeL", "eyeR"),
  ...mirrored({ shape: "sphere", bone: "head", at: [-0.4, 1.33, 0.45], size: [0.09, 0.05, 0.03], rot: [0, -0.7, 0], color: PALETTE.blush }, "head", "head"),
  ...mirrored({ shape: "sphere", bone: "earL", at: [-0.25, 2.06, -0.02], size: [0.13, 0.38, 0.09], rot: [0, 0, 0.12], color: PALETTE.coat, outline: true }, "earL", "earR"),
  ...mirrored({ shape: "sphere", bone: "earL", at: [-0.25, 2.04, 0.055], size: [0.07, 0.27, 0.03], rot: [0, 0, 0.12], color: PALETTE.pink }, "earL", "earR"),
  ...mirrored({ shape: "sphere", bone: "armL", at: [-0.47, 0.66, 0.06], size: [0.13, 0.23, 0.13], rot: [0, 0, -0.28], color: PALETTE.coat, outline: true }, "armL", "armR"),
  ...mirrored({ shape: "sphere", bone: "legL", at: [-0.2, 0.11, 0.06], size: [0.17, 0.12, 0.21], color: PALETTE.coat, outline: true }, "legL", "legR"),
  { shape: "sphere", bone: "tail", at: [0, 0.42, -0.42], size: [0.14, 0.14, 0.14], color: PALETTE.cream, outline: true },
];

function primitive(part: Part): THREE.BufferGeometry {
  switch (part.shape) {
    case "sphere":
      return new THREE.SphereGeometry(1, 28, 18);
    case "torus":
      return new THREE.TorusGeometry(0.36, 0.075, 10, 36);
    case "box":
      return new THREE.BoxGeometry(1, 1, 1);
    case "arc":
      // A small smile: the lower half of a thin torus.
      return new THREE.TorusGeometry(0.055, 0.013, 6, 14, Math.PI).rotateZ(Math.PI);
  }
}

function partGeometry(part: Part): THREE.BufferGeometry {
  const geometry = primitive(part);
  geometry.scale(...part.size);
  if (part.rot) geometry.rotateX(part.rot[0]).rotateY(part.rot[1]).rotateZ(part.rot[2]);
  geometry.translate(...part.at);
  geometry.deleteAttribute("uv");
  const count = geometry.getAttribute("position").count;
  const color = new THREE.Color(part.color);
  const colors = new Float32Array(count * 3);
  const skinIndex = new Uint16Array(count * 4);
  const skinWeight = new Float32Array(count * 4);
  const bone = BONES.indexOf(part.bone);
  for (let i = 0; i < count; i++) {
    colors.set([color.r, color.g, color.b], i * 3);
    skinIndex[i * 4] = bone;
    skinWeight[i * 4] = 1;
  }
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  geometry.setAttribute("skinIndex", new THREE.BufferAttribute(skinIndex, 4));
  geometry.setAttribute("skinWeight", new THREE.BufferAttribute(skinWeight, 4));
  return geometry;
}

function toonRamp(): THREE.DataTexture {
  const ramp = new THREE.DataTexture(new Uint8Array([110, 190, 255]), 3, 1, THREE.RedFormat);
  ramp.minFilter = ramp.magFilter = THREE.NearestFilter;
  ramp.needsUpdate = true;
  return ramp;
}

/** Inverted-hull outline: back faces pushed out along normals, before skinning. */
function outlineMaterial(width: number): THREE.MeshBasicMaterial {
  const material = new THREE.MeshBasicMaterial({ color: PALETTE.outline, side: THREE.BackSide });
  material.onBeforeCompile = (shader) => {
    shader.vertexShader = shader.vertexShader.replace(
      "#include <begin_vertex>",
      `vec3 transformed = position + normal * ${width.toFixed(4)};`,
    );
  };
  return material;
}

export type Rig = {
  object: THREE.Group;
  body: THREE.SkinnedMesh;
  bones: Record<BoneName, THREE.Bone>;
  rest: Record<BoneName, THREE.Vector3>;
  /** Height of the eyes above the feet, in model units. */
  eyeHeight: number;
};

export function buildRig(): Rig {
  const bones = {} as Record<BoneName, THREE.Bone>;
  const rest = {} as Record<BoneName, THREE.Vector3>;
  for (const name of BONES) {
    const joint = JOINTS[name];
    const bone = new THREE.Bone();
    bone.name = name;
    const parent = joint.parent ? JOINTS[joint.parent].at : [0, 0, 0];
    bone.position.set(joint.at[0] - parent[0], joint.at[1] - parent[1], joint.at[2] - parent[2]);
    rest[name] = bone.position.clone();
    if (joint.parent) bones[joint.parent].add(bone);
    bones[name] = bone;
  }
  const skeleton = new THREE.Skeleton(BONES.map((name) => bones[name]));

  const geometry = mergeGeometries(PARTS.map(partGeometry))!;
  const body = new THREE.SkinnedMesh(
    geometry,
    new THREE.MeshToonMaterial({ vertexColors: true, gradientMap: toonRamp() }),
  );
  body.add(bones.root);
  body.updateMatrixWorld(true);
  body.bind(skeleton);
  // Generous bounds so raycasts are not rejected while limbs are raised.
  body.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 1.1, 0), 2.4);

  const hull = mergeGeometries(PARTS.filter((p) => p.outline).map(partGeometry))!;
  const outline = new THREE.SkinnedMesh(hull, outlineMaterial(0.032));
  outline.bind(skeleton, body.bindMatrix);
  outline.raycast = () => {};

  const object = new THREE.Group();
  object.add(body, outline);
  return { object, body, bones, rest, eyeHeight: 1.47 };
}
