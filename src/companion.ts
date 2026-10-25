import { problem } from "./voice";
import { AGENT_NAMES, VERB, folder, sessionLabel, type AgentEvent } from "./agents";
import type { Card, Choice, Fact } from "./bubble";
import { explain, HELP, parse } from "./commands";
import { Familiar, type Look } from "./familiar";

/** Mirrors `Ask` in src-tauri/src/requests.rs: a permission request, shown exactly as it would run. */
export type Ask = {
  id: string;
  source: "claude" | "codex";
  session: string;
  cwd: string;
  project: string;
  tool: string;
  /** command | file | web | tool */
  kind: string;
  title: string;
  /** The command byte for byte, the diff or the file's content, hidden characters made visible. */
  text: string;
  /** The file an edit or write touches. */
  path: string | null;
  /** Everything the agent will do is in `text`; when false there's no Allow outside the terminal. */
  complete: boolean;
  canDefer: boolean;
  /** Unix ms when the agent stops waiting. */
  expires: number;
};

/** What fits on a card whole; anything longer is reviewed in the window before it can be allowed. */
const CARD_CHARS = 600;
const CARD_LINES = 12;
export const fitsCard = (text: string) => text.length <= CARD_CHARS && text.split("\n").length <= CARD_LINES;

/** A session the companion can open: live where it runs, or resumed in a terminal. */
export type SessionRef = { source: string; session: string; cwd: string };

/** Side effects the companion needs from the desktop app (or the browser preview). */
export type Host = {
  saveName(name: string): Promise<void>;
  /** Sends the user's answer; resolves to why it wasn't taken, or null. */
  resolvePermission(id: string, decision: string): Promise<string | null>;
  typing(typing: boolean): void;
  /** Reminder commands, handled by reminders.ts. */
  command?(text: string, kind: "remind" | "reminders" | "new-reminder"): Promise<string | void>;
  /** Hides the companion (the summon shortcut brings it back). */
  hide?(): void;
  /** Opens the Sidefolk window on a section ("home", "review:<id>", "reminders"). */
  openTab?(tab: string): void;
  /** Brings an agent session forward, or continues it in a terminal. Resolves to what happened. */
  openSession?(ref: SessionRef): Promise<string>;
  /** The folder a command would run in ("api" → ~/git/api); throws when there's none. */
  resolveFolder?(folder: string | null): Promise<{ path: string; label: string }>;
  /** Runs a confirmed command in the user's terminal. Resolves to what happened. */
  runCommand?(command: string, cwd: string): Promise<string>;
  /** Starts a new agent session in a folder, in the user's terminal. Resolves to what happened. */
  startSession?(agent: "claude" | "codex", cwd: string, fullAccess: boolean): Promise<string>;
  /** Opens a folder in an app, a web address or an app; resolves to what opened. */
  open?(target: string, app: string | null): Promise<string>;
  /** Settings → Labs (docs/V1.md F-10, F-17): `$` commands and starting sessions, off by default. */
  labs?(): { commands: boolean; sessions: boolean };
  /** Note commands, handled by notes.ts. */
  note?(command: { kind: "note"; notebook: string | null; text: string } | { kind: "notebook"; name: string }): Promise<string | void>;
};

const ACTION: Record<string, [string, string]> = {
  command: ["run this command", "Command"],
  file: ["change this file", "File"],
  web: ["open this page", "Page"],
  tool: ["use this tool", "Input"],
};

/**
 * Pip, the one companion on the desktop: it acts out the agent sessions, brings you their
 * requests and your reminders, and understands Quick add locally. It never answers a request on
 * its own (docs/V1.md V1-D10). Every request it shows is also kept here, so closing a card never
 * loses it: it stays answerable in the Sidefolk window.
 */
export class Companion {
  /** Open requests (permissions, agent questions, due reminders), oldest first. */
  private readonly requests = new Map<string, Card>();
  /** Due reminders whose card is on screen: Pip holds the note while any is. */
  private readonly notes = new Set<string>();
  /** Called after anything the window shows changed (sessions, requests, the name). */
  onChange: () => void = () => {};

