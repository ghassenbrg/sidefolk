import { applyTheme, type Theme } from "./theme";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { handleToolCall, type ToolCall } from "./agent-tools";
import { AGENT_NAMES, type AgentEvent } from "./agents";
import { AWAY_SECS, weeklyDue, welcomeBack, type JournalEntry } from "./away";
import { mondayOf, today } from "./notes";
import { Companion, type Ask, type Host } from "./companion";
import { install } from "./demo";
import { area, needed, place, shouldMove, type Rect } from "./frame";
import { wireInput } from "./input";
import { sound } from "./sound";
import { memoryNotes, Notes, type NoteStore } from "./notes";
import { memoryStore, Reminders, type Reminder, type ReminderStore } from "./reminders";
import { lookOf } from "./roster";

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
  theme: Theme;
  pet_x: number | null;
  sleep_after_secs: number;
  pet_size: "small" | "medium" | "large";
  calm: boolean;
  large_text: boolean;
  sounds: boolean;
  volume: number;
  labs_commands: boolean;
  labs_sessions: boolean;
  your_week: boolean;
};
const settings = inTauri ? await invoke<Settings>("get_settings") : null;
// The window covers only the companions (frame.ts); a reloaded page starts where it is.
const layout = inTauri ? await invoke<{ width: number; height: number; frame: Rect } | null>("overlay_area") : null;
if (layout) place(layout.width, layout.height, layout.frame);
else place(innerWidth, innerHeight);
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

/** crew.json keeps the companion's name and whether it's Pip or Spark (older keys are dropped). */
type Stored = { main?: { name?: string; look?: string } } | null;
const stored = inTauri ? await invoke<Stored>("get_crew") : null;
const storedName = inTauri ? stored?.main?.name : webName.load();
// Browser preview: ?look=spark shows Spark.
const look = lookOf(inTauri ? stored?.main?.look : new URLSearchParams(location.search).get("look"));
const crew: { main: { name: string; look?: string } } = { main: { name: storedName?.trim() || (look === "spark" ? "Spark" : "Pip"), ...(look === "spark" ? { look } : {}) } };
const saveCrew = () => (inTauri ? invoke("save_crew", { crew }) : Promise.resolve());

