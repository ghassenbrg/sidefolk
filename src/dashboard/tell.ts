import { sheet } from "./dialog";
import { explain, parse } from "../commands";
import { icon } from "../icons";
import { invoke } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h } from "./dom";

// "Tell Pip…": the companion's field, in the window. Same commands, same preview of what Enter
// will do, and the reply comes back from the companion itself, so both always agree.

export function tellBar(app: App) {
  const input = h("input", {
    type: "text",
    class: "tell-input",
    placeholder: `Tell ${app.state.crew.main.name}…`,
    "aria-label": "Tell your companion",
    autocomplete: "off",
    spellcheck: false,
  });
  const preview = h("p", { class: "tell-preview", "aria-live": "polite" });
  const update = () => {
    const text = input.value.trim();
    preview.textContent = text ? `↵ ${explain(text, context(app))}` : "";
  };
  input.addEventListener("input", update);
  input.addEventListener("keydown", async (event) => {
    if (event.key === "Escape") {
      input.value = "";
      update();
      return input.blur();
    }
    if (event.key !== "Enter" || !input.value.trim()) return;
    event.preventDefault();
    const text = input.value.trim();
    input.value = "";
    update();
    const command = parse(text);
    if (command.kind === "run") return confirmRun(app, command.command, command.folder);
    if (command.kind === "start") return confirmStart(app, command.agent, command.folder, command.full);
    const reply = await app.tell(text);
    if (reply) app.toast(reply);
    void app.refresh();
  });
  const examples = h("details", { class: "tell-examples" }, h("summary", { text: "Examples" }));
  const options = h("div", { class: "example-options" });
  for (const text of ["remind me tomorrow at 9 to check the results", "note for Ideas: try a quieter morning", "open Sidefolk", "help"]) options.append(button(text, () => { input.value = text; examples.open = false; input.focus(); update(); }));
  examples.append(options);
  return h("form", { class: "tell", onsubmit: (e: Event) => e.preventDefault() }, h("div", { class: "tell-row" }, h("span", { class: "tell-icon" }, icon("requests")), input, examples), preview);
}

/** Same rule as on the companion: the exact command and folder first, then it runs where you can watch. */
async function confirmRun(app: App, command: string, wanted: string | null) {
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    review(app, "Run in your terminal?", command, folder.path, "Run in terminal", () => invoke<string>("run_command", { command, cwd: folder.path }));
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
}

async function confirmStart(app: App, agent: "claude" | "codex", wanted: string | null, full: boolean) {
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    const name = agent === "codex" ? "Codex" : "Claude Code";
    review(app, `Start ${name}?`, `${name} · ${full ? "Full access" : "Asks first"}`, folder.path, `Start ${name}`, () => invoke<string>("start_session", { agent, cwd: folder.path, fullAccess: full }));
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
}

function review(app: App, title: string, action: string, path: string, label: string, run: () => Promise<string>) {
  const error = h("p", { class: "field-error", role: "alert" });
  const content = h("div", {}, h("div", { class: "facts" }, h("span", { class: "fact-label", text: "Action" }), h("code", { text: action }), h("span", { class: "fact-label", text: "Folder" }), h("code", { text: path })), h("p", { class: "muted", text: "Opens in your configured terminal so you can see the output." }), error);
  const editor = sheet(title, content);
  const submit = button(label, async () => {
    submit.disabled = true;
    try { const done = await run(); editor.close(); app.toast(done); }
    catch (reason) { error.textContent = String(reason); submit.disabled = false; }
  }, "primary");
  content.append(h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close), submit));
  // The dialog initially focuses its close control, never the action.
}

/** "run … in api": the folder of the api work session when there is one. */
function sessionFolder(app: App, project: string | null) {
  if (!project) return null;
  const pet = app.state.status.pets[0];
  const live = pet?.sessions.find((s) => folder(s.project).toLowerCase() === project.toLowerCase());
  return live ? live.cwd || live.project : null;
}

function context(app: App) {
  return {
    name: app.state.crew.main.name,
    sessionFor(project: string | null) {
      const pet = app.state.status.pets[0];
      if (!pet) return null;
      const want = project?.toLowerCase();
      const matches = (p: string) => !want || folder(p).toLowerCase() === want;
      const live = pet.sessions.find((s) => s.id && matches(s.project));
      if (live) return { agent: agentShort(live.source), live: true };
      const last = pet.outcomes.find((o) => o.session && matches(o.project));
      return last ? { agent: agentShort(last.source), live: false } : null;
    },
  };
}
