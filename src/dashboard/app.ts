import { applyTheme } from "../theme";
import { icon, mark, type IconName } from "../icons";
import { invoke, inTauri, listen, type Ask, type CrewFile, type Integrations, type Reminder, type Settings, type Status, type Waiting } from "./api";
import { button, h } from "./dom";
import { Feedback } from "./feedback";
import { dataState } from "./kit";
import { problem } from "../voice";
import { renderHome } from "./home";
import { renderNotes } from "./notes";
import { renderReminders } from "./reminders";
import { renderRequests, renderReview } from "./requests";
import { renderSessions } from "./sessions";
import { prepareSettings, renderSettings } from "./settings";
import { renderSetup } from "./setup";
import { renderWeek } from "./week";
import { tellBar } from "./tell";
import { picture } from "../roster";

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
    /** Permission requests, from Rust (requests.rs); merged into `status.waiting`. */
    requests: Ask[];
    /** Where each session runs, by "source:session" ("Ghostty"), for labels. */
    hosts: Record<string, string>;
    version: string;
    dataDir: string;
  };
  go(view: string, arg?: string): void;
  /** Redraws the current view with the latest state (skipped while a field is being edited). */
  redraw(force?: boolean): void;
  refresh(): Promise<void>;
  toast(text: string, action?: { label: string; run: () => void | Promise<void> }, error?: boolean): void;
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
  ["sessions", "Sessions", "terminal"],
  ["reminders", "Reminders", "reminders"],
  ["notes", "Work log", "notes"],
  ["settings", "Settings", "settings"],
];
/** Views reached from a destination keep that destination selected. */
const PARENT: Record<string, string> = { review: "sessions", requests: "today", home: "today", week: "notes" };

const main = document.querySelector<HTMLElement>("main")!;
const topbar = document.querySelector<HTMLElement>("#topbar")!;
const nav = document.querySelector<HTMLElement>("nav")!;
const toastBox = document.querySelector<HTMLElement>("#toast")!;
const feedback = new Feedback(toastBox);
const preferences = new URLSearchParams(location.search).get("window") === "preferences";

let current = { view: "home", arg: "" };
let cleanups: (() => void)[] = [];
const waiters = new Map<string, (ok: boolean, text?: string) => void>();

