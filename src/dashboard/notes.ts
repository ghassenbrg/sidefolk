import { sheet } from "./dialog";
import { icon } from "../icons";
import { LOG, matchesNote, mondayOf, today, type NoteEntry, type Notebook } from "../notes";
import { invoke, listen } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { back, empty, header } from "./ui";

// The work log (docs/V1.md §5): Log and the notebooks you name, one dated timeline across them,
// search by text or date, edit, move, Markdown export. The files are plain Markdown in the data
// folder, so they open anywhere; this page is one way in, the companion ("note: …") the other.

type Page = Notebook & { entries: NoteEntry[]; path: string };

let changed: (() => void) | null = null;
listen("notes-changed", () => changed?.());

const longDay = (date: string) =>
  new Date(`${date}T12:00:00`).toLocaleDateString([], {
    weekday: "short",
    day: "numeric",
    month: "long",
    year: "numeric",
  });

export function markdown(page: Pick<Page, "name" | "entries">) {
  return `# ${page.name}\n\n${page.entries.map((e) => `- ${e.date} — ${e.text}${e.project ? ` _(${e.project})_` : ""}`).join("\n")}\n`;
}

export function renderNotes(app: App, arg: string) {
  const view = h("div", { class: "view notes" });
  app.live(() => {});
  const [id] = arg.split(":");
  if (id && id !== "new") void notebook(app, view, id);
  else void list(app, view, id === "new");
  return view;
}

/** Log first (the inbox), then the most recently changed. */
const shelfOrder = (books: Notebook[]) => [...books].sort((a, b) => Number(b.name === LOG) - Number(a.name === LOG) || b.updated - a.updated);

/** Entries grouped by the week they're dated in, newest week first (docs/V1.md V1-L5). */
function timeline(app: App, hits: { p: Page; e: NoteEntry }[]) {
  const weeks = new Map<string, { p: Page; e: NoteEntry }[]>();
  for (const hit of [...hits].sort((a, b) => b.e.date.localeCompare(a.e.date))) weeks.set(mondayOf(hit.e.date), [...(weeks.get(mondayOf(hit.e.date)) ?? []), hit]);
  const nodes: HTMLElement[] = [];
  for (const [monday, items] of weeks) {
    nodes.push(h("h3", { class: "section-title", text: `Week of ${new Date(`${monday}T12:00:00`).toLocaleDateString([], { day: "numeric", month: "long", year: "numeric" })}` }));
    nodes.push(h("div", { class: "card list" }, ...items.map(({ p, e }) => row(app, p, e, undefined, true))));
  }
  return nodes;
}

