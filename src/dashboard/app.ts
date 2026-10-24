import { icon, mark, type IconName } from "../icons";
import { setCustomReader } from "../pet/model";
import { invoke, inTauri, listen, type CrewFile, type Integrations, type Reminder, type Settings, type Status } from "./api";
import { button, h } from "./dom";
import { renderActivity } from "./activity";
import { renderCrew, renderPet } from "./crew";
import { renderHome } from "./home";
import { renderReminders } from "./reminders";
import { renderRequests, renderReview } from "./requests";
import { renderSettings } from "./settings";
import { renderWelcome } from "./welcome";

// The Sidefolk window: Home, Requests, Crew, Reminders and Settings, plus the views they lead
// to (a request's review, a pet's page, activity, the first-run welcome). Changes go through
// the app's commands; agent configs change only through its confirming installers.

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
  openSession(ref: { source: string; session: string; cwd: string }, resume?: boolean): Promise<void>;
  /** Runs when the current view is left (live previews stop). */
  onLeave(cleanup: () => void): void;
  /** The current view updates itself on live changes instead of being rebuilt (the pet page keeps its previews). */
  live(update: () => void): void;
  /** Holds live redraws (a choice is being sent). */
  hold: boolean;
};

const NAV: [string, string, IconName][] = [
  ["home", "Home", "home"],
  ["requests", "Requests", "requests"],
  ["crew", "Crew", "crew"],
  ["reminders", "Reminders", "reminders"],
  ["settings", "Settings", "settings"],
];
/** Views reached from a destination keep that destination selected. */
const PARENT: Record<string, string> = { review: "requests", pet: "crew", activity: "home" };

const main = document.querySelector<HTMLElement>("main")!;
const nav = document.querySelector<HTMLElement>("nav")!;
const toastBox = document.querySelector<HTMLElement>("#toast")!;

let current = { view: "home", arg: "" };
let cleanups: (() => void)[] = [];
const waiters = new Map<string, (ok: boolean) => void>();

const app: App = {
  state: {
    settings: {} as Settings,
    integrations: { claude_hooks: false, claude_tools: false, codex_tools: false, start_at_login: false },
    crew: { main: { name: "Pip", look: { species: "bunny", palette: "snow", accessory: "none" } }, pets: [] },
    reminders: [],
    status: { pets: [], waiting: [] },
    version: "",
    dataDir: "",
  },
  hold: false,
  go(view, arg = "") {
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
  const welcome = view === "welcome";
  document.body.classList.toggle("welcome-mode", welcome);
  const render =
    {
      home: renderHome,
      requests: renderRequests,
      review: renderReview,
      crew: renderCrew,
      pet: renderPet,
      reminders: renderReminders,
      settings: renderSettings,
      activity: renderActivity,
      welcome: renderWelcome,
    }[view] ?? renderHome;
  const scroll = main.scrollTop;
  main.replaceChildren(render(app, arg));
  updateNav();
  // Navigation moves focus to the new heading; a live redraw keeps the reader's place.
  if (focus) {
    main.scrollTop = 0;
    main.querySelector<HTMLElement>("h1")?.focus();
  } else main.scrollTop = scroll;
}

function updateNav() {
  const selected = PARENT[current.view] ?? current.view;
  for (const b of nav.querySelectorAll<HTMLButtonElement>("[data-view]")) {
    if (b.dataset.view === selected) b.setAttribute("aria-current", "page");
    else b.removeAttribute("aria-current");
  }
  const count = app.state.status.waiting.length;
  const badge = nav.querySelector<HTMLElement>(".count")!;
  badge.hidden = count === 0;
  badge.textContent = String(count);
  badge.setAttribute("aria-label", `${count} waiting`);
}

function buildNav() {
  const brand = h("div", { class: "brand" }, mark(30), h("span", { class: "wordmark", text: "sidefolk" }));
  const list = h("div", { class: "nav-list" });
  for (const [view, label, glyph] of NAV) {
    const b = button([icon(glyph), h("span", { text: label })], () => app.go(view), "", { "data-view": view });
    if (view === "requests") b.append(h("span", { class: "count", hidden: true }));
    list.append(b);
  }
  nav.replaceChildren(brand, list);
}

/** "review:<id>", "crew:<id>", "requests", … from the pets, the tray or the URL. */
function route(target: string) {
  const [view, ...rest] = target.split(":");
  const arg = rest.join(":");
  if (view === "crew" && arg) return app.go("pet", arg);
  app.go(view || "home", arg);
}

// Kept in <data dir>/logs/page.log with the overlay's, so a bug report can include them.
if (inTauri && !import.meta.env.DEV) {
  const log = (message: string) => void invoke("log_error", { message: `[window] ${message}` }).catch(() => {});
  addEventListener("error", (e) => log(`${e.message} at ${e.filename}:${e.lineno}`));
  addEventListener("unhandledrejection", (e) => log(`Unhandled: ${e.reason instanceof Error ? e.reason.stack : e.reason}`));
}

buildNav();
if (inTauri) setCustomReader((name) => invoke<ArrayBuffer>("read_model", { name }));
await app.refresh().catch((error) => app.toast(String(error), undefined, true));
void invoke<{ version: string; data_dir: string }>("app_info").then((info) => {
  app.state.version = info.version;
  app.state.dataDir = info.data_dir;
});
const params = new URLSearchParams(location.search);
route(params.get("tab") ?? (app.state.settings.onboarded === false ? "welcome" : "home"));

listen<string>("navigate", route);
listen<Status>("status", (status) => {
  app.state.status = status;
  app.redraw();
  updateNav();
});
listen<{ id: string; ok: boolean }>("answered", ({ id, ok }) => waiters.get(id)?.(ok));
listen("reminders-changed", () => void app.refresh());
listen<Settings>("settings-changed", (settings) => {
  app.state.settings = settings;
  app.redraw();
});
// Confirmations happen in dialogs and pets change on the desktop; pick both up.
addEventListener("focus", () => void app.refresh());
setInterval(() => void app.refresh(), 3_000);
