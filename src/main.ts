import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { handleToolCall, type ToolCall } from "./agent-tools";
import type { AgentEvent } from "./agents";
import { AWAY_SECS, welcomeBack, type JournalEntry } from "./away";
import { knowCommands } from "./commands";
import { Companion, type Ask, type Host } from "./companion";
import { install } from "./demo";
import { wireInput } from "./input";
import { sound } from "./sound";
import { memoryNotes, Notes, type NoteStore } from "./notes";
import { memoryStore, Reminders, type Reminder, type ReminderStore } from "./reminders";
import { Workers, type WorkerSpec } from "./workers";

const inTauri = "__TAURI_INTERNALS__" in window;
document.body.classList.toggle("web", !inTauri);

// Kept in <data dir>/logs/page.log, so a bug report can include what went wrong.
if (inTauri && !import.meta.env.DEV) {
  const log = (message: string) => void invoke("log_error", { message }).catch(() => {});
  addEventListener("error", (e) => log(`${e.message} at ${e.filename}:${e.lineno}`));
  addEventListener("unhandledrejection", (e) => log(`Unhandled: ${e.reason instanceof Error ? e.reason.stack : e.reason}`));
}

/** Mirrors `Settings` in src-tauri/src/settings.rs (the fields the overlay uses). */
type Settings = {
  pet_x: number | null;
  sleep_after_secs: number;
  pet_size: "small" | "medium" | "large";
  calm: boolean;
  large_text: boolean;
  sounds: boolean;
  volume: number;
  speak: boolean;
  voice: string;
};
const settings = inTauri ? await invoke<Settings>("get_settings") : null;
const SIZES = { small: 0.8, medium: 1, large: 1.3 };
// Browser preview only: ?zoom=3 enlarges the companion for close inspection.
const zoom = settings ? (SIZES[settings.pet_size] ?? 1) : Number(new URLSearchParams(location.search).get("zoom")) || 1;
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

// The browser preview keeps the companion's name in localStorage; it may be unavailable.
const WEB_NAME = "sidefolk-name";
const webName = {
  load: () => {
    try {
      return localStorage.getItem(WEB_NAME);
    } catch {
      return null;
    }
  },
  save: (name: string) => {
    try {
      localStorage.setItem(WEB_NAME, name);
    } catch {
      // Preview only; the name just won't survive a reload.
    }
  },
};

/** crew.json keeps the companion's name and its Spark workers (v0.1's other keys are dropped). */
type Stored = { main?: { name?: string; look?: string }; workers?: unknown } | null;
const stored = inTauri ? await invoke<Stored>("get_crew") : null;
const storedName = inTauri ? stored?.main?.name : webName.load();
const crew: { main: { name: string; look?: string }; workers: WorkerSpec[] } = {
  main: { name: storedName?.trim() || "Pip", ...(stored?.main?.look ? { look: stored.main.look } : {}) },
  workers: Array.isArray(stored?.workers) ? stored.workers.filter((w): w is WorkerSpec => typeof w?.project === "string" && typeof w?.name === "string" && typeof w?.hue === "number") : [],
};
const saveCrew = () => (inTauri ? invoke("save_crew", { crew }) : Promise.resolve());

const host: Host = {
  saveName: async (name) => {
    crew.main.name = name;
    if (inTauri) await saveCrew();
    else webName.save(name);
  },
  resolvePermission: (id, decision) => {
    if (inTauri) void invoke("resolve_permission", { id, decision });
  },
  // Takes keyboard focus without activating Sidefolk, and hands it back afterwards.
  typing: (typing) => {
    if (inTauri) void invoke("overlay_typing", { typing });
  },
  command: (text, kind) => reminders.command(text, kind),
  spark: (project, change) => sparks(project, change),
  note: (command) => (command.kind === "note" ? notes.take(command.text, command.notebook) : notes.create(command.name)),
  ...(inTauri && {
    hide: () => void invoke("tray_action", { action: "toggle" }),
    openTab: (tab: string) => void invoke("open_tab", { tab }),
    openSession: async (ref) => (await invoke<{ message: string }>("open_session", { ...ref })).message,
    resolveFolder: (folder) => invoke("resolve_folder", { folder }),
    runCommand: (command, cwd) => invoke<string>("run_command", { command, cwd }),
    syncFullAccess: (keys) => void invoke("sync_full_access", { keys }).catch(() => {}),
    startSession: (agent, cwd, fullAccess) => invoke<string>("start_session", { agent, cwd, fullAccess }),
  }),
  // Browser preview: the confirmation card can be looked at; nothing runs.
  ...(!inTauri && {
    resolveFolder: async (folder) => ({ path: "/Users/you", label: folder ? `~/git/${folder}` : "~" }),
    runCommand: async () => "Running in Terminal. (Preview: nothing ran.)",
    startSession: async (agent, _cwd, full) => `Started ${agent === "codex" ? "Codex" : "Claude Code"} in Terminal${full ? " with full access" : ""}. (Preview: nothing ran.)`,
  }),
};

