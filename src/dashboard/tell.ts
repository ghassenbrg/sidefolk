import { explain } from "../commands";
import { icon } from "../icons";
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
    const reply = await app.tell(text);
    if (reply) app.toast(reply);
    void app.refresh();
  });
  return h("form", { class: "tell", onsubmit: (e: Event) => e.preventDefault() }, h("span", { class: "tell-icon" }, icon("requests")), input, preview);
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
