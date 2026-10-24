import { sheet } from "./dialog";
import { icon } from "../icons";
import { badge } from "../states";
import { invoke } from "./api";
import type { App } from "./app";
import { COLORS, colorName } from "../worker-colors";
import { cachedCharacters, characters } from "./characters";
import { agentShort, ago, button, folder, h } from "./dom";
import { empty, folderPicker, header, sessionRow } from "./ui";

// Sessions: the Claude Code and Codex sessions the companion follows, the ones that finished
// recently (one click continues them), and starting a new one in a folder. Everything here is
// also a sentence to the companion ("start a claude session in api").

let charactersLoaded = false;

export function renderSessions(app: App) {
  if (!charactersLoaded) {
    charactersLoaded = true;
    void characters().then(() => app.redraw(true));
  }
  const view = h("div", { class: "view sessions" }, h("div", { class: "page-heading" }, h("div", {}, ...header("Sessions", "Pick up where your AI tools left off.")), button([icon("plus"), "New session"], () => {
    let close = () => {};
    const editor = sheet("New session", newSession(app, () => close()));
    close = editor.close;
  }, "primary")));
  const running = h("section", { class: "card list", "aria-label": "Running sessions" });
  const finished = h("section", { class: "card list", "aria-label": "Recently finished" });
  const fill = () => {
    const pets = app.state.status.pets;
    const live = pets.flatMap((p) => p.sessions).filter((s) => s.id);
    running.replaceChildren(...(live.length ? live.map((s) => sessionRow(app, s)) : [h("p", { class: "muted", text: "Nothing running. Sessions appear here as soon as Claude Code or Codex starts working." })]));
    const ended = pets.flatMap((p) => p.outcomes).filter((o) => o.session).sort((a, b) => b.at - a.at).slice(0, 8);
    finished.replaceChildren(
      ...(ended.length
        ? ended.map((o) =>
            h(
              "div",
              { class: "row line" },
              h("div", { class: "identity-text" }, h("strong", { text: `${agentShort(o.source)} · ${folder(o.project || o.cwd || "")}` }), h("span", { class: "meta", text: `${o.kind === "done" ? "Finished" : "Stopped with a problem"} ${ago(o.at)}${o.detail ? ` · ${o.detail}` : ""}` })),
              h("div", { class: "inline" }, badge(o.kind === "done" ? "done" : "failed"), button([icon("terminal"), "Continue"], () => void app.openSession({ source: o.source, session: o.session!, cwd: o.cwd || o.project }, true), "small")),
            ),
          )
        : [h("p", { class: "muted", text: "Finished sessions show up here, ready to continue in your terminal." })]),
    );
  };
  fill();

  const workers = h("section", { "aria-label": "Sparks" });
  const options = h("details", { class: "project-options" }, h("summary", { text: "Project companion options" }), workers);
  const fillWorkers = () => workers.replaceChildren(sparks(app));
  fillWorkers();
  app.live(() => {
    if (!view.contains(document.activeElement) || !document.activeElement?.matches("input, select, textarea")) {
      fill();
      fillWorkers();
    }
  });
  view.append(h("h2", { class: "section-title", text: "Running" }), running, h("h2", { class: "section-title", text: "Recently finished" }), finished, options);
  if (!app.state.integrations.claude_hooks) view.append(empty("Claude Code isn't connected", "Connect it in Settings to see its sessions here and answer its requests.", button("Open Settings", () => app.go("settings", "tools"))));
  return view;
}

/** Folders the companions have seen sessions in, most useful first. */
function knownFolders(app: App) {
  const pets = app.state.status.pets;
  return [...new Set([...pets.flatMap((p) => p.sessions.map((s) => s.cwd || s.project)), ...pets.flatMap((p) => p.outcomes.map((o) => o.cwd || o.project))].filter(Boolean))];
}