const reminderStore: ReminderStore = inTauri
  ? {
      list: () => invoke<Reminder[]>("list_reminders"),
      add: (text, due, project, from, repeat) => invoke<Reminder>("add_reminder", { text, due, project, from, repeat }),
      update: async (id, change) => void (await invoke("update_reminder", { id, change })),
      remove: async (id) => void (await invoke("remove_reminder", { id })),
      peek: (show) => void invoke("peek", { show }),
    }
  : memoryStore();
const journal = (since: number) => (inTauri ? invoke<JournalEntry[]>("journal_since", { since }) : Promise.resolve([]));

// What's on your PATH, so "terraform plan -out x" is a command and "say hi" stays a sentence.
if (inTauri) void invoke<string[]>("path_commands").then(knowCommands).catch(() => {});
/** A made character's frames (Settings → Characters); null if it was deleted. */
const characterFrames = (id: string) => (inTauri ? invoke<Record<string, string>>("character_frames", { id }).catch(() => null) : Promise.resolve(null));
const mainFrames = crew.main.look ? await characterFrames(crew.main.look) : null;
const companion = await Companion.start(crew.main.name, host, zoom, mainFrames ? { frames: mainFrames } : {});
const pet = companion.pet;

/** Settings that apply without a restart. Companion size rebuilds it, so that reloads the page. */
function applySettings(next: Settings | null) {
  document.body.classList.toggle("large-text", !!next?.large_text);
  const calm = !!next?.calm || reducedMotion.matches;
  document.body.classList.toggle("reduce-motion", calm);
  pet.mind.calm = calm;
  if (!next) return;
  pet.mind.sleepAfterSecs = next.sleep_after_secs;
  sound.enabled = next.sounds;
  sound.volume = next.volume / 100;
  sound.speaker = next.speak ? (text, voice) => void invoke("speak", { text, voice: next.voice, pitch: voice.pitch / 640 }).catch(() => {}) : null;
}
applySettings(settings);
reducedMotion.addEventListener("change", () => applySettings(settings));
const reminders = new Reminders(companion, reminderStore);
const noteStore: NoteStore = inTauri
  ? {
      list: () => invoke("list_notebooks"),
      create: (name) => invoke("create_notebook", { name }),
      add: (notebook, text, date, project, create) => invoke("add_note", { notebook, text, date, project, create }),
      remove: (id, entry) => invoke("remove_note", { id, entry }),
    }
  : memoryNotes();
const notes = new Notes(companion, noteStore);
reminders.writeNote = (text) => void notes.capture(text);

// Spark's own frames once they're in public/spark; until then a worker is a recolored Pip.
const character = await new Promise<string>((resolve) => {
  const probe = new Image();
  probe.onload = () => resolve("spark");
  probe.onerror = () => resolve("pip");
  probe.src = "spark/idle.png";
});
const workers = new Workers(
  companion,
  zoom,
  character,
  (specs) => {
    crew.workers = specs;
    return saveCrew();
  },
  characterFrames,
);
await workers.load(crew.workers);
/** "give api a spark", the window's Sparks list: a folder name or path becomes the project's root. */
async function sparks(project: string, change: { name?: string; hue?: number; remove?: boolean; look?: string | null }): Promise<string> {
  if (change.remove) return workers.remove(project);
  let path = project;
  if (!project.startsWith("/")) {
    const session = companion.sessionOf(project);
    if (session) path = session.cwd;
    else if (inTauri) path = (await invoke<{ path: string }>("resolve_folder", { folder: project })).path;
  }
  return workers.add(path, change.name, change.hue, change.look);
}
if (inTauri) reminders.manage = (id) => host.openTab?.(id ? `reminders:${id}` : "reminders");
companion.seedOutcomes(await journal(Date.now() - 7 * 86_400_000));
await reminders.start();