  private constructor(
    readonly pet: Familiar,
    private readonly host: Host,
  ) {
    pet.bubble.onTyping = (typing) => {
      host.typing(typing);
      this.pose();
    };
  }

  /** Listening while you type beats holding a reminder's note, which beats everything else. */
  private pose() {
    this.pet.mind.pose = this.pet.bubble.typing ? "listen" : this.notes.size ? "note" : null;
    this.pet.heldNotes = [...this.notes].reduce((n, id) => n + Math.max(1, Number(this.requests.get(id)?.meta?.count) || 1), 0);
  }

  static async start(name: string, host: Host, zoom = 1, look: Look = {}): Promise<Companion> {
    return new Companion(await Familiar.create(name, zoom, look), host);
  }

  get name() {
    return this.pet.name;
  }

  /** Every companion on the desktop (Pip alone in v1). */
  get familiars(): Familiar[] {
    return [this.pet];
  }

  get typing() {
    return this.pet.bubble.typing;
  }

  /** Remembers recent outcomes from the journal, so "open session" works after a restart. */
  seedOutcomes(entries: { at: number; source: string; session?: string; project: string; kind: string; detail: string }[]) {
    for (const e of entries) {
      if ((e.kind !== "done" && e.kind !== "failed") || (e.source !== "claude" && e.source !== "codex")) continue;
      this.pet.agents.outcomes.set(e.project, { kind: e.kind, source: e.source, project: e.project, detail: e.detail, at: e.at, session: e.session, cwd: e.project });
    }
  }

  handleEvent(event: AgentEvent) {
    this.pet.agents.handle(event);
    this.onChange();
  }

  handleAsk(ask: Ask) {
    this.request(this.askCard(ask));
  }

  /**
   * A permission card: companion · project, tool · work session, the plain question, the exact
   * operation and explicit choices, none preselected. Allow is offered only when the whole
   * operation is on the card; a longer one is reviewed in the window first (docs/V1.md V1-D7).
   */
  private askCard(ask: Ask): Card {
    const agent = AGENT_NAMES[ask.source];
    const project = folder(ask.project || ask.cwd);
    const [action, label] = ACTION[ask.kind] ?? ACTION.tool;
    const whole = ask.complete && fitsCard(ask.text) && (ask.path ?? "").length <= 200;
    const shown = whole ? ask.text : `${ask.text.split("\n").slice(0, 8).join("\n").slice(0, CARD_CHARS)}\n…`;
    const facts: Fact[] = [
      ...(ask.path ? [{ label: "File", value: ask.path }] : []),
      ...(ask.text ? [{ label: ask.kind === "file" ? "Change" : label, value: shown }] : []),
      ...(ask.cwd ? [{ label: "Folder", value: ask.cwd }] : []),
    ];
    const go: Choice[] = whole ? [{ label: "Allow once", value: "allow", primary: true }] : ask.complete ? [{ label: "Review all of it", value: "review", primary: true }] : [];
    const choices: Choice[] = [{ label: "Decline", value: "deny" }, ...go, ...(ask.canDefer ? [{ label: `Answer in ${agent}'s window`, value: "defer", quiet: true }] : [])];
    return {
      id: ask.id,
      who: `${this.name} · ${project}`,
      context: `${agent} · ${sessionLabel(ask.session)}`,
      title: ask.title,
      lines: [`${agent} is asking to ${action} in ${project}.`],
      facts,
      wholeFacts: whole,
      // How long the agent waits, said once (docs/V1.md V1-D5).
      note: `${whole ? "Review it before allowing." : ask.complete ? "It's longer than this card. Review all of it in Sidefolk before allowing." : `It's too long to show here. Answer it in ${agent}'s window.`} ${agent} waits about a minute, then asks in its own window.`,
      choices,
      urgent: true,
      meta: {
        kind: "permission",
        action: ask.kind,
        title: ask.title,
        command: ask.text,
        path: ask.path ?? "",
        complete: String(ask.complete),
        tool: ask.tool,
        source: ask.source,
        session: ask.session,
        project: ask.project,
        cwd: ask.cwd,
        expires: String(ask.expires),
        canDefer: String(ask.canDefer),
      },
      onChoose: (value) => {
        if (value === "review") return this.host.openTab?.(`review:${ask.id}`);
        void this.host.resolvePermission(ask.id, value).then((refused) => refused && this.pet.bubble.say(refused, 6, "fail"));
        // Answering in the agent's own window: take the user there.
        if (value === "defer") void this.openSession({ source: ask.source, session: ask.session, cwd: ask.cwd });
      },
    };
  }

