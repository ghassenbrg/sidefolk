import { icon, type IconName } from "../icons";
import { acceleratorFrom, shortcutLabel } from "../keys";
import { invoke, type Settings } from "./api";
import type { App } from "./app";
import { PRESETS, lookAvailable, suggestions, type Comfort } from "./comfort";
import { button, h } from "./dom";
import { portraitImage } from "./portrait";
import { header } from "./ui";

// Settings in plain language. Each control saves when it changes and says "Saved." only after
// the settings file is written. Connecting a tool opens the app's own confirmation, which
// explains the file it changes and keeps a backup.

let voices: { name: string; language: string }[] | null = null;
let terminals: string[] | null = null;
let draftComfort: Comfort | null = null;
let unticked = new Set<string>();
let recording = false;

const TERMINAL_LABELS: Record<string, string> = { terminal: "Terminal", iterm: "iTerm", ghostty: "Ghostty" };

function group(title: string, glyph: IconName, id: string, ...rows: (HTMLElement | null)[]) {
  return h("section", { class: "card settings-group", id, "aria-labelledby": `${id}-title` }, h("h2", { id: `${id}-title`, class: "with-icon" }, icon(glyph), h("span", { text: title })), ...rows);
}

function row(label: string, description: string | null, control: HTMLElement, forId?: string) {
  return h(
    "div",
    { class: "setting" },
    h("div", { class: "setting-text" }, forId ? h("label", { for: forId, text: label }) : h("strong", { text: label }), description ? h("p", { class: "muted", id: forId ? `${forId}-help` : undefined, text: description }) : null),
    control,
  );
}

function toggle(app: App, key: keyof Settings, label: string, description: string) {
  const id = `setting-${key}`;
  const input = h("input", { type: "checkbox", class: "switch", role: "switch", id, checked: !!app.state.settings[key], "aria-describedby": `${id}-help` });
  input.addEventListener("change", () => void app.save({ [key]: input.checked }));
  return row(label, description, input, id);
}

function select(app: App, key: keyof Settings, label: string, description: string | null, options: [string, string][], numeric = false) {
  const id = `setting-${key}`;
  const control = h("select", { id, "aria-describedby": description ? `${id}-help` : undefined });
  for (const [value, text] of options) control.append(h("option", { value, text }));
  control.value = String(app.state.settings[key] ?? "");
  control.addEventListener("change", () => {
    control.blur();
    void app.save({ [key]: numeric ? Number(control.value) : control.value });
  });
  return row(label, description, control, id);
}

function segmented(app: App, key: keyof Settings, label: string, description: string, options: [string, string][]) {
  const control = h("div", { class: "segmented", role: "radiogroup", "aria-label": label });
  for (const [value, text] of options)
    control.append(button(text, () => void app.save({ [key]: value }), "", { role: "radio", "aria-checked": String(app.state.settings[key] === value) }));
  return h("div", { class: "setting stack" }, h("div", { class: "setting-text" }, h("strong", { text: label }), h("p", { class: "muted", text: description })), control);
}

function comfortGroup(app: App) {
  const { settings } = app.state;
  const chosen = draftComfort ?? settings.comfort;
  const cards = h("div", { class: "choice-grid", role: "radiogroup", "aria-label": "Comfort" });
  for (const [key, preset] of Object.entries(PRESETS) as [Comfort, (typeof PRESETS)[Comfort]][]) {
    const available = lookAvailable(preset.look);
    cards.append(
      button(
        [available ? portraitImage(preset.look, "", "thumb large") : h("span", { class: "thumb placeholder" }), h("strong", { text: preset.label }), h("small", { text: `${preset.who} · ${preset.describe}` })],
        () => {
          draftComfort = key;
          unticked = new Set();
          app.redraw(true);
        },
        "choice tall",
        { role: "radio", "aria-checked": String(chosen === key) },
      ),
    );
  }
  const nodes: HTMLElement[] = [h("p", { class: "muted", text: "A starting point. You'll see each suggested change before anything is applied, and can change any of them later." }), cards];
  if (draftComfort && draftComfort !== settings.comfort) {
    const list = suggestions(draftComfort, settings);
    const box = h("div", { class: "notice" }, h("strong", { text: list.length ? "Suggested changes" : "Nothing else changes." }));
    for (const s of list) {
      const id = `suggest-${s.key}`;
      const check = h("input", { type: "checkbox", id, checked: !unticked.has(s.key) });
      check.addEventListener("change", () => (check.checked ? unticked.delete(s.key) : unticked.add(s.key)));
      box.append(h("div", { class: "check" }, check, h("label", { for: id, text: s.label })));
    }
    box.append(h("p", { class: "muted", text: "Looks never change what an AI tool is allowed to do." }));
    nodes.push(
      box,
      h(
        "div",
        { class: "actions" },
        button("Cancel", () => ((draftComfort = null), app.redraw(true))),
        button(`Apply ${PRESETS[draftComfort].label}`, async () => {
          const change: Partial<Settings> = { comfort: draftComfort! };
          for (const s of list) if (!unticked.has(s.key)) Object.assign(change, s.change);
          if (await app.save(change, `${PRESETS[draftComfort!].label} applied.`)) draftComfort = null;
          app.redraw(true);
        }, "primary"),
      ),
    );
  }
  return group("Comfort", "crew", "comfort", ...nodes);
}