async function list(app: App, view: HTMLElement, focus: boolean) {
  const books = shelfOrder(await invoke<Notebook[]>("list_notebooks"));
  const pages = await Promise.all(books.map((b) => invoke<Page>("read_notebook", { id: b.id }).catch(() => null))).then((all) => all.filter((p): p is Page => !!p));
  const fill = () => void list(app, view, false);
  changed = fill;
  app.onLeave(() => (changed = null));

  const name = h("input", {
    type: "text",
    id: "notebook-name",
    maxlength: 60,
    autocomplete: "off",
    placeholder: "Evaluation H2 2026",
  });
  const create = h(
    "form",
    { class: "card inline-form", "aria-label": "New notebook" },
    h("div", { class: "field" }, h("label", { for: name.id, text: "New notebook" }), name),
    h("button", { type: "submit", class: "primary", text: "Create" }),
  );
  let editor: { close: () => void } | null = null;
  const openCreate = () => { editor = sheet("New notebook", create); name.focus(); };
  create.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!name.value.trim()) return name.focus();
    const submit = create.querySelector<HTMLButtonElement>("button[type=submit]")!;
    if (submit.disabled) return;
    submit.disabled = true;
    try {
      const book = await invoke<Notebook>("create_notebook", {
        name: name.value,
      });
      editor?.close();
      app.go("notes", book.id);
    } catch (error) {
      app.toast(String(error), undefined, true);
    } finally { submit.disabled = false; }
  });

  // One search and one timeline over every notebook; words match the text, project, notebook
  // and the date ("evaluation october", "last week", "2026-04").
  const search = h("input", {
    type: "search",
    id: "notes-search",
    placeholder: "Search notes, notebooks or dates (“october”, “last week”)",
    autocomplete: "off",
    "aria-label": "Search all notes",
  });
  const only = h("select", { id: "notes-notebook", "aria-label": "Show notes from" }, h("option", { value: "", text: "All notebooks" }), ...pages.map((p) => h("option", { value: p.id, text: p.name })));
  const stream = h("section", { "aria-label": "All entries", "aria-live": "polite" });
  const draw = () => {
    const q = search.value.trim();
    const hits = pages.filter((p) => !only.value || p.id === only.value).flatMap((p) => p.entries.filter((e) => matchesNote(e, p.name, q)).map((e) => ({ p, e })));
    stream.replaceChildren(...(hits.length ? timeline(app, hits.slice(0, 300)) : [h("p", { class: "muted", text: q ? "Nothing matches." : "No notes yet." })]));
  };
  search.addEventListener("input", draw);
  only.addEventListener("change", draw);

  const shelf = h("section", { class: "card list", "aria-label": "Notebooks" });
  for (const b of books)
    shelf.append(
      h(
        "div",
        { class: "row line" },
        h(
          "div",
          { class: "identity-text" },
          h("strong", {}, icon("notes"), " ", b.name),
          h("span", {
            class: "meta",
            text: `${b.name === LOG ? "Where notes go when you don't name a notebook · " : ""}${b.count} ${b.count === 1 ? "note" : "notes"}${b.updated ? ` · changed ${new Date(b.updated).toLocaleDateString()}` : ""}`,
          }),
        ),
        button("Open", () => app.go("notes", b.id), "small"),
      ),
    );

  view.replaceChildren(
    ...[
      h("div", { class: "page-heading" }, h("div", {}, ...header("Work log", "What you got done, dated and kept.")), h("div", { class: "inline" }, button("Your week", () => app.go("week")), button([icon("plus"), "New notebook"], openCreate, "primary"))),
      books.length ? shelf : empty("Nothing logged yet", "Tell your companion “note: …” and it goes to your Log, or “note for evaluation: …” to start a notebook."),
      books.length ? h("h2", { class: "section-title", text: "All entries" }) : null,
      books.length ? h("div", { class: "inline notes-filters" }, h("div", { class: "field grow" }, search), only) : null,
      books.length ? stream : null,
    ].filter((n): n is HTMLElement => !!n),
  );
  draw();
  if (focus) requestAnimationFrame(openCreate);
}

async function notebook(app: App, view: HTMLElement, id: string) {
  let page: Page;
  try {
    page = await invoke<Page>("read_notebook", { id });
  } catch (error) {
    view.replaceChildren(
      back("Notes", () => app.go("notes")),
      empty("Notebook not found", String(error)),
    );
    return;
  }
  const fill = async () => {
    try { page = await invoke<Page>("read_notebook", { id }); draw(); }
    catch (error) { app.toast(String(error), undefined, true); }
  };
  changed = () => void fill();
  app.onLeave(() => (changed = null));

  const text = h("textarea", {
    id: "note-text",
    rows: 2,
    maxlength: 2000,
    placeholder: "Shipped the login migration; errors down 40%",
  });
  const add = h(
    "form",
    { class: "card", "aria-label": `Add to ${page.name}` },
    h("label", {
      for: text.id,
      text: `Add to ${page.name}`,
      class: "field-label",
    }),
    text,
    h("div", { class: "actions" }, h("span", { class: "hint", text: `Dated ${longDay(today())}.` }), h("button", { type: "submit", class: "primary", text: "Add note" })),
  );
  add.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!text.value.trim() || text.disabled) return text.focus();
    text.disabled = true;
    try {
      await invoke("add_note", {
        notebook: page.id,
        text: text.value,
        date: today(),
        project: null,
      });
      text.value = "";
      await fill();
    } catch (error) {
      app.toast(String(error), undefined, true);
    } finally { text.disabled = false; }
  });
  text.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) add.requestSubmit();
  });

  const search = h("input", {
    type: "search",
    placeholder: "Search this notebook",
    autocomplete: "off",
    "aria-label": "Search this notebook",
  });
  const entries = h("section", { class: "card list", "aria-label": "Notes" });
  const draw = () => {
    // Incoming notes must not replace a half-written edit. Refresh after Save or Cancel.
    if (entries.querySelector(".note.editing")) return;
    const q = search.value.trim().toLowerCase();
    const shown = page.entries.filter((e) => matchesNote(e, page.name, q)).reverse();
    entries.replaceChildren(
      ...(shown.length
        ? shown.map((e) => row(app, page, e, draw))
        : [
            h("p", {
              class: "muted",
              text: page.entries.length ? "Nothing matches." : "No notes yet. Add your first one below.",
            }),
          ]),
    );
  };
  search.addEventListener("input", draw);
  draw();

  view.replaceChildren(
    ...[
      back("Work log", () => app.go("notes")),
      h("div", { class: "page-heading" }, h("div", {}, ...header(page.name, "Dated notes, collected over time.")), button([icon("plus"), "New note"], () => { text.scrollIntoView({ block: "center" }); text.focus(); }, "primary")),
      h(
        "div",
        { class: "actions" },
        button(
          [icon("copy"), "Copy as Markdown"],
          () =>
            void navigator.clipboard.writeText(markdown(page)).then(
              () => app.toast("Copied. Paste it into a doc or an email."),
              () => app.toast("Couldn't copy.", undefined, true),
            ),
        ),
        button([icon("folder"), "Show in Finder"], () => void invoke("reveal_data_dir", { notes: true }).catch((e) => app.toast(String(e), undefined, true))),
      ),
      page.entries.length > 5 ? h("div", { class: "field" }, search) : null,
      entries,
      add,
    ].filter((n): n is HTMLElement => !!n),
  );
  const content = h("div", { class: "notebook-content" }, ...Array.from(view.childNodes));
  const sidebar = h("aside", { class: "notebook-sidebar", "aria-label": "Notebooks" });
  view.append(h("div", { class: "notebook-layout" }, sidebar, content));
  void invoke<Notebook[]>("list_notebooks").then((books) => {
    for (const book of books) sidebar.append(button([icon("notes"), book.name], () => app.go("notes", book.id), "", { "aria-current": book.id === id ? "page" : undefined }));
    sidebar.append(button([icon("plus"), "New notebook"], () => app.go("notes", "new"), "quiet"));
  }).catch(() => sidebar.append(button("All notebooks", () => app.go("notes"))));

}

