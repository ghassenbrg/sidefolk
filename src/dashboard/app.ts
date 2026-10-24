import { applyTheme } from "../theme";
import { knowCommands } from "../commands";
import { icon, mark, type IconName } from "../icons";
import { invoke, inTauri, listen, type CrewFile, type Integrations, type Reminder, type Settings, type Status } from "./api";
import { button, h } from "./dom";
import { renderHome } from "./home";
import { renderActions } from "./actions";
import { renderCharacters } from "./characters";
import { renderNotes } from "./notes";
import { renderReminders } from "./reminders";
import { renderRequests, renderReview } from "./requests";
import { renderSessions } from "./sessions";
import { prepareSettings, renderSettings } from "./settings";
import { renderSetup } from "./setup";
import { tellBar } from "./tell";

// The Sidefolk app window: a sidebar of sections, a "Tell Pip…" bar that runs the companion's
// commands, and the first-launch setup guide. Changes go through the app's commands; agent
// configs change only through its confirming installers.

export type Answer = "sent" | "failed" | "gone";

export type App = {
  state: {
    settings: Settings;
    integrations: Integrations;
    crew: CrewFile;
    reminders: Reminder[];
    status: Status;
    version: string;
    dataDir: string;
  };
  go(view: string, arg?: string): void;
  /** Redraws the current view with the latest state (skipped while a field is being edited). */
  redraw(force?: boolean): void;
  refresh(): Promise<void>;
  toast(text: string, action?: { label: string; run: () => void }, error?: boolean): void;
  /** Saves settings; true once they are on disk. */
  save(change: Partial<Settings>, done?: string): Promise<boolean>;
  petAction(action: Record<string, unknown>, done?: string): Promise<boolean>;
  /** Answers a request on the pet; resolves when the pet confirms (or not). */
  answer(id: string, value: string): Promise<Answer>;
  /** Runs a command through the companion (as if typed to it); resolves to its reply. */
  tell(text: string): Promise<string>;
  openSession(ref: { source: string; session: string; cwd: string }, resume?: boolean): Promise<void>;
  /** Runs when the current view is left (timers stop). */
  onLeave(cleanup: () => void): void;
  /** The current view updates itself on live changes instead of being rebuilt (keeps a half-typed form). */
  live(update: () => void): void;
  /** Holds live redraws (a choice is being sent). */
  hold: boolean;
};

const NAV: [string, string, IconName][] = [
  ["today", "Today", "home"],
  ["reminders", "Reminders", "reminders"],
  ["notes", "Notes", "notes"],
  ["sessions", "Sessions", "terminal"],
  ["actions", "Actions", "next"],
  ["settings", "Settings", "settings"],
];
/** Views reached from a destination keep that destination selected. */
const PARENT: Record<string, string> = { review: "sessions", requests: "today", home: "today", characters: "settings" };

const main = document.querySelector<HTMLElement>("main")!;
const topbar = document.querySelector<HTMLElement>("#topbar")!;
const nav = document.querySelector<HTMLElement>("nav")!;
const toastBox = document.querySelector<HTMLElement>("#toast")!;

let current = { view: "home", arg: "" };
let cleanups: (() => void)[] = [];
const waiters = new Map<string, (ok: boolean, text?: string) => void>();

