import { FullAccess, sessionKey, stillAsk } from "./access";
import { AGENT_NAMES, VERB, folder, sessionLabel, type AgentEvent } from "./agents";
import type { Card, Choice, Fact } from "./bubble";
import { explain, HELP, parse } from "./commands";
import { Familiar, type Look } from "./familiar";

/** Mirrors `PermissionAsk` in src-tauri/src/bus.rs. */
export type Ask = {
  id: string;
  source: "claude" | "codex";
  session: string;
  title: string;
  detail: string;
  cwd: string;
  project: string;
  canDefer: boolean;
  /** command | file | web | tool */
  kind: string;
  /** Unix ms when the agent stops waiting. */
  expires: number;
};

/** A session the companion can open: live where it runs, or resumed in a terminal. */
export type SessionRef = { source: string; session: string; cwd: string };

/** Side effects the companion needs from the desktop app (or the browser preview). */
export type Host = {
  saveName(name: string): Promise<void>;
  resolvePermission(id: string, decision: string): void;
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
  /** Saved actions (actions.rs): save one, find one by name, run it. */
  actions?: {
    save(name: string, kind: "command" | "link", value: string, folder: string | null): Promise<string>;
    find(name: string): Promise<{ name: string; kind: string; value: string; folder: string } | null>;
    run(name: string, background: boolean): Promise<{ ok: boolean; message: string; log: string | null }>;
    showOutput(log: string): void;
  };
  /** "next meeting": the next calendar event, in a sentence (calendar.ts). */
  nextMeeting?(): Promise<string>;
  /** Gives a project its Spark worker, renames or recolors it, or sends it home (workers.ts). */
  spark?(project: string, change: { name?: string; hue?: number; remove?: boolean }): Promise<string>;
  /** Note commands, handled by notes.ts. */
  note?(command: { kind: "note"; notebook: string | null; text: string } | { kind: "notebook"; name: string }): Promise<string | void>;
  /** Tells the app which sessions have full access, so their requests always come here. */
  syncFullAccess?(keys: string[]): void;
};

const ACTION: Record<string, [string, string]> = {
  command: ["run this command", "Command"],
  file: ["change this file", "File"],
  web: ["open this page", "Page"],
  tool: ["use this tool", "Input"],
};

/**
 * The one companion on the desktop: it acts out the agent sessions, brings you their requests
 * and your reminders, and understands a few local commands. Every request it shows is also
 * kept here, so closing a card never loses it: it stays answerable in the Sidefolk window.
 */
export class Companion {
  /** Open requests (permissions, agent questions, due reminders), oldest first. */
  private readonly requests = new Map<string, Card>();
  /** Due reminders whose card is on screen: Pip holds the note while any is. */
  private readonly notes = new Set<string>();
  /** Spark workers by project folder; a project without one is Pip's. */
  readonly workers = new Map<string, Familiar>();
  /** Which companion shows each open request. */
  private readonly shownBy = new Map<string, Familiar>();

  private constructor(
    readonly pet: Familiar,
    private readonly host: Host,
  ) {
    host.syncFullAccess?.(this.access.list());
    pet.bubble.onTyping = (typing) => {
      host.typing(typing);
      this.pose();
    };
  }

  /** Listening while you type beats holding a reminder's note, which beats everything else. */
  private pose() {
    this.pet.mind.pose = this.pet.bubble.typing ? "listen" : this.notes.size ? "note" : null;
  }

  static async start(name: string, host: Host, zoom = 1, look: Look = {}): Promise<Companion> {
    return new Companion(await Familiar.create(name, zoom, look), host);
  }

  get name() {
    return this.pet.name;
  }

  /** Every companion on the desktop, Pip first. */
  get familiars(): Familiar[] {
    return [this.pet, ...this.workers.values()];
  }

  /** The worker for a project (by folder path or name), else Pip. */
  familiarFor(project: string | null | undefined): Familiar {
    if (!project) return this.pet;
    const exact = this.workers.get(project);
    if (exact) return exact;
    const name = folder(project).toLowerCase();
    for (const [path, worker] of this.workers) if (folder(path).toLowerCase() === name || project.startsWith(`${path}/`)) return worker;
    return this.pet;
  }