const overlay = inTauri ? getCurrentWindow() : null;
// One way to talk to it: a click (left or right) opens the field.
const input = wireInput({
  familiars: () => companion.familiars,
  setInteractive: (on) => void overlay?.setIgnoreCursorEvents(!on),
  onClick: () => companion.openPrompt(),
});

// Clicking the companion or a card button can make the panel key (web views ask for it).
// Hand keyboard focus straight back unless the user is typing.
addEventListener("pointerdown", () => sound.unlock());
addEventListener("pointerup", () => {
  if (inTauri && !companion.typing) void invoke("overlay_typing", { typing: false });
});

const onCursor = (x: number, y: number) => {
  pet.mind.onCursor(pet.bounds.toWorld(x, y));
  input.refresh(x, y);
};

if (inTauri) {
  void listen<Settings>("settings-changed", (e) => {
    if (e.payload.pet_size !== settings!.pet_size) return location.reload();
    Object.assign(settings!, e.payload);
    applySettings(settings);
  });
  // From the Sidefolk window and the tray. Answers are acknowledged, so the window shows
  // "Sent" only once the companion really passed the answer on.
  type Action = { action: string; text?: string; id?: string; name?: string; source?: string; session?: string; on?: boolean; project?: string; hue?: number; remove?: boolean; look?: string | null };
  void listen<Action>("pet-action", (e) => {
    const { action, text, id, name, source, session, on, project, hue, remove, look } = e.payload;
    const reply = (line?: string | void) => line && pet.bubble.say(line, 6);
    // From the window's "Tell Pip…" bar: the same commands, and the reply goes back to it.
    if (action === "run" && text)
      void companion.run(text).then((line) => {
        reply(line);
        if (id) void invoke("answered", { id, ok: true, text: line ?? "" });
      });
    if (action === "rename" && name) void companion.rename(name).then(reply);
    if (action === "open-session") void companion.openSession();
    if (action === "full-access" && source && session) companion.setFullAccess(source, session, !!on);
    // A new look for Pip: saved, then the overlay starts over with it.
    if (action === "look" && !project) {
      if (look) crew.main.look = look;
      else delete crew.main.look;
      void saveCrew().then(() => location.reload());
    }
    if (action === "spark" && project)
      void sparks(project, { name, hue, remove, look }).then(
        (line) => id && void invoke("answered", { id, ok: true, text: line }),
        (error) => id && void invoke("answered", { id, ok: false, text: String(error) }),
      );
    if (action === "new-reminder") void reminders.command("", "new-reminder");
    if (action === "answer" && id && text) void invoke("answered", { id, ok: companion.answer(id, text) });
  });
  // Coming back after a long time away earns a briefing of what the agents did meanwhile.
  let lastIdle = 0;
  void listen<number>("idle", (e) => {
    const idle = e.payload;
    pet.mind.setOsIdle(idle);
    if (lastIdle >= AWAY_SECS && idle < 1) void briefing(Date.now() - lastIdle * 1000);
    lastIdle = idle;
  });
  void listen("reminders-changed", () => void reminders.reload());
  // An agent called one of the companion's tools (MCP); Rust waits for the answer.
  void listen<ToolCall>("mcp", (e) => handleToolCall(e.payload, companion, reminders, (result) => void invoke("mcp_reply", { id: e.payload.id, result }), sparks));
  void listen<string>("mcp-closed", (e) => companion.closeRequest(e.payload));
  if (settings!.pet_x !== null) pet.mind.x = settings!.pet_x;
  pet.mind.fitBounds();
  void invoke("ui_log", { line: `restored x=${pet.mind.x.toFixed(0)} sleep_after=${pet.mind.sleepAfterSecs}s` });
  let savedX = pet.mind.x;
  setInterval(() => {
    if (!pet.mind.onGround || Math.abs(pet.mind.x - savedX) <= 8) return;
    const x = pet.mind.x;
    void invoke("save_pet", { x }).then(() => {
      savedX = x;
    }).catch(console.error);
  }, 5_000);
  void listen<[number, number]>("cursor", (e) => onCursor(e.payload[0], e.payload[1]));
  void listen<{ x: number }>("summon", (e) => {
    for (const f of companion.familiars) f.resize();
    pet.mind.summon(e.payload.x);
    void invoke("save_pet", { x: pet.mind.x }).catch(console.error);
    void invoke("ui_log", { line: `summon x=${pet.mind.x.toFixed(0)}`, focus: true });
  });
  void listen<AgentEvent>("agent", (e) => companion.handleEvent(e.payload));
  void listen<Ask>("permission", (e) => companion.handleAsk(e.payload));
  void listen<string>("permission-closed", (e) => companion.closeRequest(e.payload));
  void listen("overlay-resized", () => companion.familiars.forEach((f) => f.resize()));
  // The Sidefolk window's live view: sent when something changed, checked once a second.
  let published = "";
  setInterval(() => {
    const status = companion.status();
    const json = JSON.stringify(status);
    if (json === published) return;
    published = json;
    void invoke("publish_status", { status }).catch(() => {});
  }, 1_000);
} else {
  addEventListener("pointermove", (e) => onCursor(e.clientX, e.clientY));
  install(companion);
}

