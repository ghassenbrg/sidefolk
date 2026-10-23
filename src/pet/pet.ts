import * as THREE from "three";
import { buildClips, CLIPS, type ClipName } from "./clips";
import { buildRig, PALETTE, type Rig } from "./rig";

/** CSS pixels per model unit: the pet stands about 140 px tall. */
export const SCALE = 60;
export const HEIGHT = 2.35 * SCALE;

export type Eyes = "open" | "closed" | "happy";

const damp = (from: number, to: number, rate: number, dt: number) =>
  from + (to - from) * (1 - Math.exp(-rate * dt));

function signProp(): THREE.Group {
  const canvas = document.createElement("canvas");
  canvas.width = 128;
  canvas.height = 96;
  const ctx = canvas.getContext("2d")!;
  ctx.fillStyle = "#fff6dc";
  ctx.fillRect(0, 0, 128, 96);
  ctx.fillStyle = "#e0663b";
  ctx.font = "bold 76px ui-rounded, system-ui, sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("!", 64, 52);
  const face = new THREE.CanvasTexture(canvas);
  face.colorSpace = THREE.SRGBColorSpace;
  const edge = new THREE.MeshBasicMaterial({ color: PALETTE.outline });
  const board = new THREE.Mesh(new THREE.BoxGeometry(0.56, 0.42, 0.04), [
    edge,
    edge,
    edge,
    edge,
    new THREE.MeshBasicMaterial({ map: face }),
    edge,
  ]);
  board.position.y = 0.62;
  const stick = new THREE.Mesh(
    new THREE.BoxGeometry(0.05, 0.6, 0.05),
    new THREE.MeshBasicMaterial({ color: 0x9a6b45 }),
  );
  stick.position.y = 0.25;
  const sign = new THREE.Group();
  sign.add(stick, board);
  return sign;
}

/**
 * The character as the rest of the app sees it: play a clip, face a direction, look
 * at something, squash on landing. Everything here is local and costs no tokens.
 */
export class Pet {
  readonly holder = new THREE.Group();
  readonly rig: Rig;
  private readonly mixer: THREE.AnimationMixer;
  private readonly actions: Record<ClipName, THREE.AnimationAction>;
  private current: ClipName = "idle";
  private readonly sign = signProp();
  private yaw = 0.15;
  private targetYaw = 0.15;
  private look = { yaw: 0, pitch: 0 };
  private squashAmount = 0;
  private blinkIn = 3;
  private blinking = 0;
  private readonly lookQ = new THREE.Quaternion();
  private readonly lookE = new THREE.Euler();

  constructor() {
    this.rig = buildRig();
    this.holder.add(this.rig.object);
    this.holder.scale.setScalar(SCALE);
    this.holder.rotation.x = 0.1;
    this.mixer = new THREE.AnimationMixer(this.rig.object);
    const clips = buildClips(this.rig);
    this.actions = Object.fromEntries(
      CLIPS.map((name) => [name, this.mixer.clipAction(clips[name])]),
    ) as Record<ClipName, THREE.AnimationAction>;
    this.actions.idle.play();
    // Held up in the raised right paw while the alert clip plays.
    this.sign.position.set(0.12, -0.36, 0.1);
    this.sign.rotation.z = -2.25;
    this.sign.visible = false;
    this.rig.bones.armR.add(this.sign);
  }

  get clip(): ClipName {
    return this.current;
  }

  play(name: ClipName, fade = 0.25) {
    if (name === this.current) return;
    const next = this.actions[name];
    next.reset().setEffectiveWeight(1).fadeIn(fade).play();
    this.actions[this.current].fadeOut(fade);
    this.current = name;
    this.sign.visible = name === "alert";
  }

  /** -1 faces left, 1 faces right, 0 faces the viewer (slightly turned). */
  face(direction: number) {
    this.targetYaw = direction === 0 ? 0.15 : Math.sign(direction) * 1.05;
  }

  squash(amount: number) {
    this.squashAmount = Math.max(this.squashAmount, amount);
  }

  /** Model point in overlay pixels, for anchoring bubbles. */
  headTop(): THREE.Vector3 {
    return this.holder.position.clone().add(new THREE.Vector3(0, HEIGHT, 0));
  }

  /**
   * @param target cursor in overlay pixels, or null to look ahead
   * @param gaze how much the head follows the target (0..1)
   */
  update(dt: number, target: { x: number; y: number } | null, gaze: number, eyes: Eyes) {
    this.mixer.update(dt);
    const { bones, rest } = this.rig;

    this.yaw = damp(this.yaw, this.targetYaw, 7, dt);
    this.rig.object.rotation.y = this.yaw;

    // Head follows the cursor on top of whatever the clip is doing.
    let yaw = 0;
    let pitch = 0;
    if (target && gaze > 0) {
      const dx = target.x - this.holder.position.x;
      const dy = target.y - (this.holder.position.y + this.rig.eyeHeight * SCALE);
      yaw = (THREE.MathUtils.clamp(dx / 260, -0.75, 0.75) - this.yaw * 0.7) * gaze;
      pitch = THREE.MathUtils.clamp(-dy / 320, -0.32, 0.28) * gaze;
    }
    this.look.yaw = damp(this.look.yaw, yaw, 6, dt);
    this.look.pitch = damp(this.look.pitch, pitch, 6, dt);
    this.lookQ.setFromEuler(this.lookE.set(this.look.pitch, this.look.yaw, 0));
    bones.head.quaternion.multiply(this.lookQ);

    // Eyes: blink now and then, close for sleep, squint when happy.
    this.blinkIn -= dt;
    if (this.blinkIn <= 0) {
      this.blinking = 0.14;
      this.blinkIn = 2 + Math.random() * 4.5;
    }
    this.blinking = Math.max(0, this.blinking - dt);
    const open = eyes === "closed" ? 0.1 : eyes === "happy" ? 0.3 : this.blinking > 0 ? 0.12 : 1;
    for (const [bone, side] of [
      [bones.eyeL, -1],
      [bones.eyeR, 1],
    ] as const) {
      bone.scale.set(1, open, 1);
      bone.position.set(
        rest[side < 0 ? "eyeL" : "eyeR"].x + this.look.yaw * 0.045,
        rest.eyeL.y - this.look.pitch * 0.03,
        rest.eyeL.z,
      );
    }

    // Landing squash springs back on its own.
    this.squashAmount = damp(this.squashAmount, 0, 9, dt);
    const s = this.squashAmount;
    this.rig.object.scale.set(1 + s * 0.6, 1 - s, 1 + s * 0.6);
  }
}