function toolRow(app: App, key: "claude_hooks" | "claude_tools" | "codex_tools", action: string, title: string, what: string, change: string, stops: string) {
  const on = app.state.integrations[key];
  return h(
    "div",
    { class: "setting tool" },
    h(
      "div",
      { class: "setting-text" },
      h("strong", {}, title, " ", h("span", { class: `pill${on ? " on" : ""}`, text: on ? "Connected" : "Not connected" })),
      h("p", { class: "muted", text: what }),
      h("details", {}, h("summary", { text: on ? "What disconnecting does" : "What setting up changes" }), h("p", { class: "muted", text: on ? stops : change })),
    ),
    button(on ? "Disconnect…" : "Set up…", () => {
      void invoke("tray_action", { action }).catch((e) => app.toast(String(e), undefined, true));
      app.toast("Confirm in the dialog that opened.");
    }, on ? "" : "primary"),
  );
}

export function renderSettings(app: App, arg: string) {
  const { settings, integrations } = app.state;
  voices ?? void invoke<{ name: string; language: string }[]>("voices").then((v) => ((voices = v), app.redraw(true))).catch(() => (voices = []));
  terminals ?? void invoke<string[]>("terminals").then((t) => ((terminals = t), app.redraw(true))).catch(() => (terminals = []));
  // Settings don't change while being read; only saves (forced) redraw this page.
  app.live(() => {});

  const view = h("div", { class: "view settings" }, ...header("Make Sidefolk comfortable.", "A few simple preferences. Everything here can change later."));

  view.append(comfortGroup(app));

  view.append(
    group(
      "On your desktop",
      "home",
      "desktop",
      segmented(app, "presence", "Desktop presence", {
        always: "Your main companion stays on the desktop; others come out when their project needs you.",
        needed: "Companions rest and come out only when something needs you. Requests also wait in the menu bar.",
        menubar: "No companions on the desktop. Requests and reminders wait in the menu bar and arrive as notifications.",
      }[settings.presence], [
        ["always", "Always visible"],
        ["needed", "Only when needed"],
        ["menubar", "Menu bar only"],
      ]),
      segmented(app, "pet_size", "Companion size", "Card text size is set separately, under Accessibility.", [
        ["small", "Small"],
        ["medium", "Medium"],
        ["large", "Large"],
      ]),
    ),
  );

  view.append(
    group(
      "Accessibility",
      "info",
      "accessibility",
      toggle(app, "calm", "Reduce motion", "Companions stay put and changes happen at once, without hops or pulsing. Also on when macOS asks for reduced motion."),
      toggle(app, "large_text", "Larger text", "Bigger cards and text, here and on the desktop, without changing the companions' size."),
      select(app, "sleep_after_secs", "Fall asleep after", "With no keyboard or mouse input.", [
        ["60", "1 minute"],
        ["120", "2 minutes"],
        ["300", "5 minutes"],
        ["600", "10 minutes"],
        ["1800", "30 minutes"],
        ["86400", "Never"],
      ], true),
    ),
  );

  const volume = h("input", { type: "range", id: "setting-volume", min: 0, max: 100, step: 5, value: String(settings.volume) });
  volume.addEventListener("change", () => void app.save({ volume: Number(volume.value) }));
  const voice = h("select", { id: "setting-voice" }, h("option", { value: "", text: "System voice" }));
  for (const v of [...(voices ?? [])].sort((a, b) => Number(!a.language.startsWith("en")) - Number(!b.language.startsWith("en")) || a.name.localeCompare(b.name)))
    voice.append(h("option", { value: v.name, text: `${v.name} (${v.language.replace("_", "-")})` }));
  voice.value = settings.voice;
  voice.addEventListener("change", () => void app.save({ voice: voice.value }));
  view.append(
    group(
      "Sound",
      "reminders",
      "sound",
      toggle(app, "sounds", "Sound cues", "Short sounds when a companion talks or something needs you."),
      row("Volume", null, volume, "setting-volume"),
      toggle(app, "speak", "Speak out loud", "Companions read their lines with a macOS voice instead of sounds. AI tools' text is read too."),
      row("Voice", "More voices: System Settings → Accessibility → Spoken Content.", h("div", { class: "inline" }, voice, button("Try", () => void invoke("speak", { text: "Byte here. The tests are ready to run.", voice: voice.value }).catch((e) => app.toast(String(e), undefined, true)))), "setting-voice"),
    ),
  );

  view.append(
    group(
      "Privacy",
      "info",
      "privacy",
      toggle(app, "hide_in_recordings", "Hide from screen recordings", "Asks macOS to keep companions and their cards out of screenshots, recordings and screen sharing. Works with tools that respect it; some recording tools may still show them."),
      select(app, "detail", "Card detail", "What companions' cards and notifications show to anyone who can see your screen. The Sidefolk window always shows everything.", [
        ["full", "Full preview (commands and paths)"],
        ["project", "Project and status"],
        ["status", "Status only (no project names)"],
      ]),
    ),
  );

  const terminalOptions: [string, string][] = [["auto", "Automatic (where your sessions run)"], ...(terminals ?? []).map((t): [string, string] => [t, TERMINAL_LABELS[t] ?? t])];
  view.append(
    group(
      "Connected tools",
      "terminal",
      "tools",
      h("p", { class: "muted", text: "Connect an AI tool to see its progress and requests here. Each change is explained first and a backup is kept." }),
      toolRow(app, "claude_hooks", "claude", "Claude Code", "Companions see Claude Code's work sessions and bring you its requests.", "Adds Sidefolk's hooks to Claude Code's settings (~/.claude/settings.json) and keeps a backup next to it.", "Companions stop seeing Claude Code sessions, and requests stay in Claude Code's own window. Only Sidefolk's hooks are removed; a backup is kept."),
      toolRow(app, "claude_tools", "tools-claude", "Companion tools for Claude Code", "Claude Code can send you a note, ask a question, set a reminder or check if you're around.", "Runs `claude mcp add` to register Sidefolk's tools for your user and keeps a backup of Claude's config.", "Claude Code can no longer reach you through a companion. Notes, questions and reminders from it stop."),
      toolRow(app, "codex_tools", "tools-codex", "Companion tools for Codex", "The same tools for Codex sessions.", "Runs `codex mcp add` to register Sidefolk's tools and keeps a backup of Codex's config.", "Codex can no longer reach you through a companion."),
      integrations.claude_hooks ? toggle(app, "pet_answers_permissions", "Answer requests on the companion", "When no terminal or editor is in front, the companion asks for up to 60 seconds. Otherwise the tool asks in its own window as usual.") : null,
      select(app, "terminal", "Open sessions in", "Where “Continue” opens an ended work session. A running session always comes forward where it is.", terminalOptions),
    ),
  );

  const shortcut = button(recording ? "Press keys…" : shortcutLabel(settings.shortcut), () => {
    recording = !recording;
    app.redraw(true);
    if (recording) app.toast("Press the new shortcut with ⌘, ⌃ or ⌥. Esc cancels.");
  }, `keys${recording ? " recording" : ""}`, { "aria-label": `Summon shortcut: ${shortcutLabel(settings.shortcut)}. Press to change.` });
  if (recording) {
    const onKey = (event: KeyboardEvent) => {
      event.preventDefault();
      if (event.key === "Escape") {
        recording = false;
        removeEventListener("keydown", onKey);
        return app.redraw(true);
      }
      const accelerator = acceleratorFrom(event);
      if (!accelerator) return;
      recording = false;
      removeEventListener("keydown", onKey);
      void app.save({ shortcut: accelerator }, `Shortcut is ${shortcutLabel(accelerator)}.`);
    };
    addEventListener("keydown", onKey);
    app.onLeave(() => removeEventListener("keydown", onKey));
    requestAnimationFrame(() => shortcut.focus());
  }
  view.append(
    group(
      "Shortcut and startup",
      "settings",
      "startup",
      row(settings.presence === "menubar" ? "Open Sidefolk" : "Summon shortcut", settings.presence === "menubar" ? "Opens your requests." : "Hides the companions, or calls them to your cursor.", shortcut),
      row("Start at login", "Opens Sidefolk when you log in.", button(integrations.start_at_login ? "Turn off" : "Turn on", () => void invoke("tray_action", { action: "login" }).then(() => app.refresh()))),
    ),
  );

  view.append(
    group(
      "About and help",
      "info",
      "about",
      row("Sidefolk", `Version ${app.state.version}`, h("span")),
      row("Your data", `Crew, journal, reminders and backups stay on this Mac: ${app.state.dataDir}`, button("Show in Finder", () => void invoke("reveal_data_dir", {}))),
      row("Logs", "Errors and crashes, to attach to a bug report.", button("Show in Finder", () => void invoke("reveal_data_dir", { logs: true }))),
      row("Welcome tour", "The first-minute setup again: comfort, name, tools.", button("Start", () => app.go("welcome"))),
      h(
        "div",
        { class: "help" },
        h("h3", { text: "Talking to companions" }),
        h("p", { text: "Click a companion for its status and to open its work session. Right-click for everything it can do. Double-click to type; the line under the field says what Enter will do before anything happens." }),
        h(
          "table",
          {},
          ...[
            ["open session · continue Byte", "Bring a work session forward, or continue it in a terminal"],
            ["call Byte · send Byte home", "Bring a companion out, or back to rest"],
            ["remind me tomorrow at 3 to …", "A reminder, from the right companion"],
            ["Byte: run the tests", "Codex works in Byte's project (uses Codex quota)"],
            ["Byte wear glasses · Byte become a fox", "Change a look without opening anything"],
          ].map(([command, what]) => h("tr", {}, h("td", {}, h("code", { text: command })), h("td", { text: what }))),
        ),
      ),
    ),
  );

  if (arg) requestAnimationFrame(() => view.querySelector(`#${CSS.escape(arg)}`)?.scrollIntoView({ block: "start" }));
  return view;
}
