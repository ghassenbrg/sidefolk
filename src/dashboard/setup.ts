import { notificationSetting } from "./notifications";
import { shortcutLabel } from "../keys";
import { invoke } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { header } from "./ui";

// The first-launch guide: five short steps anyone can follow, no technical words until the
// optional developer step. Everything it sets can change later in Settings, and it can be run
// again from there. Each step does the real thing (the reminder in "Try it" is real).

const STEPS = ["Meet", "Try it", "Where it lives", "AI tools", "Done"];
let step = 0;

export function renderSetup(app: App, arg: string) {
  if (arg === "start") step = 0;
  app.live(() => {});
  const name = app.state.crew.main.name;
  const go = (to: number) => {
    step = Math.max(0, Math.min(STEPS.length - 1, to));
    app.redraw(true);
    requestAnimationFrame(() => document.querySelector<HTMLElement>("main h1")?.focus());
  };
  const next = (label = "Continue") => button(label, () => go(step + 1), "primary");
  const backButton = step > 0 ? button("Back", () => go(step - 1)) : null;

  const progress = h("ol", { class: "setup-steps", "aria-label": `Step ${step + 1} of ${STEPS.length}` });
  STEPS.forEach((label, i) => progress.append(h("li", { class: i === step ? "current" : i < step ? "done" : "", "aria-current": i === step ? "step" : undefined, text: label })));

  const body = h("div", { class: "setup-body" });
  const actions = h("div", { class: "actions" }, backButton);

  switch (step) {
    case 0: {
      const input = h("input", { type: "text", id: "setup-name", maxlength: 24, value: name, autocomplete: "off", spellcheck: false });
      body.append(
        ...header(`Hi, I'm ${name}.`, "I live on your desktop and keep small things for you: reminders, notes, and what your AI tools are up to. I never use AI unless you ask me to."),
        h("div", { class: "field" }, h("label", { for: input.id, text: "What should I be called?" }), input),
      );
      actions.append(
        button("Continue", async () => {
          const wanted = input.value.trim();
          if (wanted && wanted !== name) await app.tell(`rename to ${wanted}`);
          await app.refresh();
          go(1);
        }, "primary"),
      );
      break;
    }
    case 1: {
      const result = h("p", { class: "hint", "aria-live": "polite" });
      body.append(
        ...header("Try it.", `Click ${name} on your desktop and type, like a sticky note that talks back. Or try one right here:`),
        h("p", {}, h("code", { text: "remind me in 1 minute to stretch" })),
        result,
      );
      actions.append(
        button("Set this reminder", async () => {
          result.textContent = await app.tell("remind me in 1 minute to stretch");
          await app.refresh();
        }),
        next(),
      );
      break;
    }
    case 2: {
      const { settings, integrations } = app.state;
      const size = h("div", { class: "segmented", role: "radiogroup", "aria-label": "Size" });
      for (const [value, text] of [["small", "Small"], ["medium", "Medium"], ["large", "Large"]] as const)
        size.append(button(text, () => void app.save({ pet_size: value }), "", { role: "radio", "aria-checked": String(settings.pet_size === value) }));
      const check = (id: string, label: string, help: string, on: boolean, change: (on: boolean) => void) => {
        const input = h("input", { type: "checkbox", class: "switch", role: "switch", id, checked: on });
        input.addEventListener("change", () => change(input.checked));
        return h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("label", { for: id, text: label }), h("p", { class: "muted", text: help })), input);
      };
      body.append(
        ...header("Where it lives.", `${name} stays where you put it. Drag it anywhere; it never wanders off.`),
        h("div", { class: "setting stack" }, h("div", { class: "setting-text" }, h("strong", { text: "Size" })), size),
        notificationSetting(app),
        check("setup-login", "Start at login", "So your reminders are always on time.", integrations.start_at_login, () => void invoke("tray_action", { action: "login" }).then(() => app.refresh())),
        check("setup-recordings", "Hide from screen recordings", "Keeps the companion out of screen sharing and screenshots.", settings.hide_in_recordings, (on) => void app.save({ hide_in_recordings: on })),
        h("p", { class: "muted", text: `Hide or call ${name} anytime with ${shortcutLabel(settings.shortcut)}. This window is in the Dock; you can hide it from the Dock in Settings.` }),
      );
      actions.append(next());
      break;
    }
    case 3: {
      const { integrations } = app.state;
      const connect = (on: boolean, action: string, title: string, what: string) =>
        h(
          "div",
          { class: "setting tool" },
          h("div", { class: "setting-text" }, h("strong", {}, title, " ", h("span", { class: `pill${on ? " on" : ""}`, text: on ? "Connected" : "Not connected" })), h("p", { class: "muted", text: what })),
          on
            ? h("span")
            : button("Set up…", () => {
                void invoke("tray_action", { action }).catch((e) => app.toast(String(e), undefined, true));
                app.toast("Confirm in the dialog that opened.");
              }),
        );
      body.append(
        ...header("AI tools (optional).", `If you use Claude Code or Codex, ${name} can show their progress, bring you their questions and open their sessions. Skip this if you don't.`),
        connect(integrations.claude_hooks, "claude", "Claude Code", "See its sessions and answer its requests. Each change is explained first and a backup is kept."),
        connect(integrations.claude_tools, "tools-claude", "Companion tools for Claude Code", "Lets Claude Code send you a note, ask a question or set a reminder."),
        connect(integrations.codex_tools, "tools-codex", "Companion tools for Codex", "The same for Codex."),
        terminalControl(),
      );
      actions.append(next("Skip or continue"));
      break;
    }
    default: {
      body.append(
        ...header("You're set.", `${name} is on your desktop. Everything here is also in the window: Today, Reminders and Settings.`),
        h("p", { class: "muted", text: "Tip: type “help” to see what I understand." }),
      );
      actions.append(
        button("Start using Sidefolk", async () => {
          if (await app.save({ onboarded: true }, "Welcome!")) {
            step = 0;
            app.go("today");
          }
        }, "primary"),
      );
    }
  }

  return h(
    "div",
    { class: "view setup" },
    h("img", { class: "setup-pip", src: step === 4 ? "/pip/done.png" : step === 1 ? "/pip/note.png" : "/pip/wave.png", alt: "", width: 168, height: 152 }),
    progress,
    body,
    actions,
  );
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
