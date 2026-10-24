import { applyTheme, themeOf } from "../theme";
import { notificationSetting } from "./notifications";
import { icon, mark, type IconName } from "../icons";
import { acceleratorFrom, shortcutLabel } from "../keys";
import { invoke, type Settings } from "./api";
import type { App } from "./app";
import { button, h, TERMINAL_LABELS } from "./dom";
import { cachedCharacters, characters as loadCharacters } from "./characters";
import { terminalControl } from "./setup";
import { header } from "./ui";
import { framesDir, MAIN_LOOK, ROSTER } from "../roster";

// Settings in plain language. Each control saves when it changes and says "Saved." only after
// the settings file is written. Connecting a tool opens the app's own confirmation, which
// explains the file it changes and keeps a backup.

let voices: { name: string; language: string }[] | null = null;
let terminals: string[] | null = null;
let recording = false;
let charactersLoaded = false;


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

/** The crew and the characters you made, as pictures to pick your companion's look from. */
function crewChoices(app: App) {
  const current = app.state.crew.main.look ?? MAIN_LOOK;
  const choices = h("fieldset", { class: "crew-choices" }, h("legend", { text: "Looks like" }));
  const choose = (id: string, name: string) => {
    if (id === current) return;
    void app.petAction({ action: "look", look: id === MAIN_LOOK ? null : id }, `${app.state.crew.main.name} looks like ${name} now.`);
  };
  const tile = (id: string, name: string, kind: string, picture: HTMLElement) => {
    const radio = h("input", { type: "radio", id: `look-${id}`, name: "look", value: id, checked: id === current });
    radio.addEventListener("change", () => choose(id, name));
    return h("label", { class: "crew-choice", for: radio.id }, radio, picture, h("strong", { text: name }), h("span", { class: "muted", text: kind }));
  };
  for (const m of ROSTER) choices.append(tile(m.id, m.name, m.kind, h("img", { src: `${framesDir(m.id, app.state.settings.art_style)}/idle.webp`, alt: "" })));
  for (const c of cachedCharacters()) choices.append(tile(c.id, c.name, "Made by you", h("span", { class: "crew-initial", "aria-hidden": "true", text: c.name.slice(0, 1).toUpperCase() })));
  return choices;
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

function settingsContents(app: App) {
  const { settings, integrations } = app.state;
  voices ?? void invoke<{ name: string; language: string }[]>("voices").then((v) => ((voices = v), app.redraw(true))).catch(() => (voices = []));
  if (!charactersLoaded) {
    charactersLoaded = true;
    void loadCharacters().then(() => app.redraw(true));
  }
  terminals ?? void invoke<string[]>("terminals").then((t) => ((terminals = t), app.redraw(true))).catch(() => (terminals = []));
  // Settings don't change while being read; only saves (forced) redraw this page.

  const view = h("div", { class: "view settings" }, ...header("Make Sidefolk comfortable.", "A few simple preferences. Everything here can change later."));

  view.append(
    group(
      "Your companion",
      "home",
      "companion",
      crewChoices(app),
      segmented(app, "art_style", "Style", "Soft 3D renders or flat 2D drawings of the same characters, for your companion and every Spark.", [
        ["3d", "3D"],
        ["2d", "2D"],
      ]),
      row("Your own", "Turn a drawing into a companion: one picture, or one per pose.", button("Make your own…", () => app.go("characters"))),
    ),
  );

  const terminalOptions: [string, string][] = [["auto", "Automatic"], ...(terminals ?? []).map((t): [string, string] => [t, TERMINAL_LABELS[t] ?? t])];
  view.append(
    group(
      "Terminal",
      "terminal",
      "terminal",
      select(app, "terminal", "Default terminal", "Where commands, new sessions and continued sessions open. Automatic uses the one your sessions run in, else a terminal you installed. A running session always comes forward where it is.", terminalOptions),
      terminalControl(),
      row("Command line tool", "In a project folder, “sidefolk here --name Backend” gives it a Spark; “sidefolk home” sends it home. Asks for your password once to install.", button("Install…", () => void invoke<string>("install_cli").then((done) => app.toast(done), (error) => app.toast(String(error), undefined, true)))),
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
      notificationSetting(app),
      row("Voice", "More voices: System Settings → Accessibility → Spoken Content.", h("div", { class: "inline" }, voice, button("Try", () => void invoke("speak", { text: "Pip here. Your reminder is due.", voice: voice.value }).catch((e) => app.toast(String(e), undefined, true)))), "setting-voice"),
    ),
  );

  const calendarOn = h("input", { type: "checkbox", class: "switch", role: "switch", id: "setting-calendar", checked: settings.calendar_heads_up, "aria-describedby": "setting-calendar-help" });
  const calendarNote = h("p", { class: "muted", "aria-live": "polite" });
  calendarOn.addEventListener("change", async () => {
    if (!calendarOn.checked) return void app.save({ calendar_heads_up: false });
    // Asked here, with the reason on screen, the first time it's turned on.
    const status = await invoke<string>("request_calendar").catch((e) => String(e));
    if (status === "allowed") return void app.save({ calendar_heads_up: true }, "Calendar heads-up is on.");
    calendarOn.checked = false;
    calendarNote.textContent = status === "denied" ? "macOS says no. Allow Sidefolk in System Settings → Privacy & Security → Calendars, then turn this on again." : status;
  });
  view.append(
    group(
      "Calendar",
      "reminders",
      "calendar",
      row("Meeting heads-up", "A few minutes before a meeting, your companion says so, with Join when there's a video link. Read from your Mac's calendars, never sent anywhere.", calendarOn, "setting-calendar"),
      calendarNote,
      settings.calendar_heads_up
        ? select(app, "calendar_lead_mins", "How early", null, [
            ["2", "2 minutes before"],
            ["5", "5 minutes before"],
            ["10", "10 minutes before"],
            ["15", "15 minutes before"],
          ], true)
        : null,
    ),
  );

  view.append(
    group(
      "Privacy",
      "info",
      "privacy",
      toggle(app, "hide_in_recordings", "Hide from screen recordings", "Asks macOS to keep the companion and its cards out of screenshots, recordings and screen sharing. While it's on, Mission Control shows a dark patch where the companion stands, so it's off unless you need it."),
    ),
  );

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
      row("Summon shortcut", "Hides the companion, or calls it to your cursor.", shortcut),
      row("Start at login", "Opens Sidefolk when you log in.", button(integrations.start_at_login ? "Turn off" : "Turn on", () => void invoke("tray_action", { action: "login" }).then(() => app.refresh()))),
      toggle(app, "hide_from_dock", "Hide from Dock", "Sidefolk leaves the Dock and ⌘Tab; open this window from the menu bar icon instead."),
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
      row(
        "Report a problem",
        "Copies a short report (versions, settings, recent errors; never your reminders, notes or names) to paste into an email or an issue.",
        button("Copy report", () =>
          void invoke<string>("problem_report")
            .then((report) => navigator.clipboard.writeText(report))
            .then(() => app.toast("Report copied. Add what happened at the top, then send it."), (error) => app.toast(String(error), undefined, true)),
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
  { id: "general", title: "General", glyph: "settings", groups: ["startup"], words: "login startup dock shortcut keyboard" },
  { id: "appearance", title: "Appearance", glyph: "idle", groups: ["appearance"], words: "theme dark light system colors" },
  { id: "companion", title: "Companion", glyph: "home", groups: ["companion", "desktop"], words: "pet pip name rename size look character import hide show" },
  { id: "calendar", title: "Reminders & calendar", glyph: "reminders", groups: ["calendar"], words: "meeting join lead time repeat snooze" },
  { id: "sound", title: "Notifications & sound", glyph: "reminders", groups: ["sound"], words: "notifications permission reminder volume speech voice speak" },
  { id: "tools", title: "AI tools", glyph: "terminal", groups: ["tools", "terminal"], words: "claude codex connections terminal automation command cli spark project session access" },
  { id: "privacy", title: "Privacy", glyph: "info", groups: ["privacy"], words: "screen recording capture sharing local" },
  { id: "accessibility", title: "Accessibility", glyph: "crew", groups: ["accessibility"], words: "motion reduced calm text large sleep idle" },
  { id: "help", title: "About & data", glyph: "info", groups: ["help"], words: "version help logs report export notebook data folder setup" },
];
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
  const wanted = CATEGORIES.find((c) => c.id === arg || c.groups.includes(arg));
  if (wanted) category = wanted.id;
  const selected = CATEGORIES.find((c) => c.id === category) ?? CATEGORIES[0];
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
    button([icon("back"), "Back to Sidefolk"], () => { query = ""; app.go("today"); }, "back settings-back"));
  const draw = () => {
    content.replaceChildren(...header(query.trim() ? "Search settings" : selected.title, query.trim() ? undefined : "Everything here can change later."));
    if (query.trim()) {
      const words = query.toLowerCase().trim().split(/\s+/);
      const results = h("div", { class: "settings-results" });
      for (const c of CATEGORIES) {
        const rows = c.groups.flatMap((id) => [...(groups.get(id)?.querySelectorAll<HTMLElement>(".setting") ?? [])]);
        const matches = rows.filter((row) => words.every((w) => `${c.title} ${c.words} ${row.textContent}`.toLowerCase().includes(w)));
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
      h("div", { class: "actions" }, button("Show companion", () => void invoke("tray_action", { action: "show" }).catch((e) => app.toast(String(e), undefined, true))), button("Hide companion", () => void app.tell("hide"))));
    }
    if (category === "calendar") content.append(h("div", { class: "card" }, h("h2", { text: "Your reminders" }), h("p", { class: "muted", text: "Manage repeating reminders, snooze and reminder history in Reminders." }), h("div", { class: "actions" }, button("Manage reminders", () => app.go("reminders")), button("Notification delivery", () => selectCategory(CATEGORIES[4])))));
    if (category === "tools") content.append(h("div", { class: "actions" }, button("Sessions & project companions", () => app.go("sessions")), button("Saved actions", () => app.go("actions"))));
    if (category === "help") content.append(h("div", { class: "actions" }, button("Notebooks & export", () => app.go("notes")), button("Saved actions", () => app.go("actions"))));
  };
  search.addEventListener("input", () => { query = search.value; draw(); });
  draw();
  return h("div", { class: "settings-layout" }, sidebar, content);
}


export function prepareSettings() { query = ""; }
