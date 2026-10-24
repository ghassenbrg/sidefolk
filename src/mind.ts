import type { ClipName } from "./pet/clips";
import type { Eyes, Pet } from "./pet/pet";

/** What agent activity asks the pet to act out. `come` walks it over to the cursor. */
export type Directive = { clip: "think" | "read" | "work" | "alert"; come: boolean } | null;

type Point = { x: number; y: number };
type Bounds = { width: number; height: number };

const WALK_SPEED = 72;
const GRAVITY = 2600;
const MARGIN = 70;
/** Fading back to the den; matches the overlay's --motion-entrance. */
const LEAVE_SECS = 0.52;

const between = (min: number, max: number) => min + Math.random() * (max - min);

/**
 * Decides what the pet does each frame: physics while held or thrown, short reactions,
 * agent directives, and otherwise a small autonomous routine. No AI involved.
 */
export class Mind {
  x: number;
  y = 0;
  private vx = 0;
  private vy = 0;
  private mode: "ground" | "held" | "air" = "ground";
  private activity: ClipName = "idle";
  private activityLeft = 2;
  private walkTo: number | null = null;
  private reaction: { clip: ClipName; left: number } | null = null;
  private cursor: Point | null = null;
  private cursorMovedAt = 0;
  private idle = 0;
  private osIdle = false;
  sleepAfterSecs = 120;
  /** Settings → Reduce motion, or macOS reduced motion: no wandering, hops or walking over. */
  calm = false;
  private cursorWasNear = false;
  private waveCooldown = 5;
  /** Seconds left fading out to the den. */
  private leaving: number | null = null;
  /** Off screen, in the den: nothing to update or draw. */
  away = false;
  directive: Directive = null;

  constructor(
    public pet: Pet,
    private readonly bounds: Bounds,
  ) {
    this.x = Math.max(MARGIN, bounds.width - 180);
  }

  get onGround(): boolean {
    return this.mode === "ground";
  }

  get target(): Point | null {
    return this.cursor;
  }

  get eyes(): Eyes {
    if (this.pet.clip === "sleep") return "closed";
    if (this.pet.clip === "celebrate") return "happy";
    return "open";
  }

  get gaze(): number {
    switch (this.pet.clip) {
      case "sleep":
        return 0;
      case "work":
      case "read":
      case "dangle":
        return 0.35;
      default:
        return 1;
    }
  }

  /**
   * Frames per second worth spending on the current state. WebKit caps the overlay at 30, and
   * every frame costs the page, the GPU process and the compositor in the app process, so calm
   * poses run at a fraction of that. Values divide 30 so frames land evenly on the display.
   */
  get fps(): number {
    if (this.mode !== "ground" || this.reaction) return 30;
    // Smooth gaze while the cursor moves nearby.
    const watching =
      !!this.cursor && performance.now() - this.cursorMovedAt < 600 && Math.hypot(this.cursor.x - this.x, this.cursor.y - this.y) < 420;
    switch (this.pet.clip) {
      case "sleep":
        return 5;
      case "idle":
      case "sit":
        return watching ? 30 : 10;
      case "think":
      case "read":
      case "sad":
      case "work":
      case "alert":
        return watching ? 30 : 15;
      default:
        return 30;
    }
  }

  onCursor(point: Point) {
    if (this.cursor && Math.hypot(point.x - this.cursor.x, point.y - this.cursor.y) > 2) {
      this.cursorMovedAt = performance.now();
      if (!this.osIdle) this.idle = 0;
    }
    this.cursor = point;
  }

  /** Desktop idle is authoritative; cursor stillness is only a preview fallback. */
  setOsIdle(seconds: number) {
    if (!Number.isFinite(seconds) || seconds < 0) return;
    this.osIdle = true;
    this.idle = seconds;
    if (seconds < 0.5 && this.activity === "sleep") this.begin("wave", 1.6);
  }

  /** Told about reactions, so the pet can make a sound. */
  onReact: (clip: ClipName | "poke") => void = () => {};

  react(clip: ClipName, seconds: number) {
    this.onReact(clip);
    // Reduced motion: the state shows at once, without hops and waves.
    if (this.calm && clip !== "sad") return;
    this.reaction = { clip, left: seconds };
  }

  poke() {
    if (this.mode !== "ground") return;
    this.onReact("poke");
    if (!this.osIdle) this.idle = 0;
    if (this.calm) return;
    this.reaction = { clip: "celebrate", left: 0.9 };
    this.pet.squash(0.12);
  }

  summon(x: number) {
    this.x = x;
    this.y = this.vx = this.vy = 0;
    this.mode = "ground";
    this.away = false;
    this.leaving = null;
    this.fitBounds();
    this.begin("idle", 3);
    this.react("wave", 1.2);
    if (!this.calm) this.pet.squash(0.18);
  }

  /**
   * Comes out of the den at `x`: the pet fades in where it is needed (the overlay fades its
   * canvas) instead of walking across the screen, and waves once.
   */
  enter(x: number) {
    if (this.away) {
      this.x = this.clampX(x);
      this.y = this.vx = this.vy = 0;
      this.mode = "ground";
      this.begin("idle", between(2, 4));
      this.react("wave", 1.2);
    }
    this.away = false;
    this.leaving = null;
  }

  /** Fades back to the den. */
  leave() {
    if (this.away || this.leaving !== null) return;
    this.leaving = this.calm ? 0 : LEAVE_SECS;
  }

  get isLeaving() {
    return this.leaving !== null;
  }

