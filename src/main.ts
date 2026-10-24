import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { handleToolCall, type ToolCall } from "./agent-tools";
import type { AgentEvent } from "./agents";
import { AWAY_SECS, welcomeBack, type JournalEntry } from "./away";
import { Crew, type Ask, type CrewFile, type Host } from "./crew";
import { install, play } from "./demo";
import { wireInput } from "./input";
import { sound } from "./sound";
import { normalizeLook } from "./pet/look";
import { setCustomReader } from "./pet/model";
import { privacy, type Detail } from "./states";
import { memoryStore, Reminders, type Reminder, type ReminderStore } from "./reminders";

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
  onboarded: boolean;
  pet_size: "small" | "medium" | "large";
  calm: boolean;
  large_text: boolean;
  shortcut: string;
  sounds: boolean;
  volume: number;
  speak: boolean;
  voice: string;
  presence: "always" | "needed" | "menubar";
  detail: Detail;
  comfort: string;
};
const settings = inTauri ? await invoke<Settings>("get_settings") : null;
const SIZES = { small: 0.8, medium: 1, large: 1.3 };
// Browser preview only: ?zoom=3 enlarges the characters for close inspection.
const zoom = settings ? (SIZES[settings.pet_size] ?? 1) : Number(new URLSearchParams(location.search).get("zoom")) || 1;
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

// The browser preview keeps its crew in localStorage; it may be unavailable (private mode).
const WEB_CREW = "sidefolk-crew";
const webStore = {
  load: (): unknown => {
    try {
      return JSON.parse(localStorage.getItem(WEB_CREW) ?? "null");
    } catch {
      return null;
    }
  },
  save: (file: CrewFile) => {
    try {
      localStorage.setItem(WEB_CREW, JSON.stringify(file));
    } catch {
      // Preview only; the crew just won't survive a reload.
    }
  },
};

const host: Host = {
  saveCrew: async (crew) => (inTauri ? invoke("save_crew", { crew }) : webStore.save(crew)),
  dispatch: async (prompt, cwd) => {
    if (!inTauri) throw new Error("Codex needs the desktop app.");
    await invoke("dispatch", { prompt, cwd });
  },
  resolvePermission: (id, decision) => {
    if (inTauri) void invoke("resolve_permission", { id, decision });
  },
  // Takes keyboard focus without activating Sidefolk, and hands it back afterwards.
  typing: (typing) => {
    if (inTauri) void invoke("overlay_typing", { typing });
  },
  command: (text, kind, from) => reminders.command(text, kind, from),
  trayAction: (action) => {
    if (inTauri) void invoke("tray_action", { action });
  },
  ...(inTauri && {
    openTab: (tab: string) => void invoke("open_tab", { tab }),
    openSession: async (ref) => (await invoke<{ message: string }>("open_session", { ...ref })).message,
  }),
};
if (inTauri) setCustomReader((name) => invoke<ArrayBuffer>("read_model", { name }));

const reminderStore: ReminderStore = inTauri
  ? {
      list: () => invoke<Reminder[]>("list_reminders"),
      add: (text, due, project, from) => invoke<Reminder>("add_reminder", { text, due, project, from }),
      update: async (id, change) => void (await invoke("update_reminder", { id, change })),
      peek: (show) => void invoke("peek", { show }),
    }
  : memoryStore();
const journal = (since: number) => (inTauri ? invoke<JournalEntry[]>("journal_since", { since }) : Promise.resolve([]));

const crew = await Crew.start(inTauri ? await invoke("get_crew") : webStore.load(), host, zoom);
const main = crew.main;

/** Settings that apply without a restart. Pet size rebuilds the pets, so it reloads the page. */
function applySettings(next: Settings | null) {
  document.body.classList.toggle("large-text", !!next?.large_text);
  const calm = !!next?.calm || reducedMotion.matches;
  document.body.classList.toggle("reduce-motion", calm);
  if (next) {
    privacy.detail = next.detail;
    crew.presence = next.presence;
    crew.comfort = next.comfort;
    sound.enabled = next.sounds;
    sound.volume = next.volume / 100;
    sound.speaker = next.speak
      ? (text, voice) => void invoke("speak", { text, voice: next.voice, pitch: voice.pitch / 640 }).catch(() => {})
      : null;
  }
  for (const f of crew.all) {
    f.mind.calm = calm;
    f.agents.redraw();
    if (next) f.mind.sleepAfterSecs = next.sleep_after_secs;
  }
  crew.tick();
}
applySettings(settings);
reducedMotion.addEventListener("change", () => applySettings(settings));
const reminders = new Reminders(crew, reminderStore);
if (inTauri) reminders.manage = () => host.openTab?.("reminders");
crew.seedOutcomes(await journal(Date.now() - 7 * 86_400_000));
await reminders.start();

