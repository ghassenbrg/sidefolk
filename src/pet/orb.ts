import * as THREE from "three";
import type { ClipName } from "./clips";

// The floating status light from the concept sheet: a small glowing orb that trails the pet's
// head and changes color with what the agents are doing, readable without any text.

export type Glow = "idle" | "think" | "work" | "alert" | "done" | "sad" | "sleep";

const LOOK: Record<Glow, { color: number; strength: number; pulse: number }> = {
  idle: { color: 0xffd98a, strength: 0.75, pulse: 0.5 },
  think: { color: 0x8cc6ff, strength: 0.9, pulse: 1.4 },
  work: { color: 0xffb547, strength: 0.95, pulse: 2.2 },
  alert: { color: 0xff7a2e, strength: 1, pulse: 4 },
  done: { color: 0x6fe3b4, strength: 1, pulse: 0.8 },
  sad: { color: 0x9d90b8, strength: 0.55, pulse: 0.4 },
  sleep: { color: 0xffe3ad, strength: 0.3, pulse: 0.25 },
};

export function glowFor(clip: ClipName, alerting: boolean): Glow {
  if (alerting) return "alert";
  switch (clip) {
    case "think":
      return "think";
    case "read":
    case "work":
      return "work";
    case "alert":
      return "alert";
    case "celebrate":
      return "done";
    case "sad":
      return "sad";
    case "sleep":
      return "sleep";
    default:
      return "idle";
  }
}

function haloTexture(): THREE.CanvasTexture {
  const size = 64;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext("2d")!;
  const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, "rgba(255,255,255,1)");
  gradient.addColorStop(0.2, "rgba(255,255,255,0.65)");
  gradient.addColorStop(0.5, "rgba(255,255,255,0.18)");
  gradient.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

const WHITE = new THREE.Color(0xffffff);

const damp = (from: number, to: number, rate: number, dt: number) =>
  from + (to - from) * (1 - Math.exp(-rate * dt));

/** Lives in world pixels next to the pet, not inside it, so it can lag and float freely. */
export class Orb {
  readonly object = new THREE.Group();
  private readonly core: THREE.Mesh<THREE.SphereGeometry, THREE.MeshBasicMaterial>;
  private readonly halo: THREE.Sprite;
  private readonly color = new THREE.Color(LOOK.idle.color);
  private readonly target = new THREE.Color();
  private strength = LOOK.idle.strength;
  private time = 0;
  private placed = false;

  constructor(private readonly size: number) {
    this.core = new THREE.Mesh(
      new THREE.SphereGeometry(size * 0.11, 16, 12),
      new THREE.MeshBasicMaterial({ color: 0xffffff }),
    );
    this.halo = new THREE.Sprite(
      new THREE.SpriteMaterial({ map: haloTexture(), transparent: true, depthWrite: false }),
    );
    this.halo.scale.setScalar(size);
    this.object.add(this.halo, this.core);
    this.object.renderOrder = 10;
  }

  /**
   * @param anchor where the orb wants to float, in world pixels
   * @param still reduced motion: a steady light, no bobbing or pulsing
   */
  update(dt: number, anchor: THREE.Vector3, glow: Glow, still = false) {
    const look = LOOK[glow];
    this.time += dt;
    if (!this.placed) {
      this.object.position.copy(anchor);
      this.placed = true;
    }
    // The pulse rate belongs to the state; more events never make it flash faster.
    const bob = still ? 0 : Math.sin(this.time * 1.7) * this.size * 0.12;
    this.object.position.x = damp(this.object.position.x, anchor.x, 3.5, dt);
    this.object.position.y = damp(this.object.position.y, anchor.y + bob, 3.5, dt);
    this.object.position.z = anchor.z;

    this.color.lerp(this.target.set(look.color), 1 - Math.exp(-5 * dt));
    this.strength = damp(this.strength, look.strength, 4, dt);
    const pulse = still ? 1 : 0.82 + 0.18 * Math.sin(this.time * look.pulse * Math.PI);
    this.halo.material.color.copy(this.color);
    this.halo.material.opacity = this.strength * pulse;
    this.core.material.color.copy(this.color).lerp(WHITE, 0.55);
    this.core.material.opacity = Math.min(1, this.strength + 0.2);
    this.core.material.transparent = this.strength < 0.8;
    this.halo.scale.setScalar(this.size * (1.2 + 0.35 * pulse * this.strength));
  }
}
