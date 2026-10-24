import { icon, mark } from "../icons";
import { invoke } from "./api";
import type { App } from "./app";
import { PRESETS, lookAvailable, suggestions, type Comfort } from "./comfort";
import { button, h } from "./dom";
import { portraitImage } from "./portrait";
import { header } from "./ui";

// The first minute (creative-design/APP-UX.md): what Sidefolk is, choosing your comfort and
// your companion's name, and connecting a tool when you're ready. Tools show as connected only
// once their setup really succeeded; reminders work without any.

let step = 1;
let comfort: Comfort | null = null;
let name = "";
let unticked = new Set<string>();

function frame(...content: (HTMLElement | null)[]) {
  return h(
    "div",
    { class: "view welcome" },
    h("div", { class: "welcome-top" }, h("div", { class: "brand" }, mark(34), h("span", { class: "wordmark", text: "sidefolk" })), h("span", { class: "pill", text: `${step} of 3` })),
    ...content,
  );
}

function finish(app: App, then: string) {
  step = 1;
  comfort = null;
  void app.save({ onboarded: true }, "You're set. Everything here can change in Settings.").then(() => app.go(then));
}

export function renderWelcome(app: App) {
  const { settings, integrations, crew } = app.state;
  if (step === 1)
    return frame(
      ...header("A little help, by your side.", "See what needs you. Keep track of your work."),
      h(
        "section",
        { class: "card" },
        h("h2", { text: "Know when your tools need an answer." }),
        h("p", { text: "Connect an AI tool like Claude Code or Codex, give each project a familiar face, and keep reminders nearby. Companions live on your desktop and show what's happening; you decide everything that matters." }),
      ),
      h(
        "div",
        { class: "actions equal" },
        button("Try a demo", () => {
          void app.petAction({ action: "demo" }, "Watch your desktop: Pip shows a sample work session. Nothing is connected or run.");
        }),
        button(["Get started", icon("next")], () => ((step = 2), app.go("welcome")), "primary"),
      ),
    );

  if (step === 2) {
    const chosen = comfort ?? settings.comfort;
    const preset = PRESETS[chosen];
    if (!name) name = crew.main.name;
    const grid = h("div", { class: "choice-grid", role: "radiogroup", "aria-label": "Comfort" });
    for (const [key, p] of Object.entries(PRESETS) as [Comfort, (typeof PRESETS)[Comfort]][])
      grid.append(
        button(
          [lookAvailable(p.look) ? portraitImage(p.look, "", "thumb large", "full") : h("span", { class: "thumb placeholder" }), h("strong", { text: p.label }), h("small", { text: `${p.who} · ${p.describe}` })],
          () => {
            // Picking a preset suggests its companion's name, unless one was typed.
            if (name === PRESETS[comfort ?? settings.comfort].name || name === crew.main.name) name = p.name;
            comfort = key;
            unticked = new Set();
            app.redraw(true);
          },
          "choice tall",
          { role: "radio", "aria-checked": String(chosen === key) },
        ),
      );
    const field = h("input", { type: "text", id: "companion-name", maxlength: 24, value: name, autocomplete: "off", "aria-describedby": "companion-name-error" });
    field.addEventListener("input", () => (name = field.value));
    const error = h("p", { class: "field-error", id: "companion-name-error", role: "alert" });
    const list = suggestions(chosen, settings);
    const changes = h("div", { class: "notice" }, h("strong", { text: list.length ? `${preset.label} suggests` : `${preset.label} keeps your current settings.` }));
    for (const s of list) {
      const id = `welcome-${s.key}`;
      const check = h("input", { type: "checkbox", id, checked: !unticked.has(s.key) });
      check.addEventListener("change", () => (check.checked ? unticked.delete(s.key) : unticked.add(s.key)));
      changes.append(h("div", { class: "check" }, check, h("label", { for: id, text: s.label })));
    }
    if (lookAvailable(preset.look)) changes.append(h("p", { class: "muted", text: `Your main companion will look like ${preset.who}. Looks never change what an AI tool may do.` }));
    const form = h(
      "form",
      {},
      h("div", { class: "field" }, h("label", { for: "companion-name", text: "Name your companion" }), field, error),
      changes,
      h("div", { class: "actions equal" }, button("Back", () => ((step = 1), app.go("welcome"))), h("button", { type: "submit", class: "primary", text: "Apply and continue" })),
    );
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const clean = name.replace(/\s+/g, " ").trim();
      if (!clean) {
        error.textContent = "Enter a name. You can change it later.";
        return field.focus();
      }
      const change = { comfort: chosen };
      for (const s of list) if (!unticked.has(s.key)) Object.assign(change, s.change);
      if (!(await app.save(change, "Saved."))) return;
      if (clean !== crew.main.name) await app.petAction({ action: "rename", id: "main", name: clean });
      if (lookAvailable(preset.look)) await app.petAction({ action: "look", id: "main", look: preset.look });
      step = 3;
      app.go("welcome");
    });
    return frame(...header("Make yourself at home.", "Choose a style, then give your companion a name."), grid, form);
  }

  const tool = (title: string, key: "claude_hooks" | "codex_tools", action: string, what: string) => {
    const on = integrations[key];
    return h(
      "section",
      { class: "card row tool" },
      h("div", {}, h("strong", { text: title }), h("p", { class: "meta", text: on ? "Connected" : "Not connected" }), h("p", { class: "muted", text: what })),
      on
        ? h("span", { class: "pill on", text: "Connected" })
        : button("Set up…", () => {
            void invoke("tray_action", { action }).catch((e) => app.toast(String(e), undefined, true));
            app.toast("Read the dialog: it says which file changes. A backup is kept.");
          }),
    );
  };
  const any = integrations.claude_hooks || integrations.codex_tools;
  return frame(
    ...header("Connect when you're ready.", "Connect an AI tool to see its progress and requests here."),
    tool("Claude Code", "claude_hooks", "claude", "See its work sessions and answer its requests from a companion."),
    tool("Codex", "codex_tools", "tools-codex", "Let Codex sessions send you notes, questions and reminders."),
    h("p", { class: "notice", text: "Sidefolk explains each change before setup and keeps a backup of every file it edits." }),
    h(
      "div",
      { class: "actions equal" },
      button("Back", () => ((step = 2), app.go("welcome"))),
      any ? button("Finish", () => finish(app, "home"), "primary") : button("Use reminders for now", () => finish(app, "reminders"), "primary"),
    ),
  );
}