/** Another notebook for an entry; it keeps its date and project. */
async function move(app: App, page: Page, entry: NoteEntry) {
  const books = shelfOrder(await invoke<Notebook[]>("list_notebooks")).filter((b) => b.id !== page.id);
  if (!books.length) return app.toast(`${page.name} is your only notebook. Create another to move notes into it.`);
  const to = h("select", { id: "move-to" }, ...books.map((b) => h("option", { value: b.id, text: b.name })));
  const form = h("form", { class: "card", "aria-label": "Move note" }, h("p", { class: "note-text", text: entry.text }), h("div", { class: "field" }, h("label", { for: to.id, text: "Move to" }), to));
  const editor = sheet("Move note", form);
  form.append(h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close), h("button", { type: "submit", class: "primary", text: "Move" })));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const [book] = await invoke<[Notebook, NoteEntry]>("move_note", { id: page.id, entry, to: to.value });
      editor.close();
      app.toast(`Moved to ${book.name}.`);
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  });
}

function row(app: App, page: Page, entry: NoteEntry, redraw?: () => void, withNotebook = false): HTMLElement {
  const node = h(
    "div",
    { class: "row line note" },
    h(
      "div",
      { class: "identity-text" },
      h("span", {
        class: "meta",
        text: `${longDay(entry.date)}${withNotebook ? ` · ${page.name}` : ""}${entry.project ? ` · ${entry.project}` : ""}`,
      }),
      h("p", { class: "note-text", text: entry.text }),
    ),
    h(
      "div",
      { class: "inline" },
      button("Edit", () => edit(), "small", { "aria-label": `Edit note from ${longDay(entry.date)}` }),
      button("Move…", () => void move(app, page, entry), "small", { "aria-label": `Move note from ${longDay(entry.date)}` }),
      button(
        "Delete",
        async () => {
          try {
            await invoke("remove_note", { id: page.id, entry });
            app.toast("Note deleted.", {
              label: "Undo",
              run: () => void invoke("restore_note", { id: page.id, entry }),
            });
          } catch (error) {
            app.toast(String(error), undefined, true);
          }
        },
        "small",
      ),
    ),
  );
  const edit = () => {
    const field = h("textarea", {
      rows: 3,
      maxlength: 2000,
      "aria-label": "Edit note",
    });
    field.value = entry.text;
    const form = h(
      "form",
      { class: "row line note editing" },
      field,
      h(
        "div",
        { class: "inline" },
        button("Cancel", () => { form.replaceWith(row(app, page, entry, redraw)); redraw?.(); }, "small"),
        h("button", { type: "submit", class: "small primary", text: "Save" }),
      ),
    );
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (field.disabled) return;
      field.disabled = true;
      try {
        await invoke("edit_note", { id: page.id, entry, text: field.value });
        form.replaceWith(row(app, page, { ...entry, text: field.value }, redraw));
        redraw?.();
        app.toast("Saved.");
      } catch (error) {
        app.toast(String(error), undefined, true);
      }
      field.disabled = false;
    });
    node.replaceWith(form);
    field.focus();
  };
  return node;
}

