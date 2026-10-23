import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { JournalEntry } from "./away";
import { projects, renderActivity } from "./dashboard-activity";
import { renderHome, type Status } from "./dashboard-home";
import { acceleratorFrom, shortcutLabel } from "./keys";
import { PALETTES, SPECIES, type PaletteName, type SpeciesName } from "./pet/look";
import type { Reminder } from "./reminders";
import { describeDue, parseReminder } from "./when";

// The Sidefolk window: a live dashboard (Home, Activity) and every setting. Each control saves
// as soon as it changes. Agent connections open the app's own confirmation dialog, and crew
// changes and answers are carried out by the pets themselves, so this page never writes
// agent configs or crew.json directly.

type Settings = Record<string, string | number | boolean | null>;
type Integrations = Record<string, boolean>;
type Pet = { id: string; name: string; look: { species: string; palette: string; accessory: string }; bindings: { kind: string; key: string }[] };
type CrewFile = { main?: { name: string; look: Pet["look"] }; pets?: Pet[] };

const inTauri = "__TAURI_INTERNALS__" in window;
const invoke = inTauri ? tauriInvoke : preview();

const $ = <T extends HTMLElement>(selector: string) => document.querySelector<T>(selector)!;
const status = $("#status");
const say = (text: string, error = false) => {
  status.textContent = text;
  status.classList.toggle("error", error);
};
const attempt = async (work: () => Promise<unknown>, done = "Saved.") => {
  try {
    await work();
    say(done);
  } catch (error) {
    say(String(error), true);
  }
  await refresh();
};
const el = <K extends keyof HTMLElementTagNameMap>(tag: K, text?: string, className = "") => {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

// ---------------------------------------------------------------- tabs

const tabs = [...document.querySelectorAll<HTMLButtonElement>("nav [data-tab]")];
function show(tab: string) {
  for (const button of tabs)
    if (button.dataset.tab === tab) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  for (const section of document.querySelectorAll("main section")) (section as HTMLElement).hidden = section.id !== tab;
  say("");
  if (tab === "activity") void loadActivity();
}
for (const button of tabs) button.addEventListener("click", () => show(button.dataset.tab!));
const initial = new URLSearchParams(location.search).get("tab");
if (initial) show(initial);

// ---------------------------------------------------------------- general and agents

let settings: Settings = {};
const save = (change: Settings) => attempt(() => invoke("update_settings", { change }));

for (const input of document.querySelectorAll<HTMLInputElement | HTMLSelectElement>("input[data-setting], select[data-setting]")) {
  input.addEventListener("change", () => {
    const key = input.dataset.setting!;
    const value =
      input instanceof HTMLInputElement && input.type === "checkbox" ? input.checked : input.dataset.text !== undefined ? input.value : Number(input.value);
    void save({ [key]: value });
  });
}

for (const group of document.querySelectorAll<HTMLElement>(".segmented[data-setting]")) {
  for (const button of group.querySelectorAll<HTMLButtonElement>("button")) {
    button.addEventListener("click", () => void save({ [group.dataset.setting!]: button.dataset.value! }));
  }
}

// Voices installed on this Mac, English first.
const voiceSelect = $<HTMLSelectElement>("#voice");
void invoke<{ name: string; language: string }[]>("voices").then((voices) => {
  const sorted = [...voices].sort((a, b) => Number(!a.language.startsWith("en")) - Number(!b.language.startsWith("en")) || a.name.localeCompare(b.name));
  voiceSelect.append(
    ...sorted.map((v) => {
      const option = el("option", `${v.name} (${v.language.replace("_", "-")})`);
      option.value = v.name;
      return option;
    }),
  );
  voiceSelect.value = String(settings.voice ?? "");
});
$("#try-voice").addEventListener("click", () =>
  void invoke("speak", { text: "Hi! I'm your Sidefolk. I'll tell you when your agents need you.", voice: voiceSelect.value }).catch((e) => say(String(e), true)),
);

const LABELS: Record<string, [string, string]> = {
  claude_hooks: ["Connect…", "Disconnect…"],
  claude_tools: ["Add…", "Remove…"],
  codex_tools: ["Add…", "Remove…"],
  start_at_login: ["Turn on", "Turn off"],
};
for (const button of document.querySelectorAll<HTMLButtonElement>("[data-action]")) {
  button.addEventListener("click", () => {
    void invoke("tray_action", { action: button.dataset.action }).catch((error) => say(String(error), true));
    say(button.dataset.action === "login" ? "" : "Confirm in the dialog that opened.");
  });
}

// The shortcut is recorded by pressing it, not typed as "CommandOrControl+…".
const shortcut = $<HTMLButtonElement>("#shortcut");
let recording = false;
shortcut.addEventListener("click", () => {
  recording = !recording;
  shortcut.classList.toggle("recording", recording);
  shortcut.textContent = recording ? "Press keys…" : shortcutLabel(String(settings.shortcut));
  say(recording ? "Press the new shortcut, with ⌘, ⌃ or ⌥. Esc cancels." : "");
});
addEventListener("keydown", (event) => {
  if (!recording) return;
  event.preventDefault();
  if (event.key === "Escape") return shortcut.click();
  const accelerator = acceleratorFrom(event);
  if (!accelerator) return;
  recording = false;
  shortcut.classList.remove("recording");
  void save({ shortcut: accelerator });
});

// ---------------------------------------------------------------- crew

const crewList = $("#crew-list");
const projectOf = (pet: Pet) => pet.bindings.find((b) => b.kind === "project")?.key;
const folder = (path: string) => path.split("/").filter(Boolean).pop() ?? path;

function petRow(pet: Pet, main: boolean) {
  const row = el("div", undefined, "row pet");
  const dot = el("span", undefined, "dot");
  dot.style.background = PALETTES[pet.look.palette as PaletteName]?.body ?? PALETTES.snow.body;
  const text = el("div");
  const title = el("strong", pet.name);
  const species = SPECIES[pet.look.species as SpeciesName]?.label ?? "Imported model";
  const project = projectOf(pet);
  const agent = pet.bindings.find((b) => b.kind === "agent")?.key;
  text.append(title);
  text.append(el("p", main ? `${species} · the main pet, always out` : `${species} · looks after ${project ? folder(project) : agent === "codex" ? "Codex" : agent ? "Claude" : "a session"}`));
  const actions = el("div", undefined, "actions");
  const action = (label: string, run: () => void, className = "") => {
    const b = el("button", label, className);
    b.addEventListener("click", run);
    actions.append(b);
  };
  const id = main ? "main" : pet.id;
  if (!main) action("Call", () => void attempt(() => invoke("pet_action", { action: { action: "call", id } }), `${pet.name} is coming.`));
  action("Customize", () => void attempt(() => invoke("pet_action", { action: { action: "customize", id } }), `${pet.name}'s customizer is open by the pet.`));
  // Renamed in place; pauses the refresh so the field is not replaced while typing.
  action("Rename", () => {
    const field = el("input");
    field.type = "text";
    field.value = pet.name;
    field.maxLength = 24;
    field.setAttribute("aria-label", `New name for ${pet.name}`);
    editing = true;
    title.replaceWith(field);
    field.focus();
    field.select();
    const finish = (save: boolean) => {
      editing = false;
      const name = field.value.trim().replace(/\s+/g, " ");
      if (save && name && name !== pet.name)
        void attempt(() => invoke("pet_action", { action: { action: "run", id, text: `rename to ${name}` } }), `Renamed to ${name}.`);
      else void refresh();
    };
    field.addEventListener("keydown", (e) => {
      if (e.key === "Enter") finish(true);
      if (e.key === "Escape") finish(false);
    });
    field.addEventListener("blur", () => editing && finish(true));
  });
  // Forgetting takes a second click; kept outside the row so a refresh does not reset it.
  if (!main)
    action(
      confirming === id ? "Click to confirm" : "Forget",
      () => {
        if (confirming !== id) {
          confirming = id;
          say(project ? `Forget ${pet.name}? ${folder(project)} would go back to the main pet.` : `Forget ${pet.name}?`);
          setTimeout(() => {
            if (confirming === id) confirming = null;
            void refresh();
          }, 4_000);
          return void refresh();
        }
        confirming = null;
        void attempt(() => invoke("pet_action", { action: { action: "forget", id } }), `${pet.name} is gone.`);
      },
      "danger",
    );
  row.append(dot, text, actions);
  return row;
}

/** True while a name is being edited, so the periodic refresh leaves the list alone. */
let editing = false;
/** The pet whose Forget button was clicked once. */
let confirming: string | null = null;

function renderCrew(crew: CrewFile) {
  if (editing) return;
  const rows: HTMLElement[] = [];
  if (crew.main) rows.push(petRow({ id: "main", name: crew.main.name, look: crew.main.look, bindings: [] }, true));
  for (const pet of crew.pets ?? []) rows.push(petRow(pet, false));
  if (rows.length < 2) rows.push(el("p", "No crew yet. Add one below, or say yes when the main pet offers one for a new project.", "empty"));
  crewList.replaceChildren(...rows);
}

$("#add-pet").addEventListener("click", async () => {
  const project = await invoke<string | null>("pick_project").catch((error) => (say(String(error), true), null));
  if (project) await attempt(() => invoke("pet_action", { action: { action: "create", project } }), `A pet for ${folder(project)} is on its way.`);
});

// ---------------------------------------------------------------- reminders

const reminderText = $<HTMLInputElement>("#reminder-text");
const reminderWhen = $<HTMLInputElement>("#reminder-when");
const reminderPreview = $("#reminder-preview");
const local = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);

