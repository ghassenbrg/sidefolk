import * as THREE from "three";

/** Side of the square canvas that follows the pet, in CSS pixels. */
export const VIEW = 320;

/**
 * Renders into a small canvas that moves with the pet instead of a full-screen one, so
 * each frame clears and composites a few hundred pixels rather than the whole display.
 *
 * World space is overlay CSS pixels: x from the left edge, y up from the bottom edge.
 */
export class Stage {
  readonly scene = new THREE.Scene();
  readonly renderer: THREE.WebGLRenderer;
  private readonly camera = new THREE.OrthographicCamera(0, 1, 1, 0, 1, 2000);
  width = innerWidth;
  height = innerHeight;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly view = VIEW,
  ) {
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: true,
      powerPreference: "low-power",
    });
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    this.renderer.setSize(view, view);
    this.renderer.setClearColor(0x000000, 0);
    this.camera.position.z = 1000;

    this.scene.add(new THREE.AmbientLight(0xffffff, 1.5));
    const key = new THREE.DirectionalLight(0xfff3e6, 2.2);
    key.position.set(-0.6, 1, 1);
    const rim = new THREE.DirectionalLight(0xdfe8ff, 0.7);
    rim.position.set(1, 0.4, -0.6);
    this.scene.add(key, rim);

    addEventListener("resize", () => this.resize());
  }

  resize() {
    this.width = innerWidth;
    this.height = innerHeight;
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  }

  /** Points the view at a world position and moves the canvas there. */
  frame(x: number, y: number) {
    const view = this.view;
    const left = Math.round(x - view / 2);
    const bottom = Math.round(y - view / 2);
    this.camera.left = left;
    this.camera.right = left + view;
    this.camera.bottom = bottom;
    this.camera.top = bottom + view;
    this.camera.updateProjectionMatrix();
    this.canvas.style.transform = `translate(${left}px, ${this.height - bottom - view}px)`;
  }

  render() {
    this.renderer.render(this.scene, this.camera);
  }

  /** Overlay CSS coordinates (y down) to world (y up). */
  toWorld(x: number, y: number) {
    return { x, y: this.height - y };
  }
}
