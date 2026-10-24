import { icon } from "../icons";
import { badge } from "../states";
import { describeDue } from "../when";
import type { Waiting } from "./api";
import type { App } from "./app";
import { agentShort, button, h } from "./dom";
import { header, identity, petLine, petOf, petState, requestTitle, sessionLabel, sessionOf } from "./ui";

// Home: what needs you first, then each companion's plain status, reminders coming up, and a
// way to connect a tool when none is. No token counts, graphs or terminal output here.

export function greeting(now = new Date()) {
  const hour = now.getHours();
  return hour < 5 ? "Working late" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
}

/** One waiting thing as a card; requests open their review, offers and reminders answer here. */
export function attentionCard(app: App, w: Waiting) {
  const pet = petOf(app.state.status, w.pet);
  const source = w.meta.source;
  const second = source ? `${agentShort(source)}${w.meta.session ? ` · ${sessionLabel(w.meta.session)}` : ""}` : undefined;
  const card = h(
    "section",
    { class: "card attention" },
    h("div", { class: "row" }, identity(pet?.look ?? null, w.petName, w.meta.project || pet?.project || null, second), badge("alert")),
    h("h2", { class: "request-title", text: requestTitle(w) }),
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
  const lead =
    waiting.length === 0 ? "You're all caught up." : waiting.length === 1 ? "One thing needs your attention." : `${waiting.length} things need your attention.`;
  const view = h("div", { class: "view home" }, ...header(`${greeting()}.`, lead));

  for (const w of waiting.slice(0, 3)) view.append(attentionCard(app, w));
  if (waiting.length > 3) view.append(button(`See all ${waiting.length} requests`, () => app.go("requests"), "wide"));

  const connected = integrations.claude_hooks || integrations.codex_tools || integrations.claude_tools;
  if (!connected)
    view.append(
      h(
        "section",
        { class: "card notice-card" },
        h("h2", { text: "Connect an AI tool to see its progress and requests here." }),
        h("p", { text: "Claude Code and Codex aren't connected yet. Sidefolk explains each change before it makes it, and keeps a backup." }),
        h("div", { class: "actions" }, button("Connect a tool", () => app.go("settings", "tools"), "primary"), button("Add a reminder", () => app.go("reminders"))),
      ),
    );

  view.append(h("h2", { class: "section-title", text: "Your crew" }));
  const grid = h("div", { class: "grid" });
  for (const pet of status.pets) {
    const state = petState(pet, waiting);
    const session = sessionOf(pet);
    const card = h(
      "section",
      { class: "card pet-card" },
      h("div", { class: "row" }, identity(pet.look, pet.name, pet.project, pet.main ? "Main companion" : undefined), badge(state)),
      h("p", { text: petLine(pet) }),
    );
    const actions = h("div", { class: "actions" });
    if (session)
      actions.append(
        button(
          [icon(session.live ? "open" : "terminal"), session.live ? "Open session" : "Continue"],
          () => void app.openSession(session),
          "",
          { title: session.live ? "Bring this work session forward" : "Continue the last work session in a terminal" },
        ),
      );
    actions.append(button("Details", () => app.go("pet", pet.id), "quiet"));
    card.append(actions);
    grid.append(card);
  }
  view.append(grid);

  const next = reminders.filter((r) => !r.done).sort((a, b) => a.due - b.due).slice(0, 3);
  view.append(h("h2", { class: "section-title", text: "Coming up" }));
  const list = h("section", { class: "card list" });
  for (const r of next)
    list.append(h("div", { class: "row line" }, h("span", { class: "with-icon" }, icon("reminders"), h("strong", { text: r.text })), h("span", { class: "meta", text: describeDue(new Date(r.due)) })));
  if (!next.length) list.append(h("p", { class: "muted", text: "Nothing coming up. Add a reminder for your next small step." }));
  list.append(h("div", { class: "actions" }, button("Add reminder", () => app.go("reminders")), button(["Recent activity", icon("next")], () => app.go("activity"), "quiet")));
  view.append(list);
  return view;
}
