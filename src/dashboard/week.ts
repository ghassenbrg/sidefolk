import { icon } from "../icons";
import { mondayOf, today, type NoteEntry, type Notebook } from "../notes";
import type { Reminder } from "../reminders";
import { invoke } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { back, empty, header } from "./ui";

// Your week (docs/V1.md V1-L8): this week's notes from every notebook and the reminders you
// completed, as a plain dated list to copy into an evaluation or a status update. No AI.

type Page = Notebook & { entries: NoteEntry[] };
export type WeekItem = { date: string; text: string; where: string };

/** The week's notes and completed reminders, oldest first. `monday` is YYYY-MM-DD. */
export function weekItems(pages: Page[], reminders: Reminder[], monday: string): WeekItem[] {
  const start = new Date(`${monday}T00:00:00`).getTime();
  const end = start + 7 * 86_400_000;
  const notes = pages.flatMap((p) => p.entries.filter((e) => mondayOf(e.date) === monday).map((e) => ({ date: e.date, text: e.text, where: e.project ? `${p.name} · ${e.project}` : p.name })));
  const done = reminders.flatMap((r) =>
    (r.history ?? []).filter((x) => x.action === "Completed" && x.at >= start && x.at < end).map((x) => ({ date: today(new Date(x.at)), text: r.text, where: "Reminder done" })),
  );
  return [...notes, ...done].sort((a, b) => a.date.localeCompare(b.date));
}

export function weekMarkdown(monday: string, items: WeekItem[]) {
  return `# Week of ${monday}\n\n${items.map((i) => `- ${i.date} — ${i.text} _(${i.where})_`).join("\n")}\n`;
}

export function renderWeek(app: App) {
  const view = h("div", { class: "view week" });
  void fill(app, view);
  return view;
}

async function fill(app: App, view: HTMLElement) {
  const monday = mondayOf(today());
  const books = await invoke<Notebook[]>("list_notebooks").catch(() => [] as Notebook[]);
  const pages = (await Promise.all(books.map((b) => invoke<Page>("read_notebook", { id: b.id }).catch(() => null)))).filter((p): p is Page => !!p);
  const items = weekItems(pages, app.state.reminders, monday);
  const list = h("section", { class: "card list", "aria-label": "This week" });
  for (const i of items)
    list.append(h("div", { class: "row line" }, h("div", { class: "identity-text" }, h("span", { class: "meta", text: `${new Date(`${i.date}T12:00:00`).toLocaleDateString([], { weekday: "long", day: "numeric", month: "short" })} · ${i.where}` }), h("p", { class: "note-text", text: i.text }))));
  view.replaceChildren(
    back("Work log", () => app.go("notes")),
    h(
      "div",
      { class: "page-heading" },
      h("div", {}, ...header("Your week", `Since Monday ${new Date(`${monday}T12:00:00`).toLocaleDateString([], { day: "numeric", month: "long" })}.`)),
      items.length
        ? button([icon("copy"), "Copy as Markdown"], () =>
            void navigator.clipboard.writeText(weekMarkdown(monday, items)).then(
              () => app.toast("Copied. Paste it into your evaluation or an update."),
              () => app.toast("Couldn't copy.", undefined, true),
            ), "primary")
        : null,
    ),
    items.length ? list : empty("Nothing logged this week yet", "Tell your companion “note: …” when something goes well. It shows up here, dated."),
  );
}
