import { AGENT_NAMES, VERB, folder, sessionLabel, type AgentEvent } from "./agents";
import type { Card, Choice, Fact } from "./bubble";
import { HELP, parse } from "./commands";
import { Familiar, MAIN_ID, type Binding, type PetRecord } from "./familiar";
import { DEFAULT_LOOK, normalizeLook, type Look } from "./pet/look";
import { findPet, nextCompanion, resolve, type Origin } from "./routing";
import { privacy } from "./states";
import { describeDue, parseReminder } from "./when";

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

/** A session a pet can open: live where it runs, or resumed in a terminal. */
export type SessionRef = { source: string; session: string; cwd: string };

/** Stored as crew.json in the data directory. */
export type CrewFile = {
  main: { name: string; look: Look };
  pets: PetRecord[];
  /** Projects the user never wants a pet for. */
  ignored: string[];
};

/** Side effects the crew needs from the desktop app (or the browser preview). */
export type Host = {
  saveCrew(file: CrewFile): Promise<void>;
  dispatch(prompt: string, cwd: string | null): Promise<void>;
  resolvePermission(id: string, decision: string): void;
  typing(typing: boolean): void;
  /** Extra commands (reminders) handled outside the crew. */
  command?(text: string, kind: "remind" | "reminders" | "new-reminder", from: Familiar): Promise<string | void>;
  /** Tray actions the pet's menu offers (Sidefolk window, hide). */
  trayAction?(action: "settings" | "toggle"): void;
  /** Opens the Sidefolk window on a section ("crew:<id>", "review:<id>", …). */
  openTab?(tab: string): void;
  /** Brings an agent session forward, or continues it in a terminal. Resolves to what happened. */
  openSession?(ref: SessionRef): Promise<string>;
};

/** Crew pets on screen at once, besides the main pet. */
const CAP = 3;
const OUT_AFTER_DONE_MS = 8_000;
const OUT_AFTER_FAILED_MS = 25_000;
const OUT_WHEN_CALLED_MS = 45_000;

export function emptyCrew(): CrewFile {
  return { main: { name: "Pip", look: DEFAULT_LOOK }, pets: [], ignored: [] };
}

/** Accepts whatever was stored and returns a usable crew. */
export function normalizeCrew(value: unknown): CrewFile {
  const v = (value ?? {}) as Partial<CrewFile>;
  const kinds = ["session", "project", "agent"];
  const pets = (Array.isArray(v.pets) ? v.pets : [])
    .filter((p): p is PetRecord => !!p && typeof p.id === "string" && typeof p.name === "string" && p.id !== MAIN_ID)
    .map((p) => ({
      id: p.id,
      name: p.name.slice(0, 24),
      look: normalizeLook(p.look),
      bindings: (Array.isArray(p.bindings) ? p.bindings : []).filter(
        (b): b is Binding => !!b && kinds.includes(b.kind) && typeof b.key === "string" && !!b.key,
      ),
    }))
    // Session pets end with their session; one left over from a crash has nothing to do.
    .filter((p) => p.bindings.some((b) => b.kind !== "session"));
  return {
    main: { name: typeof v.main?.name === "string" && v.main.name ? v.main.name.slice(0, 24) : "Pip", look: normalizeLook(v.main?.look) },
    pets,
    ignored: Array.isArray(v.ignored) ? v.ignored.filter((p): p is string => typeof p === "string") : [],
  };
}

const mainRecord = (file: CrewFile): PetRecord => ({ id: MAIN_ID, name: file.main.name, look: file.main.look, bindings: [] });


const ACTION: Record<string, [string, string]> = {
  command: ["run this command", "Command"],
  file: ["change this file", "File"],
  web: ["open this page", "Page"],
  tool: ["use this tool", "Input"],
};

/**
 * The main pet and its crew: routes each agent event and question to the pet that speaks for
 * it, brings crew pets out when their project needs you and sends them home afterwards.
 */
