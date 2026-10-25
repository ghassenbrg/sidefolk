import { agentProblem } from "./voice";
import type { Bubble } from "./bubble";
import type { Directive, Mind } from "./mind";
import { badge, stateOf } from "./states";

/** Mirrors `AgentEvent` in src-tauri/src/bus.rs. */
export type AgentEvent = {
  source: "claude" | "codex";
  session: string;
  kind:
    | "start"
    | "prompt"
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
  /** Git root of `cwd`, or `cwd` outside a repository. */
  project: string;
};

type Busy = "think" | "read" | "edit" | "run" | "tool" | "waiting";
export type Session = {
  key: string;
  /** The agent's own session (Claude) or thread (Codex) ID, for "Open session". */
  id: string;
  cwd: string;
  source: AgentEvent["source"];
  project: string;
  state: Busy;
  detail: string;
  at: number;
};
export type Outcome = {
  kind: "done" | "failed";
  source: AgentEvent["source"];
  project: string;
  detail: string;
  at: number;
  /** The session that finished, so it can be opened again. */
  session?: string;
  cwd?: string;
};

export const AGENT_NAMES = { claude: "Claude", codex: "Codex" } as const;
const RANK: Record<Busy, number> = { waiting: 5, edit: 4, run: 4, tool: 3, read: 2, think: 1 };
const CLIP: Record<Busy, NonNullable<Directive>["clip"]> = {
  waiting: "alert",
  edit: "work",
  run: "work",
  tool: "work",
  read: "read",
  think: "think",
};
export const VERB: Record<Busy, string> = {
  waiting: "needs you",
  edit: "editing",
  run: "running",
  tool: "using",
  read: "reading",
  think: "thinking",
};
/** A session that goes quiet this long is assumed gone (crashed, closed terminal). */
const STALE_MS = 10 * 60 * 1000;

export const folder = (path: string) => path.split("/").filter(Boolean).pop() ?? path;

/** A session ID as people can tell them apart: "Work session 3f2a". */
export const sessionLabel = (id: string) => (id ? `Work session ${id.replace(/[^a-z0-9]/gi, "").slice(0, 4)}` : "Work session");

/** " in api", or nothing outside a project. */
const inProject = (project: string) => (project ? ` in ${folder(project)}` : "");

/**
 * Folds events from the sessions one pet speaks for into one thing it can act out:
 * the most urgent session wins, finishes and failures play a short reaction.
 */
export class Agents {
  private sessions = new Map<string, Session>();
  private openAsks = 0;
  /** Sessions already announced as needing you: repeated events say nothing new. */
  private announced = new Set<string>();
  /** Latest finish or failure per project, for briefings. */
  readonly outcomes = new Map<string, Outcome>();
  /** Told about every event after it is applied, so the crew can bring the pet out. */
  onEvent: (event: AgentEvent) => void = () => {};
  /** Each session's first prompt line, for "Log it" when it finishes (docs/V1.md V1-L7). */
  private readonly firstPrompt = new Map<string, string>();
  /** A session's first request, to tell sessions apart ("add rate limiting"). */
  firstLine(key: string): string {
    return this.firstPrompt.get(key) ?? "";
  }

  /** A finished session's card; null keeps the plain line. Given the session's first prompt line. */
  onDone: ((event: AgentEvent, firstPrompt: string) => void) | null = null;

  constructor(
    private readonly mind: Mind,
    private readonly bubble: Bubble,
    private readonly hud: HTMLElement,
  ) {}

  get list(): Session[] {
    return [...this.sessions.values()].sort((a, b) => RANK[b.state] - RANK[a.state] || b.at - a.at);
  }

  /** A session is waiting on the user or a question is open. */
  get needsYou() {
    return this.openAsks > 0 || this.list.some((s) => s.state === "waiting");
  }

  handle(event: AgentEvent) {
    const key = `${event.source}:${event.session}`;
    const name = AGENT_NAMES[event.source];
    const where = inProject(event.project || event.cwd);
    if (event.kind !== "waiting") this.announced.delete(key);
    if (event.kind === "prompt" && event.detail && !this.firstPrompt.has(key)) this.firstPrompt.set(key, event.detail.split("\n")[0].trim());
    switch (event.kind) {
      case "start":
        this.bubble.say(`${name} started${where}.`, 3);
        this.mind.react("wave", 1.4);
        break;
      case "prompt":
      case "think":
      case "read":
      case "edit":
      case "run":
      case "tool":
      case "waiting":
        this.sessions.set(key, {
          key,
          id: event.session,
          cwd: event.cwd,
          source: event.source,
          project: event.project,
          state: event.kind === "prompt" ? "think" : event.kind,
          detail: event.kind === "prompt" ? "" : event.detail,
          at: Date.now(),
        });
        if (event.kind === "waiting" && !this.announced.has(key)) {
          this.announced.add(key);
          if (!this.bubble.busy) this.bubble.say(event.detail || `${name} needs your answer${where}.`, 12);
        }
        break;
      case "message":
        if (event.detail) this.bubble.say(event.detail, 7);
        break;
      case "done":
      case "failed":
        this.sessions.delete(key);
        this.outcomes.set(event.project, {
          kind: event.kind,
          source: event.source,
          project: event.project,
          detail: event.detail,
          at: Date.now(),
          session: event.session,
          cwd: event.cwd,
        });
        // One short celebration (under 1.2 s); a failure says what and where to look.
        if (event.kind === "done") {
          this.mind.react("celebrate", 1.1);
          if (this.onDone) this.onDone(event, this.firstPrompt.get(key) ?? "");
          else this.bubble.say(`${name} finished${where}.${event.detail ? ` ${event.detail}` : ""}`, 9, "done");
        } else {
          this.mind.react("sad", 1.6);
          this.bubble.say(agentProblem(name, event.detail ?? "", event.project.split("/").pop() ?? ""), 12, "fail");
        }
        break;
      case "idle":
      case "end":
        this.sessions.delete(key);
        this.firstPrompt.delete(key);
        break;
    }
    this.refresh();
    this.onEvent(event);
  }

  /** Hands over sessions to a pet that was just created for them. */
  extract(which: (session: Session) => boolean): Session[] {
    const moved = this.list.filter(which);
    for (const s of moved) this.sessions.delete(s.key);
    if (moved.length) this.refresh();
    return moved;
  }

  adopt(sessions: Session[]) {
    for (const s of sessions) this.sessions.set(s.key, s);
    if (sessions.length) this.refresh();
  }

  /** Questions open on this pet; keep it at the cursor while any is open. */
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
    const top = this.list[0];
    if (this.openAsks > 0) this.mind.directive = { clip: "alert" };
    else this.mind.directive = top ? { clip: CLIP[top.state] } : null;

    // While a question is open the bubble says it all.
    if (!top || this.openAsks > 0) {
      this.hud.hidden = true;
      return;
    }
    this.hud.hidden = false;
    const others = this.sessions.size - 1;
    const what = `${AGENT_NAMES[top.source]}${top.detail && top.state !== "waiting" ? ` · ${VERB[top.state]} ${top.detail}` : ""}`;
    const next = badge(stateOf(top.state), [what, others > 0 ? `+${others}` : ""].filter(Boolean).join(" ") || undefined);
    next.classList.add("hud");
    this.hud.className = next.className;
    this.hud.dataset.state = next.dataset.state;
    this.hud.replaceChildren(...next.childNodes);
  }
}