  grab() {
    this.leaving = null;
    this.mode = "held";
    this.reaction = null;
    this.walkTo = null;
  }

  hold(x: number, y: number) {
    this.x = x;
    this.y = Math.max(0, y);
  }

  release(vx: number, vy: number) {
    this.mode = "air";
    this.vx = vx;
    this.vy = vy;
  }

  update(dt: number) {
    if (!this.osIdle) this.idle += dt;
    this.waveCooldown -= dt;
    if (this.mode === "held") {
      this.pet.play("dangle", 0.15);
      this.pet.face(0);
      return;
    }
    if (this.mode === "air") return this.fly(dt);

    if (this.leaving !== null) {
      this.leaving -= dt;
      if (this.leaving <= 0) {
        this.away = true;
        this.leaving = null;
        this.reaction = null;
        return;
      }
    }

    if (this.reaction) {
      this.reaction.left -= dt;
      this.pet.play(this.reaction.clip);
      this.pet.face(0);
      if (this.reaction.left <= 0) this.reaction = null;
      return;
    }

    if (this.directive) {
      if (this.directive.come && this.cursor && !this.calm && this.walkTowardCursor(dt)) return;
      this.pet.play(this.directive.clip);
      this.pet.face(0);
      return;
    }

    this.routine(dt);
  }

  /** Returns true while still walking. Stops beside the cursor, not under it. */
  private walkTowardCursor(dt: number): boolean {
    const cursor = this.cursor!;
    const goal = this.clampX(cursor.x + (cursor.x > this.x ? -90 : 90));
    if (Math.abs(goal - this.x) < 30) return false;
    this.step(goal, dt, 1.8);
    return true;
  }

  private routine(dt: number) {
    const near = !!this.cursor && Math.hypot(this.cursor.x - this.x, this.cursor.y - this.y - 70) < 220;
    if (this.activity === "sleep" && this.idle < 0.5) {
      this.begin("wave", 1.6);
    } else if (this.idle >= this.sleepAfterSecs && this.activity !== "sleep" && this.activity !== "sit") {
      this.begin("sit", 2);
    } else if (near && !this.cursorWasNear && this.waveCooldown <= 0 && this.activity !== "walk" && this.activity !== "sleep") {
      this.begin("wave", 1.6);
      this.waveCooldown = 40;
    }
    this.cursorWasNear = near;

    if (this.activity === "walk" && this.walkTo !== null) {
      this.step(this.walkTo, dt);
      if (Math.abs(this.walkTo - this.x) < 2) this.activityLeft = 0;
    }
    this.activityLeft -= dt;
    if (this.activityLeft <= 0) this.chooseNext();

    this.pet.play(this.activity);
    if (this.activity !== "walk") this.pet.face(0);
  }

  private begin(activity: ClipName, seconds: number) {
    this.activity = activity;
    this.activityLeft = seconds;
    this.walkTo = null;
  }

  private chooseNext() {
    if (this.activity === "sit" && this.idle >= this.sleepAfterSecs) return this.begin("sleep", Infinity);
    // A calm routine: short strolls, long sits. Walking renders at full rate, so how much of
    // the day the pet spends walking decides most of its CPU cost.
    const roll = Math.random();
    if (roll < 0.3 && !this.calm) {
      const towardCursor = this.cursor && Math.random() < 0.35;
      const goal = towardCursor ? this.cursor!.x + between(-160, 160) : this.x + between(160, 480) * (Math.random() < 0.5 ? -1 : 1);
      this.begin("walk", 8);
      this.walkTo = this.clampX(goal);
    } else if (roll < 0.6) this.begin("idle", between(4, 9));
    else if (roll < 0.9) this.begin("sit", between(15, 35));
    else this.begin("think", between(2.5, 4));
  }

  private step(goal: number, dt: number, speed = 1) {
    const direction = Math.sign(goal - this.x);
    this.x += direction * Math.min(Math.abs(goal - this.x), WALK_SPEED * speed * dt);
    this.pet.play("walk");
    this.pet.face(direction);
  }

  private fly(dt: number) {
    this.vy -= GRAVITY * dt;
    this.x += this.vx * dt;
    this.y += this.vy * dt;
    this.pet.play("fall", 0.12);
    this.pet.face(0);
    if (this.x < MARGIN || this.x > this.bounds.width - MARGIN) {
      this.x = this.clampX(this.x);
      this.vx = -this.vx * 0.5;
    }
    const ceiling = this.bounds.height - 180;
    if (this.y > ceiling) {
      this.y = ceiling;
      this.vy = -Math.abs(this.vy) * 0.3;
    }
    if (this.y > 0) return;
    this.y = 0;
    this.pet.squash(Math.min(0.28, Math.abs(this.vy) / 4000));
    if (Math.abs(this.vy) > 320) {
      this.vy = -this.vy * 0.32;
      this.vx *= 0.7;
      return;
    }
    this.mode = "ground";
    this.vx = this.vy = 0;
    this.begin("idle", between(1.5, 3));
  }

  /** Keeps the pet on screen after the overlay changes size. */
  fitBounds() {
    if (this.away) return;
    this.x = this.clampX(this.x);
    this.y = Math.min(this.y, Math.max(0, this.bounds.height - 180));
    if (this.walkTo !== null) this.walkTo = this.clampX(this.walkTo);
  }

  private clampX(x: number) {
    return Math.min(this.bounds.width - MARGIN, Math.max(MARGIN, x));
  }
}
