import { problem } from "../voice";
import { timeZone } from "./dom";
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
let trialDue: number | null = null;

export function renderSetup(app: App, arg: string) {
  if (arg === "start") { step = 0; trialDue = null; }
  app.live(() => {});
  const name = app.state.crew.main.name;
  const go = (to: number) => { step = to; app.go("setup"); requestAnimationFrame(() => document.querySelector<HTMLElement>("main h1")?.focus()); };
  const progress = h("ol", { class: "setup-steps", "aria-label": `Step ${step + 1} of ${STEPS.length}` });
  STEPS.forEach((label, i) => progress.append(h("li", { class: i === step ? "current" : "", "aria-current": i === step ? "step" : undefined, text: label })));
  const body = h("div", { class: "setup-body" });
  const actions = h("div", { class: "actions" });
  if (step > 0) actions.append(button("Back", () => go(step - 1)));
  if (step === 0) {
    const result = h("p", { class: "hint", role: "status", text: trialDue ? `Saved for ${new Date(trialDue).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} (${timeZone()}).` : "" });
    const input = h("input", { type: "text", id: "setup-name", maxlength: 24, value: name, autocomplete: "off" });
    const tryIt = button(trialDue ? "Reminder saved" : "Set a two-minute reminder", async () => {
      tryIt.disabled = true;
      try {
        const due = Date.now() + 120_000;
        await invoke("add_reminder", { text: "Stretch", due, project: null, repeat: null });
        trialDue = due;
        result.textContent = `Saved for ${new Date(due).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} (${timeZone()}). I’ll remind you to stretch.`;
        next.disabled = false;
        tryIt.textContent = "Reminder saved";
      } catch (error) { result.textContent = problem(error); tryIt.disabled = false; }
    }, "primary");
    tryIt.disabled = !!trialDue;
    body.append(...header(`Hi, I'm ${name}.`, "Keep a small reminder or a dated note. No AI connection needed."),
      h("div", { class: "field" }, h("label", { for: input.id, text: "Companion name (optional)" }), input),
      h("p", { text: "Try a real reminder: stretch in two minutes." }), tryIt, result);
    const next = button("Continue", async () => {
      const wanted = input.value.trim();
      if (wanted && wanted !== name) { await app.tell(`rename to ${wanted}`); await app.refresh(); }
      go(1);
    }, "primary", { disabled: !trialDue });
    actions.append(next);
  } else if (step === 1) {
    body.append(...header("By your side.", `${name} stays where you put it. Drag it anywhere, and click it to capture a reminder or a note.`),
      h("p", { class: "muted", text: `Your shortcut is ${shortcutLabel(app.state.settings.shortcut)}. Everything can change later in Settings.` }),
      notificationSetting(app),
      h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("strong", { text: "Hide Pip’s cards from screen shares?" }), h("p", { class: "muted", text: "Recording protection is off by default while Mission Control is being checked. You can change it in Privacy & data." })),
        button(app.state.settings.hide_in_recordings ? "Turn protection off" : "Turn protection on", () => void app.save({ hide_in_recordings: !app.state.settings.hide_in_recordings }))),
      h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("strong", { text: "Start at login" }), h("p", { class: "muted", text: "Keep your companion ready when you sign in." })), button(app.state.integrations.start_at_login ? "Turn off" : "Turn on", () => void invoke("tray_action", { action: "login" }).then(() => app.refresh()))));
    actions.append(button("Continue", () => go(2), "primary"));
  } else {
    body.append(...header("Claude Code, when you need it.", "Optionally follow its sessions and review requests. Each connection is confirmed and backed up."));
    const health = h("div", { class: "setting", role: "status" });
    const finish = async () => {
      if (await app.save({ onboarded: true }, "Welcome!")) { step = 0; app.go("today"); }
    };
    const done = button("Start using Sidefolk", () => void finish(), "primary");
    const drawConnection = () => {
      const state = app.state.integrations;
      const heard = state.claude_health === "working";
      const connected = state.claude_hooks;
      done.disabled = !heard;
      health.replaceChildren(h("div", { class: "setting-text" }, h("strong", { text: "Claude Code" }),
        h("p", { class: "muted", text: heard ? "A real session reached Sidefolk. You're ready." : state.claude_health === "unavailable" ? "Sidefolk can't listen. Open Settings → Agents to repair the connection." : connected ? "Connected. Start a new Claude Code session; I’ll wait for its first event." : "Connect when you're ready, or skip this step." })));
      if (!connected || state.claude_health === "repair") health.append(button("Connect…", () => void invoke("tray_action", { action: "claude" }).catch((error) => app.toast(problem(error), undefined, true))));
    };
    drawConnection();
    app.live(drawConnection);
    body.append(health, h("p", { class: "muted", text: "Codex beta and terminal support are in Settings → Agents." }));
    actions.append(button("Skip for now", () => void finish()), done);
  }
  return h("div", { class: "view setup" }, h("img", { class: "setup-pip", src: picture(app.state.crew.main.look, "wave"), alt: "", width: 168, height: 152 }), progress, body, actions);
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
        result.textContent = problem(error);
      }
    }),
  );
}