export class Crew {
  private readonly pets = new Map<string, Familiar>();
  private readonly askOwner = new Map<string, Familiar>();
  /** Projects offered a pet during this run (answered "Not now" or still open). */
  private readonly offered = new Set<string>();
  /** Settings → Desktop presence. With "needed", the main pet rests in the den too. */
  presence: "always" | "needed" | "menubar" = "always";
  /** Settings → Comfort: whose crew new companions come from. */
  comfort = "friendly";

  private constructor(
    readonly main: Familiar,
    private file: CrewFile,
    private readonly host: Host,
    private readonly zoom: number,
  ) {
    this.wire(main);
  }

  static async start(stored: unknown, host: Host, zoom = 1): Promise<Crew> {
    const file = normalizeCrew(stored);
    const crew = new Crew(await Familiar.create(mainRecord(file), zoom), file, host, zoom);
    for (const record of file.pets) crew.add(await Familiar.create(record, zoom));
    return crew;
  }

  /** Main pet first. */
  get all(): Familiar[] {
    return [this.main, ...this.pets.values()];
  }

  get typing() {
    return this.all.some((f) => f.bubble.typing);
  }

  private get outCount() {
    return [...this.pets.values()].filter((f) => f.out).length;
  }

  private add(f: Familiar) {
    f.mind.away = true;
    this.pets.set(f.record.id, f);
    this.wire(f);
  }

  private wire(f: Familiar) {
    f.bubble.onTyping = (typing) => this.host.typing(typing);
    f.agents.onEvent = (event) => {
      if (event.kind === "done") f.holdUntil = Math.max(f.holdUntil, Date.now() + OUT_AFTER_DONE_MS);
      if (event.kind === "failed") f.holdUntil = Math.max(f.holdUntil, Date.now() + OUT_AFTER_FAILED_MS);
      if (f.isMain) return;
      const sessionPet = f.record.bindings.length > 0 && f.record.bindings.every((b) => b.kind === "session");
      if (event.kind === "end" && sessionPet) void this.retire(f, event);
    };
  }

  private familiarFor(origin: Origin): Familiar {
    const id = resolve([...this.pets.values()].map((f) => f.record), origin);
    return (id && this.pets.get(id)) || this.main;
  }

  /** The pet that looks after a project (the main pet if none does). */
  petFor(project: string): Familiar {
    return this.familiarFor({ source: "", session: "", project });
  }

  /** Remembers recent outcomes from the journal, so briefings survive a restart. */
  seedOutcomes(entries: { at: number; source: string; session?: string; project: string; kind: string; detail: string }[]) {
    for (const e of entries) {
      if ((e.kind !== "done" && e.kind !== "failed") || (e.source !== "claude" && e.source !== "codex")) continue;
      this.petFor(e.project).agents.outcomes.set(e.project, {
        kind: e.kind,
        source: e.source,
        project: e.project,
        detail: e.detail,
        at: e.at,
        session: e.session,
        cwd: e.project,
      });
    }
  }

  find(words: string): Familiar | undefined {
    const record = findPet(
      this.all.map((f) => f.record),
      words,
    );
    return record && (record.id === MAIN_ID ? this.main : this.pets.get(record.id));
  }

  byId(id: string): Familiar | undefined {
    return id === MAIN_ID ? this.main : this.pets.get(id);
  }

  handleEvent(event: AgentEvent) {
    const f = this.familiarFor(event);
    if (f.isMain && event.project && !["end", "idle"].includes(event.kind)) this.offer(event.project);
    f.agents.handle(event);
    // An open status card follows what the pet is doing.
    if (f.bubble.has(`status-${f.record.id}`)) this.statusCard(f, true);
  }

  handleAsk(ask: Ask) {
    const f = this.familiarFor(ask);
    // A crew pet that cannot come out (too many on screen) asks through the main pet.
    const target = !f.isMain && !f.out && this.outCount >= CAP ? this.main : f;
    this.question(target, this.askCard(f, target, ask));
  }