function planned(): { what: string; due: Date } | null {
  const text = reminderText.value.trim();
  if (!text) return null;
  if (reminderWhen.value) return { what: text, due: new Date(reminderWhen.value) };
  return parseReminder(text);
}
const updatePreview = () => {
  const plan = planned();
  reminderPreview.textContent = !reminderText.value.trim()
    ? "Type what to remember. Put the time in the text or pick it."
    : plan
      ? `Reminds you ${describeDue(plan.due)}: ${plan.what}`
      : "Add a time, like “tomorrow at 10”, or pick one.";
};
reminderText.addEventListener("input", updatePreview);
reminderWhen.addEventListener("input", updatePreview);
$("#reminder-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const plan = planned();
  if (!plan) return say("Add a time, like “tomorrow at 10”.", true);
  if (plan.due.getTime() <= Date.now()) return say("That time has passed.", true);
  void attempt(async () => {
    await invoke("add_reminder", { text: plan.what, due: plan.due.getTime(), project: null });
    reminderText.value = reminderWhen.value = "";
    updatePreview();
  }, `Reminder set for ${describeDue(plan.due)}.`);
});
reminderWhen.min = local(new Date());
updatePreview();

function renderReminders(list: Reminder[]) {
  const open = list.filter((r) => !r.done).sort((a, b) => a.due - b.due);
  const rows = open.map((r) => {
    const row = el("div", undefined, "row reminder");
    const text = el("div");
    text.append(el("strong", r.text));
    const where = r.project ? ` · ${folder(r.project)}` : "";
    const by = r.from === "you" ? "" : ` · set by ${r.from === "codex" ? "Codex" : "Claude"}`;
    text.append(el("p", `${r.due < Date.now() ? "Due " : ""}${describeDue(new Date(r.due))}${where}${by}`));
    const actions = el("div", undefined, "actions");
    const done = el("button", "Done");
    done.addEventListener("click", () => void attempt(() => invoke("update_reminder", { id: r.id, change: { done: true } }), "Marked done."));
    const later = el("button", "+1 hour");
    later.addEventListener("click", () =>
      void attempt(() => invoke("update_reminder", { id: r.id, change: { due: Math.max(r.due, Date.now()) + 3_600_000 } }), "Moved an hour later."),
    );
    actions.append(later, done);
    row.append(text, actions);
    return row;
  });
  $("#reminder-list").replaceChildren(...(rows.length ? rows : [el("p", "Nothing coming up.", "empty")]));
}

