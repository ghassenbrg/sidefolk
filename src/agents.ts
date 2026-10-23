import type { Bubble } from "./bubble";
import type { Directive, Mind } from "./mind";

/** Mirrors `AgentEvent` in src-tauri/src/bus.rs. */
export type AgentEvent = {
  source: "claude" | "codex";
  session: string;
  kind:
    | "start"
    | "think"
    | "read"
    | "edit"
    | "run"
    | "tool"
    | "waiting"
    | "idle"
    | "message"
    | "done"
    | "failed"
    | "end";
  detail: string;
  cwd: string;
};

type Busy = "think" | "read" | "edit" | "run" | "tool" | "waiting";
type Session = { source: AgentEvent["source"]; cwd: string; state: Busy; detail: string; at: number };

const NAMES = { claude: "Claude", codex: "Codex" } as const;
const RANK: Record<Busy, number> = { waiting: 5, edit: 4, run: 4, tool: 3, read: 2, think: 1 };
const CLIP: Record<Busy, NonNullable<Directive>["clip"]> = {
  waiting: "alert",
  edit: "work",
  run: "work",
  tool: "work",
  read: "read",
  think: "think",
};
const VERB: Record<Busy, string> = {
  waiting: "needs you",
  edit: "editing",
  run: "running",
  tool: "using",
  read: "reading",
  think: "thinking",
};
/** A session that goes quiet this long is assumed gone (crashed, closed terminal). */
const STALE_MS = 10 * 60 * 1000;

const folder = (path: string) => path.split("/").filter(Boolean).pop() ?? "";

/**
 * Folds events from every agent session into one thing the pet can act out:
 * the most urgent session wins, finishes and failures play a short reaction.
 */
export class Agents {
  private sessions = new Map<string, Session>();
  private openAsks = 0;

  constructor(
    private readonly mind: Mind,
    private readonly bubble: Bubble,
    private readonly hud: HTMLElement,
  ) {}

  handle(event: AgentEvent) {
    const key = `${event.source}:${event.session}`;
    const name = NAMES[event.source];
    const where = folder(event.cwd);
    switch (event.kind) {
      case "start":
        this.bubble.say(`${name} started in ${where}.`, 3);
        this.mind.react("wave", 1.4);
        break;
      case "think":
      case "read":
      case "edit":
      case "run":
      case "tool":
      case "waiting":
        this.sessions.set(key, {
          source: event.source,
          cwd: event.cwd,
          state: event.kind,
          detail: event.detail,
          at: Date.now(),
        });
        if (event.kind === "waiting" && !this.bubble.busy)
          this.bubble.say(event.detail || `${name} needs you in ${where}.`, 12);
        break;
      case "message":
        if (event.detail) this.bubble.say(event.detail, 7);
        break;
      case "done":
        this.sessions.delete(key);
        this.mind.react("celebrate", 2.2);
        this.bubble.say(`${name} finished in ${where}.${event.detail ? ` ${event.detail}` : ""}`, 9, "done");
        break;
      case "failed":
        this.sessions.delete(key);
        this.mind.react("sad", 2.6);
        this.bubble.say(`${name} hit a problem in ${where}: ${event.detail || "unknown error"}`, 9, "fail");
        break;
      case "idle":
      case "end":
        this.sessions.delete(key);
        break;
    }
    this.refresh();
  }

  /** A permission bubble is open or closed; keep the pet at the cursor while any is open. */
  asking(open: number) {
    this.openAsks = open;
    this.refresh();
  }

  tick() {
    const now = Date.now();
    let changed = false;
    for (const [key, session] of this.sessions)
      if (now - session.at > STALE_MS) changed = this.sessions.delete(key) || changed;
    if (changed) this.refresh();
  }

  private refresh() {
    const top = [...this.sessions.values()].sort((a, b) => RANK[b.state] - RANK[a.state] || b.at - a.at)[0];
    if (this.openAsks > 0) this.mind.directive = { clip: "alert", come: true };
    else this.mind.directive = top ? { clip: CLIP[top.state], come: top.state === "waiting" } : null;

    // While a question is open the bubble says it all.
    if (!top || this.openAsks > 0) {
      this.hud.hidden = true;
      return;
    }
    this.hud.hidden = false;
    this.hud.className = `state-${top.state}`;
    const others = this.sessions.size - 1;
    this.hud.textContent =
      `${NAMES[top.source]} · ${VERB[top.state]}${top.detail && top.state !== "waiting" ? ` ${top.detail}` : ""}` +
      (others > 0 ? `  +${others}` : "");
  }
}