async function briefing(since: number) {
  const lines = welcomeBack(await journal(since), reminders.upcoming);
  if (!lines.length) return;
  pet.bubble.show({
    id: "welcome",
    who: pet.name,
    title: "Welcome back. While you were away:",
    lines,
    choices: [{ label: "OK", value: "ok", primary: true }],
    onChoose: () => {},
  });
}

// The companion renders only as often as its state needs. Between slow frames the page sleeps
// instead of waking for every display refresh; rAF still stops by itself when hidden.
function loop() {
  const now = performance.now();
  for (const f of companion.familiars) f.frame(now);
  const wait = Math.min(...companion.familiars.map((f) => f.due(performance.now())));
  if (wait > 40) setTimeout(() => (document.hidden ? requestAnimationFrame(loop) : loop()), wait);
  else requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
setInterval(() => companion.familiars.forEach((f) => f.agents.tick()), 30_000);

if (import.meta.env.DEV) {
  Object.assign(window, { sidefolk: { companion } });
  // Lets the terminal see what the overlay is doing when screenshots are not possible.
  if (inTauri) {
    let frames = 0;
    const count = () => {
      frames++;
      requestAnimationFrame(count);
    };
    requestAnimationFrame(count);
    const report = (line: string, focus = false) => void invoke("ui_log", { line, focus });
    // Clicking the companion must leave your current app frontmost.
    addEventListener("pointerup", () => setTimeout(() => report("after click", true), 250));
    void listen<string>("dev", (e) => {
      if (e.payload === "prompt") companion.openPrompt();
      if (e.payload === "dismiss") pet.bubble.dismissPrompt();
      if (e.payload === "sleep") pet.mind.setOsIdle(pet.mind.sleepAfterSecs + 1);
      if (e.payload === "wake") pet.mind.setOsIdle(0);
      if (e.payload === "welcome") void briefing(0);
      if (e.payload === "bubbles") report(`bubbles [${pet.name}] ${pet.bubble.root.hidden ? "" : pet.bubble.root.innerText.replace(/\s+/g, " ")}`);
      if (e.payload === "state") report(`state ${pet.name}:${pet.view.clip}@${pet.mind.x.toFixed(0)}`, true);
      if (e.payload.startsWith("run:")) void companion.run(e.payload.slice(4)).then((r) => r && pet.bubble.say(r, 5));
      // Presses the first visible card button with this label.
      if (e.payload.startsWith("choose:")) {
        const label = e.payload.slice(7);
        const button = [...document.querySelectorAll<HTMLButtonElement>(".bubble:not([hidden]) button")].find((b) => b.textContent === label);
        report(`choose ${label} ${button ? "pressed" : "not found"}`);
        button?.click();
      }
    });
    report(`overlay ${pet.bounds.width}x${pet.bounds.height} dpr=${devicePixelRatio}`);
    void listen("overlay-resized", () => setTimeout(() => report(`refit ${innerWidth}x${innerHeight}`), 100));
    void listen<AgentEvent>("agent", (e) => report(`agent ${e.payload.source} ${e.payload.kind} ${e.payload.project} ${e.payload.detail}`));
    void listen<Ask>("permission", (e) => report(`ask ${e.payload.id} ${e.payload.title} ${e.payload.detail}`));
    let lastInteractive = false;
    setInterval(() => {
      const interactive = document.body.classList.contains("hover");
      if (interactive !== lastInteractive) report(`interactive=${(lastInteractive = interactive)}`);
    }, 100);
    setInterval(() => {
      report(`vis=${document.visibilityState} raf=${(frames / 10).toFixed(0)}/s clip=${pet.view.clip} x=${pet.mind.x.toFixed(0)} size=${pet.bounds.width}x${pet.bounds.height}`, true);
      frames = 0;
    }, 10_000);
  }
}
