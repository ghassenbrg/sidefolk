import { problem } from "./voice";
import { folder } from "./agents";
import type { Companion } from "./companion";
import { dateValue, timeValue, fromFields, describeDue, describeRepeat, parseReminder, parseEventReminder, type EventReminderDraft, type Repeat } from "./when";
import { button, h, timeZone } from "./dashboard/dom";
import { sheet } from "./dashboard/dialog";
import { EVENT_TTL_MS, eventDescription, isScheduledReminder, type ProjectResolver } from "./event-reminders";

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
  seriesText?: string;
  event?: { expires: number; triggeredAt?: number | null; expiredAt?: number | null } | null;
  history?: { at: number; action: string; due: number; text?: string }[];
};

/** How a reminder card was answered; the schedule itself is Rust's (src-tauri/src/reminders.rs). */
export type ReminderAnswer = { action: "done" | "skip" } | { action: "snooze"; until: number };

export type ReminderStore = {
  list(): Promise<Reminder[]>;
  add(text: string, due: number, project: string | null, from?: string, repeat?: Repeat): Promise<Reminder>;
  update(id: string, change: { done?: boolean; due?: number; fired?: boolean; completed?: boolean }): Promise<void>;
  remove(id: string): Promise<void>;
  answer(id: string, answer: ReminderAnswer): Promise<void>;
  /** Host resolves an exact repository root before any event condition can be saved. */
  resolveProject?: ProjectResolver;
  addEvent?(text: string, project: string): Promise<Reminder>;
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
  private checkedAt = 0;
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
    let changedAway = false;
    for (const old of this.list) {
      const current = next.find((r) => r.id === old.id);
      if (!current || current.done || current.due !== old.due || current.text !== old.text || current.event?.expiredAt !== old.event?.expiredAt) {
        this.companion.closeRequest(`reminder-${old.id}`);
        this.unpeek(old);
        // Its next time (a repeat, a snooze) shows on its own again.
        if (this.gathered.delete(old.id)) changedAway = true;
      }
    }
    this.list = next;
    if (changedAway) {
      this.companion.closeRequest("away");
      const remaining = next.filter((r) => this.gathered.has(r.id) && isScheduledReminder(r));
      if (remaining.length) this.away(remaining);
    }
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
    const event = parseEventReminder(text);
    if (event) return this.proposeEvent(event, text);
    if (/^(?:remind me\s+)?when\b/i.test(text.trim())) return "Choose one project completion condition.";
    const parsed = parseReminder(text);
    if (!parsed) return this.askWhen(text.replace(/^(to|about)\s+/i, ""));
    return this.propose(parsed.what, parsed.due, parsed.repeat, text, parsed.alternative);
  }

  private async proposeEvent(draft: EventReminderDraft, original: string): Promise<string> {
    const bubble = this.companion.pet.bubble;
    if (!this.store.resolveProject || !this.store.addEvent) return "Event reminders need the desktop project connection.";
    let project;
    try { project = await this.store.resolveProject(draft.project); }
    catch (reason) { return problem(reason); }
    const expires = () => new Date(Date.now() + EVENT_TTL_MS).toLocaleString();
    let saving = false;
    const card = {
      id: "reminder-event-preview", who: `${this.companion.name} · new reminder`, title: draft.what,
      lines: [`When ${project.path} next finishes.`, `Expires 24 hours after saving · ${expires()} (${timeZone()}).`],
      choices: [{ label: "Save", value: "save", primary: true }, { label: "Change", value: "change" }],
      onChoose: async (value: string) => {
        if (saving) return;
        if (value === "change") { this.form(original); return; }
        saving = true;
        try {
          const reminder = await this.store.addEvent!(draft.what, project.path);
          this.list.push(reminder);
          this.confirm(reminder, eventDescription(reminder));
        } catch (reason) { bubble.show({ ...card, note: problem(reason) }); }
        finally { saving = false; }
      },
    };
    bubble.show(card);
    return "Review the project condition, then Save or Change.";
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
        const event = parseEventReminder(text);
        if (event) return `When ${event.project} next finishes · expires 24 hours after saving; confirm the exact project first`;
        const parsed = parseReminder(text);
        return parsed ? `Remind you ${parsed.repeat ? `${describeRepeat(parsed.repeat, parsed.due)}, from ` : ""}${describeDue(parsed.due)}: ${parsed.what}` : "Then pick when";
      },
      submit: (text) => this.command(text, "remind"),
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
    const resumed = starting || this.checkedAt > 0 && now - this.checkedAt > 2 * CHECK_MS;
    this.checkedAt = now;
    // Shown before Sidefolk quit but never answered: show it again.
    const due = this.list.filter((r) => isScheduledReminder(r) && !this.showing.has(r.id) && !this.gathered.has(r.id) && r.due <= now && (!r.fired || starting));
    const late = due.filter((r) => resumed ? r.due < now : now - r.due > 2 * MINUTE);
    for (const r of due) if (!late.includes(r)) this.show(r, false);
    // After a quit or sleep: one card for everything that came due meanwhile (docs/V1.md V1-R8).
    if (late.length) this.away(this.list.filter((r) => isScheduledReminder(r) && (this.gathered.has(r.id) || late.includes(r))));
  }

  private away(late: Reminder[]) {
    const pet = this.companion.pet;
    for (const r of late) {
      this.gathered.add(r.id);
      if (!r.fired) {
        r.fired = true;
        void this.store.update(r.id, { fired: true }).catch((reason) => pet.bubble.say(problem(reason), 6, "fail"));
      }
    }
    this.store.peek(true);
    const lines = late
      .sort((a, b) => a.due - b.due)
      .slice(0, 6)
      .map((r) => `Late · Was due ${describeDue(new Date(r.occurrence || r.due))} · ${r.text}`);
    if (late.length > 6) lines.push(`+${late.length - 6} more`);
    this.companion.request({
      id: "away",
      who: `${pet.name} · reminders`,
      title: `While you were away: ${late.length} reminder${late.length === 1 ? "" : "s"}`,
      lines,
      meta: { kind: "reminder", count: String(late.length), text: "While you were away", project: "" },
      choices: [{ label: "One by one", value: "each" }, ...(this.manage ? [{ label: "Open the list", value: "list", primary: true }] : [])],
      onChoose: (value) => {
        this.companion.closeRequest("away");
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
      lines: [missed ? `Late · Was due ${describeDue(new Date(r.occurrence || r.due))}` : `Due ${due}`].concat(r.project ? [folder(r.project)] : []),
      meta: { kind: "reminder", text: r.text, due: String(r.due), project: r.project },
      choices: [
        { label: "10 min", value: "10" }, { label: "1 hour", value: "60" },
        ...([10, 60].includes(this.snoozeMinutes) ? [] : [{ label: `${this.snoozeMinutes} min (default)`, value: String(this.snoozeMinutes) }]),
        { label: new Date().getHours() < 18 ? "This evening 18:00" : "Tomorrow 18:00", value: "evening" },
        { label: "Tomorrow 9:00", value: "tomorrow" },
        { label: "Pick…", value: "pick" },
        ...(r.repeat ? [{ label: "Skip this one", value: "skip", quiet: true }] : []),
        // "Every Friday at 4, note what I achieved": the reminder opens the notebook's capture.
        ...(this.writeNote && aboutWriting(r.text) ? [{ label: "Write it now", value: "write", primary: true }, { label: "Done", value: "done" }] : [{ label: "Done", value: "done", primary: true }]),
        ...(this.manage ? [{ label: "Open", value: "open", quiet: true }] : []),
      ],
      onChoose: (value) => {
        if (value === "open") { this.unpeek(r); this.manage?.(r.id); return; }
        if (value === "pick") { this.pick(r, missed); return; }
        if (value === "write") this.writeNote?.(r.text);
        if (value === "write") value = "done";
        void this.answer(r, value).catch((e) => { pet.bubble.say(problem(e), 6, "fail"); this.show(r, missed); });
      },
      // Closed without an answer: it stays in the window's Requests; a hidden companion hides again.
      onClose: () => this.unpeek(r),
    });
    pet.mind.react("wave", 1.6);
  }

  /** The overlay keeps the form inside its measured, clickable card rectangle. */
  private pick(r: Reminder, missed: boolean) {
    const bubble = this.companion.pet.bubble;
    const id = `reminder-pick-${r.id}`;
    const close = () => { bubble.close(id); bubble.onTyping(false); };
    bubble.show({ id, who: `${this.companion.name} · snooze`, title: r.text, choices: [],
      onChoose: () => {}, onClose: () => { bubble.onTyping(false); this.unpeek(r); } });
    const fields = snoozeForm(async (due) => {
      await this.store.answer(r.id, { action: "snooze", until: due.getTime() });
      close(); this.unpeek(r); await this.reload();
    }, () => { close(); this.show(r, missed); });
    bubble.root.append(fields.form);
    bubble.onTyping(true);
    requestAnimationFrame(() => fields.focus());
  }

  private unpeek(r: Reminder) {
    this.showing.delete(r.id);
    if (this.showing.size === 0) this.store.peek(false);
  }

  /** Done and Skip move a series to its next occurrence; a snooze moves only this one (Rust). */
  private async answer(r: Reminder, value: string) {
    if (value === "done" || value === "skip") await this.store.answer(r.id, { action: value });
    else await this.store.answer(r.id, { action: "snooze", until: snoozeUntil(value).getTime() });
    this.unpeek(r);
    await this.reload();
  }

  private showList() {
    const on = this.companion.pet;
    const next = this.upcoming;
    const lines = next.slice(0, 6).map((r) => `${r.event && !isScheduledReminder(r) ? eventDescription(r) : describeDue(new Date(r.due))} · ${r.text}`);
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
  if (choice === "evening") {
    at.setHours(18, 0, 0, 0);
    if (at <= now) at.setDate(at.getDate() + 1);
  }
  else if (choice === "tomorrow") {
    at.setDate(at.getDate() + 1);
    at.setHours(9, 0, 0, 0);
  } else {
    const minutes = Number(choice);
    if (!Number.isFinite(minutes) || minutes <= 0) throw new Error("Choose a later snooze time.");
    at.setTime(at.getTime() + minutes * MINUTE);
  }
  if (!Number.isFinite(at.getTime()) || at <= now) throw new Error("Choose a later snooze time.");
  return at;
}

/** A reminder to write something down ("note what I achieved this week", "log the wins"). */
export const aboutWriting = (text: string) => /\b(note|notes|write( it)? down|log|jot|journal)\b|what (i|we) (did|achieved|shipped)|\bwins\b/i.test(text);

/** A browser-preview store: kept in memory, gone on reload. */
export function memoryStore(): ReminderStore {
  const list: Reminder[] = [];
  let serial = 0;
  return {
    list: async () => structuredClone(list),
    add: async (text, due, project, from = "you", repeat) => {
      const r = { id: `r${Date.now()}-${serial++}`, text, due, project: project ?? "", from, created: Date.now(), done: false, fired: false, repeat };
      list.push(r);
      return r;
    },
    addEvent: async (text, project) => {
      const now = Date.now();
      const r: Reminder = { id: `r${now}-${serial++}`, text, due: 0, project, from: "you", created: now, done: false, fired: false, event: { expires: now + EVENT_TTL_MS } };
      list.push(r); return structuredClone(r);
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


/** Same validated fields on the window's native sheet and the overlay's measured card. */
function snoozeForm(save: (due: Date) => Promise<void>, cancel: () => void) {
  const due = snoozeUntil("10");
  const date = h("input", { id: "snooze-date", type: "date", value: dateValue(due), required: true, "aria-describedby": "snooze-preview snooze-error" });
  const time = h("input", { id: "snooze-time", type: "time", value: timeValue(due), required: true, "aria-describedby": "snooze-preview snooze-error" });
  const preview = h("p", { id: "snooze-preview", class: "hint", "aria-live": "polite" });
  const error = h("p", { id: "snooze-error", class: "field-error", role: "alert" });
  const submit = h("button", { type: "submit", class: "primary", text: "Snooze" });
  const form = h("form", { "aria-label": "Pick snooze time", class: "form-grid" },
    h("div", { class: "field" }, h("label", { for: date.id, text: "Date" }), date),
    h("div", { class: "field" }, h("label", { for: time.id, text: "Time" }), time),
    preview, error, h("div", { class: "actions sheet-actions" }, button("Cancel", cancel), submit));
  const update = () => {
    const at = fromFields(date.value, time.value);
    preview.textContent = `${at ? at.toLocaleString([], { dateStyle: "full", timeStyle: "short" }) : "Choose a date and time"} · ${timeZone()} · this Mac`;
  };
  date.addEventListener("input", update); time.addEventListener("input", update); update();
  form.addEventListener("keydown", (event) => {
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); cancel(); }
  });
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (submit.disabled) return;
    const at = fromFields(date.value, time.value);
    if (!at || at.getTime() <= Date.now()) { error.textContent = "Choose a date and time later than now."; return; }
    submit.disabled = true;
    try { await save(at); }
    catch (reason) { error.textContent = problem(reason); submit.disabled = false; }
  });
  return { form, focus: () => date.focus() };
}

export function pickSnooze(text: string, save: (due: Date) => Promise<void>) {
  let close = () => {};
  const fields = snoozeForm(async (due) => { await save(due); close(); }, () => close());
  const editor = sheet(`Snooze ${text}`, fields.form);
  close = editor.close;
  requestAnimationFrame(fields.focus);
}
