import { reminderRow } from "./reminders";
import { isScheduledReminder } from "../event-reminders";
import { problem } from "../voice";
import { sheet } from "./dialog";
import type { Notebook, NoteEntry } from "../notes";
import { icon } from "../icons";
import { badge } from "../states";
import { describeDue } from "../when";
import { invoke, type StoreProblem, type Waiting } from "./api";
import type { App } from "./app";
import { agentShort, button, h } from "./dom";
import { header, identity, petOf, requestTitle, sessionLabel, sessionRow } from "./ui";

// Home: what needs you first, then the work sessions the companion follows, reminders coming
// up, and a way to connect a tool when none is. No token counts, graphs or terminal output here.

/** One waiting thing as a card; requests open their review, offers and reminders answer here. */
export function attentionCard(app: App, w: Waiting) {
  const pet = petOf(app.state.status, w.pet);
  const source = w.meta.source;
  const second = source ? `${agentShort(source)}${w.meta.session ? ` · ${sessionLabel(w.meta.session)}` : ""}` : undefined;
  const card = h(
    "section",
    { class: "card attention" },
    h("div", { class: "row" }, identity(w.petName, w.meta.project || pet?.project || null, second, app.state.crew.main.look), badge("alert")),
    h("h2", { class: "request-title", text: w.meta.title || requestTitle(w) }),
  );
  const actions = h("div", { class: "actions" });
  if (w.meta.kind === "permission" || w.meta.kind === "question") {
    actions.append(button(["Review request", icon("next")], () => app.go("review", w.id), "primary"));
  } else {
    if (w.meta.kind === "reminder" && w.meta.due) card.append(h("p", { text: `Due ${describeDue(new Date(Number(w.meta.due)))}` }));
    else for (const line of w.lines) card.append(h("p", { text: line }));
    for (const choice of w.choices.filter((c) => !c.quiet))
      actions.append(
        button(
          choice.label,
          async (event) => {
            for (const b of actions.querySelectorAll("button")) b.disabled = true;
            (event.currentTarget as HTMLButtonElement).textContent = "Sending…";
            const result = await app.answer(w.id, choice.value);
            app.toast(result === "sent" ? "Done." : result === "gone" ? "That was already answered on the pet." : "Connection lost. Your answer hasn't been sent.", undefined, result === "failed");
            void app.refresh();
          },
          choice.primary ? "primary" : "",
        ),
      );
  }
  card.append(actions);
  return card;
}

/** What each store holds, for the damaged-file notice (docs/V1.md V1-S2). */
const STORE_NAMES: Record<string, string> = { "reminders.json": "reminders", "settings.json": "settings", "crew.json": "companion's name", "update-policy.json": "update safety policy" };

/** A file that couldn't be read at launch: it was kept aside, and the last good copy can come back. */
function storeNotices(app: App, into: HTMLElement) {
  void invoke<StoreProblem[]>("store_problems").then((problems) => {
    for (const p of problems) {
      const what = STORE_NAMES[p.file] ?? p.file;
      into.append(h("section", { class: "card attention", role: "alert" },
        h("h2", { text: `I couldn't read your ${what} file.` }),
        h("p", { text: `Your data is safe: the file was kept as it was${p.kept ? ` (${p.kept.split("/").pop()})` : ""}, and nothing will be written over it.` }),
        h("div", { class: "actions" },
          p.backup ? button("Restore last good copy", () => {
            const body = h("div", {}, h("p", { text: "Sidefolk will restore the last good backup and restart. The damaged file stays in your data folder for recovery." }));
            const dialog = sheet(`Restore ${what}?`, body);
            body.append(h("div", { class: "actions sheet-actions" }, button("Cancel", dialog.close), button("Restore and restart", () => void invoke("restore_store", { file: p.file }).catch((e) => app.toast(problem(e), undefined, true)), "primary")));
          }, "primary") : null,
          button([icon("folder"), "Show in Finder"], () => void invoke("reveal_data_dir", {})))));
    }
  }).catch(() => {});
}

