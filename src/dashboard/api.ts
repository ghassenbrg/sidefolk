import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import { listen as tauriListen } from "@tauri-apps/api/event";
import type { NoteEntry } from "../notes";
import type { Reminder } from "../reminders";

// What the Sidefolk window reads and calls. In the browser preview (npm run web, /settings.html)
// the same calls answer from sample data, so every screen can be looked at without the app.

export const inTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

/** Mirrors `Settings` in src-tauri/src/settings.rs. */
export type Settings = {
  theme: import("../theme").Theme;
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
  terminal: "auto" | "terminal" | "iterm" | "ghostty" | "wezterm" | "kitty" | "alacritty";
  /** Settings → Labs (docs/V1.md F-10, F-17). */
  labs_commands: boolean;
  labs_sessions: boolean;
  /** "Your week" on Friday from 16:00 (docs/V1.md V1-L8). */
  your_week: boolean;
  hide_from_dock: boolean;
};
/** Mirrors `Problem` in src-tauri/src/store.rs: a file that couldn't be read at launch. */
export type StoreProblem = { file: string; kept: string; error: string; backup: boolean };
/** `hook_error`: why Sidefolk can't hear Claude Code (its port is taken), or null. */
export type Integrations = { claude_hooks: boolean; claude_tools: boolean; codex_tools: boolean; start_at_login: boolean; hook_error: string | null };
/** crew.json: the companion's name, and `look: "spark"` when it's Spark. */
export type CrewFile = { main: { name: string; look?: string } };

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
/** Mirrors `Ask` in src-tauri/src/requests.rs. */
export type Ask = import("../companion").Ask;
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
  const notesDir = "/Users/you/Library/Application Support/dev.sidefolk.companion/notes";
  const state = {
    notebooks: [
      {
        id: "evaluation-h2-2026",
        name: "Evaluation H2 2026",
        count: 0,
        updated: now - 86_400_000,
        path: `${notesDir}/evaluation-h2-2026.md`,
        entries: [
          { line: 2, date: "2026-09-12", text: "Led the login migration; errors down 40%.", project: "api" },
          { line: 3, date: "2026-10-03", text: "Mentored Sam through their first on-call week.", project: "" },
        ] as NoteEntry[],
      },
      { id: "ideas", name: "Ideas", count: 0, updated: now - 3 * 86_400_000, path: `${notesDir}/ideas.md`, entries: [{ line: 2, date: "2026-10-20", text: "A weekly wins digest from the notebooks.", project: "" }] as NoteEntry[] },
    ],
    settings: {
      theme: (() => { try { return localStorage.getItem("sidefolk-theme") ?? "system"; } catch { return "system"; } })(),
      shortcut: "CommandOrControl+Shift+Space",
      sleep_after_secs: 120,
      pet_answers_permissions: true,
      hide_in_recordings: false,
      onboarded: true,
      pet_size: "medium",
      calm: false,
      large_text: false,
      sounds: true,
      volume: 60,
      terminal: "auto",
      labs_commands: false,
      labs_sessions: false,
      your_week: true,
      hide_from_dock: false,
    } as Settings,
    integrations: { claude_hooks: true, claude_tools: false, codex_tools: false, start_at_login: false, hook_error: null } as Integrations,
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
            { source: "claude", id: "04c1e7d2-5b8a-4f0e-9c1d-2e3f4a5b6c7d", cwd: api, state: "waiting", verb: "needs you", detail: "", project: api, at: now },
            { source: "claude", id: "7b3e9a10", cwd: web, state: "edit", verb: "editing", detail: "launch-notes.md", project: web, at: now - 60_000 },
          ],
          outcomes: [{ kind: "done", source: "claude", project: api, detail: "Rate limiting added; 14 tests pass.", at: now - 3_600_000, session: "9f2a", cwd: api }],
        },
      ],
      waiting: [],
    } as Status,
    requests: [
      {
        id: "claude-1",
        source: "claude",
        session: "04c1e7d2-5b8a-4f0e-9c1d-2e3f4a5b6c7d",
        cwd: api,
        project: api,
        tool: "Bash",
        kind: "command",
        title: "Run a command?",
        text: "npm test -- --run --reporter=verbose src/routes/login.test.ts",
        path: null,
        complete: true,
        canDefer: true,
        expires: now + 50_000,
      },
    ] as import("../companion").Ask[],
  };
  return (async (command: string, args?: Record<string, unknown>) => {
    const a = (args ?? {}) as Record<string, any>;
    switch (command) {
      case "notification_status":
        return { permission: "notRequested", error: null };
      case "request_notifications":
        return { permission: "allowed", error: null };
      case "get_settings":
        try { state.settings.theme = (localStorage.getItem("sidefolk-theme") ?? "system") as Settings["theme"]; } catch { /* Storage can be unavailable. */ }
        return state.settings;
      case "update_settings":
        return Object.assign(state.settings, a.change);
      // ?portbusy shows the notice for a hook port another app holds.
      case "integrations":
        return new URLSearchParams(location.search).has("portbusy") ? { ...state.integrations, hook_error: "Another app is using port 47821, so Sidefolk can't hear Claude Code. Quit the other copy of Sidefolk, or restart your Mac." } : state.integrations;
      case "get_crew":
        return state.crew;
      case "list_reminders":
        return state.reminders;
      case "add_reminder": {
        const r = { id: `r${Date.now()}`, text: a.text, due: a.due, project: a.project ?? "", from: "you", created: Date.now(), done: false, fired: false, repeat: a.repeat };
        state.reminders.push(r);
        return r;
      }
      // The preview has no series engine: done finishes, skip and snooze move it.
      case "answer_reminder": {
        const r = state.reminders.find((x) => x.id === a.id);
        if (r) {
          if (a.action === "snooze") Object.assign(r, { due: a.until, fired: false });
          else if (a.action === "done" && !r.repeat) r.done = true;
          else Object.assign(r, { due: r.due + 7 * 86_400_000, fired: false });
        }
        setTimeout(() => emit("reminders-changed", null), 20);
        return !!r;
      }
      case "update_reminder": {
        const r = state.reminders.find((x) => x.id === a.id);
        if (r) {
          Object.assign(r, a.change);
          if (a.change.clear_repeat) r.repeat = null;
          if (a.change.due !== undefined) r.fired = false;
        }
        return !!r;
      }
      case "choose_project_folder":
        return "/Users/you/git/api";
      case "resolve_folder": {
        const folder = (args as { folder?: string | null }).folder;
        return { path: "/Users/you", label: folder ? `~/git/${folder.split("/").pop()}` : "~" };
      }
      case "list_notebooks":
        return state.notebooks.map(({ entries, path, ...book }) => ({ ...book, count: entries.length }));
      case "read_notebook": {
        const book = state.notebooks.find((b) => b.id === (args as { id: string }).id);
        if (!book) throw "No such notebook";
        return { ...book, count: book.entries.length };
      }
      case "create_notebook": {
        const name = (args as { name: string }).name.trim();
        const book = { id: name.toLowerCase().replace(/[^a-z0-9]+/g, "-"), name, count: 0, updated: Date.now(), entries: [] as NoteEntry[], path: `/Users/you/Library/Application Support/dev.sidefolk.companion/notes/${name.toLowerCase()}.md` };
        state.notebooks.push(book);
        return book;
      }
      case "add_note": {
        const a = args as { notebook: string; text: string; date: string; project?: string | null; create?: boolean };
        let book = state.notebooks.find((b) => b.id === a.notebook || b.name.toLowerCase() === a.notebook.toLowerCase());
        if (!book && a.create) {
          book = { id: a.notebook.toLowerCase().replace(/[^a-z0-9]+/g, "-"), name: a.notebook, count: 0, updated: Date.now(), entries: [], path: `${notesDir}/${a.notebook.toLowerCase()}.md` };
          state.notebooks.push(book);
        }
        if (!book) throw `There's no notebook called ${a.notebook}.`;
        const entry = { line: book.entries.length + 2, date: a.date, text: a.text.trim(), project: a.project ?? "" };
        book.entries.push(entry);
        book.updated = Date.now();
        setTimeout(() => emit("notes-changed", null), 50);
        return [book, entry];
      }
      case "edit_note":
      case "remove_note":
      case "restore_note": {
        const a = args as { id: string; entry: NoteEntry; text?: string };
        const book = state.notebooks.find((b) => b.id === a.id)!;
        const at = book.entries.findIndex((e) => e.line === a.entry.line);
        if (command === "edit_note") book.entries[at] = { ...book.entries[at], text: a.text!.trim() };
        if (command === "remove_note") book.entries.splice(at, 1);
        if (command === "restore_note") book.entries.splice(Math.min(a.entry.line - 2, book.entries.length), 0, a.entry);
        setTimeout(() => emit("notes-changed", null), 50);
        return null;
      }
      case "problem_report":
        return "Sidefolk preview on macOS (preview)\n\nWhat happened, and what did you expect?\n";
      case "allow_terminal_control":
        return "Sidefolk can open sessions and commands in Terminal. (Preview)";
      case "start_session":
        return "Started Claude Code in Terminal. (Preview: nothing ran.)";
      case "run_command":
        return "Running in Terminal. (Preview: nothing ran.)";
      case "remove_reminder": {
        const i = state.reminders.findIndex((x) => x.id === a.id);
        return i < 0 ? null : state.reminders.splice(i, 1)[0];
      }
      case "restore_reminder":
        state.reminders.push(a.reminder);
        return null;
      case "get_status":
        return state.status;
      // ?longrequest adds a request too long to read without scrolling.
      case "list_requests":
        if (new URLSearchParams(location.search).has("longrequest") && !state.requests.some((r) => r.id === "claude-2"))
          state.requests.push({ ...state.requests[0], id: "claude-2", text: `${Array.from({ length: 120 }, (_, i) => `echo step ${i}`).join("\n")}\nrm -rf build` });
        return state.requests;
      case "resolve_permission": {
        const at = state.requests.findIndex((r) => r.id === a.id);
        if (at < 0) throw "That request isn't waiting anymore.";
        state.requests.splice(at, 1);
        setTimeout(() => emit("requests", state.requests), 50);
        return null;
      }
      // ?damaged shows the notice for a reminders file that couldn't be read.
      case "store_problems":
        return new URLSearchParams(location.search).has("damaged") ? [{ file: "reminders.json", kept: "/Users/you/Library/Application Support/dev.sidefolk.companion/reminders.json.corrupt-1792900000000", error: "expected value at line 1 column 3", backup: true }] : [];
      case "pet_action":
        if (a.action.action === "run") setTimeout(() => emit("answered", { id: a.action.id, ok: true, text: `Preview: "${a.action.text}" would go to the companion.` }), 200);
        if (a.action.action === "look") state.crew.main.look = a.action.look === "spark" ? "spark" : undefined;
        if (a.action.action === "answer") {
          state.status.waiting = state.status.waiting.filter((w) => w.id !== a.action.id);
          setTimeout(() => emit("answered", { id: a.action.id, ok: true }), 400);
        }
        return null;
      case "app_info":
        return { version: "preview", data_dir: "~/Library/Application Support/dev.sidefolk.companion" };
      case "terminals":
        return ["ghostty", "iterm", "terminal"];
      case "open_session":
        return { how: "focused", message: "Opened in Ghostty." };
      case "tray_action":
      case "reveal_data_dir":
        return null;
    }
    throw new Error(`${command} needs the desktop app.`);
  }) as typeof tauriInvoke;
}
