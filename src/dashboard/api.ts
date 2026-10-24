import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import { listen as tauriListen } from "@tauri-apps/api/event";
import type { Reminder } from "../reminders";

// What the Sidefolk window reads and calls. In the browser preview (npm run web, /settings.html)
// the same calls answer from sample data, so every screen can be looked at without the app.

export const inTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

/** Mirrors `Settings` in src-tauri/src/settings.rs. */
export type Settings = {
  shortcut: string;
  sleep_after_secs: number;
  pet_answers_permissions: boolean;
  hide_in_recordings: boolean;
  onboarded: boolean;
  pet_size: "small" | "medium" | "large";
  calm: boolean;
  large_text: boolean;
  sounds: boolean;
  volume: number;
  speak: boolean;
  voice: string;
  terminal: "auto" | "terminal" | "iterm" | "ghostty";
  hide_from_dock: boolean;
};
export type Integrations = { claude_hooks: boolean; claude_tools: boolean; codex_tools: boolean; start_at_login: boolean };
/** crew.json: the companion's name. */
export type CrewFile = { main: { name: string } };

/** Mirrors `status()` in src/companion.ts. */
export type SessionInfo = { source: string; id: string; cwd: string; state: string; verb: string; detail: string; project: string; at: number };
export type Outcome = { kind: "done" | "failed"; source: string; project: string; detail: string; at: number; session?: string; cwd?: string };
export type PetStatus = {
  id: string;
  name: string;
  label: string;
  main: boolean;
  project: string | null;
  out: boolean;
  clip: string;
  sessions: SessionInfo[];
  outcomes: Outcome[];
};
export type Waiting = {
  id: string;
  pet: string;
  petName: string;
  who: string;
  title: string;
  lines: string[];
  meta: Record<string, string>;
  choices: { label: string; value: string; primary: boolean; quiet: boolean }[];
};
export type Status = { pets: PetStatus[]; waiting: Waiting[] };
export type { Reminder };

type Handler = (payload: unknown) => void;
const handlers = new Map<string, Set<Handler>>();

let sample: typeof tauriInvoke | null = null;
export const invoke: typeof tauriInvoke = inTauri ? tauriInvoke : (command, args) => (sample ??= preview())(command, args);

export function listen<T>(event: string, handler: (payload: T) => void) {
  if (inTauri) return void tauriListen<T>(event, (e) => handler(e.payload));
  if (!handlers.has(event)) handlers.set(event, new Set());
  handlers.get(event)!.add(handler as Handler);
}

const emit = (event: string, payload: unknown) => handlers.get(event)?.forEach((h) => h(payload));

/** Browser preview only: sample data so the window can be looked at without the app. */
function preview(): typeof tauriInvoke {
  const now = Date.now();
  const api = "/Users/you/git/api";
  const web = "/Users/you/git/website";
  const state = {
    settings: {
      shortcut: "CommandOrControl+Shift+Space",
      sleep_after_secs: 120,
      pet_answers_permissions: true,
      hide_in_recordings: true,
      onboarded: true,
      pet_size: "medium",
      calm: false,
      large_text: false,
      sounds: true,
      volume: 60,
      speak: false,
      voice: "",
      terminal: "auto",
      hide_from_dock: false,
    } as Settings,
    integrations: { claude_hooks: true, claude_tools: false, codex_tools: false, start_at_login: false } as Integrations,
    crew: { main: { name: "Pip" } } as CrewFile,
    reminders: [
      { id: "r1", text: "Review launch notes", due: now + 3 * 3_600_000, project: "", from: "you", created: now, done: false, fired: false },
      { id: "r2", text: "Check the nightly build", due: now + 26 * 3_600_000, project: api, from: "claude", created: now, done: false, fired: false },
    ] as Reminder[],
    status: {
      pets: [
        {
          id: "main",
          name: "Pip",
          label: "Pip",
          main: true,
          project: null,
          out: true,
          clip: "alert",
          sessions: [
            { source: "codex", id: "04c1e7d2", cwd: api, state: "waiting", verb: "needs you", detail: "", project: api, at: now },
            { source: "claude", id: "7b3e9a10", cwd: web, state: "edit", verb: "editing", detail: "launch-notes.md", project: web, at: now - 60_000 },
          ],
          outcomes: [{ kind: "done", source: "claude", project: api, detail: "Rate limiting added; 14 tests pass.", at: now - 3_600_000, session: "9f2a", cwd: api }],
        },
      ],
      waiting: [
        {
          id: "codex-1",
          pet: "main",
          petName: "Pip",
          who: "Pip · api",
          title: "Run a command?",
          lines: ["Codex is asking to run this command in api."],
          meta: {
            kind: "permission",
            action: "command",
            title: "Run a command?",
            command: "npm test -- --run --reporter=verbose src/routes/login.test.ts",
            source: "codex",
            session: "04c1e7d2-5b8a-4f0e-9c1d-2e3f4a5b6c7d",
            project: api,
            cwd: api,
            expires: String(now + 9 * 60_000),
            canDefer: "false",
          },
          choices: [
            { label: "Decline", value: "deny", primary: false, quiet: false },
            { label: "Allow once", value: "allow", primary: true, quiet: false },
          ],
        },
      ],
    } as Status,
  };
  return (async (command: string, args?: Record<string, unknown>) => {
    const a = (args ?? {}) as Record<string, any>;
    switch (command) {
      case "get_settings":
        return state.settings;
      case "update_settings":
        return Object.assign(state.settings, a.change);
      case "integrations":
        return state.integrations;
      case "get_crew":
        return state.crew;
      case "list_reminders":
        return state.reminders;
      case "add_reminder": {
        const r = { id: `r${Date.now()}`, text: a.text, due: a.due, project: a.project ?? "", from: "you", created: Date.now(), done: false, fired: false };
        state.reminders.push(r);
        return r;
      }
      case "update_reminder": {
        const r = state.reminders.find((x) => x.id === a.id);
        if (r) Object.assign(r, a.change);
        return !!r;
      }
      case "remove_reminder": {
        const i = state.reminders.findIndex((x) => x.id === a.id);
        return i < 0 ? null : state.reminders.splice(i, 1)[0];
      }
      case "restore_reminder":
        state.reminders.push(a.reminder);
        return null;
      case "get_status":
        return state.status;
      case "pet_action":
        if (a.action.action === "run") setTimeout(() => emit("answered", { id: a.action.id, ok: true, text: `Preview: "${a.action.text}" would go to the companion.` }), 200);
        if (a.action.action === "answer") {
          state.status.waiting = state.status.waiting.filter((w) => w.id !== a.action.id);
          setTimeout(() => emit("answered", { id: a.action.id, ok: true }), 400);
        }
        return null;
      case "app_info":
        return { version: "preview", data_dir: "~/Library/Application Support/dev.sidefolk.companion" };
      case "voices":
        return [
          { name: "Samantha", language: "en_US" },
          { name: "Daniel", language: "en_GB" },
        ];
      case "terminals":
        return ["terminal", "ghostty"];
      case "open_session":
        return { how: "focused", message: "Opened in Ghostty." };
      case "tray_action":
      case "reveal_data_dir":
      case "speak":
        return null;
    }
    throw new Error(`${command} needs the desktop app.`);
  }) as typeof tauriInvoke;
}
