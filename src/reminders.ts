import { problem } from "./voice";
import { folder } from "./agents";
import type { Companion } from "./companion";
import { describeDue, describeRepeat, parseReminder, type Repeat } from "./when";

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
  /** A series' first occurrence; its weekday and time never move with a snooze. */
  anchor?: number;
  /** When the current occurrence was due before any snooze. */
  occurrence?: number;
  history?: { at: number; action: string; due: number }[];
};

/** How a reminder card was answered; the schedule itself is Rust's (src-tauri/src/reminders.rs). */
export type ReminderAnswer = { action: "done" | "skip" } | { action: "snooze"; until: number };

export type ReminderStore = {
  list(): Promise<Reminder[]>;
  add(text: string, due: number, project: string | null, from?: string, repeat?: Repeat): Promise<Reminder>;
  update(id: string, change: { done?: boolean; due?: number; fired?: boolean; completed?: boolean }): Promise<void>;
  remove(id: string): Promise<void>;
  answer(id: string, answer: ReminderAnswer): Promise<void>;
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
  snoozeMinutes = 10;
  private list: Reminder[] = [];
  private showing = new Set<string>();
  /** Late reminders gathered into one "While you were away" card; they stay overdue in the window. */
  private gathered = new Set<string>();
  /** Opens the Settings window's reminder list (desktop app only). */
  manage?: (id?: string) => void;
  /** Opens a quick note capture; a reminder about writing something down offers it. */
  writeNote?: (reminderText: string) => void;

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
    const next = await this.store.list();
    for (const old of this.list) {
      const current = next.find((r) => r.id === old.id);
      if (!current || current.done || current.due !== old.due || current.text !== old.text) {
        this.companion.closeRequest(`reminder-${old.id}`);
        this.unpeek(old);
        // Its next time (a repeat, a snooze) shows on its own again.
        this.gathered.delete(old.id);
      }
    }
    this.list = next;
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
    return this.propose(parsed.what, parsed.due, parsed.repeat, text, parsed.alternative);
  }

  /**
   * The reminder as understood, before it's saved. A bare hour with two sensible readings ("at 9":
   * tonight or tomorrow morning) offers both as the buttons, so no time is ever guessed in silence
   * (docs/V1.md V1-Q5).
   */
  private propose(what: string, due: Date, repeat?: Repeat, original = what, alternative?: Date) {
    const bubble = this.companion.pet.bubble;
    const when = (d: Date) => d.toLocaleString([], { weekday: "short", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
    const save = (at: Date) => {
      if (at.getTime() <= Date.now()) { bubble.say("That time has passed. Choose a later one.", 5); return this.form(original); }
      void this.add(what, at, repeat).catch((e) => bubble.say(problem(e), 6, "fail"));
    };
    bubble.show({
      id: "reminder-preview", who: `${this.companion.name} · new reminder`, title: what,
      lines: alternative ? ["Which one do you mean?"] : [`${when(due)}${repeat ? ` · ${describeRepeat(repeat, due)}` : ""}`],
      choices: alternative
        ? [{ label: describeDue(due), value: "due", primary: true }, { label: describeDue(alternative), value: "alternative" }, { label: "Change", value: "change", quiet: true }]
        : [{ label: "Save", value: "save", primary: true }, { label: "Change", value: "change" }],
      onChoose: (value) => {
        if (value === "change") return this.form(original);
        save(value === "alternative" && alternative ? alternative : due);
      },
    });
    return alternative ? "Pick the time on the companion." : "Review the reminder on the companion, then Save or Change.";
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

  /** The saved reminder, with Undo until dismissed (a misheard time is fixed in one click). */
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
        try {
          await this.store.remove(reminder.id);
          this.list = this.list.filter((r) => r.id !== reminder.id);
          bubble.say("Removed.", 3);
        } catch (error) { bubble.say(problem(error), 6, "fail"); }
      },
    });
  }

  /** "New reminder…": one field that takes the time too, or asks for it next. */
  private form(value = "") {
    const on = this.companion.pet;
    on.bubble.prompt({
      who: `${on.name} · new reminder`,
      placeholder: "Call the bank tomorrow at 10",
      value,
      suggestions: ["Stretch in 30 minutes", "Review the PR tomorrow at 10", "Standup Monday at 9:30"],
      preview: (text) => {
        const parsed = parseReminder(text);
        return parsed ? `Remind you ${parsed.repeat ? `${describeRepeat(parsed.repeat, parsed.due)}, from ` : ""}${describeDue(parsed.due)}: ${parsed.what}` : "Then pick when";
      },
      submit: async (text) => {
        const parsed = parseReminder(text);
        return parsed ? this.propose(parsed.what, parsed.due, parsed.repeat, text, parsed.alternative) : this.askWhen(text);
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
      onChoose: (value) => { this.propose(what, options[Number(value)][1]); },
    });
  }

  /** Reminders still to come, soonest first. */
  get upcoming() {
    return this.list.filter((r) => !r.done).sort((a, b) => a.due - b.due);
  }

  private check(starting: boolean) {
    const now = Date.now();
    // Shown before Sidefolk quit but never answered: show it again.
    const due = this.list.filter((r) => !r.done && !this.showing.has(r.id) && !this.gathered.has(r.id) && r.due <= now && (!r.fired || starting));
    const late = due.filter((r) => now - r.due > 2 * MINUTE);
    for (const r of due) if (!late.includes(r)) this.show(r, false);
    // After a quit or sleep: one card for everything that came due meanwhile (docs/V1.md V1-R8).
    if (late.length === 1) this.show(late[0], true);
    else if (late.length > 1) this.away(late);
  }

  private away(late: Reminder[]) {
    const pet = this.companion.pet;
    for (const r of late) this.gathered.add(r.id);
    this.store.peek(true);
    const lines = late
      .sort((a, b) => a.due - b.due)
      .slice(0, 6)
      .map((r) => `${describeDue(new Date(r.due))} · ${r.text}`);
    if (late.length > 6) lines.push(`+${late.length - 6} more`);
    pet.bubble.show({
      id: "away",
      who: `${pet.name} · reminders`,
      title: `While you were away: ${late.length} reminders`,
      lines,
      choices: [{ label: "One by one", value: "each" }, ...(this.manage ? [{ label: "Open the list", value: "list", primary: true }] : [])],
      onChoose: (value) => {
        pet.bubble.close("away");
        this.store.peek(false);
        if (value === "list") this.manage?.();
        else for (const r of late) this.show(r, true);
      },
      onClose: () => this.store.peek(false),
    });
    pet.mind.react("wave", 1.6);
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
        { label: `In ${this.snoozeMinutes} min`, value: String(this.snoozeMinutes) },
        ...(this.snoozeMinutes === 60 ? [] : [{ label: "In 1 hour", value: "60" }]),
        ...(new Date().getHours() < 17 ? [{ label: "This evening", value: "evening" }] : []),
        { label: "Tomorrow 9:00", value: "tomorrow" },
        ...(r.repeat ? [{ label: "Skip this one", value: "skip", quiet: true }] : []),
        // "Every Friday at 4, note what I achieved": the reminder opens the notebook's capture.
        ...(this.writeNote && aboutWriting(r.text) ? [{ label: "Write it now", value: "write", primary: true }, { label: "Done", value: "done" }] : [{ label: "Done", value: "done", primary: true }]),
        ...(this.manage ? [{ label: "Open", value: "open", quiet: true }] : []),
      ],
      onChoose: (value) => {
        if (value === "open") { this.unpeek(r); this.manage?.(r.id); return; }
        if (value === "write") this.writeNote?.(r.text);
        if (value === "write") value = "done";
        void this.answer(r, value).catch((e) => { pet.bubble.say(problem(e), 6, "fail"); this.show(r, missed); });
      },
      // Closed without an answer: it stays in the window's Requests; a hidden companion hides again.
      onClose: () => this.unpeek(r),
    });
    pet.mind.react("wave", 1.6);
  }

  private unpeek(r: Reminder) {
    this.showing.delete(r.id);
    if (this.showing.size === 0) this.store.peek(false);
  }

  /** Done and Skip move a series to its next occurrence; a snooze moves only this one (Rust). */
  private async answer(r: Reminder, value: string) {
    this.unpeek(r);
    if (value === "done" || value === "skip") await this.store.answer(r.id, { action: value });
    else await this.store.answer(r.id, { action: "snooze", until: snoozeUntil(value).getTime() });
    await this.reload();
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

/** When a snooze choice shows the reminder again: minutes, "evening" (18:00) or "tomorrow" (09:00). */
export function snoozeUntil(choice: string, now = new Date()): Date {
  const at = new Date(now);
  if (choice === "evening") at.setHours(18, 0, 0, 0);
  else if (choice === "tomorrow") {
    at.setDate(at.getDate() + 1);
    at.setHours(9, 0, 0, 0);
  } else at.setTime(at.getTime() + Number(choice) * MINUTE);
  return at;
}

/** A reminder to write something down ("note what I achieved this week", "log the wins"). */
export const aboutWriting = (text: string) => /\b(note|notes|write( it)? down|log|jot|journal)\b|what (i|we) (did|achieved|shipped)|\bwins\b/i.test(text);

/** A browser-preview store: kept in memory, gone on reload. */
export function memoryStore(): ReminderStore {
  const list: Reminder[] = [];
  return {
    list: async () => structuredClone(list),
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
    // The preview has no series engine: done finishes, a snooze moves it.
    answer: async (id, answer) => {
      const r = list.find((r) => r.id === id);
      if (!r) return;
      if (answer.action === "snooze") Object.assign(r, { due: answer.until, fired: false });
      else r.done = true;
    },
    peek: () => {},
  };
}
