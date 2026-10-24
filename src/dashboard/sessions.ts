import { icon } from "../icons";
import { badge } from "../states";
import { invoke } from "./api";
import type { App } from "./app";
import { agentShort, ago, button, folder, h } from "./dom";
import { empty, header, sessionRow } from "./ui";

// Sessions: the Claude Code and Codex sessions the companion follows, the ones that finished
// recently (one click continues them), and starting a new one in a folder. Everything here is
// also a sentence to the companion ("start a claude session in api").

export function renderSessions(app: App) {
  const view = h("div", { class: "view sessions" }, ...header("Sessions", "Claude Code and Codex sessions your companion follows. Start one here, or tell it “start a claude session in api”."));
  const running = h("section", { class: "card list", "aria-label": "Running sessions" });
  const finished = h("section", { class: "card list", "aria-label": "Recently finished" });
  const fill = () => {
    const pet = app.state.status.pets[0];
    const live = pet?.sessions.filter((s) => s.id) ?? [];
    running.replaceChildren(...(live.length ? live.map((s) => sessionRow(app, s)) : [h("p", { class: "muted", text: "Nothing running. Sessions appear here as soon as Claude Code or Codex starts working." })]));
    const ended = (pet?.outcomes ?? []).filter((o) => o.session).slice(0, 8);
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
    if (!view.contains(document.activeElement) || document.activeElement === document.body) fill();
  });

  view.append(h("h2", { class: "section-title", text: "Running" }), running, h("h2", { class: "section-title", text: "Recently finished" }), finished, newSession(app));
  if (!app.state.integrations.claude_hooks) view.append(empty("Claude Code isn't connected", "Connect it in Settings to see its sessions here and answer its requests.", button("Open Settings", () => app.go("settings", "tools"))));
  return view;
}

function newSession(app: App) {
  const pet = app.state.status.pets[0];
  const known = [...new Set([...(pet?.sessions ?? []).map((s) => s.cwd || s.project), ...(pet?.outcomes ?? []).map((o) => o.cwd || o.project)].filter(Boolean))];
  const tool = h("select", { id: "new-session-tool" }, h("option", { value: "claude", text: "Claude Code" }), h("option", { value: "codex", text: "Codex" }));
  const where = h("input", { type: "text", id: "new-session-folder", list: "known-folders", autocomplete: "off", placeholder: "~/git/api or api", value: known[0] ?? "" });
  const folders = h("datalist", { id: "known-folders" }, ...known.map((path) => h("option", { value: path })));
  const full = h("input", { type: "checkbox", class: "switch", role: "switch", id: "new-session-full" });
  const form = h(
    "form",
    { class: "card", "aria-label": "New session" },
    h("h2", { text: "New session" }),
    h(
      "div",
      { class: "form-grid" },
      h("div", { class: "field" }, h("label", { for: tool.id, text: "Tool" }), tool),
      h("div", { class: "field wide" }, h("label", { for: where.id, text: "Folder" }), where, folders),
    ),
    h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("label", { for: full.id, text: "Full access" }), h("p", { class: "muted", text: "Works without asking. Claude Code uses its auto mode; Codex stays sandboxed to the folder. Off: it asks first." })), full),
    h("div", { class: "actions" }, h("button", { type: "submit", class: "primary", text: "Start in terminal" })),
  );
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: where.value.trim() || null });
      app.toast(await invoke<string>("start_session", { agent: tool.value, cwd: folder.path, fullAccess: full.checked }));
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  });
  return form;
}
