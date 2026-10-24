import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { handleToolCall, type ToolCall } from "./agent-tools";
import type { AgentEvent } from "./agents";
import { AWAY_SECS, welcomeBack, type JournalEntry } from "./away";
import { Companion, type Ask, type Host } from "./companion";
import { install } from "./demo";
import { wireInput } from "./input";
import { sound } from "./sound";
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

/** crew.json keeps the companion's name (v0.1 also kept a crew there; that part is ignored). */
type Stored = { main?: { name?: string } } | null;
const storedName = inTauri ? (await invoke<Stored>("get_crew"))?.main?.name : webName.load();

const host: Host = {
  saveName: async (name) => (inTauri ? invoke("save_crew", { crew: { main: { name } } }) : webName.save(name)),
  resolvePermission: (id, decision) => {
    if (inTauri) void invoke("resolve_permission", { id, decision });
  },
  // Takes keyboard focus without activating Sidefolk, and hands it back afterwards.
  typing: (typing) => {
    if (inTauri) void invoke("overlay_typing", { typing });
  },
  command: (text, kind) => reminders.command(text, kind),
  ...(inTauri && {
    hide: () => void invoke("tray_action", { action: "toggle" }),
    openTab: (tab: string) => void invoke("open_tab", { tab }),
    openSession: async (ref) => (await invoke<{ message: string }>("open_session", { ...ref })).message,
  }),
};

const reminderStore: ReminderStore = inTauri
  ? {
      list: () => invoke<Reminder[]>("list_reminders"),
      add: (text, due, project, from, repeat) => invoke<Reminder>("add_reminder", { text, due, project, from, repeat }),
      update: async (id, change) => void (await invoke("update_reminder", { id, change })),
      peek: (show) => void invoke("peek", { show }),
    }
  : memoryStore();
const journal = (since: number) => (inTauri ? invoke<JournalEntry[]>("journal_since", { since }) : Promise.resolve([]));

const companion = await Companion.start(storedName?.trim() || "Pip", host, zoom);
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
if (inTauri) reminders.manage = () => host.openTab?.("reminders");
companion.seedOutcomes(await journal(Date.now() - 7 * 86_400_000));
await reminders.start();

const overlay = inTauri ? getCurrentWindow() : null;
// One way to talk to it: a click (left or right) opens the field.
const input = wireInput({
  familiar: pet,
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
  type Action = { action: string; text?: string; id?: string; name?: string };
  void listen<Action>("pet-action", (e) => {
    const { action, text, id, name } = e.payload;
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
    pet.resize();
    pet.mind.summon(e.payload.x);
    void invoke("save_pet", { x: pet.mind.x }).catch(console.error);
    void invoke("ui_log", { line: `summon x=${pet.mind.x.toFixed(0)}`, focus: true });
  });
  void listen<AgentEvent>("agent", (e) => companion.handleEvent(e.payload));
  void listen<Ask>("permission", (e) => companion.handleAsk(e.payload));
  void listen<string>("permission-closed", (e) => companion.closeRequest(e.payload));
  void listen("overlay-resized", () => pet.resize());
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
  pet.frame(performance.now());
  const wait = pet.due(performance.now());
  if (wait > 40) setTimeout(() => (document.hidden ? requestAnimationFrame(loop) : loop()), wait);
  else requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
setInterval(() => pet.agents.tick(), 30_000);

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