  /**
   * Shows something that waits for an answer. Closing the card only hides it from the desktop;
   * the request stays here (and in the window) until it's answered or expires.
   */
  request(card: Card) {
    const by = this.pet;
    const tracked: Card = {
      ...card,
      onChoose: (value) => {
        // Opening a reminder's details or reviewing a long request keeps it waiting.
        if ((card.meta?.kind === "reminder" && value === "open") || (card.meta?.kind === "permission" && value === "review")) {
          this.pet.bubble.close(card.id);
          tracked.onClose?.();
        } else this.closeRequest(card.id);
        card.onChoose(value);
      },
      // Closed with ×: the request still waits (window, menu bar), but Pip stops insisting.
      onClose: () => {
        const f = this.pet;
        this.notes.delete(card.id);
        f.asks.delete(card.id);
        f.agents.asking(f.asks.size);
        this.pose();
        card.onClose?.();
        this.onChange();
      },
    };
    this.requests.set(card.id, tracked);
    if (card.meta?.kind === "reminder") {
      this.notes.add(card.id);
      // A reminder folds without invoking Close: the note/count and answer remain available.
      setTimeout(() => { if (this.requests.get(card.id) === tracked && by.bubble.has(card.id)) {
        by.bubble.close(card.id); this.pose(); this.onChange();
      } }, 120_000);
    }
    this.pose();
    by.asks.add(card.id);
    by.bubble.show(tracked);
    by.agents.asking(by.asks.size);
    this.onChange();
  }

  /** The user went to the session, so its own prompt asks now. */
  released(id: string) {
    if (!this.requests.has(id)) return;
    this.closeRequest(id);
    this.pet.bubble.say("Moved to your terminal.", 4);
  }

  /** The request ended elsewhere (answered in the terminal, expired, the agent went away). */
  closeRequest(id: string) {
    if (!this.requests.delete(id)) return;
    this.notes.delete(id);
    this.pose();
    const f = this.pet;
    f.asks.delete(id);
    f.bubble.close(id);
    f.agents.asking(f.asks.size);
    this.onChange();
  }

  /** The session "open session" goes to: the most urgent live one (in a project, if named), else the last that ended. */
  sessionOf(project: string | null = null): (SessionRef & { live: boolean }) | null {
    const want = project?.toLowerCase();
    const matches = (p: string) => !want || folder(p).toLowerCase() === want;
    const live = this.familiars.flatMap((f) => f.agents.list).find((s) => s.id && matches(s.project));
    if (live) return { source: live.source, session: live.id, cwd: live.cwd || live.project, live: true };
    const last = this.familiars.flatMap((f) => [...f.agents.outcomes.values()]).filter((o) => o.session && matches(o.project)).sort((a, b) => b.at - a.at)[0];
    return last ? { source: last.source, session: last.session!, cwd: last.cwd || last.project, live: false } : null;
  }

  async openSession(ref?: SessionRef | null) {
    const bubble = this.pet.bubble;
    const target = ref ?? this.sessionOf();
    if (!target) return bubble.say("There's no work session to open yet.", 4);
    if (!this.host.openSession) return bubble.say("Opening sessions needs the desktop app.", 4, "fail");
    try {
      bubble.say(await this.host.openSession(target), 3);
    } catch (error) {
      bubble.say(problem(error), 8, "fail");
    }
  }