const host: Host = {
  saveName: async (name) => {
    crew.main.name = name;
    if (inTauri) await saveCrew();
    else webName.save(name);
  },
  resolvePermission: async (id, decision) => {
    if (!inTauri) return null;
    return invoke("resolve_permission", { id, decision }).then(
      () => null,
      (refused) => String(refused),
    );
  },
  // Takes keyboard focus without activating Sidefolk, and hands it back afterwards.
  typing: (typing) => {
    if (inTauri) void invoke("overlay_typing", { typing });
  },
  command: (text, kind) => reminders.command(text, kind),
  // The browser preview has Labs on, so its cards can be looked at (nothing runs there).
  labs: () => ({ commands: settings ? settings.labs_commands : true, sessions: settings ? settings.labs_sessions : true }),
  note: (command) => (command.kind === "note" ? notes.take(command.text, command.notebook) : notes.create(command.name)),
  ...(inTauri && {
    hide: () => void invoke("tray_action", { action: "toggle" }),
    openTab: (tab: string) => void invoke("open_tab", { tab }),
    openSession: async (ref) => (await invoke<{ message: string }>("open_session", { ...ref })).message,
    resolveFolder: (folder) => invoke("resolve_folder", { folder }),
    runCommand: (command, cwd) => invoke<string>("run_command", { command, cwd }),
    startSession: (agent, cwd, fullAccess) => invoke<string>("start_session", { agent, cwd, fullAccess }),
    open: (target, app) => invoke<string>("open_target", { target, app }),
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
      answer: async (id, answer) => void (await invoke("answer_reminder", { id, ...answer })),
      peek: (show) => void invoke("peek", { show }),
    }
  : memoryStore();
const journal = (since: number) => (inTauri ? invoke<JournalEntry[]>("journal_since", { since }) : Promise.resolve([]));

const companion = await Companion.start(crew.main.name, host, zoom, { character: look });
const pet = companion.pet;

/** Settings that apply without a restart. Companion size rebuilds it, so that reloads the page. */
function applySettings(next: Settings | null) {
  if (next) applyTheme(next.theme);
  document.body.classList.toggle("large-text", !!next?.large_text);
  const calm = !!next?.calm || reducedMotion.matches;
  document.body.classList.toggle("reduce-motion", calm);
  pet.mind.calm = calm;
  if (!next) return;
  pet.mind.sleepAfterSecs = next.sleep_after_secs;
  sound.enabled = next.sounds;
  sound.volume = next.volume / 100;
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
      move: (id, entry, to) => invoke("move_note", { id, entry, to }),
    }
  : memoryNotes();
const notes = new Notes(companion, noteStore);
reminders.writeNote = (text) => void notes.capture(text);
// A finished session: one short card with "Log it" (docs/V1.md V1-L7). Only the project and the
// first prompt line go into the note, never the agent's output.
pet.agents.onDone = (event, first) => {
  const project = event.project ? event.project.split("/").pop()! : "";
  const agent = AGENT_NAMES[event.source];
  const id = `done-${event.source}-${event.session}`;
  pet.bubble.show({
    id,
    who: `${pet.name} · ${project || agent}`,
    title: `${agent} finished${project ? ` in ${project}` : ""}.`,
    lines: event.detail ? [event.detail] : [],
    choices: [
      { label: "OK", value: "ok" },
      { label: "Log it", value: "log", primary: true },
    ],
    onChoose: (value) => {
      pet.bubble.close(id);
      if (value === "log") notes.logWork(`${project ? `${project}: ` : ""}${first}`.trim());
    },
  });
};
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
  type Action = { action: string; text?: string; id?: string; name?: string; look?: string };
  void listen<Action>("pet-action", (e) => {
    const { action, text, id, name, look } = e.payload;
    // Pip or Spark: saved, then the overlay starts over with it. Open requests live in Rust and
    // come back after the reload (requests.rs).
    if (action === "look") {
      if (lookOf(look) === "spark") crew.main.look = "spark";
      else delete crew.main.look;
      void saveCrew().then(() => location.reload());
    }
    const reply = (line?: string | void) => line && pet.bubble.say(line, 6);
    // From the window's "Tell Pip…" bar: the same commands, and the reply goes back to it.
    if (action === "run" && text)
      void companion.run(text).then((line) => {
        reply(line);
        if (id) void invoke("answered", { id, ok: true, text: line ?? "" });
      });
    if (action === "rename" && name) void companion.rename(name).then(reply);
    if (action === "open-session") void companion.openSession();
    if (action === "new-reminder") void reminders.command("", "new-reminder");
    if (action === "answer" && id && text) void invoke("answered", { id, ok: companion.answer(id, text) });
  });
  setTimeout(() => void weeklyWins(), 6000);
  // Coming back after a long time away earns a briefing of what the agents did meanwhile.
  let lastIdle = 0;
  void listen<number>("idle", (e) => {
    const idle = e.payload;
    pet.mind.setOsIdle(idle);
    // Falling asleep or waking shows in the window too.
    companion.onChange();
    if (lastIdle >= AWAY_SECS && idle < 1) void briefing(Date.now() - lastIdle * 1000).then(weeklyWins);
    lastIdle = idle;
  });
  void listen("reminders-changed", () => void reminders.reload());
  // An agent called one of the companion's tools (MCP); Rust waits for the answer.
  void listen<ToolCall>("mcp", (e) => handleToolCall(e.payload, companion, reminders, (result) => void invoke("mcp_reply", { id: e.payload.id, result })));
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
  // Requests live in Rust (requests.rs): a reloaded overlay shows the ones still waiting.
  for (const ask of await invoke<Ask[]>("list_requests").catch(() => [] as Ask[])) companion.handleAsk(ask);
  void listen<string>("permission-closed", (e) => companion.closeRequest(e.payload));
  // Handed back because the user went to the session (docs/V1.md V1-D4).
  void listen<string>("permission-released", (e) => companion.released(e.payload));
  void listen<{ width: number; height: number }>("overlay-resized", (e) => {
    place(e.payload.width, e.payload.height);
    companion.familiars.forEach((f) => f.resize());
  });
  // The Sidefolk window's live view: sent when the companion says something changed, at most once
  // per frame, and only when it differs from what was sent (no polling; docs/V1.md §11).
  let published = "";
  let queued = false;
  const publish = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      const status = companion.status();
      const json = JSON.stringify(status);
      if (json === published) return;
      published = json;
      void invoke("publish_status", { status }).catch(() => {});
    });
  };
  companion.onChange = publish;
  publish();
} else {
  addEventListener("pointermove", (e) => onCursor(e.clientX, e.clientY));
  install(companion);
}