  /**
   * A permission card: pet · project, tool · work session, the plain question, the exact action
   * and explicit choices, none preselected. With less card detail (screens others can see) the
   * card names less and sends you to Sidefolk to review before allowing.
   */
  private askCard(f: Familiar, target: Familiar, ask: Ask): Card {
    const agent = AGENT_NAMES[ask.source];
    const project = folder(ask.project || ask.cwd);
    const [action, label] = ACTION[ask.kind] ?? ACTION.tool;
    const detail = privacy.detail;
    const ref: SessionRef = { source: ask.source, session: ask.session, cwd: ask.cwd };
    const facts: Fact[] = [{ label, value: ask.detail }, ...(ask.cwd ? [{ label: "Folder", value: ask.cwd }] : [])];
    const choices: Choice[] =
      detail === "full"
        ? [{ label: "Decline", value: "deny" }, { label: "Allow once", value: "allow", primary: true }]
        : [{ label: "Decline", value: "deny" }, { label: "Review…", value: "review", primary: true }];
    if (ask.canDefer) choices.push({ label: `Answer in ${agent}'s window`, value: "defer", quiet: true });
    const card: Card = {
      id: ask.id,
      who: detail === "status" ? f.name : `${f.name} · ${project}`,
      context: `${agent} · ${sessionLabel(ask.session)}`,
      title: detail === "status" ? "A request needs your answer." : ask.title,
      lines: detail === "status" ? [] : [`${agent} is asking to ${action} in ${project}.`],
      facts: detail === "full" ? facts : [],
      note: detail === "full" ? "Review it before allowing." : "Review it in Sidefolk before allowing.",
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
        // Reviewing is navigation, not an answer: the card stays until a real choice.
        if (value === "review") {
          this.host.openTab?.(`review:${ask.id}`);
          return this.question(target, card);
        }
        this.host.resolvePermission(ask.id, value);
        // Answering in the agent's own window: take the user there.
        if (value === "defer") void this.openSession(f, ref);
      },
    };
    return card;
  }

  /** Shows a question that keeps its pet out, at the cursor, until it is answered or closed. */
  question(target: Familiar, card: Card) {
    target.asks.add(card.id);
    this.askOwner.set(card.id, target);
    target.bubble.show({
      ...card,
      urgent: true,
      onChoose: (value) => {
        this.closeAsk(card.id);
        card.onChoose(value);
      },
    });
    target.agents.asking(target.asks.size);
    this.tick();
  }

  closeAsk(id: string) {
    const owner = this.askOwner.get(id);
    if (!owner) return;
    this.askOwner.delete(id);
    owner.asks.delete(id);
    owner.bubble.close(id);
    owner.agents.asking(owner.asks.size);
  }

  /** Brings pets out when needed and sends them home when they are done. */
  tick() {
    const now = Date.now();
    const needed = (f: Familiar) => f.agents.needsYou || f.asks.size > 0 || f.holdUntil > now || f.bubble.busy;
    for (const f of this.pets.values()) {
      const want = needed(f);
      if (want && !f.out) {
        if (this.outCount < CAP) f.mind.enter(this.spotFor(f));
      } else if (want && f.mind.isLeaving) {
        f.mind.enter(f.mind.x);
      } else if (!want && f.out && !f.mind.isLeaving) {
        f.mind.leave();
      }
    }
    // "Only when needed": the main pet rests too, and comes back where it last stood.
    const main = this.main;
    const mainWanted = this.presence !== "needed" || needed(main) || [...this.pets.values()].some((f) => f.out);
    if (mainWanted && (!main.out || main.mind.isLeaving)) main.mind.enter(main.mind.x);
    else if (!mainWanted && main.out && !main.mind.isLeaving) main.mind.leave();
  }

  /**
   * Where a crew pet stands when it comes out: near the cursor when it needs you, otherwise
   * beside the main pet on the side with room, never on top of another pet.
   */
  private spotFor(f: Familiar): number {
    const cursor = this.main.mind.target;
    const width = this.main.stage.width;
    const taken = this.all.filter((p) => p !== f && p.out).map((p) => p.mind.x);
    const free = (x: number) => x > 70 && x < width - 70 && taken.every((t) => Math.abs(t - x) > 140);
    const anchor = f.agents.needsYou && cursor ? cursor.x : this.main.mind.x;
    const side = anchor > width / 2 ? -1 : 1;
    for (let step = 1; step < 12; step++)
      for (const dir of [side, -side]) {
        const x = anchor + dir * step * 150;
        if (free(x)) return x;
      }
    return anchor;
  }

  /** Brings a pet out with its status card. */
  call(f: Familiar) {
    f.holdUntil = Date.now() + OUT_WHEN_CALLED_MS;
    this.tick();
    this.statusCard(f, true);
  }

  /** The session a pet would open: the most urgent live one, else the last one that ended. */
  sessionOf(f: Familiar): (SessionRef & { live: boolean }) | null {
    const live = f.agents.list.find((s) => s.id);
    if (live) return { source: live.source, session: live.id, cwd: live.cwd || live.project, live: true };
    const last = [...f.agents.outcomes.values()].filter((o) => o.session).sort((a, b) => b.at - a.at)[0];
    return last ? { source: last.source, session: last.session!, cwd: last.cwd || last.project, live: false } : null;
  }

  async openSession(f: Familiar, ref?: SessionRef | null) {
    const target = ref ?? this.sessionOf(f);
    if (!target) return f.bubble.say("There's no work session to open yet.", 4);
    if (!this.host.openSession) return f.bubble.say("Opening sessions needs the desktop app.", 4, "fail");
    try {
      f.bubble.say(await this.host.openSession(target), 3);
    } catch (error) {
      f.bubble.say(error instanceof Error ? error.message : String(error), 8, "fail");
    }
  }

  /**
   * Clicking a pet: what it is doing, factual and short, and the ways on from here: its work
   * session, the Sidefolk window, home. A second click closes it.
   */
  statusCard(f: Familiar, keep = false) {
    const id = `status-${f.record.id}`;
    if (f.bubble.has(id) && !keep) return f.bubble.close(id);
    const minutes = (at: number) => {
      const m = Math.round((Date.now() - at) / 60_000);
      return m < 1 ? "just now" : m === 1 ? "1 min ago" : m < 90 ? `${m} min ago` : `${Math.round(m / 60)} h ago`;
    };
    const full = privacy.detail === "full";
    const named = privacy.detail !== "status";
    const sessions = f.agents.list.map((s) => {
      const where = named && f.isMain && s.project ? ` in ${folder(s.project)}` : "";
      return `${AGENT_NAMES[s.source]} · ${VERB[s.state]}${full && s.detail && s.state !== "waiting" ? ` ${s.detail}` : ""}${where}`;
    });
    const outcomes = [...f.agents.outcomes.values()]
      .sort((a, b) => b.at - a.at)
      .slice(0, 2)
      .map((o) => `${AGENT_NAMES[o.source]} ${o.kind === "done" ? "finished" : "stopped with a problem"} ${minutes(o.at)}${full && o.detail ? `: ${o.detail}` : "."}`);
    const where = named && f.project ? folder(f.project) : "";
    const session = this.sessionOf(f);
    const agent = session ? (AGENT_NAMES[session.source as keyof typeof AGENT_NAMES] ?? "the") : "";
    f.bubble.show({
      id,
      who: f.shownLabel,
      title: sessions.length
        ? `${sessions.length === 1 ? "One work session" : `${sessions.length} work sessions`}${where ? ` in ${where}` : ""}.`
        : `All quiet${where ? ` in ${where}` : ""}.`,
      lines: [...sessions, ...outcomes].slice(0, 5),
      choices: [
        ...(session ? [{ label: session.live ? `Open ${agent} session` : `Continue in ${agent}`, value: "open", primary: true }] : []),
        { label: "Open Sidefolk", value: "sidefolk", primary: !session },
        ...(f.isMain ? [{ label: "Type a command…", value: "prompt" }] : [{ label: "Send home", value: "home" }]),
      ],
      onChoose: (value) => {
        if (value === "open") void this.openSession(f, session);
        else if (value === "sidefolk") this.host.openTab?.(f.isMain ? "home" : `crew:${f.record.id}`);
        else if (value === "prompt") this.openPrompt(f);
        else if (value === "home") this.sendHome(f);
        f.holdUntil = Math.max(f.holdUntil, Date.now() + 3_000);
      },
    });
  }

  private showCrew(on: Familiar) {
    const lines = [...this.pets.values()].map((f) => {
      const top = f.agents.list[0];
      const state = top ? `${AGENT_NAMES[top.source]} ${VERB[top.state]}` : f.out ? "out" : "resting";
      return `${privacy.detail === "status" ? f.name : f.label} — ${state}`;
    });
    on.bubble.show({
      id: "crew",
      who: this.main.name,
      title: lines.length ? "Your crew" : "No crew yet",
      lines: lines.length ? lines : ["When an AI tool works in a git project, I'll offer it a companion."],
      choices: [
        { label: "Open Crew", value: "crew", primary: true },
        { label: "OK", value: "ok" },
      ],
      onChoose: (value) => value === "crew" && this.host.openTab?.("crew"),
    });
  }

  sendHome(f: Familiar) {
    if (f.isMain) return;
    if (f.asks.size) return f.bubble.say("A request is still waiting for your answer.", 4);
    f.holdUntil = 0;
    f.bubble.close(`status-${f.record.id}`);
    this.tick();
  }

  openPrompt(f: Familiar) {
    const crew = [...this.pets.values()];
    f.bubble.prompt({
      who: f.isMain ? `Talk to ${f.name}` : `Talk to ${f.shownLabel}`,
      placeholder: f.isMain ? "Type a command or a task…" : `Tell ${f.name} what to do…`,
      // Short, concrete starters; most are understood here without any model.
      suggestions: f.isMain
        ? [crew[0] ? `Call ${crew[0].name}` : "Crew", "Remind me tomorrow at 3 to …", "Open session", "Help"]
        : ["Open session", "What's happening", `Send ${f.name} home`],
      preview: (text) => this.explain(text, f),
      submit: (text) => this.run(/^what'?s happening$/i.test(text) ? `call ${f.name}` : text, f),
    });
  }

  /** What Enter would do with this text, shown under the field before anything happens. */
  explain(text: string, from: Familiar): string {
    const command = parse(text);
    const name = (who: string | null) => (who ? this.find(who)?.name : from.name);
    const unknown = (who: string) => `I don't know "${who}" yet. Try "crew".`;
    const codex = (f: Familiar | undefined) =>
      `Codex works on this in ${f?.project ? folder(f.project) : "a scratch folder"} (uses your Codex quota)`;
    switch (command.kind) {
      case "help":
        return "Show what I understand";
      case "crew":
        return "Show your crew";
      case "customize":
        return name(command.who) ? `Open ${name(command.who)}'s appearance in Sidefolk` : unknown(command.who!);
      case "call":
        return name(command.who) ? `Bring ${name(command.who)} out` : unknown(command.who);
      case "home":
        return command.who && !/^(everyone|everybody|all|the crew)$/i.test(command.who) && !name(command.who)
          ? unknown(command.who)
          : `Send ${command.who ? name(command.who) ?? "everyone" : from.isMain ? "everyone" : from.name} home`;
      case "open": {
        const f = command.who ? this.find(command.who) : from;
        if (!f) return codex(from);
        const session = this.sessionOf(f);
        if (!session) return `${f.name} has no work session to open yet`;
        const agent = AGENT_NAMES[session.source as keyof typeof AGENT_NAMES];
        return session.live ? `Bring ${agent}'s session forward` : `Continue ${agent}'s last session in a terminal`;
      }
      case "sidefolk":
        return "Open the Sidefolk window";
      case "tell":
        return codex(command.who ? (this.find(command.who) ?? from) : from);
      case "codex":
        return codex(undefined);
      case "task":
        return codex(from);
      case "rename":
        return name(command.who) ? `Rename ${name(command.who)} to ${command.name}` : unknown(command.who!);
      case "look":
        return name(command.who) ? `Change how ${name(command.who)} looks` : unknown(command.who!);
      case "forget":
        return name(command.who) ? `Forget ${name(command.who)} (asks first)` : unknown(command.who);
      case "adopt":
        return "Give the latest work session its own companion";
      case "remind": {
        const parsed = parseReminder(command.text);
        return parsed ? `Remind you ${describeDue(parsed.due)}: ${parsed.what}` : "Set a reminder (then pick when)";
      }
      case "reminders":
        return "Show your reminders";
    }
  }

  /** Right-click on a pet: what it can do right now. Setup lives in the Sidefolk window. */
  menu(f: Familiar) {
    const session = this.sessionOf(f);
    const agent = session ? AGENT_NAMES[session.source as keyof typeof AGENT_NAMES] : "";
    const open = session ? [{ label: session.live ? `Open ${agent} session` : `Continue in ${agent}`, value: "open" }] : [];
    const choices = f.isMain
      ? [
          ...open,
          { label: "Type a command…", value: "prompt" },
          { label: "New reminder…", value: "reminder" },
          { label: "Your crew", value: "crew" },
          { label: "Open Sidefolk…", value: "settings" },
          { label: "Hide companions", value: "hide" },
        ]
      : [
          ...open,
          { label: "What's happening", value: "brief" },
          { label: `Ask Codex in ${f.project ? folder(f.project) : "a scratch folder"}…`, value: "prompt" },
          { label: "Appearance…", value: "look" },
          { label: "Send home", value: "home" },
        ];
    f.bubble.show({
      id: `menu-${f.record.id}`,
      who: f.shownLabel,
      title: f.isMain ? "What would you like?" : `${f.name} looks after ${f.project && privacy.detail !== "status" ? folder(f.project) : "a project"}`,
      choices,
      menu: true,
      onChoose: (value) => {
        if (value === "open") void this.openSession(f, session);
        else if (value === "prompt") this.openPrompt(f);
        else if (value === "reminder") void this.host.command?.("", "new-reminder", f);
        else if (value === "crew") this.showCrew(f);
        else if (value === "look") void this.customize(f);
        else if (value === "settings") this.host.trayAction?.("settings");
        else if (value === "hide") this.host.trayAction?.("toggle");
        else if (value === "brief") this.statusCard(f, true);
        else if (value === "home") this.sendHome(f);
      },
    });
    if (!f.isMain) f.holdUntil = Math.max(f.holdUntil, Date.now() + 20_000);
  }

  /** Runs what was typed into a pet's command bar. Returns what the pet says. */
  async run(text: string, from: Familiar): Promise<string | void> {
    const command = parse(text);
    const target = (who: string | null) => (who ? this.find(who) : from);
    switch (command.kind) {
      case "help":
        from.bubble.show({ id: "help", who: from.name, title: "Things I understand", lines: HELP, choices: [{ label: "OK", value: "ok", primary: true }], onChoose: () => {} });
        return;
      case "crew":
        return this.showCrew(from);
      case "sidefolk":
        return this.host.openTab?.("home");
      case "customize": {
        const f = target(command.who);
        if (!f) return `I don't know "${command.who}".`;
        return this.customize(f);
      }
      case "open": {
        const f = target(command.who);
        // "continue the refactor" is a task, not a pet called "the refactor".
        if (!f) return this.task(text, from);
        return this.openSession(f);
      }
      case "call": {
        const f = this.find(command.who);
        if (!f) return `I don't know "${command.who}". Try "crew".`;
        return this.call(f);
      }
      case "home": {
        if (command.who && /^(everyone|everybody|all|the crew)$/i.test(command.who)) {
          for (const f of this.pets.values()) this.sendHome(f);
          return;
        }
        const f = target(command.who);
        if (!f) return `I don't know "${command.who}".`;
        if (f.isMain) {
          for (const p of this.pets.values()) this.sendHome(p);
          return;
        }
        return this.sendHome(f);
      }
      case "tell": {
        const f = target(command.who);
        // "fix: the login bug" is a task, not a pet called "fix".
        if (!f) return this.task(text, from);
        return this.task(command.task, f);
      }
      case "codex":
        await this.host.dispatch(command.task, null);
        return "On it. Codex is working in the playground.";
      case "task":
        return this.task(command.text, from);
      case "rename": {
        const f = target(command.who);
        if (!f) return `I don't know "${command.who}".`;
        return this.rename(f, command.name);
      }
      case "look": {
        const f = target(command.who);
        if (!f) return `I don't know "${command.who}".`;
        await this.setLook(f, {
          ...(command.palette && { palette: command.palette }),
          ...(command.accessory && { accessory: command.accessory }),
          ...(command.species && { species: command.species }),
          ...(command.style && { style: command.style }),
        });
        return;
      }
      case "forget": {
        const f = this.find(command.who);
        if (!f || f.isMain) return `I can't forget "${command.who}".`;
        return this.confirmForget(f, from);
      }
      case "adopt":
        return this.adopt();
      case "remind":
      case "reminders":
        return this.host.command?.(command.kind === "remind" ? command.text : "", command.kind, from);
    }
  }

  async rename(f: Familiar, name: string): Promise<string> {
    name = name.replace(/\s+/g, " ").trim().slice(0, 24);
    if (!name) return "A name needs at least one letter.";
    if (this.all.some((p) => p !== f && p.name.toLowerCase() === name.toLowerCase())) return `${name} is already taken.`;
    const old = f.name;
    f.record = { ...f.record, name };
    await this.save();
    return `${old} is ${name} now.`;
  }

  /** Changes a pet's look (from a command or the Sidefolk window) and keeps it. */
  async setLook(f: Familiar, change: Partial<Look>) {
    await f.setLook(change);
    f.mind.react("celebrate", 1.1);
    await this.save();
  }

  /** Appearance is edited in the Sidefolk window, with idle and alert previews. */
  customize(f: Familiar) {
    if (!this.host.openTab) return f.bubble.say('Try "wear glasses", "become a fox" or "color midnight".', 6);
    this.host.openTab(`crew:${f.record.id}`);
  }

  private async task(task: string, f: Familiar) {
    const cwd = f.project;
    await this.host.dispatch(task, cwd);
    return cwd ? `On it. Codex is working in ${folder(cwd)}.` : "On it. Codex is working in the playground.";
  }

  private offer(project: string) {
    if (this.offered.has(project) || this.file.ignored.includes(project)) return;
    this.offered.add(project);
    const named = privacy.detail !== "status";
    this.main.bubble.show({
      id: `offer-${project}`,
      who: this.main.name,
      title: named ? `New project: ${folder(project)}` : "An AI tool started work in a new project.",
      lines: ["Give it its own companion? It comes out when this project needs you and rests otherwise."],
      choices: [
        { label: "Not now", value: "later" },
        { label: "Never for this project", value: "never" },
        { label: "Yes, add one", value: "yes", primary: true },
      ],
      meta: { kind: "offer", project },
      onChoose: (value) => {
        if (value === "yes") void this.create({ kind: "project", key: project });
        if (value === "never") {
          this.file.ignored.push(project);
          void this.save();
        }
      },
    });
  }

  /** Gives the latest session the main pet speaks for its own temporary pet. */
  private async adopt() {
    const session = this.main.agents.list[0];
    if (!session) return "There's no work session to adopt right now.";
    await this.create({ kind: "session", key: session.key });
  }

  async create(binding: Binding, look?: Partial<Look>, name?: string) {
    const companion = nextCompanion(this.all.map((f) => f.record), this.comfort);
    const record: PetRecord = {
      id: crypto.randomUUID(),
      name: name?.trim().slice(0, 24) || companion.name,
      look: normalizeLook({ ...companion.look, ...look }),
      bindings: [binding],
    };
    const f = await Familiar.create(record, this.zoom);
    this.add(f);
    // Sessions the main pet was tracking for this project (or session) move over.
    f.agents.adopt(
      this.main.agents.extract((s) => (binding.kind === "project" ? s.project === binding.key : s.key === binding.key)),
    );
    f.holdUntil = Date.now() + 7_000;
    this.tick();
    const what = binding.kind === "project" ? folder(binding.key) : "this work session";
    f.bubble.say(`Hi, I'm ${f.name}. I'll look after ${what}.`, 6, "done");
    await this.save();
    return f;
  }

  /** Points a pet at another project (Sidefolk window → Crew → Change project). */
  async assign(f: Familiar, project: string) {
    if (f.isMain) return;
    f.record = { ...f.record, bindings: [{ kind: "project", key: project }] };
    await this.save();
  }

  private confirmForget(f: Familiar, on: Familiar) {
    on.bubble.show({
      id: `forget-${f.record.id}`,
      who: this.main.name,
      title: `Remove ${f.name} from your crew?`,
      lines: [f.project ? `${folder(f.project)}'s work sessions go back to ${this.main.name}.` : `Its work sessions go back to ${this.main.name}.`],
      choices: [
        { label: "Keep", value: "keep" },
        { label: `Remove ${f.name}`, value: "forget" },
      ],
      onChoose: (value) => {
        if (value === "forget") void this.forget(f);
      },
    });
  }

  /** Removes a crew pet; its sessions go back to the main pet. */
  async forget(f: Familiar) {
    if (f.isMain) return;
    this.pets.delete(f.record.id);
    this.main.agents.adopt(f.agents.list);
    for (const id of f.asks) this.closeAsk(id);
    f.destroy();
    await this.save();
  }

  /** A session pet waves goodbye and leaves for good when its session ends. */
  private async retire(f: Familiar, event: AgentEvent) {
    f.holdUntil = 0;
    f.bubble.say(`${AGENT_NAMES[event.source]}'s work session ended.`, 4);
    f.record = { ...f.record, bindings: [] };
    setTimeout(() => {
      if (f.agents.list.length === 0 && !f.asks.size) void this.forget(f);
    }, 6_000);
  }

  private async save() {
    this.file = {
      main: { name: this.main.name, look: this.main.record.look },
      pets: [...this.pets.values()].map((f) => f.record).filter((r) => r.bindings.some((b) => b.kind !== "session")),
      ignored: this.file.ignored,
    };
    await this.host.saveCrew(this.file);
  }

  /** What the Sidefolk window shows: every pet, its sessions, and what is waiting on the user. */
  status() {
    const pets = this.all.map((f) => ({
      id: f.record.id,
      name: f.name,
      label: f.label,
      main: f.isMain,
      project: f.project,
      look: f.record.look,
      out: f.out,
      clip: f.out ? f.pet.clip : "away",
      sessions: f.agents.list.map((s) => ({
        source: s.source,
        id: s.id,
        cwd: s.cwd,
        state: s.state,
        verb: VERB[s.state],
        detail: s.detail,
        project: s.project,
        at: s.at,
      })),
      outcomes: [...f.agents.outcomes.values()].sort((a, b) => b.at - a.at).slice(0, 3),
    }));
    // Requests, offers and reminders can be answered from the window; menus and lines cannot.
    const waiting = this.all.flatMap((f) =>
      f.bubble.open
        .filter((c) => c.urgent || c.id.startsWith("offer-") || c.id.startsWith("reminder-"))
        .map((c) => ({
          id: c.id,
          pet: f.record.id,
          petName: f.name,
          who: c.who,
          title: c.title,
          lines: c.lines ?? [],
          meta: c.meta ?? {},
          choices: c.choices.filter((x) => x.value !== "review").map(({ label, value, primary, quiet }) => ({ label, value, primary: !!primary, quiet: !!quiet })),
        })),
    );
    return { pets, waiting, presence: this.presence };
  }

  /** An answer sent from the Sidefolk window. Permission requests take any of their real choices. */
  answer(id: string, value: string): boolean {
    for (const f of this.all) {
      const card = f.bubble.open.find((c) => c.id === id);
      if (!card) continue;
      const allowed = card.meta?.kind === "permission" ? ["allow", "deny", ...(card.meta.canDefer === "true" ? ["defer"] : [])] : card.choices.map((c) => c.value);
      const written = card.meta?.free === "true" && value.trim() !== "" && !value.startsWith("\u0000");
      if (!allowed.includes(value) && !written) return false;
      f.bubble.close(id);
      card.onChoose(value);
      return true;
    }
    return false;
  }

  resize() {
    for (const f of this.all) f.resize();
  }

  onCursor(point: { x: number; y: number }) {
    for (const f of this.all) if (f.out) f.mind.onCursor(point);
  }

  agentsTick() {
    for (const f of this.all) f.agents.tick();
  }
}