  /** Clicking the companion: one field, with what Enter will do shown before anything happens,
   * and the work sessions above it, most urgent first (docs/V1.md V1-D11). */
  openPrompt() {
    if (this.pet.bubble.focusPrompt()) return;
    const session = this.sessionOf();
    const live = this.pet.agents.list.filter((s) => s.id).slice(0, 4);
    this.pet.bubble.prompt({
      sessions: live.map((s) => {
        const first = this.pet.agents.firstLine(s.key);
        return {
          label: `${folder(s.project || s.cwd)}${first ? ` · ${first.length > 28 ? `${first.slice(0, 27)}…` : first}` : ""}`,
          state: VERB[s.state],
          open: () => void this.openSession({ source: s.source, session: s.id, cwd: s.cwd || s.project }),
        };
      }),
      who: `Talk to ${this.name}`,
      placeholder: "Remind me tomorrow at 9 to…",
      suggestions: ["Remind me in 10 minutes to …", "Reminders", ...(session ? ["Open session"] : []), "Open Sidefolk"],
      preview: (text) => this.explain(text),
      submit: (text) => this.run(text),
    });
  }

  /** What Enter would do with this text. */
  explain(text: string): string {
    return explain(text, {
      name: this.name,
      sessionFor: (project) => {
        const s = this.sessionOf(project);
        return s ? { agent: AGENT_NAMES[s.source as keyof typeof AGENT_NAMES], live: s.live } : null;
      },
    });
  }

  /** Runs what was typed. Returns what the companion says. */
  async run(text: string): Promise<string | void> {
    const command = parse(text);
    switch (command.kind) {
      case "help":
        this.pet.bubble.show({ id: "help", who: this.name, title: "Things I understand", lines: HELP, choices: [{ label: "OK", value: "ok", primary: true }], onChoose: () => {} });
        return;
      case "remind":
      case "reminders":
        return this.host.command?.(command.kind === "remind" ? command.text : "", command.kind);
      case "open": {
        const session = this.sessionOf(command.project);
        if (!session && command.project) return `There's no work session in ${command.project} yet.`;
        return this.openSession(session);
      }
      case "sidefolk":
        return this.host.openTab?.("home");
      case "rename":
        return this.rename(command.name);
      case "hide":
        return this.host.hide?.();
      case "note":
      case "notebook":
        return this.host.note ? this.host.note(command) : "Notes need the desktop app.";
      case "notes":
        return this.host.openTab?.("notes");
      case "run":
        if (!this.host.labs?.().commands) return "Commands are off. Turn them on in Settings → Labs.";
        return this.confirmRun(command.command, command.folder);
      case "open-thing":
        if (!this.host.open) return "Opening things needs the desktop app.";
        return this.host.open(command.target, command.app).catch((e) => problem(e));
      case "start":
        if (!this.host.labs?.().sessions) return "Starting sessions is off. Turn it on in Settings → Labs.";
        return this.confirmStart(command.agent, command.folder, command.full);
      case "chat":
        // Small talk: one line in Pip's voice, with a pose (creative-design/PIP.md).
        this.pet.mind.react(command.pose === "note" ? "write" : command.pose, 1.4);
        return command.reply;
      case "unknown":
        return this.offerNote(command.text);
    }
  }