/** Spark workers: one per project you choose, in its own color, with the project under its feet. */
function sparks(app: App) {
  const pets = app.state.status.pets.filter((p) => !p.main && p.project);
  const send = (change: Record<string, unknown>, done: string) => void app.petAction({ action: "spark", ...change }, done);
  const list = h("div", { class: "card list" });
  for (const p of pets) {
    const color = h("select", { "aria-label": `Color of ${p.name}` }, ...COLORS.map(([name, hue]) => h("option", { value: String(hue), text: name })));
    color.value = String(p.hue ?? 0);
    color.addEventListener("change", () => send({ project: p.project, hue: Number(color.value) }, `${p.name} is ${colorName(Number(color.value)).toLowerCase()} now.`));
    const spec = app.state.crew.workers?.find((w) => w.project === p.project);
    const look = h("select", { "aria-label": `Look of ${p.name}` }, h("option", { value: "", text: "Spark" }), ...cachedCharacters().map((c) => h("option", { value: c.id, text: c.name })));
    look.value = spec?.look ?? "";
    look.addEventListener("change", () => send({ project: p.project, look: look.value || null }, "New look on the desktop."));
    list.append(
      h(
        "div",
        { class: "row line" },
        h("div", { class: "identity-text" }, h("strong", { text: `${p.name} · ${folder(p.project!)}` }), h("span", { class: "meta", text: `${p.sessions.length ? `${p.sessions.length} running` : "Waiting for work"} · ${colorName(p.hue ?? 0)}` })),
        h("div", { class: "inline" }, look, color, button("Remove", () => send({ project: p.project, remove: true }, `${p.name} went home.`), "small")),
      ),
    );
  }
  if (!pets.length) list.append(h("p", { class: "muted", text: "A Spark looks after one project: it acts out that project's sessions and brings their requests, in its own color. Pip keeps everything else." }));
  const where = h("input", { type: "text", id: "spark-folder", list: "known-folders", autocomplete: "off", placeholder: "api or ~/git/api" });
  const name = h("input", { type: "text", id: "spark-name", maxlength: 24, autocomplete: "off", placeholder: "Spark" });
  const form = h(
    "form",
    { class: "form-grid spark-form", "aria-label": "Give a project a Spark" },
    h("div", { class: "field wide" }, h("label", { for: where.id, text: "Project folder" }), folderPicker(app, where)),
    h("div", { class: "field" }, h("label", { for: name.id, text: "Name (optional)" }), name),
    h("div", { class: "actions" }, h("button", { type: "submit", class: "primary", text: "Add Spark" })),
  );
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    if (!where.value.trim()) return where.focus();
    send({ project: where.value.trim(), name: name.value.trim() || undefined }, "Your Spark is on its way to the desktop.");
    where.value = name.value = "";
  });
  list.append(form);
  return h("div", {}, h("h2", { class: "section-title", text: "Sparks" }), list);
}

function newSession(app: App, close: () => void) {
  const known = knownFolders(app);
  const tool = h("select", { id: "new-session-tool" }, h("option", { value: "claude", text: "Claude Code" }), h("option", { value: "codex", text: "Codex" }));
  const where = h("input", { type: "text", id: "new-session-folder", list: "known-folders", autocomplete: "off", placeholder: "~/git/api or api", value: known[0] ?? "" });
  const folders = h("datalist", { id: "known-folders" }, ...known.map((path) => h("option", { value: path })));
  const full = h("input", { type: "checkbox", class: "switch", role: "switch", id: "new-session-full" });
  const form = h(
    "form",
    { class: "card", "aria-label": "New session" },

    h(
      "div",
      { class: "form-grid" },
      h("div", { class: "field" }, h("label", { for: tool.id, text: "Tool" }), tool),
      h("div", { class: "field wide" }, h("label", { for: where.id, text: "Folder" }), folderPicker(app, where), folders),
    ),
    h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("label", { for: full.id, text: "Full access" }), h("p", { class: "muted", text: "Works without asking. Claude Code uses its auto mode; Codex stays sandboxed to the folder. Off: it asks first." })), full),
    h("div", { class: "actions sheet-actions" }, button("Cancel", close), h("button", { type: "submit", class: "primary", text: "Start in terminal" })),
  );
  const error = h("p", { class: "field-error", role: "alert" });
  form.append(error);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const submit = form.querySelector<HTMLButtonElement>("button[type=submit]")!;
    if (submit.disabled) return;
    submit.disabled = true;
    try {
      const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: where.value.trim() || null });
      const done = await invoke<string>("start_session", { agent: tool.value, cwd: folder.path, fullAccess: full.checked });
      close();
      app.toast(done);
    } catch (reason) {
      error.textContent = String(reason);
      submit.disabled = false;
    }
  });
  return form;
}
