import { problem } from "../voice";
import { applyTheme, themeOf } from "../theme";
import { notificationSetting } from "./notifications";
import { icon, mark, type IconName } from "../icons";
import { acceleratorFrom, shortcutLabel } from "../keys";
import { invoke, inTauri, type Settings } from "./api";
import type { App } from "./app";
import { button, h, TERMINAL_LABELS } from "./dom";
import { terminalControl } from "./setup";
import { header } from "./ui";
import { sheet } from "./dialog";
import { CHARACTERS, lookOf, picture } from "../roster";

// Settings in plain language. Each control saves when it changes and says "Saved." only after
// the settings file is written. Connecting a tool opens the app's own confirmation, which
// explains the file it changes and keeps a backup.

let terminals: string[] | null = null;
let recording = false;


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
    void app.save({ [key]: numeric ? Number(control.value) : control.value });
  });
  return row(label, description, control, id);
}

function segmented(app: App, key: keyof Settings, label: string, description: string, options: [string, string][]) {
  const control = h("fieldset", { class: "segmented", "aria-label": label });
  for (const [value, text] of options) {
    const id = `${key}-${value}`;
    const radio = h("input", { type: "radio", id, name: String(key), value, checked: app.state.settings[key] === value });
    radio.addEventListener("change", () => void app.save({ [key]: value }));
    control.append(h("label", { for: id }, radio, text));
  }
  return h("div", { class: "setting stack" }, h("div", { class: "setting-text" }, h("strong", { text: label }), h("p", { class: "muted", text: description })), control);
}

/** Pip or Spark, as pictures; the companion on the desktop changes at once. */
function characterChoices(app: App) {
  const current = lookOf(app.state.crew.main.look);
  const choices = h("fieldset", { class: "crew-choices" }, h("legend", { text: "Your companion is" }));
  for (const c of CHARACTERS) {
    const radio = h("input", { type: "radio", id: `look-${c.id}`, name: "look", value: c.id, checked: c.id === current });
    radio.addEventListener("change", () => {
      if (c.id !== current) void app.petAction({ action: "look", look: c.id }, `Your companion is ${c.name} now.`);
    });
    choices.append(h("label", { class: "crew-choice", for: radio.id }, radio, h("img", { src: picture(c.id), alt: "" }), h("strong", { text: c.name }), h("span", { class: "muted", text: c.kind })));
  }
  return choices;
}

/** Claude Code's connection in words (docs/V1.md V1-D13): one state, and Repair when it needs it. */
const HEALTH: Record<string, [string, string]> = {
  off: ["Not connected", ""],
  waiting: ["Connected", "Waiting for your first Claude Code session."],
  working: ["Working", "Hearing your Claude Code sessions."],
  repair: ["Needs repair", "Part of the connection is missing, outdated, or points to a moved Sidefolk. Repair hooks and companion tools together."],
  unavailable: ["Can't listen", ""],
};

function toolRow(app: App, key: "claude_hooks" | "claude_tools" | "codex_tools", action: string, title: string, what: string, change: string, stops: string) {
  const on = app.state.integrations[key];
  const health = key === "claude_hooks" ? app.state.integrations.claude_health : null;
  if (health === "repair" || health === "unavailable" || health === "waiting" || health === "working") {
    const [word, line] = HEALTH[health];
    return h(
      "div",
      { class: "setting tool" },
      h(
        "div",
        { class: "setting-text" },
        h("strong", {}, title, " ", h("span", { class: `pill${health === "working" || health === "waiting" ? " on" : ""}`, text: word })),
        h("p", { class: "muted", text: health === "unavailable" ? (problem(app.state.integrations.hook_error)) : line || what }),
        h("details", {}, h("summary", { text: "What disconnecting does" }), h("p", { class: "muted", text: stops })),
      ),
      button(app.state.integrations.claude_disconnect_pending ? "Finish disconnecting…" : health === "repair" ? "Repair…" : "Disconnect…", () => {
        void invoke("tray_action", { action }).catch((e) => app.toast(problem(e), undefined, true));
        app.toast("Confirm in the dialog that opened.");
      }, health === "repair" ? "primary" : ""),
    );
  }
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
      void invoke("tray_action", { action }).catch((e) => app.toast(problem(e), undefined, true));
      app.toast("Confirm in the dialog that opened.");
    }, on ? "" : "primary"),
  );
}