const app: App = {
  state: {
    settings: {} as Settings,
    integrations: { claude_hooks: false, claude_tools: false, codex_tools: false, start_at_login: false },
    crew: { main: { name: "Pip" } },
    reminders: [],
    status: { pets: [], waiting: [] },
    version: "",
    dataDir: "",
  },
  hold: false,
  go(view, arg = "") {
    if (view === "settings") prepareSettings();
    leave();
    current = { view, arg };
    draw(true);
  },
  redraw(force = false) {
    if (!force && (app.hold || editing())) return;
    if (!force && liveUpdate) return liveUpdate();
    leave();
    draw(false);
  },
  async refresh() {
    const [settings, integrations, crew, reminders, status] = await Promise.all([
      invoke<Settings>("get_settings"),
      invoke<Integrations>("integrations"),
      invoke<CrewFile | null>("get_crew"),
      invoke<Reminder[]>("list_reminders"),
      invoke<Status | null>("get_status"),
    ]);
    const snapshot = () => JSON.stringify([app.state.settings, app.state.integrations, app.state.crew, app.state.reminders, app.state.status]);
    const before = snapshot();
    Object.assign(app.state, { settings, integrations, crew: crew ?? app.state.crew, reminders, status: status?.pets ? status : app.state.status });
    applyTheme(settings.theme);
    // Settings → Reduce motion applies to this window too.
    document.documentElement.classList.toggle("reduce-motion", !!settings.calm);
    document.documentElement.classList.toggle("large-text", !!settings.large_text);
    if (snapshot() !== before) app.redraw();
    updateNav();
  },
  toast(text, action, error = false) {
    toastBox.replaceChildren(h("span", { text }));
    if (action) toastBox.append(button(action.label, () => (toastBox.replaceChildren(), action.run())));
    toastBox.classList.toggle("error", error);
    clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toastBox.replaceChildren(), action ? 9000 : 4500);
  },
  async save(change, done = "Saved.") {
    try {
      app.state.settings = await invoke<Settings>("update_settings", { change });
      applyTheme(app.state.settings.theme);
      document.documentElement.classList.toggle("reduce-motion", !!app.state.settings.calm);
      document.documentElement.classList.toggle("large-text", !!app.state.settings.large_text);
      app.toast(done);
      return true;
    } catch (error) {
      app.toast(`Not saved: ${error}`, undefined, true);
      return false;
    } finally {
      app.redraw(true);
    }
  },
  async petAction(action, done) {
    try {
      await invoke("pet_action", { action });
      if (done) app.toast(done);
      return true;
    } catch (error) {
      app.toast(String(error), undefined, true);
      return false;
    }
  },
  answer(id, value) {
    if (!app.state.status.waiting.some((w) => w.id === id)) return Promise.resolve("gone");
    return new Promise<Answer>((resolve) => {
      const timer = setTimeout(() => {
        waiters.delete(id);
        resolve("failed");
      }, 4000);
      waiters.set(id, (ok) => {
        clearTimeout(timer);
        waiters.delete(id);
        resolve(ok ? "sent" : "gone");
      });
      invoke("pet_action", { action: { action: "answer", id, text: value } }).catch(() => {
        clearTimeout(timer);
        waiters.delete(id);
        resolve("failed");
      });
    });
  },
  tell(text) {
    const id = `run-${Date.now()}`;
    return new Promise<string>((resolve) => {
      const timer = setTimeout(() => {
        waiters.delete(id);
        resolve("The companion didn't answer. Is it running? (menu bar → Show companion)");
      }, 4000);
      waiters.set(id, (_ok, reply) => {
        clearTimeout(timer);
        waiters.delete(id);
        resolve(reply ?? "");
      });
      invoke("pet_action", { action: { action: "run", id, text } }).catch((error) => {
        clearTimeout(timer);
        waiters.delete(id);
        resolve(String(error));
      });
    });
  },
  async openSession(ref, resume = false) {
    try {
      const opened = await invoke<{ message: string }>("open_session", { ...ref, resume });
      app.toast(opened.message);
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  },
  onLeave(cleanup) {
    cleanups.push(cleanup);
  },
  live(update) {
    liveUpdate = update;
  },
};
let liveUpdate: (() => void) | null = null;
let toastTimer = 0;

function leave() {
  for (const cleanup of cleanups) cleanup();
  cleanups = [];
  liveUpdate = null;
}

/** A text field or menu inside the page has focus: a redraw would throw away what is typed. */
function editing() {
  const active = document.activeElement;
  return !!active && main.contains(active) && active.matches("input:not([type=checkbox]):not([type=range]), textarea, select");
}

function draw(focus: boolean) {
  const { view, arg } = current;
  document.body.classList.toggle("setup-mode", view === "setup");
  document.body.classList.toggle("settings-mode", view === "settings");
  const render =
    {
      today: renderHome,
      home: renderHome,
      requests: renderRequests,
      review: renderReview,
      reminders: renderReminders,
      notes: renderNotes,
      sessions: renderSessions,
      characters: renderCharacters,
      actions: renderActions,
      settings: renderSettings,
      setup: renderSetup,
    }[view] ?? renderHome;
  const active = document.activeElement instanceof HTMLElement && main.contains(document.activeElement) ? document.activeElement : null;
  const activeId = active?.id;
  const selection = active instanceof HTMLInputElement && ["text", "search"].includes(active.type) ? [active.selectionStart, active.selectionEnd] : null;
  const scroll = main.scrollTop;
  main.replaceChildren(render(app, arg));
  updateNav();
  // Navigation moves focus to the new heading; a live redraw keeps the reader's place.
  if (focus) {
    main.scrollTop = 0;
    (main.querySelector<HTMLElement>(".review h1") ?? main.querySelector<HTMLElement>("h1"))?.focus();
  } else main.scrollTop = scroll;
  if (!focus && activeId) {
    const next = document.getElementById(activeId);
    next?.focus({ preventScroll: true });
    if (selection && next instanceof HTMLInputElement) next.setSelectionRange(selection[0], selection[1]);
  }
}