// ---------------------------------------------------------------- about

$("#reveal").addEventListener("click", () => void invoke("reveal_data_dir", {}));
$("#reveal-logs").addEventListener("click", () => void invoke("reveal_data_dir", { logs: true }));
$("#welcome").addEventListener("click", () => void attempt(() => invoke("pet_action", { action: { action: "welcome" } }), "The main pet is showing it."));
void invoke<{ version: string; data_dir: string }>("app_info").then((info) => {
  $("#version").textContent = `Version ${info.version} · ${info.data_dir}`;
});

// ---------------------------------------------------------------- home and activity

const petAction = (action: Record<string, string>, done: string) => attempt(() => invoke("pet_action", { action }), done);
let live: Status = { pets: [], waiting: [] };
let latest: { reminders: Reminder[]; integrations: Integrations } = { reminders: [], integrations: {} };
const drawHome = () =>
  renderHome(live, latest.reminders, latest.integrations, {
    answer: (id, value) => void petAction({ action: "answer", id, text: value }, "Answered."),
    call: (id) => void petAction({ action: "call", id }, "On its way."),
    customize: (id) => void petAction({ action: "customize", id }, "The customizer is open by the pet."),
    open: show,
  });

let period = 1;
const activityProject = $<HTMLSelectElement>("#activity-project");
async function loadActivity() {
  const entries = await invoke<JournalEntry[]>("journal_since", { since: Date.now() - period * 86_400_000 });
  const chosen = activityProject.value;
  activityProject.replaceChildren(
    el("option", "All projects"),
    ...projects(entries).map((p) => {
      const option = el("option", p.split("/").filter(Boolean).pop());
      option.value = p;
      return option;
    }),
  );
  (activityProject.firstElementChild as HTMLOptionElement).value = "";
  activityProject.value = chosen;
  renderActivity($("#activity-list"), entries, activityProject.value);
  for (const b of document.querySelectorAll<HTMLButtonElement>("#period button")) b.setAttribute("aria-checked", String(Number(b.dataset.value) === period));
}
for (const b of document.querySelectorAll<HTMLButtonElement>("#period button"))
  b.addEventListener("click", () => {
    period = Number(b.dataset.value);
    void loadActivity();
  });
