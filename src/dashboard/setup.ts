import { notificationSetting } from "./notifications";
import { shortcutLabel } from "../keys";
import { invoke } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { header } from "./ui";
import { picture } from "../roster";

// Start with a useful reminder, then desktop delivery, then optional AI setup.
const STEPS = ["Try Pip", "Desktop", "AI tools"];
let step = 0;

export function renderSetup(app: App, arg: string) {
  if (arg === "start") step = 0;
  app.live(() => {});
  const name = app.state.crew.main.name;
  const go = (to: number) => { step = to; app.go("setup"); requestAnimationFrame(() => document.querySelector<HTMLElement>("main h1")?.focus()); };
  const progress = h("ol", { class: "setup-steps", "aria-label": `Step ${step + 1} of ${STEPS.length}` });
  STEPS.forEach((label, i) => progress.append(h("li", { class: i === step ? "current" : "", "aria-current": i === step ? "step" : undefined, text: label })));
  const body = h("div", { class: "setup-body" });
  const actions = h("div", { class: "actions" });
  if (step > 0) actions.append(button("Back", () => go(step - 1)));
  if (step === 0) {
    const result = h("p", { class: "hint", role: "status" });
    const input = h("input", { type: "text", id: "setup-name", maxlength: 24, value: name, autocomplete: "off" });
    const tryIt = button("Set a two-minute reminder", async () => {
      tryIt.disabled = true;
      try {
        await invoke("add_reminder", { text: "Stretch", due: Date.now() + 120_000, project: null, repeat: null });
        result.textContent = "Saved. Your companion will remind you to stretch in two minutes.";
        tryIt.textContent = "Reminder saved";
      } catch (error) { result.textContent = `Couldn't save: ${error}`; tryIt.disabled = false; }
    }, "primary");
    body.append(...header(`Hi, I'm ${name}.`, "Keep a small reminder or a dated note. No AI connection needed."),
      h("div", { class: "field" }, h("label", { for: input.id, text: "Companion name (optional)" }), input),
      h("p", { text: "Try a real reminder: stretch in two minutes." }), tryIt, result);
    actions.append(button("Continue", async () => {
      const wanted = input.value.trim();
      if (wanted && wanted !== name) { await app.tell(`rename to ${wanted}`); await app.refresh(); }
      go(1);
    }));
  } else if (step === 1) {
    body.append(...header("By your side.", `${name} stays where you put it. Drag it anywhere, and click it to capture a reminder or a note.`),
      h("p", { class: "muted", text: `Your shortcut is ${shortcutLabel(app.state.settings.shortcut)}. Everything can change later in Settings.` }),
      notificationSetting(app),
      h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("strong", { text: "Start at login" }), h("p", { class: "muted", text: "Keep your companion ready when you sign in." })), button(app.state.integrations.start_at_login ? "Turn off" : "Turn on", () => void invoke("tray_action", { action: "login" }).then(() => app.refresh()))));
    actions.append(button("Continue", () => go(2), "primary"));
  } else {
    body.append(...header("AI tools, when you need them.", "Optionally connect Claude Code or Codex to follow work sessions and review requests."));
    const connect = (on: boolean, action: string, title: string, description: string) => h("div", { class: "setting" },
      h("div", { class: "setting-text" }, h("strong", { text: title }), h("p", { class: "muted", text: on ? "Connected" : description })),
      on ? null : button("Connect…", () => void invoke("tray_action", { action }).catch((error) => app.toast(String(error), undefined, true))));
    body.append(connect(app.state.integrations.claude_hooks, "claude", "Claude Code", "Follow its sessions and review its requests."),
      connect(app.state.integrations.codex_tools, "tools-codex", "Codex", "Let Codex reach you through your companion."),
      h("p", { class: "muted", text: "Each setup explains what changes and keeps a backup. More options are in Settings → AI tools." }));
    actions.append(button("Start using Sidefolk", async () => {
      if (await app.save({ onboarded: true }, "Welcome!")) { step = 0; app.go("today"); }
    }, "primary"));
  }
  return h("div", { class: "view setup" }, h("img", { class: "setup-pip", src: picture("wave"), alt: "", width: 168, height: 152 }), progress, body, actions);
}

/** macOS asks once before Sidefolk may control a terminal; better here, with the reason, than at
 * the first "Open session". */
export function terminalControl() {
  const result = h("p", { class: "muted", "aria-live": "polite", text: "Opening a session or a command in Terminal or iTerm needs your OK once. macOS asks when you press Allow." });
  return h(
    "div",
    { class: "setting tool" },
    h("div", { class: "setting-text" }, h("strong", { text: "Open sessions in your terminal" }), result),
    button("Allow…", async () => {
      try {
        result.textContent = await invoke<string>("allow_terminal_control");
      } catch (error) {
        result.textContent = String(error);
      }
    }),
  );
}
