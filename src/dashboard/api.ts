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
  art_style: import("../roster").Style;
  shortcut: string;
  sleep_after_secs: number;
  pet_answers_permissions: boolean;
  hide_in_recordings: boolean;
  onboarded: boolean;
  pet_size: "small" | "medium" | "large";
  calm: boolean;
  large_text: boolean;
  calendar_heads_up: boolean;
  calendar_lead_mins: number;
  sounds: boolean;
  volume: number;
  speak: boolean;
  voice: string;
  terminal: "auto" | "terminal" | "iterm" | "ghostty" | "wezterm" | "kitty" | "alacritty";
  hide_from_dock: boolean;
};
export type Integrations = { claude_hooks: boolean; claude_tools: boolean; codex_tools: boolean; start_at_login: boolean };
/** crew.json: the companion's name and look, and its Spark workers. */
export type CrewFile = { main: { name: string; look?: string; hue?: number }; workers?: { project: string; name: string; hue: number; look?: string }[] };

/** Mirrors `status()` in src/companion.ts. */
export type SessionInfo = { source: string; id: string; cwd: string; state: string; verb: string; detail: string; project: string; at: number; fullAccess?: boolean };
export type Outcome = { kind: "done" | "failed"; source: string; project: string; detail: string; at: number; session?: string; cwd?: string };
export type PetStatus = {
  id: string;
  /** A Spark worker's color (hue turn from mint); 0 for Pip. */
  hue?: number;
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
  const notesDir = "/Users/you/Library/Application Support/dev.sidefolk.companion/notes";
  const state = {
    actions: [{ name: "deploy staging", kind: "command", value: "npm run deploy -- staging", folder: api }] as { name: string; kind: string; value: string; folder: string }[],
    characters: [] as { id: string; name: string; poses: string[]; frames: Record<string, string> }[],
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
      art_style: "3d",
      shortcut: "CommandOrControl+Shift+Space",
      sleep_after_secs: 120,
      pet_answers_permissions: true,
      hide_in_recordings: false,
      onboarded: true,
      pet_size: "medium",
      calm: false,
      large_text: false,
      calendar_heads_up: false,
      calendar_lead_mins: 5,
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
            { source: "codex", id: "04c1e7d2-5b8a-4f0e-9c1d-2e3f4a5b6c7d", cwd: api, state: "waiting", verb: "needs you", detail: "", project: api, at: now },
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
      case "notification_status":
        return { permission: "notRequested", error: null };
      case "request_notifications":
        return { permission: "allowed", error: null };
      case "get_settings":
        try { state.settings.theme = (localStorage.getItem("sidefolk-theme") ?? "system") as Settings["theme"]; } catch { /* Storage can be unavailable. */ }
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
        const r = { id: `r${Date.now()}`, text: a.text, due: a.due, project: a.project ?? "", from: "you", created: Date.now(), done: false, fired: false, repeat: a.repeat };
        state.reminders.push(r);
        return r;
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
        const a = args as { notebook: string; text: string; date: string; project?: string | null };
        const book = state.notebooks.find((b) => b.id === a.notebook || b.name.toLowerCase() === a.notebook.toLowerCase());
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
      case "draft_tools":
        return ["claude"];
      case "draft_summary":
        return "## Reliability (Sep–Oct 2026)\n- Led the login migration; errors down 40% [Sep 12]\n\n(Preview: no AI was used.)";
      case "list_actions":
        return state.actions;
      case "save_action": {
        const a = args as { name: string; kind: string; value: string; folder?: string | null };
        const saved = { name: a.name.trim(), kind: a.kind, value: a.value.trim(), folder: a.kind === "link" ? "" : `/Users/you/git/${a.folder || "api"}` };
        if (!saved.name || !saved.value) throw "An action needs a name and a one-line command or link.";
        state.actions = [...state.actions.filter((x) => x.name !== saved.name), saved];
        return saved;
      }
      case "remove_action":
        state.actions = state.actions.filter((x) => x.name !== (args as { name: string }).name);
        return null;
      case "run_action": {
        const a = args as { name: string; background?: boolean };
        return a.background ? { ok: true, message: `${a.name} finished. (Preview: nothing ran.)`, log: "/preview.log" } : { ok: true, message: `Running ${a.name} in Terminal. (Preview: nothing ran.)`, log: null };
      }
      case "show_output":
        return null;
      case "list_characters":
        return state.characters.map(({ frames, ...c }) => c);
      case "character_frames":
        return state.characters.find((c) => c.id === (args as { id: string }).id)?.frames ?? {};
      case "save_character": {
        const a = args as { name: string; frames: Record<string, string> };
        const c = { id: a.name.toLowerCase().replace(/[^a-z0-9]+/g, "-"), name: a.name, poses: Object.keys(a.frames), frames: a.frames };
        state.characters.push(c);
        return c;
      }
      case "delete_character":
        state.characters = state.characters.filter((c) => c.id !== (args as { id: string }).id);
        return null;
      case "save_template":
        return `Saved to Downloads as ${(args as { name?: string }).name ? "character.sidefolk.png" : "sidefolk-character-template.png"}. (Preview: nothing saved.)`;
      case "problem_report":
        return "Sidefolk preview on macOS (preview)\n\nWhat happened, and what did you expect?\n";
      case "calendar_status":
        return "notRequested";
      case "request_calendar":
        return "allowed";
      case "upcoming_events":
        return [{ id: "e1@1", title: "Design review", start: now + 40 * 60_000, end: now + 70 * 60_000, location: "Room 4", link: "https://meet.google.com/abc-defg-hij", calendar: "Work" }];
      case "install_cli":
        return "Installed. (Preview: nothing changed.)";
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
      case "pet_action":
        if (a.action.action === "run") setTimeout(() => emit("answered", { id: a.action.id, ok: true, text: `Preview: "${a.action.text}" would go to the companion.` }), 200);
        if (a.action.action === "answer") {
          state.status.waiting = state.status.waiting.filter((w) => w.id !== a.action.id);
          setTimeout(() => emit("answered", { id: a.action.id, ok: true }), 400);
        }
        if (a.action.action === "spark") {
          const pets = state.status.pets;
          const project = a.action.project.startsWith("/") ? a.action.project : `/Users/you/git/${a.action.project}`;
          const at = pets.findIndex((p) => p.project === project);
          if (a.action.remove) pets.splice(at, 1);
          else if (at >= 0) Object.assign(pets[at], { name: a.action.name ?? pets[at].name, hue: a.action.hue ?? pets[at].hue });
          else pets.push({ id: `worker:${project}`, name: a.action.name ?? "Spark", label: "Spark", main: false, project, hue: 42, out: true, clip: "idle", sessions: [], outcomes: [] });
          setTimeout(() => {
            emit("status", state.status);
            emit("answered", { id: a.action.id, ok: true, text: a.action.remove ? "Spark went home." : "Spark is on it." });
          }, 100);
        }
        if (a.action.action === "look") state.crew.main.look = a.action.look ?? undefined;
        if (a.action.action === "color") state.crew.main.hue = a.action.hue || undefined;
        if (a.action.action === "full-access") {
          for (const s of state.status.pets[0].sessions) if (s.id === a.action.session) s.fullAccess = !!a.action.on;
          setTimeout(() => emit("status", state.status), 100);
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
        return ["ghostty", "iterm", "terminal"];
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