/** Disconnect & uninstall (docs/V1.md V1-X2): says exactly what happens, then does it and quits. */
function uninstallSheet() {
  const remove = h("input", { type: "checkbox", id: "uninstall-delete-data" });
  const body = h(
    "form",
    { "aria-label": "Disconnect and uninstall" },
    h("p", { text: "Sidefolk will remove its hooks from Claude Code and its tools from Claude Code and Codex, keeping a backup of each settings file. Your other settings stay as they are. It also stops opening at login, then quits." }),
    h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("label", { for: remove.id, text: "Also move my reminders, notes and backups to the Bin" }), h("p", { class: "muted", text: "Off: they stay in your data folder, and come back if you install Sidefolk again." })), remove),
  );
  const editor = sheet("Disconnect & uninstall?", body);
  const done = h("ul", { class: "help-list", "aria-live": "polite" });
  const go = h("button", { type: "submit", class: "danger", text: "Uninstall" });
  body.append(done, h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close), go));
  body.addEventListener("submit", async (event) => {
    event.preventDefault();
    go.disabled = true;
    try {
      const lines = await invoke<string[]>("uninstall_sidefolk", { deleteData: remove.checked });
      done.replaceChildren(...[...lines, "Sidefolk quits in a few seconds. Then drag it from Applications to the Bin."].map((line) => h("li", { text: line })));
    } catch (error) {
      done.replaceChildren(h("li", { text: problem(error) }));
      go.disabled = false;
    }
  });
}

