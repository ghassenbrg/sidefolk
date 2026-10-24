import { folder } from "./agents";
import type { Companion } from "./companion";
import { describeDue, describeRepeat, nextDue, parseReminder, type Repeat } from "./when";

/** Mirrors `Reminder` in src-tauri/src/reminders.rs. */
export type Reminder = {
  id: string;
  text: string;
  due: number;
  project: string;
  from: string;
  created: number;
  done: boolean;
  fired: boolean;
  repeat?: Repeat | null;
};

export type ReminderStore = {
  list(): Promise<Reminder[]>;
  add(text: string, due: number, project: string | null, from?: string, repeat?: Repeat): Promise<Reminder>;
  update(id: string, change: { done?: boolean; due?: number; fired?: boolean }): Promise<void>;
  remove(id: string): Promise<void>;
  /** Shows the overlay while the pet is hidden (false puts it back). */
  peek(show: boolean): void;
};

const CHECK_MS = 10_000;
const MINUTE = 60_000;

/**
 * Delivers reminders on time through the pet that looks after their project (the main pet
 * otherwise). Ones that came due while Sidefolk was not running are delivered at start.
 */
export class Reminders {
  private list: Reminder[] = [];
  private showing = new Set<string>();
  /** Opens the Settings window's reminder list (desktop app only). */
  manage?: () => void;

  constructor(
    private readonly companion: Companion,
    private readonly store: ReminderStore,
  ) {}

  async start() {
    await this.reload();
    this.check(true);
    setInterval(() => this.check(false), CHECK_MS);
  }

  async reload() {
    this.list = await this.store.list();
  }

  /** `remind me …` and `reminders` from a command bar. */
  /** A reminder set by an agent through its pet tools. */
  async fromAgent(text: string, due: Date, project: string, agent: string) {
    const reminder = await this.store.add(text, due.getTime(), project || null, agent);
    this.list.push(reminder);
    return reminder;
  }

  async command(text: string, kind: "remind" | "reminders" | "new-reminder"): Promise<string | void> {
    if (kind === "reminders") return this.showList();
    if (kind === "new-reminder") return this.form();
    const parsed = parseReminder(text);
    if (!parsed) return this.askWhen(text.replace(/^(to|about)\s+/i, ""));
    return this.add(parsed.what, parsed.due, parsed.repeat);
  }

  private async add(what: string, due: Date, repeat?: Repeat) {
    const reminder = await this.store.add(what, due.getTime(), null, undefined, repeat);
    this.list.push(reminder);
    // Pip writes it down.
    this.companion.pet.mind.react("write", 1.6);
    const reply = repeat ? `OK, ${describeRepeat(repeat, due)}, starting ${describeDue(due)}: ${what}` : `OK, ${describeDue(due)}: ${what}`;
    this.confirm(reminder, reply);
    return reply;
  }