const overlay = inTauri ? getCurrentWindow() : null;
const input = wireInput({
  familiars: () => crew.all,
  setInteractive: (on) => void overlay?.setIgnoreCursorEvents(!on),
  onClick: (f) => crew.statusCard(f),
  onDoubleClick: (f) => crew.openPrompt(f),
  onMenu: (f) => crew.menu(f),
});

// Clicking a pet or a bubble button can make the panel key (web views ask for it).
// Hand keyboard focus straight back unless the user is typing in a bubble.
addEventListener("pointerdown", () => sound.unlock());
addEventListener("pointerup", () => {
  if (inTauri && !crew.typing) void invoke("overlay_typing", { typing: false });
});

const onCursor = (x: number, y: number) => {
  crew.onCursor(main.stage.toWorld(x, y));
  input.refresh(x, y);
};

if (inTauri) {
  void listen<Settings>("settings-changed", (e) => {
    if (e.payload.pet_size !== settings!.pet_size) return location.reload();
    Object.assign(settings!, e.payload);
    applySettings(settings);
  });
  // From the Sidefolk window and the tray. Answers are acknowledged, so the window shows
  // "Sent" only once the pet really passed the answer on.
  type PetAction = { action: string; text?: string; project?: string; id?: string; name?: string; look?: unknown };
  void listen<PetAction>("pet-action", (e) => {
    const { action, text, project, id, name, look } = e.payload;
    const pet = (action !== "answer" && id && crew.byId(id)) || main;
    const reply = (text?: string | void) => text && pet.bubble.say(text, 6);
    if (action === "run" && text) void crew.run(text, pet).then(reply);
    if (action === "call") crew.call(pet);
    if (action === "forget") void crew.forget(pet);
    if (action === "create" && project) void crew.create({ kind: "project", key: project }, look ? normalizeLook(look) : undefined, name);
    if (action === "assign" && project) void crew.assign(pet, project);
    if (action === "rename" && name) void crew.rename(pet, name).then(reply);
    if (action === "look" && look) void crew.setLook(pet, normalizeLook({ ...pet.record.look, ...(look as object) }));
    if (action === "open-session") void crew.openSession(pet);
    if (action === "new-reminder") void reminders.command("", "new-reminder", main);
    if (action === "demo") play(crew);
    if (action === "answer" && id && text) void invoke("answered", { id, ok: crew.answer(id, text) });
  });
  // Coming back after a long time away earns a briefing of what the agents did meanwhile.
  let lastIdle = 0;
  void listen<number>("idle", (e) => {
    const idle = e.payload;
    for (const f of crew.all) f.mind.setOsIdle(idle);
    if (lastIdle >= AWAY_SECS && idle < 1) void briefing(Date.now() - lastIdle * 1000);
    lastIdle = idle;
  });
  void listen("reminders-changed", () => void reminders.reload());
  // An agent called one of the pet's tools (MCP); Rust waits for the answer.
  void listen<ToolCall>("mcp", (e) =>
    handleToolCall(e.payload, crew, reminders, (result) => void invoke("mcp_reply", { id: e.payload.id, result })),
  );
  void listen<string>("mcp-closed", (e) => crew.closeAsk(e.payload));
  if (settings!.pet_x !== null) main.mind.x = settings!.pet_x;
  main.mind.fitBounds();
  void invoke("ui_log", { line: `restored x=${main.mind.x.toFixed(0)} sleep_after=${main.mind.sleepAfterSecs}s crew=${crew.all.length - 1}` });
  let savedX = main.mind.x;
  setInterval(() => {
    if (!main.mind.onGround || Math.abs(main.mind.x - savedX) <= 8) return;
    const x = main.mind.x;
    void invoke("save_pet", { x }).then(() => { savedX = x; }).catch(console.error);
  }, 5_000);
  void listen<[number, number]>("cursor", (e) => onCursor(e.payload[0], e.payload[1]));
  void listen<{ x: number }>("summon", (e) => {
    crew.resize();
    main.mind.summon(e.payload.x);
    void invoke("save_pet", { x: main.mind.x }).catch(console.error);
    void invoke("ui_log", { line: `summon x=${main.mind.x.toFixed(0)}`, focus: true });
  });
  void listen<{ id: string }>("call", (e) => {
    const f = crew.byId(e.payload.id);
    if (f) crew.call(f);
  });
  void listen<AgentEvent>("agent", (e) => crew.handleEvent(e.payload));
  void listen<Ask>("permission", (e) => crew.handleAsk(e.payload));
  void listen<string>("permission-closed", (e) => crew.closeAsk(e.payload));
  void listen("overlay-resized", () => crew.resize());
  // The Sidefolk window's live view: sent when something changed, checked once a second.
  // Menu bar only has no pet to show a card, so new requests become notifications.
  let published = "";
  let notified = new Set<string>();
  setInterval(() => {
    const status = crew.status();
    const json = JSON.stringify(status);
    if (json === published) return;
    published = json;
    void invoke("publish_status", { status }).catch(() => {});
    const ids = new Set(status.waiting.map((w) => w.id));
    if (settings!.presence === "menubar")
      for (const w of status.waiting.filter((w) => !notified.has(w.id)))
        void invoke("notify", { title: w.who, body: `${w.title} Open Sidefolk from the menu bar to answer.` }).catch(() => {});
    notified = ids;
  }, 1_000);
} else {
  addEventListener("pointermove", (e) => onCursor(e.clientX, e.clientY));
  install(crew);
}