activityProject.addEventListener("change", () => void loadActivity());

// ---------------------------------------------------------------- state

async function refresh() {
  const [next, integrations, crew, reminders, status] = await Promise.all([
    invoke<Settings>("get_settings"),
    invoke<Integrations>("integrations"),
    invoke<CrewFile | null>("get_crew"),
    invoke<Reminder[]>("list_reminders"),
    invoke<Status | null>("get_status"),
  ]);
  if (status?.pets) live = status;
  latest = { reminders, integrations };
  drawHome();
  settings = next;
  for (const input of document.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-setting]:is(input, select)")) {
    if (document.activeElement === input) continue;
    const value = settings[input.dataset.setting!];
    if (input instanceof HTMLInputElement && input.type === "checkbox") input.checked = Boolean(value);
    else input.value = String(value ?? "");
  }
  for (const group of document.querySelectorAll<HTMLElement>(".segmented"))
    for (const button of group.querySelectorAll<HTMLButtonElement>("button"))
      button.setAttribute("aria-checked", String(settings[group.dataset.setting!] === button.dataset.value));
  if (!recording) shortcut.textContent = shortcutLabel(String(settings.shortcut));
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-status]")) {
    const on = integrations[button.dataset.status!];
    button.textContent = LABELS[button.dataset.status!][on ? 1 : 0];
  }
  for (const pill of document.querySelectorAll<HTMLElement>("[data-pill]")) {
    const on = integrations[pill.dataset.pill!];
    pill.textContent = on ? "Connected" : "Off";
    pill.classList.toggle("on", on);
  }
  renderCrew(crew ?? {});
  renderReminders(reminders);
}

