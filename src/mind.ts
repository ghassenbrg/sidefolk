import type { ClipName } from "./pet/clips";
import type { Eyes, Pet } from "./pet/pet";

/** What agent activity asks the pet to act out. `come` walks it over to the cursor. */
export type Directive = { clip: "think" | "read" | "work" | "alert"; come: boolean } | null;

type Point = { x: number; y: number };
type Bounds = { width: number; height: number };

const WALK_SPEED = 72;
const GRAVITY = 2600;
const MARGIN = 70;
/** Phase 0 uses cursor stillness; Phase 1 should use the OS idle time instead. */
const SLEEP_AFTER = 45;

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
  private cursorStill = 0;
  private cursorWasNear = false;
  private waveCooldown = 5;
  directive: Directive = null;

  constructor(
    private readonly pet: Pet,
    private readonly bounds: Bounds,
  ) {
    this.x = Math.max(MARGIN, bounds.width - 180);
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

  /** Frames per second worth spending on the current state. */
  get fps(): number {
    if (this.mode !== "ground") return 60;
    switch (this.pet.clip) {
      case "sleep":
        return 12;
      case "idle":
      case "sit":
      case "think":
      case "read":
      case "sad":
        return 30;
      default:
        return 60;
    }
  }

  onCursor(point: Point) {
    if (this.cursor && Math.hypot(point.x - this.cursor.x, point.y - this.cursor.y) > 2) this.cursorStill = 0;
    this.cursor = point;
  }

  react(clip: ClipName, seconds: number) {
    this.reaction = { clip, left: seconds };
  }

  poke() {
    if (this.mode !== "ground") return;
    this.react("celebrate", 0.9);
    this.pet.squash(0.12);
    this.cursorStill = 0;
  }

  grab() {
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
    this.cursorStill += dt;
    this.waveCooldown -= dt;
    if (this.mode === "held") {
      this.pet.play("dangle", 0.15);
      this.pet.face(0);
      return;
    }
    if (this.mode === "air") return this.fly(dt);

    if (this.reaction) {
      this.reaction.left -= dt;
      this.pet.play(this.reaction.clip);
      this.pet.face(0);
      if (this.reaction.left <= 0) this.reaction = null;
      return;
    }

    if (this.directive) {
      if (this.directive.come && this.cursor && this.walkTowardCursor(dt)) return;
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
    if (this.activity === "sleep" && this.cursorStill < 0.5) {
      this.begin("wave", 1.6);
    } else if (this.cursorStill > SLEEP_AFTER && this.activity !== "sleep") {
      this.begin(this.activity === "sit" ? "sleep" : "sit", this.activity === "sit" ? Infinity : 2);
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
    if (this.activity === "sit" && this.cursorStill > SLEEP_AFTER) return this.begin("sleep", Infinity);
    const roll = Math.random();
    if (roll < 0.45) {
      const towardCursor = this.cursor && Math.random() < 0.35;
      const goal = towardCursor
        ? this.cursor!.x + between(-160, 160)
        : between(MARGIN, this.bounds.width - MARGIN);
      this.begin("walk", 30);
      this.walkTo = this.clampX(goal);
    } else if (roll < 0.75) this.begin("idle", between(3, 7));
    else if (roll < 0.92) this.begin("sit", between(8, 16));
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

  private clampX(x: number) {
    return Math.min(this.bounds.width - MARGIN, Math.max(MARGIN, x));
  }
}
