import * as THREE from "three";
import { BONES, type BoneName, type Rig } from "./rig";

// Clips are written as functions of the loop phase and sampled into ordinary
// AnimationClips, so the mixer treats them exactly like clips from a glTF file.

type Euler3 = [number, number, number];
type Pose = Partial<Record<BoneName, { r?: Euler3; p?: Euler3; s?: Euler3 }>>;

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

const TAU = Math.PI * 2;
const wave = (phase: number, offset = 0) => Math.sin(TAU * phase + offset);
const breathe = (phase: number, depth: number): Euler3 => [1, 1 + depth * (0.5 + 0.5 * wave(phase)), 1];

const idleEars = (p: number, base = 0.08): Pose => ({
  earL: { r: [0, 0, base + 0.05 * wave(p, 0.6)] },
  earR: { r: [0, 0, -base - 0.05 * wave(p, 1.1)] },
});

const sitting = (p: number): Pose => ({
  hips: { p: [0, -0.13, 0] },
  legL: { r: [-1.3, 0, -0.18] },
  legR: { r: [-1.3, 0, 0.18] },
  chest: { s: breathe(p, 0.025) },
  armL: { r: [-0.45, 0, -0.05] },
  armR: { r: [-0.45, 0, 0.05] },
});

const POSES: Record<ClipName, { seconds: number; pose: (p: number) => Pose }> = {
  idle: {
    seconds: 3,
    pose: (p) => ({
      ...idleEars(p),
      chest: { s: breathe(p, 0.025) },
      head: { r: [0.02 * wave(p), 0, 0.03 * wave(p, 1)] },
      armL: { r: [0, 0, -0.08 - 0.03 * wave(p)] },
      armR: { r: [0, 0, 0.08 + 0.03 * wave(p)] },
      tail: { r: [0, 0.2 * wave(p), 0] },
    }),
  },
  walk: {
    seconds: 0.7,
    pose: (p) => ({
      hips: { p: [0, 0.035 * (1 - Math.cos(2 * TAU * p)), 0] },
      chest: { r: [0.06, 0, 0.05 * wave(p)] },
      head: { r: [-0.04, 0, -0.04 * wave(p)] },
      legL: { r: [0.55 * wave(p), 0, 0] },
      legR: { r: [-0.55 * wave(p), 0, 0] },
      armL: { r: [-0.5 * wave(p), 0, -0.15] },
      armR: { r: [0.5 * wave(p), 0, 0.15] },
      earL: { r: [-0.2, 0, 0.12 + 0.08 * wave(2 * p, 0.8)] },
      earR: { r: [-0.2, 0, -0.12 - 0.08 * wave(2 * p, 1.2)] },
      tail: { r: [0, 0.3 * wave(p), 0] },
    }),
  },
  sit: {
    seconds: 3,
    pose: (p) => ({ ...sitting(p), ...idleEars(p), head: { r: [0.04 * wave(p), 0, 0.05] } }),
  },
  sleep: {
    seconds: 4,
    pose: (p) => ({
      ...sitting(p),
      chest: { s: breathe(p, 0.045) },
      head: { r: [0.38 + 0.03 * wave(p), 0, 0.14] },
      earL: { r: [0.5, 0, 0.4] },
      earR: { r: [0.5, 0, -0.35] },
      armL: { r: [-0.3, 0, -0.02] },
      armR: { r: [-0.3, 0, 0.02] },
    }),
  },
  wave: {
    seconds: 1.1,
    pose: (p) => ({
      ...idleEars(p),
      chest: { s: breathe(p, 0.02) },
      head: { r: [0, 0, -0.1] },
      armR: { r: [0, 0, 2.5 + 0.35 * wave(2 * p)] },
      armL: { r: [0, 0, -0.1] },
      hips: { p: [0, 0.02 * Math.abs(wave(p)), 0] },
    }),
  },
  think: {
    seconds: 2.4,
    pose: (p) => ({
      chest: { s: breathe(p, 0.02) },
      head: { r: [-0.14, 0, 0.16 + 0.04 * wave(p)] },
      armR: { r: [-1.25, 0, 0.95] },
      armL: { r: [-0.3, 0, -0.15] },
      earL: { r: [0, 0, 0.15 + 0.04 * wave(p)] },
      earR: { r: [0, 0, -0.25] },
      tail: { r: [0, 0.25 * wave(p), 0] },
    }),
  },
  read: {
    seconds: 2,
    pose: (p) => ({
      ...idleEars(p, 0.12),
      chest: { s: breathe(p, 0.02), r: [0.05, 0, 0] },
      head: { r: [0.22, 0.18 * wave(p), 0] },
      armL: { r: [-1.0, 0, -0.42] },
      armR: { r: [-1.0, 0, 0.42] },
    }),
  },
  work: {
    seconds: 0.5,
    pose: (p) => ({
      chest: { r: [0.1, 0, 0] },
      head: { r: [0.16, 0, 0.03 * wave(p)] },
      armL: { r: [-0.95 + 0.14 * wave(p), 0, -0.3] },
      armR: { r: [-0.95 - 0.14 * wave(p), 0, 0.3] },
      earL: { r: [-0.1, 0, 0.1 + 0.05 * wave(2 * p)] },
      earR: { r: [-0.1, 0, -0.1 - 0.05 * wave(2 * p)] },
    }),
  },
  celebrate: {
    seconds: 0.7,
    pose: (p) => {
      const jump = Math.max(0, wave(p));
      return {
        hips: { p: [0, 0.3 * jump, 0] },
        armL: { r: [0, 0, -2.6 - 0.25 * wave(2 * p)] },
        armR: { r: [0, 0, 2.6 + 0.25 * wave(2 * p)] },
        legL: { r: [0.45 * jump, 0, -0.1] },
        legR: { r: [0.45 * jump, 0, 0.1] },
        earL: { r: [0.3 * jump, 0, 0.25] },
        earR: { r: [0.3 * jump, 0, -0.25] },
        head: { r: [-0.12, 0, 0] },
      };
    },
  },
  alert: {
    seconds: 0.6,
    pose: (p) => ({
      hips: { p: [0, 0.07 * Math.abs(wave(p)), 0] },
      armR: { r: [0, 0, 2.25] },
      armL: { r: [0, 0, -0.35 - 0.25 * wave(p)] },
      head: { r: [-0.08, 0, 0.06] },
      earL: { r: [-0.15, 0, 0.04] },
      earR: { r: [-0.15, 0, -0.04] },
    }),
  },
  sad: {
    seconds: 2.6,
    pose: (p) => ({
      chest: { s: breathe(p, 0.03), r: [0.12, 0, 0] },
      head: { r: [0.32, 0, 0.06 * wave(p)] },
      earL: { r: [0.6, 0, 0.55] },
      earR: { r: [0.6, 0, -0.55] },
      armL: { r: [0, 0, 0.12] },
      armR: { r: [0, 0, -0.12] },
    }),
  },
  dangle: {
    seconds: 1.6,
    pose: (p) => ({
      legL: { r: [0.3 * wave(p), 0, -0.12] },
      legR: { r: [0.3 * wave(p, 0.7), 0, 0.12] },
      armL: { r: [0, 0, -1.3 - 0.25 * wave(p)] },
      armR: { r: [0, 0, 1.3 + 0.25 * wave(p, 0.5)] },
      head: { r: [0.05, 0, 0.08 * wave(p, 1)] },
      earL: { r: [-0.2, 0, -0.1] },
      earR: { r: [-0.2, 0, 0.1] },
      tail: { r: [0, 0.4 * wave(p), 0] },
    }),
  },
  fall: {
    seconds: 0.4,
    pose: (p) => ({
      armL: { r: [0, 0, -2.1 - 0.3 * wave(p)] },
      armR: { r: [0, 0, 2.1 + 0.3 * wave(p)] },
      legL: { r: [-0.3, 0, -0.3] },
      legR: { r: [-0.3, 0, 0.3] },
      earL: { r: [0.5, 0, -0.2] },
      earR: { r: [0.5, 0, 0.2] },
    }),
  },
};

