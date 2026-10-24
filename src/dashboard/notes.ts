import { icon } from "../icons";
import { today, type NoteEntry, type Notebook } from "../notes";
import { invoke, listen } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { back, empty, header } from "./ui";

// Notes: notebooks you name, dated entries, search, edit, Markdown export. The files are plain
// Markdown in the data folder, so they open anywhere; this page is one way in, the companion
// ("note for evaluation: …") the other.

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

async function list(app: App, view: HTMLElement, focus: boolean) {
  const books = await invoke<Notebook[]>("list_notebooks");
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
  create.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!name.value.trim()) return name.focus();
    try {
      const book = await invoke<Notebook>("create_notebook", {
        name: name.value,
      });
      app.go("notes", book.id);
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  });

  const search = h("input", {
    type: "search",
    id: "notes-search",
    placeholder: "Search all notebooks",
    autocomplete: "off",
    "aria-label": "Search all notebooks",
  });
  const results = h("section", {
    "aria-label": "Search results",
    "aria-live": "polite",
  });
  let pages: Page[] | null = null;
  search.addEventListener("input", async () => {
    const q = search.value.trim().toLowerCase();
    if (!q) return results.replaceChildren();
    pages ??= await Promise.all(books.map((b) => invoke<Page>("read_notebook", { id: b.id })));
    const hits = pages.flatMap((p) => p.entries.filter((e) => e.text.toLowerCase().includes(q) || e.project.toLowerCase().includes(q)).map((e) => ({ p, e })));
    results.replaceChildren(
      hits.length
        ? h(
            "div",
            { class: "card list" },
            ...hits.slice(0, 50).map(({ p, e }) =>
              h(
                "div",
                { class: "row line" },
                h(
                  "div",
                  { class: "identity-text" },
                  h("strong", { text: e.text }),
                  h("span", {
                    class: "meta",
                    text: `${p.name} · ${longDay(e.date)}`,
                  }),
                ),
                button("Open", () => app.go("notes", p.id), "small"),
              ),
            ),
          )
        : h("p", { class: "muted", text: "Nothing matches." }),
    );
  });

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
            text: `${b.count} ${b.count === 1 ? "note" : "notes"}${b.updated ? ` · changed ${new Date(b.updated).toLocaleDateString()}` : ""}`,
          }),
        ),
        button("Open", () => app.go("notes", b.id), "small"),
      ),
    );

  view.replaceChildren(
    ...[
      ...header("Notes", "Notebooks that collect over time. Tell your companion “note for evaluation: shipped the login migration” and it lands here, dated."),
      books.length ? h("div", { class: "field" }, search) : null,
      results,
      books.length ? shelf : empty("No notebooks yet", "Create one here, or tell your companion “note for ideas: …” and it starts one for you."),
      create,
    ].filter((n): n is HTMLElement => !!n),
  );
  if (focus) name.focus();
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
  changed = () => void notebook(app, view, id);
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
    if (!text.value.trim()) return text.focus();
    try {
      await invoke("add_note", {
        notebook: page.id,
        text: text.value,
        date: today(),
        project: null,
      });
      text.value = "";
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  });
  text.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) add.requestSubmit();
  });

  const draft = h("div", { class: "draft", "aria-live": "polite" });
  const search = h("input", {
    type: "search",
    placeholder: "Search this notebook",
    autocomplete: "off",
    "aria-label": "Search this notebook",
  });
  const entries = h("section", { class: "card list", "aria-label": "Notes" });
  const draw = () => {
    const q = search.value.trim().toLowerCase();
    const shown = page.entries.filter((e) => !q || e.text.toLowerCase().includes(q) || e.project.toLowerCase().includes(q)).reverse();
    entries.replaceChildren(
      ...(shown.length
        ? shown.map((e) => row(app, page, e))
        : [
            h("p", {
              class: "muted",
              text: page.entries.length ? "Nothing matches." : "No notes yet. Add the first one above.",
            }),
          ]),
    );
  };
  search.addEventListener("input", draw);
  draw();

  view.replaceChildren(
    ...[
      back("Notes", () => app.go("notes")),
      ...header(page.name, `${page.entries.length} ${page.entries.length === 1 ? "note" : "notes"}, newest first. Saved as Markdown: ${page.path.replace(/^\/Users\/[^/]+/, "~")}`),
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
        page.entries.length ? button("Draft a summary…", () => void draftPanel(app, page, draft)) : null,
      ),
      draft,
      add,
      page.entries.length > 5 ? h("div", { class: "field" }, search) : null,
      entries,
    ].filter((n): n is HTMLElement => !!n),
  );
}

function row(app: App, page: Page, entry: NoteEntry): HTMLElement {
  const node = h(
    "div",
    { class: "row line note" },
    h(
      "div",
      { class: "identity-text" },
      h("span", {
        class: "meta",
        text: `${longDay(entry.date)}${entry.project ? ` · ${entry.project}` : ""}`,
      }),
      h("p", { class: "note-text", text: entry.text }),
    ),
    h(
      "div",
      { class: "inline" },
      button("Edit", () => edit(), "small"),
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
        button("Cancel", () => form.replaceWith(row(app, page, entry)), "small"),
        h("button", { type: "submit", class: "small primary", text: "Save" }),
      ),
    );
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      try {
        await invoke("edit_note", { id: page.id, entry, text: field.value });
        app.toast("Saved.");
      } catch (error) {
        app.toast(String(error), undefined, true);
      }
    });
    node.replaceWith(form);
    field.focus();
  };
  return node;
}

const TOOL_NAMES: Record<string, string> = { claude: "Claude Code", codex: "Codex" };

/** AI only when asked, and said plainly: which tool, what it gets, that it uses your plan. */
async function draftPanel(app: App, page: Page, box: HTMLElement) {
  const tools = await invoke<string[]>("draft_tools").catch(() => [] as string[]);
  if (!tools.length) {
    box.replaceChildren(h("section", { class: "card" }, h("p", { text: "Drafting needs Claude Code or Codex installed on this Mac. Your notes stay as they are either way." })));
    return;
  }
  const run = async (tool: string) => {
    box.replaceChildren(h("section", { class: "card" }, h("p", { class: "muted", text: `${TOOL_NAMES[tool]} is drafting from ${page.entries.length} notes… This can take a minute.` })));
    try {
      const text = await invoke<string>("draft_summary", { id: page.id, tool });
      box.replaceChildren(
        h(
          "section",
          { class: "card", "aria-label": "Draft" },
          h("h2", { text: `Draft by ${TOOL_NAMES[tool]}` }),
          h("pre", { class: "draft-text", text }),
          h(
            "div",
            { class: "actions" },
            button([icon("copy"), "Copy"], () => void navigator.clipboard.writeText(text).then(() => app.toast("Copied."))),
            button("Close", () => box.replaceChildren()),
          ),
        ),
      );
    } catch (error) {
      box.replaceChildren(h("section", { class: "card" }, h("p", { text: String(error) }), button("Close", () => box.replaceChildren())));
    }
  };
  box.replaceChildren(
    h(
      "section",
      { class: "card" },
      h("h2", { text: "Draft a summary with AI" }),
      h("p", { class: "muted", text: `Sends this notebook's ${page.entries.length} notes, and nothing else, to your own AI tool. It groups them by theme with dates and uses your plan's quota. Nothing changes in the notebook.` }),
      h("div", { class: "actions" }, button("Cancel", () => box.replaceChildren()), ...tools.map((tool, i) => button(`Draft with ${TOOL_NAMES[tool]}`, () => void run(tool), i === 0 ? "primary" : ""))),
    ),
  );
}
