import { Agents } from "./agents";
import { Bubble } from "./bubble";
import { Mind } from "./mind";
import { DRAWN, FEET, HEIGHT, PipView, VIEW_H, VIEW_W } from "./pip";
import { sound, voiceFor, type Cue } from "./sound";

/** The overlay in CSS pixels; world space has y going up from the bottom edge. */
export class Bounds {
  width = innerWidth;
  height = innerHeight;
  resize() {
    this.width = innerWidth;
    this.height = innerHeight;
  }
  toWorld(x: number, y: number) {
    return { x, y: this.height - y };
  }
}

/** How a companion looks: Pip, or a Spark worker with its color and project badge. */
export type Look = { character?: string; hue?: number; badge?: string; frames?: Partial<Record<string, string>> };

/**
 * A companion on the desktop: its drawing, its mind, card and status badge, and the agent
 * sessions it speaks for. It stays where you put it.
 */
export class Familiar {
  readonly bounds = new Bounds();
  readonly view: PipView;
  /** A worker's project name under its feet; null for Pip. */
  readonly badge: HTMLElement | null = null;
  readonly mind: Mind;
  readonly bubble: Bubble;
  readonly hud: HTMLElement;
  readonly agents: Agents;
  /** Requests this companion is showing, so it keeps its "needs you" pose until they're answered. */
  readonly asks = new Set<string>();
  private last = 0;
  private readonly unit: number;

  private constructor(
    public name: string,
    zoom = 1,
    readonly look: Look = {},
  ) {
    this.view = new PipView(look.character, look.hue, look.frames);
    this.unit = (HEIGHT * zoom) / DRAWN;
    this.view.el.style.width = `${VIEW_W * this.unit}px`;
    this.view.el.style.height = `${VIEW_H * this.unit}px`;
    this.bubble = new Bubble(document.createElement("div"));
    this.hud = document.createElement("div");
    this.hud.className = "hud";
    this.hud.hidden = true;
    document.body.append(this.view.el, this.hud, this.bubble.root);
    if (look.badge) {
      this.badge = document.createElement("div");
      this.badge.className = "worker-badge";
      this.badge.textContent = look.badge;
      if (look.hue) this.badge.style.setProperty("--hue", `${look.hue}deg`);
      document.body.append(this.badge);
    }
    this.mind = new Mind(this.view, this.bounds);
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

  static async create(name: string, zoom = 1, look: Look = {}): Promise<Familiar> {
    const f = new Familiar(name, zoom, look);
    await f.view.ready();
    return f;
  }

  get voice() {
    return voiceFor(this.name);
  }

  /** Height of the drawn companion on screen, in CSS pixels. */
  get height() {
    return DRAWN * this.unit;
  }

  /** Updates and draws the companion if its frame is due. */
  frame(now: number) {
    if (now - this.last < 1000 / this.mind.fps - 4) return;
    // Calm states run at 5–10 fps on purpose; a cap below their frame time would slow them down.
    const dt = Math.min(0.25, (now - this.last) / 1000);
    this.last = now;
    const { mind, view } = this;
    mind.update(dt);
    view.still = mind.calm;
    const eyeY = mind.y + this.height * 0.62;
    view.update(dt, mind.target ? { x: mind.target.x - mind.x, y: eyeY - mind.target.y } : null);
    const left = mind.x - (VIEW_W * this.unit) / 2;
    const top = this.bounds.height - mind.y - FEET * this.unit;
    view.el.style.transform = `translate(${Math.round(left)}px, ${Math.round(top)}px)`;
    // Over the feet, like a name tag, so it stays on screen when the worker stands on the edge.
    if (this.badge) this.badge.style.transform = `translate(${Math.round(mind.x - this.badge.offsetWidth / 2)}px, ${Math.round(this.bounds.height - mind.y - this.badge.offsetHeight - 2)}px)`;
    this.bubble.tick(now);
    const headTop = mind.y + this.height;
    const hudOffset = this.hud.hidden ? 0 : 30;
    if (!this.hud.hidden) {
      const hudLeft = Math.round(mind.x - this.hud.offsetWidth / 2);
      this.hud.style.transform = `translate(${hudLeft}px, ${Math.round(this.bounds.height - headTop - 30)}px)`;
    }
    this.bubble.place(mind.x, headTop + hudOffset + 8);
  }

  /** Milliseconds until the next frame is due. */
  due(now: number) {
    return Math.max(0, 1000 / this.mind.fps - (now - this.last));
  }

  /** Whether a screen point is on the companion itself. */
  contains(x: number, y: number) {
    return this.view.contains(x, y);
  }

  resize() {
    this.bounds.resize();
    this.mind.fitBounds();
  }

  /** A worker leaving the desktop. */
  remove() {
    this.view.el.remove();
    this.hud.remove();
    this.bubble.root.remove();
    this.badge?.remove();
  }
}