const FRAMES_PER_SECOND = 20;

function sample(name: ClipName, rig: Rig): THREE.AnimationClip {
  const { seconds, pose } = POSES[name];
  const frames = Math.max(8, Math.round(seconds * FRAMES_PER_SECOND));
  const times = Array.from({ length: frames + 1 }, (_, i) => (i / frames) * seconds);
  const euler = new THREE.Euler();
  const quaternion = new THREE.Quaternion();
  const tracks: THREE.KeyframeTrack[] = [];
  // Every clip keys every bone, so blends between clips never leave a bone behind.
  for (const bone of BONES) {
    const rotations: number[] = [];
    const positions: number[] = [];
    const scales: number[] = [];
    for (let i = 0; i <= frames; i++) {
      const key = pose((i % frames) / frames)[bone] ?? {};
      const [rx, ry, rz] = key.r ?? [0, 0, 0];
      quaternion.setFromEuler(euler.set(rx, ry, rz));
      rotations.push(quaternion.x, quaternion.y, quaternion.z, quaternion.w);
      const [dx, dy, dz] = key.p ?? [0, 0, 0];
      const rest = rig.rest[bone];
      positions.push(rest.x + dx, rest.y + dy, rest.z + dz);
      scales.push(...(key.s ?? [1, 1, 1]));
    }
    tracks.push(
      new THREE.QuaternionKeyframeTrack(`${bone}.quaternion`, times, rotations),
      new THREE.VectorKeyframeTrack(`${bone}.position`, times, positions),
      new THREE.VectorKeyframeTrack(`${bone}.scale`, times, scales),
    );
  }
  return new THREE.AnimationClip(name, seconds, tracks);
}

export function buildClips(rig: Rig): Record<ClipName, THREE.AnimationClip> {
  return Object.fromEntries(CLIPS.map((name) => [name, sample(name, rig)])) as Record<
    ClipName,
    THREE.AnimationClip
  >;
}
