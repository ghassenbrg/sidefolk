import { AGENT_NAMES, VERB, folder, type AgentEvent } from "./agents";
import type { Card } from "./bubble";
import { HELP, parse } from "./commands";
import { Familiar, MAIN_ID, type Binding, type PetRecord } from "./familiar";
import { describe } from "./describe";
import {
  ACCESSORIES,
  ACCESSORY_NAMES,
  CUSTOM,
  DEFAULT_LOOK,
  normalizeLook,
  PALETTE_NAMES,
  PALETTES,
  SPECIES,
  SPECIES_NAMES,
  type Look,
} from "./pet/look";
import { findPet, nextName, nextPalette, resolve, type Origin } from "./routing";
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
};

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
  /** Tray actions the pet's menu offers (Settings, hide). */
  trayAction?(action: "settings" | "toggle"): void;
  /** Custom pets; desktop app only. */
  models?(): Promise<string[]>;
  importModel?(): Promise<string | null>;
  photoLook?(): Promise<Partial<Look> | null>;
};

/** Crew pets on screen at once, besides the main pet. */
const CAP = 3;
const OUT_AFTER_DONE_MS = 8_000;
const OUT_AFTER_FAILED_MS = 25_000;
const OUT_WHEN_CALLED_MS = 45_000;

export function emptyCrew(): CrewFile {
  return { main: { name: "Sidefolk", look: DEFAULT_LOOK }, pets: [], ignored: [] };
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
    main: { name: typeof v.main?.name === "string" && v.main.name ? v.main.name.slice(0, 24) : "Sidefolk", look: normalizeLook(v.main?.look) },
    pets,
    ignored: Array.isArray(v.ignored) ? v.ignored.filter((p): p is string => typeof p === "string") : [],
  };
}

const mainRecord = (file: CrewFile): PetRecord => ({ id: MAIN_ID, name: file.main.name, look: file.main.look, bindings: [] });

/**
 * The main pet and its crew: routes each agent event and question to the pet that speaks for
 * it, brings crew pets out when their project needs you and sends them home afterwards.
 */