function settingsContents(app: App) {
  const { settings, integrations } = app.state;
  terminals ?? void invoke<string[]>("terminals").then((t) => ((terminals = t), app.redraw(true))).catch(() => (terminals = []));
  // Settings don't change while being read; only saves (forced) redraw this page.

  const view = h("div", { class: "view settings" }, ...header("Make Sidefolk comfortable.", "A few simple preferences. Everything here can change later."));

  view.append(group("Your companion", "home", "companion", characterChoices(app)));

  const terminalOptions: [string, string][] = [["auto", "Automatic"], ...(terminals ?? []).map((t): [string, string] => [t, TERMINAL_LABELS[t] ?? t])];
  view.append(
    group(
      "Terminal",
      "terminal",
      "terminal",
      select(app, "terminal", "Default terminal", "Where commands, new sessions and continued sessions open. Automatic uses the one your sessions run in, else a terminal you installed. A running session always comes forward where it is.", terminalOptions),
      terminalControl(),
      h("table", { class: "host-matrix" }, h("caption", { text: "Host support" }),
        h("thead", {}, h("tr", {}, ...["Host", "Open", "That session is focused"].map((text) => h("th", { scope: "col", text })))),
        h("tbody", {}, ...[
          ["Terminal.app", "Exact tab (tty)", "Exact: frontmost and the selected tab’s tty"],
          ["iTerm2", "Exact tab (tty)", "Exact"],
          ["Ghostty 1.3+", "Bring forward + select the session there", "Only if frontmost and it hosts exactly one live Claude session"],
          ["WezTerm", "Bring forward", "As Ghostty"],
          ["VS Code / Cursor", "Bring that project’s window forward, else the app", "As Ghostty"],
          ["Warp", "Bring forward", "Never"],
          ["Claude desktop", "Bring forward", "Never"],
          ["tmux / ssh / unknown", "Running in tmux on ttys004 · Copy attach command", "Never"],
          ["Ended session", "claude --resume <id> in the default terminal", "—"],
        ].map(([host, open, focus]) => h("tr", {}, h("th", { scope: "row", text: host }), h("td", { text: open }), h("td", { text: focus }))))),
      h("p", { class: "muted", text: "Ghostty has no tty in its scripting dictionary. Exact WezTerm panes are not verified. Codex beta offers companion tools; approvals stay in Codex." }),
    ),
  );

  view.append(
    group(
      "On your desktop",
      "home",
      "desktop",
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
      toggle(app, "large_text", "Larger text", "Bigger cards and text, here and on the desktop, without changing the companion's size."),
    ),
    group("Sleep", "idle", "sleep",
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
  view.append(
    group(
      "Sound",
      "reminders",
      "sound",
      (() => {
        const quiet = h("input", { type: "checkbox", class: "switch", role: "switch", id: "setting-quiet", checked: !settings.sounds });
        quiet.addEventListener("change", () => void app.save({ sounds: !quiet.checked }));
        return row("Quiet", "Stops all companion sounds. Notifications still follow your Mac’s settings.", quiet, quiet.id);
      })(),
      select(app, "snooze_mins", "Default snooze", "Moves only the current reminder, leaving repeats anchored.", [["10", "10 minutes"], ["30", "30 minutes"], ["60", "1 hour"]], true),
      row("Volume", null, volume, "setting-volume"),
      notificationSetting(app),
    ),
  );

  view.append(
    group(
      "Privacy",
      "info",
      "privacy",
      h("p", { text: "Your notes, reminders and settings stay on this Mac. Sidefolk does not upload them. Agent connections run locally; each agent has its own privacy policy." }),
      toggle(app, "journal_enabled", "Keep session history", "New history keeps the first prompt line (up to 500 characters) and dated events for 7 days, without tool input or agent output. Off stops new records. Older history may contain more detail; Clear removes it."),
      row("Session history", "Clear dated session history now. Your work log, reminders and backups stay.", button("Clear history…", () => {
        const body = h("div", {}, h("p", { text: "Remove session history from this Mac? This cannot be undone. Your work log, reminders and backups stay." }));
        const editor = sheet("Clear session history?", body);
        const clear = button("Clear history", async () => {
          clear.disabled = true;
          try { await invoke("clear_history"); editor.close(); app.toast("Session history cleared."); }
          catch (error) { app.toast(problem(error), undefined, true); clear.disabled = false; }
        }, "danger");
        body.append(h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close), clear));
      })),
      toggle(app, "hide_in_recordings", "Hide from screen recordings", "Asks macOS to keep the companion and its cards out of screenshots, recordings and screen sharing. While it's on, Mission Control shows a dark patch where the companion stands, so it's off unless you need it."),
    ),
  );

  view.append(
    group(
      "Connected tools",
      "terminal",
      "tools",
      h("p", { class: "muted", text: "Connect an AI tool to see its progress and requests here. Each change is explained first and a backup is kept." }),
      integrations.hook_error ? h("p", { class: "field-error", role: "alert", text: problem(integrations.hook_error) }) : null,
      toolRow(app, "claude_hooks", "claude", "Claude Code", "Follow Claude Code sessions, review requests, and receive its notes and reminders.", "Adds local session hooks and companion tools through Claude Code’s CLI. Each config is backed up before changing it.", "Disconnects Sidefolk’s hooks and companion tools, with backups. Requests stay in Claude Code’s own window."),
      toolRow(app, "codex_tools", "tools-codex", "Companion tools for Codex", "The same tools for Codex sessions.", "Runs `codex mcp add` to register Sidefolk's tools and keeps a backup of Codex's config.", "Codex can no longer reach you through a companion."),
      integrations.claude_hooks ? toggle(app, "pet_answers_permissions", "Answer requests on the companion", "When you are away from that exact session, your companion holds the request. Returning to the session releases it there. If time runs out, Claude Code asks in its own window.") : null,
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
      row("Summon shortcut", "Calls the companion to your cursor and focuses Quick add.", shortcut),
      row("Start at login", "Opens Sidefolk when you log in.", button(integrations.start_at_login ? "Turn off" : "Turn on", () => void invoke("tray_action", { action: "login" }).then(() => app.refresh()))),
      toggle(app, "hide_from_dock", "Hide from Dock", "Sidefolk leaves the Dock and ⌘Tab; open this window from the menu bar icon instead."),

    ),
  );

  // Labs (docs/V1.md F-10, F-17): off by default, never needed for everyday use.
  view.append(
    group(
      "Labs",
      "settings",
      "labs",
      toggle(app, "your_week", "Your week", "On Friday from 4 PM, your companion shows what you logged this week, ready to copy."),
      toggle(app, "labs_commands", "Commands", "Type “$ npm test in api” to Pip: you see the exact command and folder first, then it opens in your terminal. Plain sentences never run as commands."),
      toggle(app, "labs_sessions", "Start sessions", "Start Claude Code or Codex in a folder from Pip or the Sessions page."),
    ),
  );

  view.append(
    group(
      "About and help",
      "info",
      "help",
      row("Sidefolk", `Version ${app.state.version}`, h("span")),
      row("Your data", `Your companion, journal, reminders and backups stay on this Mac: ${app.state.dataDir}`, button("Show in Finder", () => void invoke("reveal_data_dir", {}))),
      row("Logs", "Errors and crashes, to attach to a bug report.", button("Show in Finder", () => void invoke("reveal_data_dir", { logs: true }))),
      row("Setup guide", "The short introduction from the first launch.", button("Run setup again", () => app.go("setup", "start"))),
      row("Disconnect & uninstall", "Removes what Sidefolk added to Claude Code and Codex (with backups), turns off opening at login, and quits. Your data stays unless you choose otherwise.", button("Disconnect & uninstall…", () => uninstallSheet(), "danger")),
      row(
        "Report a problem",
        "Copies a short report (versions, settings, recent errors; never your reminders, notes or names) to paste into an email or an issue.",
        button("Copy report", () =>
          void invoke<string>("problem_report")
            .then((report) => navigator.clipboard.writeText(report))
            .then(() => app.toast("Report copied. Add what happened at the top, then send it."), (error) => app.toast(problem(error), undefined, true)),
        ),
      ),
      h(
        "div",
        { class: "help" },
        h("h3", { text: "Talking to your companion" }),
        h("p", { text: "Click the companion (or right-click) and type. The line under the field says what Enter will do before anything happens. Everything here is understood on your Mac, without AI." }),
        h(
          "table",
          {},
          ...[
            ["remind me tomorrow at 9 to check the results", "A reminder; Pip brings it at that time"],
            ["reminders", "What's coming up"],
            ["open session · open api session", "Bring a work session forward, or continue it in a terminal"],
            ["open Sidefolk · hide", "This window, or hide the companion"],
            ["rename to Bun", "A new name for your companion"],
          ].map(([command, what]) => h("tr", {}, h("td", {}, h("code", { text: command })), h("td", { text: what }))),
        ),
      ),
    ),
  );


  view.append(appearance(app));
  return view;
}