  /** Text Pip has no rule for is never a dead end: it can become a note (docs/V1.md V1-Q2). */
  private offerNote(text: string): string | void {
    this.pet.mind.react("puzzled", 2.5);
    if (!this.host.note) return "I can hold reminders and notes, and open your work sessions. Type “help” to see how.";
    const bubble = this.pet.bubble;
    bubble.show({
      id: "offer-note",
      who: this.name,
      title: "Save this as a note?",
      lines: [text],
      choices: [
        { label: "Not now", value: "no" },
        { label: "Save as a note", value: "note", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close("offer-note");
        if (value !== "note") return;
        const reply = await this.host.note?.({ kind: "note", notebook: null, text });
        if (reply) bubble.say(reply, 4);
      },
    });
  }

  /** A new session: which tool, which folder, and whether it asks first; you choose before it starts. */
  private async confirmStart(agent: "claude" | "codex", wanted: string | null, full: boolean): Promise<string | void> {
    if (agent !== "claude") return "Starting Codex sessions is not available yet.";
    const { resolveFolder, startSession } = this.host;
    if (!resolveFolder || !startSession) return "Starting sessions needs the desktop app.";
    let folder: { path: string; label: string };
    try {
      folder = await resolveFolder(wanted);
    } catch (error) {
      return problem(error);
    }
    const name = "Claude Code";
    // The tool's own unattended mode, named in its own terms (docs/V1.md V1-D10); Sidefolk
    // itself never answers for a session.
    const own = "Claude Code’s auto mode (Claude decides what to ask)";
    const bubble = this.pet.bubble;
    bubble.show({
      id: "start-session",
      who: `${this.name} · new session`,
      title: `Start ${name} here?`,
      facts: [
        { label: "Folder", value: folder.label },
        { label: "Permissions", value: full ? own : "Asks you first (default)" },
      ],
      choices: [
        { label: "Cancel", value: "cancel" },
        ...(full ? [{ label: "Start, but ask first", value: "ask" }] : [{ label: "Start in auto mode", value: "full" }]),
        { label: `Start ${name}`, value: full ? "full" : "ask", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close("start-session");
        if (value === "cancel") return;
        try {
          bubble.say(await startSession(agent, folder.path, value === "full"), 4);
        } catch (error) {
          bubble.say(problem(error), 8, "fail");
        }
      },
    });
  }

  /** A command runs only after you've seen it and its folder, and always where you can watch. */
  private async confirmRun(text: string, wanted: string | null): Promise<string | void> {
    const { resolveFolder, runCommand } = this.host;
    if (!resolveFolder || !runCommand) return "Running commands needs the desktop app.";
    // A project named in "run … in api" is the folder of its work session when there is one.
    const session = wanted ? this.sessionOf(wanted) : null;
    let folder: { path: string; label: string };
    try {
      folder = await resolveFolder(session?.cwd ?? wanted);
    } catch (error) {
      return problem(error);
    }
    const bubble = this.pet.bubble;
    bubble.show({
      id: "run-command",
      who: `${this.name} · command`,
      title: "Run this in your terminal?",
      facts: [
        { label: "Command", value: text },
        { label: "Folder", value: folder.label },
      ],
      note: "It opens in a new terminal window, so you see everything it does.",
      choices: [
        { label: "Cancel", value: "cancel" },
        { label: "Run in terminal", value: "run", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close("run-command");
        if (value !== "run") return;
        try {
          bubble.say(await runCommand(text, folder.path), 4);
        } catch (error) {
          bubble.say(problem(error), 8, "fail");
        }
      },
    });
  }

  async rename(name: string): Promise<string> {
    name = name.replace(/\s+/g, " ").trim().slice(0, 24);
    if (!name) return "A name needs at least one letter.";
    this.pet.name = name;
    await this.host.saveName(name);
    this.onChange();
    return `I'm ${name} now.`;
  }

  /** What the Sidefolk window shows: the companion, its sessions, and what waits on you. */
  status() {
    const f = this.pet;
    return {
      pets: [
        {
          id: "main",
          name: f.name,
          label: f.name,
          main: true,
          project: null,
          out: true,
          clip: f.view.clip,
          sessions: f.agents.list.map((s) => ({ source: s.source, id: s.id, cwd: s.cwd, state: s.state, verb: VERB[s.state], detail: s.detail, firstPrompt: f.agents.firstLine(s.key), project: s.project, at: s.at })),
          outcomes: [...f.agents.outcomes.values()].sort((a, b) => b.at - a.at).slice(0, 5),
        },
      ],
      waiting: [...this.requests.values()].map((c) => ({
        id: c.id,
        pet: "main",
        petName: f.name,
        who: c.who,
        title: c.title,
        lines: c.lines ?? [],
        meta: c.meta ?? {},
        choices: c.choices.map(({ label, value, primary, quiet }) => ({ label, value, primary: !!primary, quiet: !!quiet })),
      })),
    };
  }

  /** An answer sent from the Sidefolk window. Permission requests take any of their real choices. */
  answer(id: string, value: string): boolean {
    const card = this.requests.get(id);
    if (!card) return false;
    const allowed = card.meta?.kind === "permission" ? ["allow", "deny", ...(card.meta.canDefer === "true" ? ["defer"] : [])] : card.choices.map((c) => c.value);
    const written = card.meta?.free === "true" && value.trim() !== "" && !value.startsWith("\u0000");
    if (!allowed.includes(value) && !written) return false;
    card.onChoose(value);
    return true;
  }
}
