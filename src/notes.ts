import { folder } from "./agents";
import type { Companion } from "./companion";

// The work log (docs/V1.md §5): notes taken in one sentence, dated, tagged with the project you're
// working in, written to Markdown notebooks (notes.rs). "note: …" goes to Log without a question;
// "note for X: …" needs X to match a notebook exactly, or asks, and the text is never lost.

/** Mirrors `Notebook` and `Entry` in src-tauri/src/notes.rs. */
export type Notebook = { id: string; name: string; count: number; updated: number };
export type NoteEntry = { line: number; date: string; text: string; project: string };

export type NoteStore = {
  list(): Promise<Notebook[]>;
  create(name: string): Promise<Notebook>;
  add(notebook: string, text: string, date: string, project: string, create?: boolean): Promise<[Notebook, NoteEntry]>;
  remove(id: string, entry: NoteEntry): Promise<void>;
  /** Moves an entry to another notebook, keeping its date and project. */
  move(id: string, entry: NoteEntry, to: string): Promise<[Notebook, NoteEntry]>;
};

/** The default notebook: the inbox every unnamed note goes to. */
export const LOG = "Log";

const pad = (n: number) => String(n).padStart(2, "0");
/** Today on this Mac, as the notebook writes it. */
export const today = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

/** A notebook named exactly (any case), and the ones a word of whose name starts with what was
 * typed ("evaluation" is near "Evaluation H2 2026"). Nothing is ever picked by a guess. */
export function matchNotebook(books: Notebook[], wanted: string): { exact: Notebook | null; near: Notebook[] } {
  const want = wanted.trim().toLowerCase();
  const exact = books.find((b) => b.name.toLowerCase() === want || b.id === want) ?? null;
  const near = exact ? [] : books.filter((b) => b.name.toLowerCase().split(/\s+/).some((w) => w.startsWith(want)) || b.name.toLowerCase().startsWith(want));
  return { exact, near };
}

const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];

/** The Monday (YYYY-MM-DD) of the week a date is in. */
export function mondayOf(date: string): string {
  const d = new Date(`${date}T12:00:00`);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return today(d);
}

/**
 * Search across the work log (docs/V1.md V1-L6): every word must match the text, the project,
 * the notebook's name or the date. Dates match as "october", "oct 2026", "2026-04", "2026",
 * "this week" and "last week".
 */
export function matchesNote(entry: NoteEntry, notebook: string, query: string, now = new Date()): boolean {
  let q = query.toLowerCase().trim();
  if (!q) return true;
  const monday = mondayOf(entry.date);
  const thisWeek = mondayOf(today(now));
  const lastWeek = mondayOf(today(new Date(now.getTime() - 7 * 86_400_000)));
  if (/\bthis week\b/.test(q)) {
    if (monday !== thisWeek) return false;
    q = q.replace(/\bthis week\b/, " ");
  }
  if (/\blast week\b/.test(q)) {
    if (monday !== lastWeek) return false;
    q = q.replace(/\blast week\b/, " ");
  }
  const month = Number(entry.date.slice(5, 7));
  const words = `${entry.text} ${entry.project} ${notebook}`.toLowerCase();
  return q.split(/\s+/).filter(Boolean).every((w) => {
    if (words.includes(w) || entry.date.startsWith(w)) return true;
    const named = MONTHS.findIndex((m) => w.length >= 3 && m.startsWith(w));
    return named >= 0 && named + 1 === month;
  });
}

export class Notes {
  constructor(
    private readonly companion: Companion,
    private readonly store: NoteStore,
  ) {}

  async take(text: string, wanted: string | null): Promise<string | void> {
    if (!wanted) return this.write(LOG, text, true);
    const { exact, near } = matchNotebook(await this.store.list(), wanted);
    if (exact) return this.write(exact.id, text);
    return this.ask(wanted, near, text);
  }

  /** A quick capture, from a reminder like "every Friday at 4, note what I achieved for evaluation". */
  async capture(reminderText: string) {
    const books = await this.store.list();
    const lower = reminderText.toLowerCase();
    const named = books.filter((b) => b.name.toLowerCase().split(/\s+/).some((w) => w.length > 3 && lower.includes(w)));
    // Only a notebook the reminder clearly names; anything else goes to Log.
    const book = named.length === 1 ? named[0] : null;
    const bubble = this.companion.pet.bubble;
    bubble.prompt({
      who: `${this.companion.pet.name} · ${book ? book.name : "note"}`,
      placeholder: "What happened? One sentence is enough.",
      suggestions: [],
      preview: (text) => (text.trim() ? `Add to ${book ? book.name : LOG}` : ""),
      submit: (text) => this.take(text, book ? book.id : null),
    });
  }

  /** "Log it" on a finished session: the line is prefilled and editable, and goes to Log. */
  logWork(line: string) {
    const bubble = this.companion.pet.bubble;
    bubble.prompt({
      who: `${this.companion.pet.name} · ${LOG}`,
      placeholder: "What got done?",
      value: line,
      suggestions: [],
      preview: (text) => (text.trim() ? `Add to ${LOG}` : ""),
      submit: (text) => this.take(text, null),
    });
  }