async function briefing(since: number) {
  const lines = welcomeBack(await journal(since), reminders.upcoming);
  if (!lines.length) return;
  main.bubble.show({
    id: "welcome",
    who: main.name,
    title: "Welcome back. While you were away:",
    lines,
    choices: [{ label: "OK", value: "ok", primary: true }],
    onChoose: () => {},
  });
}

// Each pet renders only as often as its state needs. Between slow frames the page sleeps
// instead of waking for every display refresh; rAF still stops by itself when hidden.
function loop() {
  const now = performance.now();
  for (const f of crew.all) f.frame(now);
  // With every pet resting (Only when needed) nothing is due; look again in a second.
  const wait = Math.min(1000, ...crew.all.map((f) => f.due(performance.now())));
  if (wait > 40) setTimeout(() => (document.hidden ? requestAnimationFrame(loop) : loop()), wait);
  else requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
setInterval(() => crew.agentsTick(), 30_000);
setInterval(() => crew.tick(), 500);

if (import.meta.env.DEV) {
  Object.assign(window, { sidefolk: { crew, main } });
  // Lets the terminal see what the overlay is doing when screenshots are not possible.
  if (inTauri) {
    let frames = 0;
    const count = () => {
      frames++;
      requestAnimationFrame(count);
    };
    requestAnimationFrame(count);
    const report = (line: string, focus = false) => void invoke("ui_log", { line, focus });
    // Clicking a pet must leave your current app frontmost.
    addEventListener("pointerup", () => setTimeout(() => report("after click", true), 250));
    void listen<string>("dev", (e) => {
      if (e.payload === "prompt") crew.openPrompt(main);
      if (e.payload === "dismiss") for (const f of crew.all) f.bubble.dismissPrompt();
      if (e.payload === "sleep") main.mind.setOsIdle(main.mind.sleepAfterSecs + 1);
      if (e.payload === "wake") main.mind.setOsIdle(0);
      if (e.payload === "welcome") void briefing(0);
      if (e.payload === "demo") play(crew);
      if (e.payload === "bubbles")
        report(`bubbles ${crew.all.filter((f) => !f.bubble.root.hidden).map((f) => `[${f.name}] ${f.bubble.root.innerText.replace(/\s+/g, " ")}`).join(" | ")}`);
      if (e.payload === "state")
        report(`state ${crew.all.map((f) => `${f.name}:${f.out ? f.pet.clip : "away"}@${f.mind.x.toFixed(0)}`).join(" ")}`, true);
      if (e.payload.startsWith("run:")) void crew.run(e.payload.slice(4), main).then((r) => r && main.bubble.say(r, 5));
      // Presses the first visible bubble button with this label.
      if (e.payload.startsWith("choose:")) {
        const label = e.payload.slice(7);
        const button = [...document.querySelectorAll<HTMLButtonElement>(".bubble:not([hidden]) button")].find((b) => b.textContent === label);
        report(`choose ${label} ${button ? "pressed" : "not found"}`);
        button?.click();
      }
    });
    report(`overlay ${main.stage.width}x${main.stage.height} dpr=${devicePixelRatio}`);
    void listen("overlay-resized", () => setTimeout(() => report(`refit ${innerWidth}x${innerHeight}`), 100));
    void listen<AgentEvent>("agent", (e) => report(`agent ${e.payload.source} ${e.payload.kind} ${e.payload.project} ${e.payload.detail}`));
    void listen<Ask>("permission", (e) => report(`ask ${e.payload.id} ${e.payload.title} ${e.payload.detail}`));
    let lastInteractive = false;
    setInterval(() => {
      const interactive = document.body.classList.contains("hover");
      if (interactive !== lastInteractive) report(`interactive=${(lastInteractive = interactive)}`);
    }, 100);
    setInterval(() => {
      const out = crew.all.filter((f) => f.out).map((f) => `${f.name}:${f.pet.clip}`).join(",");
      report(`vis=${document.visibilityState} raf=${(frames / 10).toFixed(0)}/s out=${out} x=${main.mind.x.toFixed(0)} size=${main.stage.width}x${main.stage.height}`, true);
      frames = 0;
    }, 10_000);
  }
}