type Category = { id: string; title: string; glyph: IconName; groups: string[]; words: string };
const CATEGORIES: Category[] = [
  { id: "general", title: "General", glyph: "settings", groups: ["startup", "appearance", "accessibility", "sound", "labs"], words: "login startup dock shortcut keyboard theme dark light motion text sound notifications labs commands" },
  { id: "companion", title: "Companion", glyph: "home", groups: ["companion", "desktop", "sleep"], words: "pet pip spark robot bunny character name rename size position sleep hide show" },
  { id: "agents", title: "Agents", glyph: "terminal", groups: ["tools", "terminal"], words: "claude codex connections terminal automation session hooks health repair" },
  { id: "privacy", title: "Privacy & data", glyph: "info", groups: ["privacy", "help"], words: "screen recording capture sharing local version help logs report export notebook data folder setup uninstall" },
];
const ALIASES: Record<string, string> = { appearance: "general", sound: "general", accessibility: "general", tools: "agents", help: "privacy" };
let category = "general";
try { category = localStorage.getItem("sidefolk-settings-category") ?? category; } catch { /* Optional convenience. */ }
let query = "";
let themeResult = "Changes save automatically.";

function appearance(app: App) {
  const selected = themeOf(app.state.settings.theme);
  const choices = h("fieldset", { class: "theme-choices" }, h("legend", { text: "Theme" }));
  const result = h("p", { class: "hint", role: "status", text: themeResult });
  for (const [value, label] of [["system", "System"], ["light", "Light"], ["dark", "Dark"]] as const) {
    const radio = h("input", { type: "radio", id: `theme-${value}`, name: "theme", value, checked: selected === value });
    const tile = h("label", { class: `theme-choice ${value}`, for: radio.id },
      h("span", { class: "theme-thumbnail", "aria-hidden": "true" }, h("span"), h("span"), h("span")),
      h("span", { class: "inline" }, radio, h("strong", { text: label })),
    );
    radio.addEventListener("change", async () => {
      for (const input of choices.querySelectorAll("input")) input.disabled = true;
      result.textContent = "Saving…";
      const before = themeOf(app.state.settings.theme);
      applyTheme(value);
      const saved = await app.save({ theme: value }, "Appearance saved.");
      themeResult = saved ? "Saved automatically." : "Appearance wasn't saved. Choose a theme to retry.";
      if (!saved) applyTheme(before);
      app.redraw(true);
      document.getElementById(`theme-${saved ? value : before}`)?.focus();
    });
    choices.append(tile);
  }
  return group("Theme", "idle", "appearance", choices,
    h("p", { class: "muted", text: selected === "system" ? "Follows your Mac automatically, including changes during the day." : `Always use ${selected} appearance. Choose System to follow your Mac.` }),
    h("div", { class: "card theme-preview" }, h("span", { class: "with-icon" }, icon("reminders"), h("strong", { text: "Review launch notes" })), h("p", { class: "meta", text: "Preview · Today at 15:00" })),
    h("p", { class: "muted", text: "Applies to Sidefolk windows and companion cards. Your companion and logo keep their look." }), result,
  );
}

