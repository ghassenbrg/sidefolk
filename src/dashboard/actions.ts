import { icon } from "../icons";
import { invoke } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { header } from "./ui";

// Actions: commands and links you name once and run by name, here or on the companion
// ("deploy staging"). A command runs in your terminal, or quietly with a done or failed note and
// its output kept. Nothing is run that wasn't shown first: the list shows exactly what runs.

type Saved = { name: string; kind: "command" | "link"; value: string; folder: string };

const home = (path: string) => path.replace(/^\/Users\/[^/]+/, "~");

export function renderActions(app: App) {
  const view = h("div", { class: "view actions-page" }, ...header("Actions", "Name a command or a link once, then run it by name here or by telling your companion (“deploy staging”)."));
  app.live(() => {});
  const list = h("section", { class: "card list", "aria-label": "Your actions" });
  const fill = async () => {
    const saved = await invoke<Saved[]>("list_actions").catch(() => [] as Saved[]);
    list.replaceChildren(...(saved.length ? saved.map((a) => row(app, a, fill)) : [h("p", { class: "muted", text: "No actions yet. Add one below, or tell your companion “save action deploy: npm run deploy in api”." })]));
  };
  void fill();

  const kind = h("select", { id: "action-kind" }, h("option", { value: "command", text: "Command" }), h("option", { value: "link", text: "Link" }));
  const name = h("input", { type: "text", id: "action-name", maxlength: 40, autocomplete: "off", placeholder: "deploy staging" });
  const value = h("input", { type: "text", id: "action-value", maxlength: 500, autocomplete: "off", spellcheck: false, placeholder: "npm run deploy -- staging" });
  const folder = h("input", { type: "text", id: "action-folder", autocomplete: "off", placeholder: "api or ~/git/api" });
  const folderField = h("div", { class: "field" }, h("label", { for: folder.id, text: "Folder" }), folder);
  kind.addEventListener("change", () => {
    folderField.hidden = kind.value === "link";
    value.placeholder = kind.value === "link" ? "https://team.atlassian.net/board" : "npm run deploy -- staging";
  });
  const form = h(
    "form",
    { class: "card", "aria-label": "New action" },
    h("h2", { text: "New action" }),
    h(
      "div",
      { class: "form-grid" },
      h("div", { class: "field" }, h("label", { for: kind.id, text: "Kind" }), kind),
      h("div", { class: "field" }, h("label", { for: name.id, text: "Name" }), name),
      h("div", { class: "field wide" }, h("label", { for: value.id, text: "Command or link" }), value),
      folderField,
    ),
    h("div", { class: "actions" }, h("button", { type: "submit", class: "primary", text: "Save action" })),
  );
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const saved = await invoke<Saved>("save_action", { name: name.value, kind: kind.value, value: value.value, folder: folder.value || null });
      app.toast(`Saved. Say “${saved.name}” to your companion, or run it here.`);
      name.value = value.value = folder.value = "";
      await fill();
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  });
  view.append(list, form);
  return view;
}

function row(app: App, a: Saved, refill: () => Promise<void>) {
  const run = async (background: boolean) => {
    if (background) app.toast(`Running ${a.name}…`);
    try {
      const result = await invoke<{ ok: boolean; message: string; log: string | null }>("run_action", { name: a.name, background });
      app.toast(result.message, result.log ? { label: "Show output", run: () => void invoke("show_output", { log: result.log }) } : undefined, !result.ok);
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  };
  return h(
    "div",
    { class: "row line" },
    h("div", { class: "identity-text" }, h("strong", { text: a.name }), h("span", { class: "meta mono", text: a.kind === "link" ? a.value : `${a.value} · ${home(a.folder)}` })),
    h(
      "div",
      { class: "inline" },
      ...(a.kind === "link"
        ? [button([icon("open"), "Open"], () => void run(false), "small")]
        : [button("Run quietly", () => void run(true), "small", { title: "Runs in the background and tells you when it's done, with its output." }), button([icon("terminal"), "Run in terminal"], () => void run(false), "small")]),
      button("Remove", () => void invoke("remove_action", { name: a.name }).then(refill), "small"),
    ),
  );
}