function updateNav() {
  const selected = PARENT[current.view] ?? current.view;
  for (const b of nav.querySelectorAll<HTMLButtonElement>("[data-view]")) {
    if (b.dataset.view === selected) b.setAttribute("aria-current", "page");
    else b.removeAttribute("aria-current");
  }
  const connected = app.state.integrations.claude_hooks || app.state.integrations.codex_tools || app.state.integrations.claude_tools || app.state.status.pets.some((p) => p.sessions.length);
  const ai = nav.querySelector<HTMLElement>(".nav-ai");
  if (ai) ai.hidden = !connected && !["sessions", "review", "requests"].includes(current.view);
  const count = app.state.status.waiting.length;
  const badge = nav.querySelector<HTMLElement>(".count")!;
  if (!topbar.firstChild && current.view !== "setup") topbar.append(tellBar(app));
  badge.hidden = count === 0;
  badge.textContent = String(count);
  badge.setAttribute("aria-label", `${count} waiting`);
}

function buildNav() {
  const brand = h("div", { class: "brand" }, mark(30), h("span", { class: "wordmark", text: "sidefolk" }));
  const list = h("div", { class: "nav-list nav-everyday" });
  const ai = h("div", { class: "nav-list nav-ai" }, h("span", { class: "nav-label", text: "AI tools" }));
  const utility = h("div", { class: "nav-list nav-utility" });
  for (const [view, label, glyph] of NAV) {
    const b = button([icon(glyph), h("span", { text: label })], () => app.go(view), "", { "data-view": view });
    if (view === "today") b.append(h("span", { class: "count", hidden: true }));
    (view === "sessions" ? ai : ["settings", "actions"].includes(view) ? utility : list).append(b);
  }
  const pet = h("img", { class: "nav-pip", src: "/pip/idle.png", alt: "", width: 84, height: 76 });
  nav.replaceChildren(h("div", { class: "drag", "data-tauri-drag-region": true }), brand, list, ai, utility, pet);
}

/** "review:<id>", "requests", … from the companion, the tray or the URL. */
function route(target: string) {
  const [view, ...rest] = target.split(":");
  app.go(view || "today", rest.join(":"));
}

// Kept in <data dir>/logs/page.log with the overlay's, so a bug report can include them.
if (inTauri && !import.meta.env.DEV) {
  const log = (message: string) => void invoke("log_error", { message: `[window] ${message}` }).catch(() => {});
  addEventListener("error", (e) => log(`${e.message} at ${e.filename}:${e.lineno}`));
  addEventListener("unhandledrejection", (e) => log(`Unhandled: ${e.reason instanceof Error ? e.reason.stack : e.reason}`));
}

buildNav();
// The Tell bar recognizes commands on your PATH the same way the companion does.
if (inTauri) void invoke<string[]>("path_commands").then(knowCommands).catch(() => {});
await app.refresh().catch((error) => app.toast(String(error), undefined, true));
void invoke<{ version: string; data_dir: string }>("app_info").then((info) => {
  app.state.version = info.version;
  app.state.dataDir = info.data_dir;
});
const params = new URLSearchParams(location.search);
route(params.get("tab") ?? "today");

listen<string>("navigate", route);
listen<Status>("status", (status) => {
  app.state.status = status;
  app.redraw();
  updateNav();
});
listen<{ id: string; ok: boolean; text?: string }>("answered", ({ id, ok, text }) => waiters.get(id)?.(ok, text));
listen("reminders-changed", () => void app.refresh());
listen<Settings>("settings-changed", (settings) => {
  app.state.settings = settings;
  applyTheme(settings.theme);
  document.documentElement.classList.toggle("reduce-motion", !!settings.calm);
  document.documentElement.classList.toggle("large-text", !!settings.large_text);
  app.redraw();
});
// Confirmations happen in dialogs and pets change on the desktop; pick both up.
addEventListener("focus", () => void app.refresh());
setInterval(() => void app.refresh(), 3_000);

// The same shortcut as the native menu also works in the browser preview.
addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === ",") {
    event.preventDefault();
    app.go("settings");
  }
});