// Confirmations happen in dialogs and pets change on the desktop; pick both up.
addEventListener("focus", () => void refresh());
setInterval(() => void refresh(), 3_000);
if (inTauri) void listen("reminders-changed", () => void refresh());
// The pets publish their state when it changes; Home redraws at once.
if (inTauri)
  void listen<Status>("status", (e) => {
    live = e.payload;
    drawHome();
  });
void refresh();

/** Browser preview only: sample data so the page can be looked at without the app. */
function preview(): typeof tauriInvoke {
  const state = {
    settings: { shortcut: "CommandOrControl+Shift+Space", pet_size: "medium", calm: false, large_text: false, sleep_after_secs: 120, hide_in_recordings: true, pet_answers_permissions: true, sounds: true, volume: 60, speak: false, voice: "" },
    crew: {
      main: { name: "Sidefolk", look: { species: "bunny", palette: "snow", accessory: "none" } },
      pets: [{ id: "p", name: "Pip", look: { species: "cat", palette: "cocoa", accessory: "glasses" }, bindings: [{ kind: "project", key: "/Users/you/git/api" }] }],
    },
    reminders: [{ id: "r", text: "Review the PR", due: Date.now() + 86_400_000, project: "", from: "claude", created: 0, done: false, fired: false }],
  };
  return (async (command: string, args?: Record<string, unknown>) => {
    if (command === "get_settings") return state.settings;
    if (command === "update_settings") return Object.assign(state.settings, (args as { change: object }).change);
    if (command === "integrations") return { claude_hooks: true, claude_tools: false, codex_tools: false, start_at_login: false };
    if (command === "get_crew") return state.crew;
    if (command === "list_reminders") return state.reminders;
    if (command === "app_info") return { version: "preview", data_dir: "~/Library/Application Support/dev.sidefolk.companion" };
    if (command === "voices") return [{ name: "Samantha", language: "en_US" }, { name: "Daniel", language: "en_GB" }];
    if (command === "journal_since")
      return [
        { at: Date.now() - 600_000, source: "claude", session: "s", project: "/Users/you/git/api", kind: "prompt", detail: "Add rate limiting to the login route" },
        { at: Date.now() - 300_000, source: "claude", session: "s", project: "/Users/you/git/api", kind: "ask", detail: "Run a command? npm test" },
        { at: Date.now() - 280_000, source: "claude", session: "s", project: "/Users/you/git/api", kind: "answer", detail: "allowed" },
        { at: Date.now() - 60_000, source: "claude", session: "s", project: "/Users/you/git/api", kind: "done", detail: "Rate limiting added; 14 tests pass." },
      ];
    if (command === "get_status")
      return {
        pets: [
          { id: "main", name: "Sidefolk", label: "Sidefolk", main: true, project: null, look: { species: "bunny", palette: "snow" }, out: true, clip: "idle", sessions: [], outcomes: [] },
          {
            id: "p",
            name: "Pip",
            label: "Pip · api",
            main: false,
            project: "/Users/you/git/api",
            look: { species: "cat", palette: "cocoa" },
            out: true,
            clip: "alert",
            sessions: [{ source: "claude", verb: "needs you", state: "waiting", detail: "", at: Date.now() }],
            outcomes: [{ kind: "done", source: "claude", detail: "Rate limiting added; 14 tests pass.", at: Date.now() - 3_600_000 }],
          },
        ],
        waiting: [{ id: "claude-1", pet: "p", who: "Pip · api · Claude", title: "Run a command?", detail: "npm test -- --watch=false", choices: [{ label: "Allow", value: "allow" }, { label: "Deny", value: "deny" }, { label: "In terminal", value: "defer" }] }],
      };
    throw new Error(`${command} needs the desktop app.`);
  }) as typeof tauriInvoke;
}