export function renderHome(app: App) {
  const { status, reminders, integrations } = app.state;
  const waiting = status.waiting;
  const view = h("div", { class: "view home" },
    h("div", { class: "page-heading" }, h("div", {}, ...header("Today", new Date().toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" }))),
      button([icon("plus"), "Add reminder"], () => app.go("reminders", "new"), "primary")));
  const notices = h("div", { class: "notices" });
  view.append(notices);
  storeNotices(app, notices);
  // Connected but not listening: requests and sessions can't arrive, so say so first.
  if (integrations.claude_hooks && integrations.hook_error)
    notices.append(h("section", { class: "card attention", role: "alert" }, h("h2", { text: "I can't hear Claude Code right now." }), h("p", { text: problem(integrations.hook_error) })));
  const primary = h("div", { class: "home-primary" });
  const secondary = h("div", { class: "home-secondary" });
  view.append(h("div", { class: "home-grid" }, primary, secondary));
  const pending = reminders.filter(isScheduledReminder).sort((a, b) => a.due - b.due);
  const overdue = pending.filter((r) => r.due < Date.now());
  const agenda = (title: string, items: typeof reminders) => {
    primary.append(h("h2", { class: "section-title", text: title }));
    const list = h("section", { class: "card list", "aria-label": title });
    for (const r of items.slice(0, 4)) list.append(reminderRow(app, r, false, true));
    if (!items.length) list.append(h("p", { class: "muted", text: "Nothing coming up. A little space for your next small step." }));
    list.append(h("div", { class: "actions" }, button(items.length > 4 ? `All ${items.length} reminders` : "All reminders", () => app.go("reminders"), "quiet")));
    primary.append(list);
  };
  if (overdue.length) agenda("Overdue", overdue);
  if (waiting.length) primary.append(h("h2", { class: "section-title", text: "Needs you" }));
  else if (!overdue.length) primary.append(h("h2", { class: "section-title", text: "You're all caught up." }));
  for (const w of waiting.slice(0, 3)) primary.append(attentionCard(app, w));
  if (waiting.length > 3) primary.append(button(`See all ${waiting.length} requests`, () => app.go("requests"), "wide"));
  const tomorrow = new Date(); tomorrow.setHours(24, 0, 0, 0);
  agenda("Today’s reminders", pending.filter((r) => r.due >= Date.now() && r.due < tomorrow.getTime()));

  const sessions = status.pets.flatMap((p) => p.sessions);
  const connected = integrations.claude_hooks || integrations.codex_health !== "off" || integrations.codex_tools || integrations.claude_tools || sessions.length;
  if (connected) {
    const list = h("section", { class: "card list", "aria-label": "Running sessions" });
    for (const s of sessions.slice(0, 3)) list.append(sessionRow(app, s));
    if (!sessions.length) list.append(h("p", { class: "muted", text: "Nothing running right now." }));
    list.append(h("div", { class: "actions" }, button("All sessions", () => app.go("sessions"), "quiet")));
    secondary.append(h("h2", { class: "section-title", text: "Running sessions" }), list);
  }
  const notes = h("section", { class: "card list recent-log", "aria-label": "Recent log" }, h("p", { class: "muted", text: "Loading notebooks…" }));
  secondary.append(h("h2", { class: "section-title", text: "Recent log" }), notes);
  const loadRecent = async () => {
    const books = await invoke<Notebook[]>("list_notebooks");
    const pages = await Promise.all(books.map((book) => invoke<Notebook & { entries: NoteEntry[] }>("read_notebook", { id: book.id })));
    const recent = pages.flatMap((book) => book.entries.map((entry) => ({ book, entry }))).sort((a, b) => b.entry.date.localeCompare(a.entry.date) || b.book.updated - a.book.updated || b.entry.line - a.entry.line).slice(0, 3);
    notes.replaceChildren();
    for (const { book, entry } of recent) notes.append(button([
      h("span", { class: "meta", text: `${new Date(`${entry.date}T12:00:00`).toLocaleDateString([], { day: "numeric", month: "short" })} · ${book.name}` }),
      h("span", { class: "recent-writing", text: entry.text }),
    ], () => app.go("notes", book.id), "recent-entry"));
    if (!recent.length) notes.append(h("p", { class: "muted", text: "Keep an idea or a small win. Your dated notes collect here." }));
    notes.append(h("div", { class: "actions" }, button("Add note", () => app.go("notes"))));
  };
  void loadRecent().catch(() => notes.replaceChildren(h("p", { class: "muted", text: "Couldn't load your recent writing." }), button("Retry", () => void loadRecent().catch((e) => app.toast(problem(e), undefined, true)))));

  return view;
}