/** One searchable settings surface; old deep links still land on their original group. */
export function renderSettings(app: App, arg: string) {
  const all = settingsContents(app);
  const groups = new Map([...all.querySelectorAll<HTMLElement>("section[id]")].map((node) => [node.id, node]));
  const wanted = CATEGORIES.find((c) => c.id === (ALIASES[arg] ?? arg) || c.groups.includes(arg));
  if (wanted) category = wanted.id;
  const selected = CATEGORIES.find((c) => c.id === (ALIASES[category] ?? category)) ?? CATEGORIES[0];
  category = selected.id;
  try { localStorage.setItem("sidefolk-settings-category", category); } catch { /* Optional convenience. */ }
  const content = h("section", { class: "settings-content" });
  const search = h("input", { id: "settings-search", type: "search", placeholder: "Search settings", "aria-label": "Search settings", value: query });
  const selectCategory = (c: Category) => { query = ""; app.go("settings", c.id); };
  const mobile = h("select", { class: "settings-mobile", "aria-label": "Settings category" }, ...CATEGORIES.map((c) => h("option", { value: c.id, text: c.title })));
  mobile.value = category;
  mobile.addEventListener("change", () => selectCategory(CATEGORIES.find((c) => c.id === mobile.value)!));
  const links = h("div", { class: "settings-categories", "aria-label": "Settings categories" });
  for (const c of CATEGORIES) links.append(button([icon(c.glyph), c.title], () => selectCategory(c), "", { "aria-current": c.id === category ? "page" : undefined }));
  const sidebar = h("aside", { class: "settings-sidebar" }, h("div", { class: "drag", "data-tauri-drag-region": true }),
    h("div", { class: "brand" }, mark(30), h("span", { class: "wordmark", text: "sidefolk" })), h("h2", { text: "Settings" }), search, mobile, links,
    inTauri ? null : button("Close Settings", () => { query = ""; app.go("today"); }, "back settings-back"));
  const draw = () => {
    content.replaceChildren(...header(query.trim() ? "Search settings" : selected.title, query.trim() ? undefined : "Everything here can change later."));
    if (query.trim()) {
      const words = query.toLowerCase().trim().split(/\s+/);
      const results = h("div", { class: "settings-results" });
      for (const c of CATEGORIES) {
        const rows = c.groups.flatMap((id) => [...(groups.get(id)?.querySelectorAll<HTMLElement>(".setting") ?? [])]);
        const matches = rows.filter((row) => words.every((w) => `${c.title} ${row.textContent}`.toLowerCase().includes(w)));
        const broad = words.every((w) => `${c.title} ${c.words}`.toLowerCase().includes(w));
        if (!matches.length && !broad) continue;
        const hits = matches.length ? matches : [null];
        for (const row of hits) {
          const label = row?.querySelector("label, strong")?.textContent ?? c.title;
          results.append(button(h("span", {}, h("strong", { text: label }), h("span", { class: "meta", text: c.title })), () => {
            selectCategory(c);
            const target = row?.querySelector<HTMLElement>("[id]")?.id;
            if (target) requestAnimationFrame(() => document.getElementById(target)?.focus());
          }, "settings-hit"));
        }
      }
      content.append(h("p", { class: "hint", role: "status", text: results.childElementCount ? `${results.childElementCount} results` : "No settings match. Try theme, sound or shortcut." }), results,
        button("Clear search", () => { query = ""; search.value = ""; draw(); search.focus(); }, "quiet"));
      return;
    }
    for (const id of selected.groups) {
      const group = groups.get(id);
      if (group) content.append(group);
    }
    if (category === "companion") {
      const rename = h("input", { id: "companion-name", type: "text", value: app.state.crew.main.name, maxlength: 24 });
      content.append(h("form", { class: "card", onsubmit: async (event: Event) => {
        event.preventDefault();
        if (rename.value.trim()) { app.toast(await app.tell(`rename to ${rename.value.trim()}`)); await app.refresh(); }
      } }, h("div", { class: "field" }, h("label", { for: rename.id, text: "Companion name" }), rename), h("div", { class: "actions" }, h("button", { type: "submit", text: "Save name" }))),
      h("div", { class: "actions" }, button("Show companion", () => void invoke("tray_action", { action: "show" }).catch((e) => app.toast(problem(e), undefined, true))), button("Hide companion", () => void app.tell("hide")), button("Move to cursor", () => void invoke("tray_action", { action: "call" }).catch((e) => app.toast(problem(e), undefined, true)))));
    }
    if (category === "agents") content.append(h("div", { class: "actions" }, button("Sessions", () => app.go("sessions"))));
    if (category === "privacy") content.append(h("div", { class: "actions" }, button("Notebooks & export", () => app.go("notes"))));
  };
  search.addEventListener("input", () => { query = search.value; draw(); });
  draw();
  return h("div", { class: "settings-layout" }, sidebar, content);
}


export function prepareSettings() { query = ""; }