function safeStorage() {
  try {
    return localStorage;
  } catch {
    return null;
  }
}

/** Friday from 16:00, once a week: Pip holds up "Your week" (docs/V1.md V1-L8). */
async function weeklyWins() {
  if (!inTauri || !settings?.your_week || !weeklyDue(safeStorage())) return;
  const monday = mondayOf(today());
  const books = await invoke<{ id: string }[]>("list_notebooks").catch(() => []);
  const pages = await Promise.all(books.map((b) => invoke<{ entries: { date: string }[] }>("read_notebook", { id: b.id }).catch(() => null)));
  const count = pages.reduce((n, p) => n + (p?.entries.filter((e) => mondayOf(e.date) === monday).length ?? 0), 0);
  pet.bubble.show({
    id: "weekly",
    who: pet.name,
    title: count ? `Your week: ${count} ${count === 1 ? "entry" : "entries"}` : "Your week",
    lines: [count ? "Here's what you got done, ready to copy." : "Nothing logged this week. Anything worth a note?"],
    choices: [
      { label: "Later", value: "later" },
      count ? { label: "Open Your week", value: "open", primary: true } : { label: "Add a note", value: "write", primary: true },
    ],
    onChoose: (value) => {
      pet.bubble.close("weekly");
      if (value === "open") host.openTab?.("week");
      if (value === "write") void notes.capture("note what I achieved this week");
    },
  });
  pet.mind.react("note", 1.6);
}

/** Coming back after a long time away: what the agents did meanwhile, and the next reminder. */
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
  fitWindow(now);
  const wait = Math.min(...companion.familiars.map((f) => f.due(performance.now())));
  if (wait > 40) setTimeout(() => (document.hidden ? requestAnimationFrame(loop) : loop()), wait);
  else requestAnimationFrame(loop);
}
requestAnimationFrame(loop);

/** Keeps the window around the companions and their cards; the whole work area while one is held or flying. */
let moving = false;
let lastFit = 0;
function fitWindow(now: number, soon = false) {
  if (!inTauri || moving) return;
  const free = companion.familiars.some((f) => !f.mind.onGround);
  if (!free && !soon && now - lastFit < 250) return;
  lastFit = now;
  const want = free ? { x: 0, y: 0, width: area.width, height: area.height } : needed(companion.familiars.flatMap((f) => f.rects()), area.width, area.height);
  if (!shouldMove(area.frame, want)) return;
  moving = true;
  void invoke<Rect>("overlay_frame", { ...want })
    .then((frame) => {
      place(area.width, area.height, frame);
      if (import.meta.env.DEV) void invoke("ui_log", { line: `frame ${frame.x},${frame.y} ${frame.width}x${frame.height} of ${area.width}x${area.height}` });
    })
    .catch(console.error)
    .finally(() => (moving = false));
}
// A card or badge appearing or changing: refit once it's placed (the next frame), not 250 ms later.
if (inTauri)
  new MutationObserver((records) => {
    // The companions' own frame swaps (hidden images) happen all the time and change nothing.
    if (records.every((r) => r.target instanceof Element && r.target.closest(".pip"))) return;
    requestAnimationFrame(() => requestAnimationFrame(() => fitWindow(performance.now(), true)));
  }).observe(document.body, {
    subtree: true,
    childList: true,
    attributeFilter: ["hidden"],
  });
setInterval(() => {
  companion.familiars.forEach((f) => f.agents.tick());
  companion.onChange();
}, 30_000);

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
    void listen("overlay-resized", () => setTimeout(() => report(`refit ${area.width}x${area.height}`), 100));
    void listen<AgentEvent>("agent", (e) => report(`agent ${e.payload.source} ${e.payload.kind} ${e.payload.project} ${e.payload.detail}`));
    void listen<Ask>("permission", (e) => report(`ask ${e.payload.id} ${e.payload.title} ${e.payload.complete ? "" : "(too long) "}${e.payload.text.slice(0, 200)}`));
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