  async create(name: string): Promise<string> {
    const book = await this.store.create(name);
    return `Notebook ${book.name} is ready. Say “note for ${book.name}: …” to add to it.`;
  }

  private async write(notebook: string, text: string, create = false): Promise<string> {
    const project = this.companion.pet.agents.list[0]?.project;
    const [book, entry] = await this.store.add(notebook, text, today(), project ? folder(project) : "", create);
    this.companion.pet.mind.react("write", 1.6);
    const reply = `Noted in ${book.name}.`;
    this.confirm(book, entry, reply);
    return reply;
  }

  /** "Noted in X", with Move and Undo; they stay until the card is closed (docs/V1.md V1-L4). */
  private confirm(book: Notebook, entry: NoteEntry, reply: string) {
    const bubble = this.companion.pet.bubble;
    const id = `note-added-${book.id}-${entry.line}`;
    bubble.show({
      id,
      who: `${this.companion.pet.name} · ${book.name}`,
      title: reply,
      lines: [entry.text],
      choices: [
        { label: "Undo", value: "undo" },
        { label: "Move…", value: "move" },
        { label: "OK", value: "ok", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close(id);
        if (value === "undo") {
          await this.store.remove(book.id, entry);
          return bubble.say("Removed.", 3);
        }
        if (value === "move") this.moveCard(book, entry);
      },
    });
  }

  /** Another notebook for a note just written. */
  private async moveCard(from: Notebook, entry: NoteEntry) {
    const bubble = this.companion.pet.bubble;
    const others = (await this.store.list()).filter((b) => b.id !== from.id).sort((a, b) => b.updated - a.updated).slice(0, 5);
    if (!others.length) return bubble.say(`${from.name} is your only notebook. Say “new notebook …” to start another.`, 6);
    bubble.show({
      id: "note-move",
      who: `${this.companion.pet.name} · move note`,
      title: "Move it to…",
      lines: [entry.text],
      choices: [{ label: "Cancel", value: "" }, ...others.map((b, i) => ({ label: b.name, value: b.id, primary: i === 0 }))],
      onChoose: async (to) => {
        bubble.close("note-move");
        if (!to) return;
        const [book] = await this.store.move(from.id, entry, to);
        bubble.say(`Moved to ${book.name}.`, 4);
      },
    });
  }

  /**
   * "note for X: …" where X isn't a notebook's exact name. One near match: confirm it. Several:
   * choose. None: start X, or keep it in Log. The text waits on the card meanwhile.
   */
  private ask(wanted: string, near: Notebook[], text: string) {
    const bubble = this.companion.pet.bubble;
    const choices = [
      { label: `Save to ${LOG}`, value: "\u0000log" },
      ...(near.length ? near.slice(0, 4).map((b, i) => ({ label: near.length === 1 ? `Add to ${b.name}` : b.name, value: b.id, primary: i === 0 })) : [{ label: `New notebook “${wanted}”`, value: "\u0000new", primary: true }]),
    ];
    bubble.show({
      id: "note-where",
      who: `${this.companion.pet.name} · note`,
      title: near.length === 1 ? `Add to ${near[0].name}?` : near.length ? "Which notebook?" : `There's no notebook called ${wanted}.`,
      lines: [text],
      choices,
      onChoose: async (value) => {
        bubble.close("note-where");
        const reply = value === "\u0000log" ? await this.write(LOG, text, true) : value === "\u0000new" ? await this.write(wanted, text, true) : await this.write(value, text);
        bubble.say(reply, 4);
      },
    });
  }
}

/** A browser-preview store: kept in memory, gone on reload. */
export function memoryNotes(): NoteStore {
  const books = new Map<string, { book: Notebook; entries: NoteEntry[] }>();
  const store: NoteStore = {
    list: async () => [...books.values()].map((b) => b.book),
    create: async (name) => {
      const id = name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
      const found = books.get(id) ?? { book: { id, name, count: 0, updated: Date.now() }, entries: [] };
      books.set(id, found);
      return found.book;
    },
    add: async (notebook, text, date, project, create) => {
      const id = notebook.toLowerCase().replace(/[^a-z0-9]+/g, "-");
      let found = books.get(id) ?? [...books.values()].find((b) => b.book.name.toLowerCase() === notebook.toLowerCase());
      if (!found && !create) throw new Error(`There's no notebook called ${notebook}.`);
      found ??= { book: { id, name: notebook, count: 0, updated: 0 }, entries: [] };
      books.set(found.book.id, found);
      const entry = { line: found.entries.length + 2, date, text, project };
      found.entries.push(entry);
      found.book.count = found.entries.length;
      found.book.updated = Date.now();
      return [found.book, entry];
    },
    remove: async (id, entry) => {
      const found = books.get(id);
      if (!found) return;
      found.entries = found.entries.filter((e) => e.line !== entry.line);
      found.book.count = found.entries.length;
    },
    move: async (id, entry, to) => {
      await store.remove(id, entry);
      return store.add(to, entry.text, entry.date, entry.project);
    },
  };
  return store;
}
