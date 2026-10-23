import * as THREE from "three";
import { GLTFLoader, type GLTF } from "three/addons/loaders/GLTFLoader.js";
import * as SkeletonUtils from "three/addons/utils/SkeletonUtils.js";
import { CLIPS, type ClipName } from "./clips";
import { accessory, CUSTOM, recolor, SPECIES, type Look, type SpeciesName } from "./look";

// The hero comes from art/blender/build_hero.py (npm run model). The glTF follows the rig
// contract in art/HERO.md: these bone names, these clip names, a "Body" mesh that gets the
// outline and a "Face" mesh of details that does not.

export const BONES = [
  "root",
  "hips",
  "chest",
  "head",
  "earL",
  "earLTip",
  "earR",
  "earRTip",
  "eyeL",
  "eyeR",
  "armL",
  "armR",
  "legL",
  "legR",
  "tail",
] as const;
export type BoneName = (typeof BONES)[number];

export const OUTLINE = 0x3b3342;

/** Model units, measured from the export: feet at 0. */
export const MODEL_HEIGHT = 2.55;
export const EYE_HEIGHT = 1.33;
/** Paw position relative to the right arm's pivot, for holding props. */
export const RIGHT_PAW = new THREE.Vector3(0.21, -0.25, 0.05);

export type Model = {
  object: THREE.Object3D;
  body: THREE.SkinnedMesh;
  bones: Record<BoneName, THREE.Bone>;
  rest: Record<BoneName, THREE.Vector3>;
  clips: Record<ClipName, THREE.AnimationClip>;
};

function toonRamp(): THREE.DataTexture {
  const ramp = new THREE.DataTexture(new Uint8Array([120, 195, 255]), 3, 1, THREE.RedFormat);
  ramp.minFilter = ramp.magFilter = THREE.NearestFilter;
  ramp.needsUpdate = true;
  return ramp;
}

/** Inverted-hull outline: back faces pushed out along normals, before skinning. */
function outlineMaterial(width: number): THREE.MeshBasicMaterial {
  const material = new THREE.MeshBasicMaterial({ color: OUTLINE, side: THREE.BackSide });
  material.onBeforeCompile = (shader) => {
    shader.vertexShader = shader.vertexShader.replace(
      "#include <begin_vertex>",
      `vec3 transformed = position + normal * ${width.toFixed(4)};`,
    );
  };
  return material;
}

function skinnedMesh(root: THREE.Object3D, name: string): THREE.SkinnedMesh {
  const mesh = root.getObjectByName(name);
  if (!(mesh instanceof THREE.SkinnedMesh)) throw new Error(`model has no skinned "${name}" mesh`);
  return mesh;
}

const loaded = new Map<string, Promise<GLTF>>();

/** Reads an imported model's bytes; set by the desktop app. */
let readCustom: (file: string) => Promise<ArrayBuffer> = () => Promise.reject(new Error("Imported models need the desktop app."));
export function setCustomReader(reader: typeof readCustom) {
  readCustom = reader;
}

/** Parses each model file once; every pet gets its own instance of it. */
function load(species: string): Promise<GLTF> {
  let gltf = loaded.get(species);
  if (!gltf) {
    gltf = species.startsWith(CUSTOM)
      ? readCustom(species.slice(CUSTOM.length)).then((bytes) => new GLTFLoader().parseAsync(bytes, ""))
      : new GLTFLoader().loadAsync((SPECIES[species as SpeciesName] ?? SPECIES.bunny).url);
    loaded.set(species, gltf);
    // A failed load (a bad import) should be retried, not cached.
    gltf.catch(() => loaded.delete(species));
  }
  return gltf;
}

/**
 * An independent copy of the hero for one pet: its own skeleton, recolored vertex colors and
 * accessory. Clips are shared; each pet's mixer plays them on its own bones.
 */
export async function loadModel(look: Look): Promise<Model> {
  const url = look.species;
  const gltf = await load(look.species);
  const scene = SkeletonUtils.clone(gltf.scene);
  const toon = new THREE.MeshToonMaterial({ vertexColors: true, gradientMap: toonRamp() });
  const body = skinnedMesh(scene, "Body");
  const face = skinnedMesh(scene, "Face");
  for (const mesh of [body, face]) {
    mesh.geometry = mesh.geometry.clone();
    recolor(mesh.geometry, look.palette);
    mesh.material = toon;
    // Skinned bounds are computed from the bind pose; animation can leave them.
    mesh.frustumCulled = false;
  }
  // Generous bounds so raycasts are not rejected while limbs are raised.
  body.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 1.2, 0), 2.6);
  face.raycast = () => {};

  const outline = new THREE.SkinnedMesh(body.geometry, outlineMaterial(0.03));
  outline.bind(body.skeleton, body.bindMatrix);
  outline.frustumCulled = false;
  outline.raycast = () => {};
  body.parent!.add(outline);

  const bones = {} as Record<BoneName, THREE.Bone>;
  const rest = {} as Record<BoneName, THREE.Vector3>;
  for (const name of BONES) {
    const bone = body.skeleton.getBoneByName(name);
    if (!bone) throw new Error(`${url} is missing bone "${name}"`);
    bones[name] = bone;
    rest[name] = bone.position.clone();
  }

  const clips = {} as Record<ClipName, THREE.AnimationClip>;
  for (const name of CLIPS) {
    const clip = THREE.AnimationClip.findByName(gltf.animations, name);
    if (!clip) throw new Error(`${url} is missing clip "${name}"`);
    clips[name] = clip;
  }

  const extra = accessory(look.accessory, OUTLINE);
  if (extra) {
    extra.object.traverse((o) => (o.raycast = () => {}));
    bones[extra.bone].add(extra.object);
  }
  return { object: scene, body, bones, rest, clips };
}
