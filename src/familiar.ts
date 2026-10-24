import * as THREE from "three";
import { Agents } from "./agents";
import { Bubble } from "./bubble";
import { Mind } from "./mind";
import { loadModel } from "./pet/model";
import { glowFor, Orb } from "./pet/orb";
import { HEIGHT, Pet, SCALE } from "./pet/pet";
import { sound, voiceFor, type Cue } from "./sound";
import { Stage, VIEW } from "./stage";

/**
 * The companion on the desktop: its model, mind, status light, canvas, speech bubble and status
 * badge, and the agent sessions it speaks for. It stays where you put it.
 */
export class Familiar {
  readonly stage: Stage;
  readonly mind: Mind;
  readonly orb: Orb;
  readonly bubble: Bubble;
  readonly hud: HTMLElement;
  readonly agents: Agents;
  /** Requests this companion is showing, so it keeps its "needs you" pose until they're answered. */
  readonly asks = new Set<string>();
  private last = 0;
  private readonly orbAnchor = new THREE.Vector3();

  private constructor(
    public name: string,
    public pet: Pet,
    private readonly zoom: number,
  ) {
    const canvas = document.createElement("canvas");
    canvas.className = "stage";
    this.bubble = new Bubble(document.createElement("div"));
    this.hud = document.createElement("div");
    this.hud.className = "hud";
    this.hud.hidden = true;
    document.body.append(canvas, this.hud, this.bubble.root);
    this.stage = new Stage(canvas, VIEW * zoom);
    pet.holder.scale.multiplyScalar(zoom);
    this.orb = new Orb(30 * zoom);
    this.stage.scene.add(pet.holder, this.orb.object);
    this.mind = new Mind(pet, this.stage);
    this.agents = new Agents(this.mind, this.bubble, this.hud);
    this.bubble.onShow = (text, urgent) => {
      if (urgent) sound.cue("alert", this.voice);
      sound.say(text, this.voice);
    };
    const cues: Record<string, Cue> = { poke: "poke", wave: "wave", celebrate: "celebrate", sad: "sad" };
    this.mind.onReact = (clip) => {
      if (cues[clip]) sound.cue(cues[clip], this.voice);
    };
  }

  static async create(name: string, zoom = 1): Promise<Familiar> {
    return new Familiar(name, new Pet(await loadModel()), zoom);
  }

  get voice() {
    return voiceFor(this.name);
  }

  /** Updates and draws the companion if its frame is due. */
  frame(now: number) {
    if (now - this.last < 1000 / this.mind.fps - 4) return;
    // Calm states run at 5–10 fps on purpose; a cap below their frame time would slow them down.
    const dt = Math.min(0.25, (now - this.last) / 1000);
    this.last = now;
    const { mind, pet, zoom } = this;
    mind.update(dt);
    const height = HEIGHT * zoom;
    pet.holder.position.set(mind.x, mind.y, 0);
    pet.update(dt, mind.target, mind.gaze, mind.eyes);
    // The light floats beside the head and lags behind when the companion is moved.
    this.orbAnchor.set(mind.x - 0.85 * SCALE * zoom, mind.y + 2.05 * SCALE * zoom, 300);
    this.orb.update(dt, this.orbAnchor, glowFor(pet.clip, mind.directive?.clip === "alert"), mind.calm);
    this.stage.frame(mind.x, mind.y + height / 2);
    this.stage.render();
    this.bubble.tick(now);
    const hudOffset = this.hud.hidden ? 0 : 30;
    if (!this.hud.hidden) {
      const left = Math.round(mind.x - this.hud.offsetWidth / 2);
      this.hud.style.transform = `translate(${left}px, ${Math.round(this.stage.height - mind.y - height - 26)}px)`;
    }
    this.bubble.place(mind.x, mind.y + height + hudOffset + 8);
  }

  /** Milliseconds until the next frame is due. */
  due(now: number) {
    return Math.max(0, 1000 / this.mind.fps - (now - this.last));
  }

  resize() {
    this.stage.resize();
    this.mind.fitBounds();
  }
}
