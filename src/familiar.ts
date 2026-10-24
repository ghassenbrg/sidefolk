import * as THREE from "three";
import { Agents, folder } from "./agents";
import { Bubble } from "./bubble";
import { Mind } from "./mind";
import { DEFAULT_LOOK, normalizeLook, type Look } from "./pet/look";
import { loadModel } from "./pet/model";
import { glowFor, Orb } from "./pet/orb";
import { HEIGHT, Pet, SCALE } from "./pet/pet";
import { sound, voiceFor, type Cue } from "./sound";
import { privacy } from "./states";
import { Stage, VIEW } from "./stage";

export type Binding = { kind: "session" | "project" | "agent"; key: string };
export type PetRecord = { id: string; name: string; look: Look; bindings: Binding[] };

export const MAIN_ID = "main";

function dispose(object: THREE.Object3D) {
  object.traverse((o) => {
    if (!(o instanceof THREE.Mesh)) return;
    o.geometry.dispose();
    for (const m of Array.isArray(o.material) ? o.material : [o.material]) m.dispose();
  });
}

/**
 * One pet on the desktop: its model, mind, status light, canvas, bubble and HUD, and the
 * agent sessions it speaks for. The main pet is always out; crew pets come and go.
 */
export class Familiar {
  readonly stage: Stage;
  readonly mind: Mind;
  readonly orb: Orb;
  readonly bubble: Bubble;
  readonly hud: HTMLElement;
  readonly agents: Agents;
  /** Permission questions this pet is showing. */
  readonly asks = new Set<string>();
  /** A crew pet stays out at least until then (after finishing, failing or being called). */
  holdUntil = 0;
  private last = 0;
  private shown = false;
  private looking: Promise<void> = Promise.resolve();
  private readonly orbAnchor = new THREE.Vector3();
  private readonly canvas: HTMLCanvasElement;

  private constructor(
    public record: PetRecord,
    public pet: Pet,
    private readonly zoom: number,
  ) {
    this.canvas = document.createElement("canvas");
    this.canvas.className = "stage";
    this.bubble = new Bubble(document.createElement("div"));
    this.hud = document.createElement("div");
    this.hud.className = "hud";
    this.hud.hidden = true;
    document.body.append(this.canvas, this.hud, this.bubble.root);
    this.stage = new Stage(this.canvas, VIEW * zoom);
    pet.holder.scale.multiplyScalar(zoom);
    this.orb = new Orb(30 * zoom);
    this.stage.scene.add(pet.holder, this.orb.object);
    this.mind = new Mind(pet, this.stage);
    this.agents = new Agents(this.mind, this.bubble, this.hud);
    // Only pets on screen make sounds; one in the den would be a voice from nowhere.
    this.bubble.onShow = (text, urgent) => {
      if (!this.out) return;
      if (urgent) sound.cue("alert", this.voice);
      sound.say(text, this.voice);
    };
    const cues: Record<string, Cue> = { poke: "poke", wave: "wave", celebrate: "celebrate", sad: "sad" };
    this.mind.onReact = (clip) => {
      if (this.out && cues[clip]) sound.cue(cues[clip], this.voice);
    };
  }

  static async create(record: PetRecord, zoom = 1): Promise<Familiar> {
    record = { ...record, look: normalizeLook(record.look) };
    let model;
    try {
      model = await loadModel(record.look);
    } catch (error) {
      // A deleted or broken imported model must not keep the pet (or the crew) from starting.
      console.error(`${record.name}: ${error}; using the bunny`);
      model = await loadModel({ ...record.look, species: DEFAULT_LOOK.species });
    }
    return new Familiar(record, new Pet(model), zoom);
  }

  get isMain() {
    return this.record.id === MAIN_ID;
  }

  get name() {
    return this.record.name;
  }

  /** The project this pet looks after, if any. */
  get project(): string | null {
    return this.record.bindings.find((b) => b.kind === "project")?.key ?? null;
  }

  /** How cards name this pet: with its project, unless cards show status only. */
  get shownLabel() {
    return privacy.detail === "status" ? this.name : this.label;
  }

  /** How bubbles name this pet: always text, so two similar pets cannot be confused. */
  get label() {
    const project = this.project;
    if (project) return `${this.name} · ${folder(project)}`;
    const agent = this.record.bindings.find((b) => b.kind === "agent");
    return agent ? `${this.name} · ${agent.key === "codex" ? "Codex" : "Claude"}` : this.name;
  }

  get voice() {
    return voiceFor(this.record.look.species, this.record.name);
  }

  get out() {
    return !this.mind.away;
  }

  get fps() {
    return this.mind.fps;
  }

  /** Applies look changes in order, each on top of the last, even while a model loads. */
  setLook(change: Partial<Look>): Promise<void> {
    const run = this.looking.then(() => this.applyLook({ ...this.record.look, ...change }));
    this.looking = run.catch(() => {});
    return run;
  }

  private async applyLook(look: Look) {
    look = normalizeLook(look);
    const next = new Pet(await loadModel(look));
    next.holder.scale.multiplyScalar(this.zoom);
    next.holder.position.copy(this.pet.holder.position);
    this.stage.scene.remove(this.pet.holder);
    dispose(this.pet.holder);
    this.stage.scene.add(next.holder);
    this.pet = next;
    this.mind.pet = next;
    this.record = { ...this.record, look };
  }

  /** Updates and draws this pet if its frame is due. */
  frame(now: number) {
    const visible = this.out;
    this.canvas.hidden = !visible;
    if (!visible) {
      this.shown = false;
      this.bubble.root.hidden = true;
      this.hud.style.visibility = "hidden";
      return;
    }
    // Fade in when coming out of the den, out when going back (--motion-entrance).
    if (!this.shown) {
      this.shown = true;
      this.canvas.classList.add("out-of-view");
      requestAnimationFrame(() => this.canvas.classList.toggle("out-of-view", this.mind.isLeaving));
    } else this.canvas.classList.toggle("out-of-view", this.mind.isLeaving);
    this.hud.style.visibility = this.mind.isLeaving ? "hidden" : "";
    if (now - this.last < 1000 / this.mind.fps - 4) return;
    // Calm states run at 5–10 fps on purpose; a cap below their frame time would slow them down.
    const dt = Math.min(0.25, (now - this.last) / 1000);
    this.last = now;
    const { mind, pet, zoom } = this;
    mind.update(dt);
    const height = HEIGHT * zoom;
    pet.holder.position.set(mind.x, mind.y, 0);
    pet.update(dt, mind.target, mind.gaze, mind.eyes);
    // The light floats beside the head on the viewer's left, as in the concept sheets, and lags
    // behind when the pet moves.
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

  /** Milliseconds until this pet's next frame is due, or Infinity when it is away. */
  due(now: number) {
    return this.out ? Math.max(0, 1000 / this.mind.fps - (now - this.last)) : Infinity;
  }

  resize() {
    this.stage.resize();
    this.mind.fitBounds();
  }

  destroy() {
    dispose(this.stage.scene);
    this.stage.renderer.dispose();
    this.stage.renderer.forceContextLoss();
    this.canvas.remove();
    this.hud.remove();
    this.bubble.root.remove();
  }
}
