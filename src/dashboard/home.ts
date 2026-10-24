import type { Notebook } from "../notes";
import { icon } from "../icons";
import { badge } from "../states";
import { describeDue } from "../when";
import type { CalendarEvent } from "../calendar";
import { invoke, type Waiting } from "./api";
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
    h("div", { class: "row" }, identity(w.petName, w.meta.project || pet?.project || null, second), badge("alert")),
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

export function renderHome(app: App) {
  const { status, reminders, integrations } = app.state;
  const waiting = status.waiting;
  const view = h("div", { class: "view home" },
    h("div", { class: "page-heading" }, h("div", {}, ...header("Today", new Date().toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" }))),
      button([icon("plus"), "Add reminder"], () => app.go("reminders", "new"), "primary")));
  const primary = h("div", { class: "home-primary" });
  const secondary = h("div", { class: "home-secondary" });
  view.append(h("div", { class: "home-grid" }, primary, secondary));
  primary.append(h("h2", { class: "section-title", text: waiting.length ? "Needs you" : "You're all caught up." }));
  for (const w of waiting.slice(0, 3)) primary.append(attentionCard(app, w));
  if (waiting.length > 3) primary.append(button(`See all ${waiting.length} requests`, () => app.go("requests"), "wide"));

  primary.append(h("h2", { class: "section-title", text: "Coming up" }));
  const upcoming = h("section", { class: "card list", "aria-label": "Coming up" });
  const next = reminders.filter((r) => !r.done).sort((a, b) => a.due - b.due).slice(0, 4);
  for (const r of next) upcoming.append(button([
    h("span", { class: "with-icon" }, icon("reminders"), h("strong", { text: r.text })),
    h("span", { class: "meta", text: describeDue(new Date(r.due)) }), icon("chevron"),
  ], () => app.go("reminders", r.id), "list-button"));
  const emptyUpcoming = h("p", { class: "muted", text: "Nothing coming up. A little space for your next small step." });
  if (!next.length) upcoming.append(emptyUpcoming);
  if (app.state.settings.calendar_heads_up)
    void invoke<CalendarEvent[]>("upcoming_events", { hours: 8 }).then((events) => {
      if (events.length) emptyUpcoming.remove();
      for (const e of events.slice(0, 3).reverse()) upcoming.prepend(h("div", { class: "row line" },
        h("span", { class: "with-icon" }, icon("activity"), h("strong", { text: e.title })),
        h("div", { class: "inline" }, h("span", { class: "meta", text: new Date(e.start).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) }),
          e.link ? button("Join", () => void invoke("open_target", { target: e.link }).catch((error) => app.toast(String(error), undefined, true))) : null)));
    }).catch(() => {});
  upcoming.append(h("div", { class: "actions" }, button(["All reminders", icon("next")], () => app.go("reminders"), "quiet")));
  primary.append(upcoming);

  const sessions = status.pets.flatMap((p) => p.sessions);
  const connected = integrations.claude_hooks || integrations.codex_tools || integrations.claude_tools || sessions.length;
  if (connected) {
    const list = h("section", { class: "card list", "aria-label": "Work sessions" });
    for (const s of sessions.slice(0, 3)) list.append(sessionRow(app, s, true));
    if (!sessions.length) list.append(h("p", { class: "muted", text: "Nothing running right now." }));
    list.append(h("div", { class: "actions" }, button("All sessions", () => app.go("sessions"), "quiet")));
    secondary.append(h("h2", { class: "section-title", text: "Work sessions" }), list);
  }
  const notes = h("section", { class: "card list", "aria-label": "Recent notes" }, h("p", { class: "muted", text: "Loading notebooks…" }));
  secondary.append(h("h2", { class: "section-title", text: "Recent notes" }), notes);
  void invoke<Notebook[]>("list_notebooks").then((books) => {
    notes.replaceChildren();
    for (const book of [...books].sort((a, b) => b.updated - a.updated).slice(0, 3)) notes.append(button([
      h("span", { class: "with-icon" }, icon("notes"), h("span", {}, h("strong", { text: book.name }), h("span", { class: "meta", text: `${book.count} ${book.count === 1 ? "note" : "notes"}` }))), icon("chevron"),
    ], () => app.go("notes", book.id), "list-button"));
    if (!books.length) notes.append(h("p", { class: "muted", text: "Keep an idea or a small win. Your dated notes collect here." }));
    notes.append(h("div", { class: "actions" }, button("Add note", () => app.go("notes"))));
  }).catch(() => notes.replaceChildren(h("p", { class: "muted", text: "Couldn't load notebooks." }), button("Open Notes", () => app.go("notes"))));
  return view;
}