  addWorker(project: string, worker: Familiar) {
    this.workers.get(project)?.remove();
    this.workers.set(project, worker);
    // It takes over its project's sessions from Pip, so the right companion acts them out.
    worker.agents.adopt(this.pet.agents.extract((s) => this.familiarFor(s.project) === worker));
    for (const [key, o] of this.pet.agents.outcomes) if (this.familiarFor(o.project) === worker) worker.agents.outcomes.set(key, o);
  }

  removeWorker(project: string) {
    const worker = this.workers.get(project);
    if (!worker) return;
    this.workers.delete(project);
    this.pet.agents.adopt(worker.agents.extract(() => true));
    for (const [key, o] of worker.agents.outcomes) this.pet.agents.outcomes.set(key, o);
    for (const [id, f] of this.shownBy) if (f === worker) this.reshow(id);
    worker.remove();
  }

  /** A request whose companion left: Pip shows it instead. */
  private reshow(id: string) {
    const card = this.requests.get(id);
    if (!card) return;
    this.shownBy.set(id, this.pet);
    this.pet.asks.add(id);
    this.pet.bubble.show(card);
    this.pet.agents.asking(this.pet.asks.size);
  }

  get typing() {
    return this.pet.bubble.typing;
  }

  /** Remembers recent outcomes from the journal, so "open session" works after a restart. */
  seedOutcomes(entries: { at: number; source: string; session?: string; project: string; kind: string; detail: string }[]) {
    for (const e of entries) {
      if ((e.kind !== "done" && e.kind !== "failed") || (e.source !== "claude" && e.source !== "codex")) continue;
      this.familiarFor(e.project).agents.outcomes.set(e.project, { kind: e.kind, source: e.source, project: e.project, detail: e.detail, at: e.at, session: e.session, cwd: e.project });
    }
  }

  handleEvent(event: AgentEvent) {
    this.familiarFor(event.project || event.cwd).agents.handle(event);
  }

  /** Sessions the user gave full access ("do it and come back when you're done"). */
  readonly access = new FullAccess();

  handleAsk(ask: Ask) {
    const key = sessionKey(ask.source, ask.session);
    const why = stillAsk(ask.kind, ask.detail);
    if (this.access.has(key) && !why) {
      this.host.resolvePermission(ask.id, "allow");
      this.familiarFor(ask.project).bubble.say(`Allowed (full access): ${ask.detail.length > 60 ? `${ask.detail.slice(0, 57)}…` : ask.detail}`, 3);
      return;
    }
    this.request(this.askCard(ask, this.access.has(key) ? why : null));
  }

  setFullAccess(source: string, session: string, on: boolean) {
    this.access.set(sessionKey(source, session), on);
    this.host.syncFullAccess?.(this.access.list());
    this.pet.bubble.say(on ? `Full access on for this ${AGENT_NAMES[source as keyof typeof AGENT_NAMES] ?? "work"} session. Risky commands still ask.` : "Full access off. I'll ask again.", 4);
  }

