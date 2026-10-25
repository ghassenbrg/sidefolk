import { sheet } from "./dialog";
import { icon } from "../icons";
import { badge } from "../states";
import { invoke } from "./api";
import type { App } from "./app";
import { agentShort, ago, button, folder, h } from "./dom";
import { empty, folderPicker, header, sessionRow } from "./ui";

// Sessions: the Claude Code sessions the companion follows, the ones that finished recently (one
// click continues them), and, with Settings → Labs on, starting a new one in a folder.

export function renderSessions(app: App) {
  const view = h("div", { class: "view sessions" }, h("div", { class: "page-heading" }, h("div", {}, ...header("Sessions", "Pick up where your AI tools left off.")), h("div", { class: "inline" },
    !app.state.settings.labs_sessions ? null : button([icon("plus"), "New session"], () => {
      let close = () => {};
      const editor = sheet("New session", newSession(app, () => close()));
      close = editor.close;
    }, "primary"))));
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

  app.live(() => {
    if (!view.contains(document.activeElement) || !document.activeElement?.matches("input, select, textarea")) fill();
  });
  view.append(h("h2", { class: "section-title", text: "Running" }), running, h("h2", { class: "section-title", text: "Recently finished" }), finished);
  if (!app.state.integrations.claude_hooks) view.append(empty("Claude Code isn't connected", "Connect it in Settings to see its sessions here and answer its requests.", button("Open Settings", () => app.go("settings", "tools"))));
  return view;
}

/** Folders the companions have seen sessions in, most useful first. */
function knownFolders(app: App) {
  const pets = app.state.status.pets;
  return [...new Set([...pets.flatMap((p) => p.sessions.map((s) => s.cwd || s.project)), ...pets.flatMap((p) => p.outcomes.map((o) => o.cwd || o.project))].filter(Boolean))];
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
    h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("label", { for: full.id, text: "Start in the tool's own auto mode" }), h("p", { class: "muted", text: "Claude Code's auto mode, or Codex without approvals sandboxed to the folder. The tool decides what to ask; Sidefolk never answers for it. Off: it asks you first." })), full),
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
