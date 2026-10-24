import { folder } from "./agents";
import type { Companion } from "./companion";

// Notes taken in one sentence ("note for evaluation: shipped the login migration"): dated,
// tagged with the project you're working in, written to a Markdown notebook (notes.rs).

/** Mirrors `Notebook` and `Entry` in src-tauri/src/notes.rs. */
export type Notebook = { id: string; name: string; count: number; updated: number };
export type NoteEntry = { line: number; date: string; text: string; project: string };

export type NoteStore = {
  list(): Promise<Notebook[]>;
  create(name: string): Promise<Notebook>;
  add(notebook: string, text: string, date: string, project: string, create?: boolean): Promise<[Notebook, NoteEntry]>;
  remove(id: string, entry: NoteEntry): Promise<void>;
};

const pad = (n: number) => String(n).padStart(2, "0");
/** Today on this Mac, as the notebook writes it. */
export const today = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

/** "evaluation" finds "Evaluation H2 2026"; the closest name wins, an exact one always. */
export function matchNotebook(books: Notebook[], wanted: string): Notebook | null {
  const want = wanted.trim().toLowerCase();
  const exact = books.find((b) => b.name.toLowerCase() === want || b.id === want);
  if (exact) return exact;
  const words = books.filter((b) => b.name.toLowerCase().split(/\s+/).some((w) => w.startsWith(want)) || b.name.toLowerCase().startsWith(want));
  return words.length === 1 ? words[0] : (words.sort((a, b) => b.updated - a.updated)[0] ?? null);
}

export class Notes {
  constructor(
    private readonly companion: Companion,
    private readonly store: NoteStore,
  ) {}

  async take(text: string, wanted: string | null): Promise<string | void> {
    const books = await this.store.list();
    if (wanted) {
      const book = matchNotebook(books, wanted);
      if (book) return this.write(book.id, text);
      return this.offerNew(wanted, text);
    }
    if (books.length === 0) return this.write("Notes", text, true);
    if (books.length === 1) return this.write(books[0].id, text);
    return this.ask(books, text);
  }

  /** A quick capture, from a reminder like "every Friday at 4, note what I achieved for evaluation". */
  async capture(reminderText: string) {
    const books = await this.store.list();
    const lower = reminderText.toLowerCase();
    const book = books.find((b) => b.name.toLowerCase().split(/\s+/).some((w) => w.length > 3 && lower.includes(w)));
    const bubble = this.companion.pet.bubble;
    bubble.prompt({
      who: `${this.companion.pet.name} · ${book ? book.name : "note"}`,
      placeholder: "What happened? One sentence is enough.",
      suggestions: [],
      preview: (text) => (text.trim() ? (book ? `Add to ${book.name}` : "Add a note (I'll ask which notebook)") : ""),
      submit: (text) => this.take(text, book ? book.id : null),
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

  /** The note, with Undo for a few seconds. */
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
        { label: "OK", value: "ok", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close(id);
        if (value !== "undo") return;
        await this.store.remove(book.id, entry);
        bubble.say("Removed.", 3);
      },
    });
    setTimeout(() => bubble.close(id), 8_000);
  }

  /** Several notebooks and none named: one click picks (most recent first). */
  private ask(books: Notebook[], text: string) {
    const bubble = this.companion.pet.bubble;
    const recent = [...books].sort((a, b) => b.updated - a.updated).slice(0, 4);
    bubble.show({
      id: "note-where",
      who: `${this.companion.pet.name} · note`,
      title: "Which notebook?",
      lines: [text],
      choices: recent.map((b, i) => ({ label: b.name, value: b.id, primary: i === 0 })),
      onChoose: async (value) => {
        bubble.close("note-where");
        bubble.say(await this.write(value, text), 4);
      },
    });
  }

  private offerNew(name: string, text: string) {
    const bubble = this.companion.pet.bubble;
    bubble.show({
      id: "note-new-book",
      who: `${this.companion.pet.name} · note`,
      title: `There's no notebook called ${name}. Start it?`,
      lines: [text],
      choices: [
        { label: "Cancel", value: "cancel" },
        { label: `Start ${name}`, value: "create", primary: true },
      ],
      onChoose: async (value) => {
        bubble.close("note-new-book");
        if (value === "create") bubble.say(await this.write(name, text, true), 4);
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
  };
  return store;
}