  /**
   * A permission card: companion · project, tool · work session, the plain question, the exact
   * action and explicit choices, none preselected.
   */
  private askCard(ask: Ask, why: string | null = null): Card {
    const agent = AGENT_NAMES[ask.source];
    const project = folder(ask.project || ask.cwd);
    const [action, label] = ACTION[ask.kind] ?? ACTION.tool;
    const facts: Fact[] = [{ label, value: ask.detail }, ...(ask.cwd ? [{ label: "Folder", value: ask.cwd }] : [])];
    const choices: Choice[] = [
      { label: "Decline", value: "deny" },
      { label: "Allow once", value: "allow", primary: true },
      ...(why ? [] : [{ label: "Allow everything from this session", value: "always", quiet: true }]),
      ...(ask.canDefer ? [{ label: `Answer in ${agent}'s window`, value: "defer", quiet: true }] : []),
    ];
    return {
      id: ask.id,
      who: `${this.name} · ${project}`,
      context: `${agent} · ${sessionLabel(ask.session)}`,
      title: ask.title,
      lines: [`${agent} is asking to ${action} in ${project}.`],
      facts,
      note: why ?? "Review it before allowing.",
      choices,
      urgent: true,
      meta: {
        kind: "permission",
        action: ask.kind,
        title: ask.title,
        command: ask.detail,
        source: ask.source,
        session: ask.session,
        project: ask.project,
        cwd: ask.cwd,
        expires: String(ask.expires),
        canDefer: String(ask.canDefer),
      },
      onChoose: (value) => {
        if (value === "always") {
          this.setFullAccess(ask.source, ask.session, true);
          value = "allow";
        }
        this.host.resolvePermission(ask.id, value);
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
    const by = this.familiarFor(card.meta?.project);
    this.shownBy.set(card.id, by);
    const tracked: Card = {
      ...card,
      onChoose: (value) => {
        if (card.meta?.kind === "reminder" && value === "open") {
          this.shownBy.get(card.id)?.bubble.close(card.id);
          tracked.onClose?.();
        } else this.closeRequest(card.id);
        card.onChoose(value);
      },
      // Closed with ×: the request still waits (window, menu bar), but Pip stops insisting.
      onClose: () => {
        const f = this.shownBy.get(card.id) ?? this.pet;
        this.notes.delete(card.id);
        f.asks.delete(card.id);
        f.agents.asking(f.asks.size);
        this.pose();
        card.onClose?.();
      },
    };
    if (card.meta?.kind === "reminder") this.notes.add(card.id);
    this.pose();
    this.requests.set(card.id, tracked);
    by.asks.add(card.id);
    by.bubble.show(tracked);
    by.agents.asking(by.asks.size);
  }

  /** The request ended elsewhere (answered in the terminal, expired, the agent went away). */
  closeRequest(id: string) {
    if (!this.requests.delete(id)) return;
    this.notes.delete(id);
    this.pose();
    const f = this.shownBy.get(id) ?? this.pet;
    this.shownBy.delete(id);
    f.asks.delete(id);
    f.bubble.close(id);
    f.agents.asking(f.asks.size);
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
      bubble.say(error instanceof Error ? error.message : String(error), 8, "fail");
    }
  }

  /** Clicking the companion: one field, with what Enter will do shown before anything happens. */
  openPrompt() {
    const session = this.sessionOf();
    this.pet.bubble.prompt({
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
      case "calendar":
        return this.host.nextMeeting ? this.host.nextMeeting().catch((e) => String(e)) : "The calendar needs the desktop app.";
      case "run":
        return this.confirmRun(command.command, command.folder);
      case "open-thing": {
        // A saved link or action by that name comes first ("open jira").
        const saved = await this.host.actions?.find(command.target).catch(() => null);
        if (saved && !command.app) return this.runSaved(saved);
        if (!this.host.open) return "Opening things needs the desktop app.";
        return this.host.open(command.target, command.app).catch((e) => String(e));
      }
      case "save-action": {
        if (!this.host.actions) return "Saved actions need the desktop app.";
        return this.host.actions.save(command.name, command.link ? "link" : "command", command.value, command.folder).catch((e) => String(e));
      }
      case "spark":
        return this.host.spark ? this.host.spark(command.project, { name: command.name ?? undefined, remove: command.remove }).catch((e) => String(e)) : "Sparks need the desktop app.";
      case "start":
        return this.confirmStart(command.agent, command.folder, command.full);
      case "unknown": {
        // A saved action's name on its own runs it ("deploy staging").
        const saved = await this.host.actions?.find(command.text).catch(() => null);
        if (saved) return this.runSaved(saved);
        return "I can set reminders, run commands and open your work sessions. Type “help” to see how.";
      }
    }
  }

  /** A saved link opens at once; a saved command shows what it runs and where, then runs. */
  private async runSaved(saved: { name: string; kind: string; value: string; folder: string }): Promise<string | void> {
    const actions = this.host.actions!;
    if (saved.kind === "link") return (await actions.run(saved.name, false).catch((e) => ({ message: String(e) }))).message;
    const bubble = this.pet.bubble;
    bubble.show({
      id: "run-saved",
      who: `${this.name} · ${saved.name}`,
      title: `Run ${saved.name}?`,
      facts: [
        { label: "Command", value: saved.value },
        { label: "Folder", value: saved.folder.replace(/^\/Users\/[^/]+/, "~") },
      ],
      choices: [
        { label: "Cancel", value: "cancel" },
        { label: "Quietly, tell me when done", value: "quiet" },
        { label: "In terminal", value: "terminal", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close("run-saved");
        if (value === "cancel") return;
        if (value === "terminal") return bubble.say((await actions.run(saved.name, false).catch((e) => ({ message: String(e) }))).message, 4);
        bubble.say(`Running ${saved.name}…`, 3);
        this.pet.mind.react("think", 1.2);
        try {
          const result = await actions.run(saved.name, true);
          this.pet.mind.react(result.ok ? "celebrate" : "sad", 1.6);
          bubble.show({
            id: "run-saved-result",
            who: `${this.name} · ${saved.name}`,
            title: result.message,
            choices: [...(result.log ? [{ label: "Show output", value: "output" }] : []), { label: "OK", value: "ok", primary: true }],
            onChoose: (choice) => {
              bubble.close("run-saved-result");
              if (choice === "output" && result.log) actions.showOutput(result.log);
            },
          });
        } catch (error) {
          bubble.say(String(error), 8, "fail");
        }
      },
    });
  }

  /** A new session: which tool, which folder, and whether it asks first; you choose before it starts. */
  private async confirmStart(agent: "claude" | "codex", wanted: string | null, full: boolean): Promise<string | void> {
    const { resolveFolder, startSession } = this.host;
    if (!resolveFolder || !startSession) return "Starting sessions needs the desktop app.";
    let folder: { path: string; label: string };
    try {
      folder = await resolveFolder(wanted);
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }
    const name = agent === "codex" ? "Codex" : "Claude Code";
    const bubble = this.pet.bubble;
    bubble.show({
      id: "start-session",
      who: `${this.name} · new session`,
      title: `Start ${name} here?`,
      facts: [
        { label: "Folder", value: folder.label },
        { label: "Permissions", value: full ? "Full access: works without asking; risky actions still stop" : "Asks first (default)" },
      ],
      choices: [
        { label: "Cancel", value: "cancel" },
        ...(full ? [{ label: "Start, but ask first", value: "ask" }] : [{ label: "Start with full access", value: "full" }]),
        { label: `Start ${name}`, value: full ? "full" : "ask", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close("start-session");
        if (value === "cancel") return;
        try {
          bubble.say(await startSession(agent, folder.path, value === "full"), 4);
        } catch (error) {
          bubble.say(error instanceof Error ? error.message : String(error), 8, "fail");
        }
      },
    });
  }

  /** A command runs only after you've seen it and its folder, and always where you can watch. */
  private async confirmRun(text: string, wanted: string | null): Promise<string | void> {
    const saved = wanted ? null : await this.host.actions?.find(text).catch(() => null);
    if (saved) return this.runSaved(saved);
    const { resolveFolder, runCommand } = this.host;
    if (!resolveFolder || !runCommand) return "Running commands needs the desktop app.";
    // A project named in "run … in api" is the folder of its work session when there is one.
    const session = wanted ? this.sessionOf(wanted) : null;
    let folder: { path: string; label: string };
    try {
      folder = await resolveFolder(session?.cwd ?? wanted);
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
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
          bubble.say(error instanceof Error ? error.message : String(error), 8, "fail");
        }
      },
    });
  }

  async rename(name: string): Promise<string> {
    name = name.replace(/\s+/g, " ").trim().slice(0, 24);
    if (!name) return "A name needs at least one letter.";
    this.pet.name = name;
    await this.host.saveName(name);
    return `I'm ${name} now.`;
  }

  /** What the Sidefolk window shows: the companions, their sessions, and what waits on you. */
  status() {
    const describe = (f: Familiar, id: string, project: string | null) => ({
      id,
      name: f.name,
      label: f.name,
      main: f === this.pet,
      project,
      hue: f.look.hue ?? 0,
      out: true,
      clip: f.view.clip,
      sessions: f.agents.list.map((s) => ({ source: s.source, id: s.id, cwd: s.cwd, state: s.state, verb: VERB[s.state], detail: s.detail, project: s.project, at: s.at, fullAccess: this.access.has(sessionKey(s.source, s.id)) })),
      outcomes: [...f.agents.outcomes.values()].sort((a, b) => b.at - a.at).slice(0, 5),
    });
    const idOf = (f: Familiar) => (f === this.pet ? "main" : `worker:${[...this.workers].find(([, w]) => w === f)?.[0]}`);
    return {
      pets: [describe(this.pet, "main", null), ...[...this.workers].map(([project, w]) => describe(w, `worker:${project}`, project))],
      waiting: [...this.requests.values()].map((c) => {
        const f = this.shownBy.get(c.id) ?? this.pet;
        return {
          id: c.id,
          pet: idOf(f),
          petName: f.name,
          who: c.who,
          title: c.title,
          lines: c.lines ?? [],
          meta: c.meta ?? {},
          choices: c.choices.map(({ label, value, primary, quiet }) => ({ label, value, primary: !!primary, quiet: !!quiet })),
        };
      }),
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
