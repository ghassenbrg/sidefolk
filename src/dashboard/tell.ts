import { explain, parse } from "../commands";
import { icon } from "../icons";
import { invoke } from "./api";
import type { App } from "./app";
import { agentShort, folder, h } from "./dom";

// "Tell Pip…": the companion's field, in the window. Same commands, same preview of what Enter
// will do, and the reply comes back from the companion itself, so both always agree.

export function tellBar(app: App) {
  const input = h("input", {
    type: "text",
    class: "tell-input",
    placeholder: `Tell ${app.state.crew.main.name}… (remind me tomorrow at 9 to…)`,
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
  return h("form", { class: "tell", onsubmit: (e: Event) => e.preventDefault() }, h("span", { class: "tell-icon" }, icon("requests")), input, preview);
}

/** Same rule as on the companion: the exact command and folder first, then it runs where you can watch. */
async function confirmRun(app: App, command: string, wanted: string | null) {
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    app.toast(`Run \`${command}\` in ${folder.label}? It opens in your terminal.`, {
      label: "Run in terminal",
      run: () => void invoke<string>("run_command", { command, cwd: folder.path }).then((done) => app.toast(done), (error) => app.toast(String(error), undefined, true)),
    });
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
}

async function confirmStart(app: App, agent: "claude" | "codex", wanted: string | null, full: boolean) {
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    const name = agent === "codex" ? "Codex" : "Claude Code";
    app.toast(`Start ${name} in ${folder.label}${full ? " with full access" : " (asks first)"}?`, {
      label: `Start ${name}`,
      run: () => void invoke<string>("start_session", { agent, cwd: folder.path, fullAccess: full }).then((done) => app.toast(done), (error) => app.toast(String(error), undefined, true)),
    });
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
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