  /** The saved reminder, with Undo for a few seconds (a misheard time is fixed in one click). */
  private confirm(reminder: Reminder, reply: string) {
    const bubble = this.companion.pet.bubble;
    const id = `reminder-added-${reminder.id}`;
    bubble.show({
      id,
      who: `${this.companion.pet.name} · reminder`,
      title: reply,
      choices: [
        { label: "Undo", value: "undo" },
        { label: "OK", value: "ok", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close(id);
        if (value !== "undo") return;
        await this.store.remove(reminder.id);
        this.list = this.list.filter((r) => r.id !== reminder.id);
        bubble.say("Removed.", 3);
      },
    });
    setTimeout(() => bubble.close(id), 8_000);
  }

  /** "New reminder…": one field that takes the time too, or asks for it next. */
  private form() {
    const on = this.companion.pet;
    on.bubble.prompt({
      who: `${on.name} · new reminder`,
      placeholder: "Call the bank tomorrow at 10",
      suggestions: ["Stretch in 30 minutes", "Review the PR tomorrow at 10", "Standup Monday at 9:30"],
      preview: (text) => {
        const parsed = parseReminder(text);
        return parsed ? `Remind you ${parsed.repeat ? `${describeRepeat(parsed.repeat, parsed.due)}, from ` : ""}${describeDue(parsed.due)}: ${parsed.what}` : "Then pick when";
      },
      submit: async (text) => {
        const parsed = parseReminder(text);
        return parsed ? this.add(parsed.what, parsed.due, parsed.repeat) : this.askWhen(text);
      },
    });
  }

  /** The thing to remember is known but not when: offer the usual times. */
  private askWhen(what: string) {
    const on = this.companion.pet;
    if (!what.trim()) return this.form();
    const at = (hours: number, minutes = 0, days = 0) => {
      const d = new Date();
      d.setDate(d.getDate() + days);
      d.setHours(hours, minutes, 0, 0);
      return d;
    };
    const now = new Date();
    const options: [string, Date][] = [
      ["In 10 min", new Date(now.getTime() + 10 * MINUTE)],
      ["In 1 hour", new Date(now.getTime() + 60 * MINUTE)],
      ...(now.getHours() < 17 ? [["This evening", at(18)] as [string, Date]] : []),
      ["Tomorrow 9:00", at(9, 0, 1)],
    ];
    on.bubble.show({
      id: "reminder-when",
      who: `${on.name} · new reminder`,
      title: `When should I remind you to ${what}?`,
      lines: ['Or type it with a time, like "tomorrow at 10".'],
      choices: options.map(([label], i) => ({ label, value: String(i), primary: i === 0 })),
      onChoose: async (value) => on.bubble.say(await this.add(what, options[Number(value)][1]), 5),
    });
  }

  /** Reminders still to come, soonest first. */
  get upcoming() {
    return this.list.filter((r) => !r.done).sort((a, b) => a.due - b.due);
  }

  private check(starting: boolean) {
    const now = Date.now();
    for (const r of this.list) {
      if (r.done || this.showing.has(r.id)) continue;
      // Shown before Sidefolk quit but never answered: show it again.
      if (r.due <= now && (!r.fired || starting)) this.show(r, now - r.due > 2 * MINUTE);
    }
  }

  private show(r: Reminder, missed: boolean) {
    const pet = this.companion.pet;
    this.showing.add(r.id);
    r.fired = true;
    void this.store.update(r.id, { fired: true });
    if (this.showing.size === 1) this.store.peek(true);
    const by = r.from === "you" ? "" : ` (set by ${r.from === "codex" ? "Codex" : "Claude"})`;
    const due = describeDue(new Date(r.due));
    this.companion.request({
      id: `reminder-${r.id}`,
      who: `${pet.name} · reminder${by}`,
      title: r.text,
      // A reminder missed while the Mac slept says when it was due.
      lines: [missed ? `Was due ${due}` : `Due ${due}`].concat(r.project ? [folder(r.project)] : []),
      meta: { kind: "reminder", text: r.text, due: String(r.due), project: r.project },
      choices: [
        { label: "In 10 min", value: "10" },
        { label: "In 1 hour", value: "60" },
        { label: "Tomorrow 9:00", value: "tomorrow" },
        { label: "Done", value: "done", primary: true },
      ],
      onChoose: (value) => void this.answer(r, value),
      // Closed without an answer: it stays in the window's Requests; a hidden companion hides again.
      onClose: () => this.unpeek(r),
    });
    pet.mind.react("wave", 1.6);
  }

  private unpeek(r: Reminder) {
    this.showing.delete(r.id);
    if (this.showing.size === 0) this.store.peek(false);
  }

  private async answer(r: Reminder, value: string) {
    this.unpeek(r);
    if (value === "done" && r.repeat) {
      // A repeating reminder isn't finished: it moves to its next time.
      r.due = nextDue(new Date(r.due), r.repeat, new Date(Math.max(Date.now(), r.due))).getTime();
      r.fired = false;
      return this.store.update(r.id, { due: r.due });
    }
    if (value === "done") {
      r.done = true;
      return this.store.update(r.id, { done: true });
    }
    const due = new Date();
    if (value === "tomorrow") {
      due.setDate(due.getDate() + 1);
      due.setHours(9, 0, 0, 0);
    } else due.setTime(due.getTime() + Number(value) * MINUTE);
    r.due = due.getTime();
    r.fired = false;
    await this.store.update(r.id, { due: r.due });
  }

  private showList() {
    const on = this.companion.pet;
    const next = this.upcoming;
    const lines = next.slice(0, 6).map((r) => `${describeDue(new Date(r.due))} · ${r.text}`);
    if (next.length > 6) lines.push(`+${next.length - 6} more`);
    on.bubble.show({
      id: "reminders",
      who: on.name,
      title: next.length ? "Coming up" : "No reminders",
      lines: next.length ? lines : ['Try "remind me tomorrow at 10 to call the bank".'],
      choices: [
        { label: "New reminder…", value: "new", primary: true },
        ...(this.manage ? [{ label: "Manage…", value: "manage" }] : []),
      ],
      onChoose: (value) => (value === "new" ? this.form() : this.manage?.()),
    });
  }
}

/** A browser-preview store: kept in memory, gone on reload. */
export function memoryStore(): ReminderStore {
  const list: Reminder[] = [];
  return {
    list: async () => [...list],
    add: async (text, due, project, from = "you", repeat) => {
      const r = { id: `r${Date.now()}`, text, due, project: project ?? "", from, created: Date.now(), done: false, fired: false, repeat };
      list.push(r);
      return r;
    },
    update: async (id, change) => {
      const r = list.find((r) => r.id === id);
      if (r) { Object.assign(r, change); if (change.due !== undefined) r.fired = false; }
    },
    remove: async (id) => void list.splice(list.findIndex((r) => r.id === id) >>> 0, 1),
    peek: () => {},
  };
}