export class Crew {
  private readonly pets = new Map<string, Familiar>();
  private readonly askOwner = new Map<string, Familiar>();
  /** Projects offered a pet during this run (answered "Not now" or still open). */
  private readonly offered = new Set<string>();

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
      if (f.isMain) return;
      if (event.kind === "done") f.holdUntil = Math.max(f.holdUntil, Date.now() + OUT_AFTER_DONE_MS);
      if (event.kind === "failed") f.holdUntil = Math.max(f.holdUntil, Date.now() + OUT_AFTER_FAILED_MS);
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
  seedOutcomes(entries: { at: number; source: string; project: string; kind: string; detail: string }[]) {
    for (const e of entries) {
      if ((e.kind !== "done" && e.kind !== "failed") || (e.source !== "claude" && e.source !== "codex")) continue;
      this.petFor(e.project).agents.outcomes.set(e.project, { kind: e.kind, source: e.source, project: e.project, detail: e.detail, at: e.at });
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
  }

  handleAsk(ask: Ask) {
    const f = this.familiarFor(ask);
    // A crew pet that cannot come out (too many on screen) asks through the main pet.
    const target = !f.isMain && !f.out && this.outCount >= CAP ? this.main : f;
    const agent = AGENT_NAMES[ask.source];
    const who = f.isMain ? `${agent} · ${folder(ask.project || ask.cwd)}` : `${f.label} · ${agent}`;
    const choices = [
      { label: "Allow", value: "allow", primary: true },
      { label: "Deny", value: "deny" },
      ...(ask.canDefer ? [{ label: "In terminal", value: "defer" }] : []),
    ];
    this.question(target, {
      id: ask.id,
      who,
      title: ask.title,
      detail: ask.detail,
      choices,
      urgent: true,
      onChoose: (value) => this.host.resolvePermission(ask.id, value),
    });
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

  /** Brings crew pets out when needed and sends them home when they are done. */
  tick() {
    const now = Date.now();
    for (const f of this.pets.values()) {
      const needed = f.agents.needsYou || f.asks.size > 0 || f.holdUntil > now || f.bubble.busy;
      if (needed && !f.out) {
        if (this.outCount < CAP) f.mind.enter(this.spotFor(f));
      } else if (needed && f.mind.isLeaving) {
        f.mind.enter(f.mind.x);
      } else if (!needed && f.out && !f.mind.isLeaving) {
        f.mind.leave();
      }
    }
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

  call(f: Familiar) {
    if (f.isMain) return this.showCrew(f);
    f.holdUntil = Date.now() + OUT_WHEN_CALLED_MS;
    this.tick();
    f.bubble.show(this.briefing(f));
  }

  private briefing(f: Familiar): Card {
    const minutes = (at: number) => {
      const m = Math.round((Date.now() - at) / 60_000);
      return m < 1 ? "just now" : m === 1 ? "1 min ago" : m < 90 ? `${m} min ago` : `${Math.round(m / 60)} h ago`;
    };
    const sessions = f.agents.list.map(
      (s) => `${AGENT_NAMES[s.source]} · ${VERB[s.state]}${s.detail && s.state !== "waiting" ? ` ${s.detail}` : ""}`,
    );
    const outcomes = [...f.agents.outcomes.values()]
      .sort((a, b) => b.at - a.at)
      .slice(0, 2)
      .map((o) => `${AGENT_NAMES[o.source]} ${o.kind === "done" ? "finished" : "hit a problem"} ${minutes(o.at)}${o.detail ? `: ${o.detail}` : "."}`);
    const where = f.project ? folder(f.project) : "my sessions";
    return {
      id: `brief-${f.record.id}`,
      who: f.label,
      title: sessions.length ? `Here's ${where}.` : `All quiet in ${where}.`,
      lines: [...sessions, ...outcomes].slice(0, 5),
      choices: [
        { label: "OK", value: "ok", primary: true },
        { label: "Ask here…", value: "ask" },
        { label: "Look…", value: "look" },
        { label: "Send home", value: "home" },
      ],
      onChoose: (value) => {
        if (value === "ask") this.openPrompt(f);
        else if (value === "look") void this.customize(f);
        else if (value === "home") this.sendHome(f);
        else f.holdUntil = Date.now() + 3_000;
      },
    };
  }

  private showCrew(on: Familiar) {
    const lines = [...this.pets.values()].map((f) => {
      const top = f.agents.list[0];
      const state = top ? `${AGENT_NAMES[top.source]} ${VERB[top.state]}` : f.out ? "out" : "in the den";
      return `${f.label} — ${state}`;
    });
    on.bubble.show({
      id: "crew",
      who: this.main.name,
      title: lines.length ? "Your crew" : "No crew yet",
      lines: lines.length ? lines : ["When an agent works in a git project, I'll offer it a pet."],
      choices: [{ label: "OK", value: "ok", primary: true }],
      onChoose: () => {},
    });
  }

  sendHome(f: Familiar) {
    if (f.isMain) return;
    if (f.asks.size) return f.bubble.say("I still have a question for you.", 4);
    f.holdUntil = 0;
    f.bubble.close(`brief-${f.record.id}`);
    this.tick();
  }

  openPrompt(f: Familiar) {
    f.bubble.prompt({
      who: f.isMain ? `Talk to ${f.name}` : `Talk to ${f.label}`,
      placeholder: f.isMain ? "Type a command or a task…" : `Tell ${f.name} what to do…`,
      suggestions: f.isMain
        ? ["crew", "remind me …", "reminders", "customize", "help"]
        : ["what's happening", "customize", "go home"],
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
        return name(command.who) ? `Change how ${name(command.who)} looks` : unknown(command.who!);
      case "call":
        return name(command.who) ? `Bring ${name(command.who)} out` : unknown(command.who);
      case "home":
        return command.who && !/^(everyone|everybody|all|the crew)$/i.test(command.who) && !name(command.who)
          ? unknown(command.who)
          : `Send ${command.who ? name(command.who) ?? "everyone" : from.isMain ? "everyone" : from.name} home`;
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
        return "Give the latest agent session its own pet";
      case "remind": {
        const parsed = parseReminder(command.text);
        return parsed ? `Remind you ${describeDue(parsed.due)}: ${parsed.what}` : "Set a reminder (then pick when)";
      }
      case "reminders":
        return "Show your reminders";
    }
  }

  /** Right-click on a pet: everything it can do, so nothing has to be remembered. */
  menu(f: Familiar) {
    const choices = f.isMain
      ? [
          { label: "Type a command…", value: "prompt" },
          { label: "New reminder…", value: "reminder" },
          { label: "Reminders", value: "reminders" },
          { label: "Your crew", value: "crew" },
          { label: "Customize…", value: "look" },
          { label: "Open Sidefolk…", value: "settings" },
          { label: "Hide pets", value: "hide" },
        ]
      : [
          { label: "What's happening", value: "brief" },
          { label: `Ask Codex in ${f.project ? folder(f.project) : "a scratch folder"}…`, value: "prompt" },
          { label: "Customize…", value: "look" },
          { label: "Send home", value: "home" },
          { label: `Forget ${f.name}…`, value: "forget" },
        ];
    f.bubble.show({
      id: `menu-${f.record.id}`,
      who: f.label,
      title: f.isMain ? "What would you like?" : `${f.name} looks after ${f.project ? folder(f.project) : "a session"}`,
      choices,
      menu: true,
      onChoose: (value) => {
        if (value === "prompt") this.openPrompt(f);
        else if (value === "reminder") void this.host.command?.("", "new-reminder", f);
        else if (value === "reminders") void this.host.command?.("", "reminders", f);
        else if (value === "crew") this.showCrew(f);
        else if (value === "look") void this.customize(f);
        else if (value === "settings") this.host.trayAction?.("settings");
        else if (value === "hide") this.host.trayAction?.("toggle");
        else if (value === "brief") this.call(f);
        else if (value === "home") this.sendHome(f);
        else if (value === "forget") this.confirmForget(f, f);
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
      case "customize": {
        const f = target(command.who);
        if (!f) return `I don't know "${command.who}".`;
        return this.customize(f);
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
        const name = command.name.replace(/\s+/g, " ").slice(0, 24);
        if (this.all.some((p) => p !== f && p.name.toLowerCase() === name.toLowerCase())) return `${name} is already taken.`;
        const old = f.name;
        f.record = { ...f.record, name };
        await this.save();
        return f === from ? `I'm ${name} now.` : `${old} is ${name} now.`;
      }
      case "look": {
        const f = target(command.who);
        if (!f) return `I don't know "${command.who}".`;
        await f.setLook({
          ...(command.palette && { palette: command.palette }),
          ...(command.accessory && { accessory: command.accessory }),
          ...(command.species && { species: command.species }),
        });
        f.mind.react("celebrate", 1.2);
        await this.save();
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

  /** The look editor: body, coat and extra apply live; Done saves. */
  async customize(f: Familiar) {
    const models = (await this.host.models?.().catch(() => [])) ?? [];
    const apply = async (change: Partial<Look>) => {
      try {
        await f.setLook(change);
      } catch (error) {
        f.bubble.say(`That model doesn't fit: ${error instanceof Error ? error.message : error}`, 8, "fail");
      }
    };
    const reopen = () => void this.customize(f);
    // A crew pet stays out while its look is being changed.
    f.holdUntil = Math.max(f.holdUntil, Date.now() + 60_000);
    this.tick();
    const look = f.record.look;
    f.bubble.show({
      id: `look-${f.record.id}`,
      who: f.label,
      title: `How should ${f.name} look?`,
      rows: [
        {
          label: "Body",
          options: [
            ...SPECIES_NAMES.map((n) => ({ label: SPECIES[n].label, value: n as string })),
            ...models.map((m) => ({ label: m.replace(/\.glb$/, ""), value: CUSTOM + m })),
          ],
          selected: look.species,
          onPick: (species) => void apply({ species }),
        },
        {
          label: "Coat",
          options: PALETTE_NAMES.map((n) => ({ label: PALETTES[n].label, value: n, swatch: PALETTES[n].body })),
          selected: look.palette,
          onPick: (palette) => void apply({ palette: palette as Look["palette"] }),
        },
        {
          label: "Extra",
          options: ACCESSORY_NAMES.map((n) => ({ label: ACCESSORIES[n], value: n })),
          selected: look.accessory,
          onPick: (accessory) => void apply({ accessory: accessory as Look["accessory"] }),
        },
      ],
      choices: [
        { label: "Done", value: "done", primary: true },
        { label: "Describe…", value: "describe" },
        ...(this.host.photoLook ? [{ label: "Photo…", value: "photo" }] : []),
        ...(this.host.importModel ? [{ label: "Import…", value: "import" }] : []),
      ],
      onChoose: async (value) => {
        if (value === "done") {
          f.holdUntil = Date.now() + 3_000;
          f.mind.react("celebrate", 1.2);
          return this.save();
        }
        if (value === "describe")
          return f.bubble.prompt({
            who: f.label,
            placeholder: "A sleepy black cat with glasses…",
            submit: async (text) => {
              const change = describe(text);
              await apply(change);
              reopen();
              return Object.keys(change).length ? undefined : "I couldn't tell. Try a color and an animal.";
            },
          });
        if (value === "photo") {
          f.bubble.say("Asking Claude to look at the photo…", 15);
          const change = await this.host.photoLook!().catch((error) => (f.bubble.say(String(error), 8, "fail"), null));
          if (change) await apply(change);
          return reopen();
        }
        if (value === "import") {
          const name = await this.host.importModel!().catch((error) => (f.bubble.say(String(error), 8, "fail"), null));
          if (name) await apply({ species: CUSTOM + name });
          return reopen();
        }
      },
    });
  }

  private async task(task: string, f: Familiar) {
    const cwd = f.project;
    await this.host.dispatch(task, cwd);
    return cwd ? `On it. Codex is working in ${folder(cwd)}.` : "On it. Codex is working in the playground.";
  }

  private offer(project: string) {
    if (this.offered.has(project) || this.file.ignored.includes(project)) return;
    this.offered.add(project);
    this.main.bubble.show({
      id: `offer-${project}`,
      who: this.main.name,
      title: `New project: ${folder(project)}`,
      lines: ["Give it its own pet? It comes out when this project needs you."],
      choices: [
        { label: "Yes", value: "yes", primary: true },
        { label: "Not now", value: "later" },
        { label: "Never", value: "never" },
      ],
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
    if (!session) return "There's no session to adopt right now.";
    await this.create({ kind: "session", key: session.key });
  }

  async create(binding: Binding) {
    const taken = this.all.map((f) => f.name);
    const record: PetRecord = {
      id: crypto.randomUUID(),
      name: nextName(taken),
      look: { ...DEFAULT_LOOK, palette: nextPalette(this.all.map((f) => f.record.look.palette)) },
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
    const what = binding.kind === "project" ? folder(binding.key) : "this session";
    f.bubble.say(`Hi! I'm ${f.name}. I'll look after ${what}.`, 6, "done");
    await this.save();
  }

  private confirmForget(f: Familiar, on: Familiar) {
    on.bubble.show({
      id: `forget-${f.record.id}`,
      who: this.main.name,
      title: `Forget ${f.name}?`,
      lines: [f.project ? `${folder(f.project)} goes back to me.` : "Its sessions go back to me."],
      choices: [
        { label: "Forget", value: "forget", primary: true },
        { label: "Keep", value: "keep" },
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
    f.bubble.say(`${AGENT_NAMES[event.source]}'s session ended. Bye!`, 4);
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

  /** What the dashboard shows: every pet, its sessions, and what is waiting on the user. */
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
      sessions: f.agents.list.map((s) => ({ source: s.source, state: s.state, verb: VERB[s.state], detail: s.detail, project: s.project, at: s.at })),
      outcomes: [...f.agents.outcomes.values()].sort((a, b) => b.at - a.at).slice(0, 3),
    }));
    // Questions and offers can be answered from the dashboard; menus and editors cannot.
    const waiting = this.all.flatMap((f) =>
      f.bubble.open
        .filter((c) => c.urgent || c.id.startsWith("offer-") || c.id.startsWith("reminder-"))
        .map((c) => ({ id: c.id, pet: f.record.id, who: c.who, title: c.title, detail: c.detail ?? "", choices: c.choices.map(({ label, value }) => ({ label, value })) })),
    );
    return { pets, waiting };
  }

  /** A dashboard answer to a question or offer showing on some pet. */
  answer(id: string, value: string): boolean {
    return this.all.some((f) => f.bubble.choose(id, value));
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