const app: App = {
  state: {
    settings: {} as Settings,
    integrations: { claude_hooks: false, claude_tools: false, codex_tools: false, start_at_login: false, hook_error: null, claude_health: "off" },
    crew: { main: { name: "Pip" } },
    reminders: [],
    status: { pets: [], waiting: [] },
    requests: [],
    hosts: {},
    version: "",
    dataDir: "",
  },
  hold: false,
  go(view, arg = "") {
    if (inTauri && view === "settings" && !preferences) {
      void invoke("open_preferences", { category: arg || "general" }).catch((error) => app.toast(problem(error), undefined, true));
      return;
    }
    if (inTauri && preferences && view !== "settings") {
      void invoke("open_tab", { tab: `${view}${arg ? `:${arg}` : ""}` }).catch((error) => app.toast(problem(error), undefined, true));
      return;
    }
    if (view === "settings" && current.view !== "settings") prepareSettings();
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
    const [settings, integrations, crew, reminders, status, requests] = await Promise.all([
      invoke<Settings>("get_settings"),
      invoke<Integrations>("integrations"),
      invoke<CrewFile | null>("get_crew"),
      invoke<Reminder[]>("list_reminders"),
      invoke<Status | null>("get_status"),
      invoke<Ask[]>("list_requests"),
    ]);
    app.state.hosts = await invoke<Record<string, string>>("session_hosts").catch(() => ({}));
    const snapshot = () => JSON.stringify([app.state.settings, app.state.integrations, app.state.crew, app.state.reminders, app.state.status]);
    const before = snapshot();
    Object.assign(app.state, { settings, integrations, crew: crew ?? app.state.crew, reminders, requests });
    if (status?.pets) companionStatus = status;
    app.state.status = merged();
    applyTheme(settings.theme);
    // Settings → Reduce motion applies to this window too.
    document.documentElement.classList.toggle("reduce-motion", !!settings.calm);
    document.documentElement.classList.toggle("large-text", !!settings.large_text);
    if (snapshot() !== before) app.redraw();
    updateNav();
  },
  toast(text, action, error = false) {
    const dialog = document.querySelector("dialog[open]");
    if (error && dialog && !action) {
      let notice = dialog.querySelector<HTMLElement>(".sheet-error");
      if (!notice) { notice = h("p", { class: "field-error sheet-error", role: "alert" }); dialog.append(notice); }
      notice.textContent = problem(text);
      return;
    }
    feedback.show(text, action, error);
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
      app.toast(problem(error), undefined, true);
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
      app.toast(problem(error), undefined, true);
      return false;
    }
  },
  answer(id, value) {
    if (!app.state.status.waiting.some((w) => w.id === id)) return Promise.resolve("gone");
    // Permission requests are answered in Rust, which says whether it took the answer.
    if (app.state.requests.some((r) => r.id === id))
      return invoke("resolve_permission", { id, decision: value }).then(
        () => "sent" as const,
        (refused) => (String(refused).includes("isn't waiting") ? "gone" : "failed"),
      );
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
        resolve(problem(error));
      });
    });
  },
  async openSession(ref, resume = false) {
    try {
      const opened = await invoke<{ message: string }>("open_session", { ...ref, resume });
      app.toast(opened.message);
    } catch (error) {
      app.toast(problem(error), undefined, true);
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
/** The companion's own view (sessions, reminders and questions it shows); requests come from Rust. */
let companionStatus: Status = { pets: [], waiting: [] };

/** A permission request as the window's lists show it. */
function waitingOf(a: Ask): Waiting {
  return {
    id: a.id,
    pet: "main",
    petName: app.state.crew.main.name,
    who: `${app.state.crew.main.name} · ${a.project.split("/").pop() || a.cwd}`,
    title: a.title,
    lines: [],
    meta: { kind: "permission", action: a.kind, title: a.title, command: a.text, path: a.path ?? "", complete: String(a.complete), tool: a.tool, source: a.source, session: a.session, project: a.project, cwd: a.cwd, expires: String(a.expires), canDefer: String(a.canDefer) },
    choices: [],
  };
}

/** Requests first (from Rust, oldest first), then what the companion holds. */
function merged(): Status {
  return { pets: companionStatus.pets, waiting: [...app.state.requests.map(waitingOf), ...companionStatus.waiting.filter((w) => w.meta.kind !== "permission")] };
}


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
      settings: renderSettings,
      setup: renderSetup,
      week: renderWeek,
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
    (next ?? main.querySelector<HTMLElement>("h1"))?.focus({ preventScroll: true });
    if (selection && next instanceof HTMLInputElement) next.setSelectionRange(selection[0], selection[1]);
  }
  if (!focus && document.activeElement === document.body) main.querySelector<HTMLElement>("h1")?.focus({ preventScroll: true });
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
  const utility = h("div", { class: "nav-list nav-utility" });
  for (const [view, label, glyph] of NAV) {
    const b = button([icon(glyph), h("span", { text: label })], () => app.go(view), "", { "data-view": view });
    if (view === "today") b.append(h("span", { class: "count", hidden: true }));
    (view === "settings" ? utility : list).append(b);
    if (view === "sessions") b.classList.add("nav-ai");
  }
  const pet = h("img", { class: "nav-pip", src: picture(app.state.crew.main.look), alt: "", width: 84, height: 76 });
  nav.replaceChildren(h("div", { class: "drag", "data-tauri-drag-region": true }), brand, list, utility, pet);
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
let startupError: unknown;
try { await app.refresh(); } catch (error) { startupError = error; }
void invoke<{ version: string; data_dir: string }>("app_info").then((info) => {
  app.state.version = info.version;
  app.state.dataDir = info.data_dir;
});
const params = new URLSearchParams(location.search);
route(params.get("tab") ?? (preferences ? "settings:general" : "today"));
if (startupError) main.replaceChildren(dataState("I couldn't load your day.", problem(startupError), () => location.reload()));

listen<string>("navigate", route);
listen<Status>("status", (status) => {
  companionStatus = status;
  app.state.status = merged();
  app.redraw();
  updateNav();
});
listen<Ask[]>("requests", (requests) => {
  app.state.requests = requests;
  app.state.status = merged();
  app.redraw();
  updateNav();
});
listen<{ id: string; ok: boolean; text?: string }>("answered", ({ id, ok, text }) => waiters.get(id)?.(ok, text));
listen("reminders-changed", () => void app.refresh().catch((error) => app.toast(problem(error), undefined, true)));
listen<Settings>("settings-changed", (settings) => {
  app.state.settings = settings;
  applyTheme(settings.theme);
  document.documentElement.classList.toggle("reduce-motion", !!settings.calm);
  document.documentElement.classList.toggle("large-text", !!settings.large_text);
  app.redraw();
});
// Confirmations happen in dialogs and the companion changes on the desktop: each says so with an
// event, and coming back to the window reads everything again. No polling (docs/V1.md §11).
addEventListener("focus", () => void app.refresh().catch((error) => app.toast(problem(error), undefined, true)));
listen("integrations-changed", () => void app.refresh().catch((error) => app.toast(problem(error), undefined, true)));

// macOS menu commands need an explicit bridge: native field Undo otherwise consumes CmdZ
// even when a list, rather than an editor, has focus.
listen("undo", () => {
  const editing = document.activeElement?.closest("input, textarea, [contenteditable=true]");
  if (editing) document.execCommand("undo");
  else void feedback.latest();
});

// The same shortcut as the native menu also works in the browser preview.
addEventListener("keydown", (event) => {
  const command = event.metaKey || event.ctrlKey;
  const editing = (event.target as HTMLElement | null)?.closest("input, textarea, [contenteditable=true]");
  if (command && event.key.toLowerCase() === "z" && !event.shiftKey && !editing) {
    event.preventDefault();
    void feedback.latest();
  }
  if (command && event.key.toLowerCase() === "k") {
    event.preventDefault();
    document.querySelector<HTMLInputElement>(".tell-input")?.focus();
  }
  if (command && event.key === ",") {
    event.preventDefault();
    app.go("settings");
  }
});
