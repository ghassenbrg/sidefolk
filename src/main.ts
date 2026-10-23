import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Agents, type AgentEvent } from "./agents";
import { Bubble, type Ask } from "./bubble";
import { wireInput } from "./input";
import { Mind } from "./mind";
import { HEIGHT, Pet } from "./pet/pet";
import { Stage, VIEW } from "./stage";

const inTauri = "__TAURI_INTERNALS__" in window;
document.body.classList.toggle("web", !inTauri);

// Browser preview only: ?zoom=3 enlarges the character for close inspection.
const zoom = inTauri ? 1 : Number(new URLSearchParams(location.search).get("zoom")) || 1;
const height = HEIGHT * zoom;

const stage = new Stage(document.querySelector<HTMLCanvasElement>("#stage")!, VIEW * zoom);
const pet = new Pet();
pet.holder.scale.multiplyScalar(zoom);
stage.scene.add(pet.holder);
const mind = new Mind(pet, stage);
const bubble = new Bubble(document.querySelector<HTMLElement>("#bubble")!);
const hud = document.querySelector<HTMLElement>("#hud")!;
const agents = new Agents(mind, bubble, hud);

const overlay = inTauri ? getCurrentWindow() : null;
const input = wireInput({
  stage,
  pet,
  mind,
  bubble,
  setInteractive: (on) => void overlay?.setIgnoreCursorEvents(!on),
});

const openAsks = new Set<string>();
const askChanged = () => agents.asking(openAsks.size);

bubble.onDecision = (id, decision) => {
  openAsks.delete(id);
  askChanged();
  if (inTauri) void invoke("resolve_permission", { id, decision });
};
bubble.onPrompt = async (prompt) => {
  if (!inTauri) throw new Error("Codex needs the desktop app.");
  await invoke("dispatch", { prompt });
};
// Takes keyboard focus without activating Sidefolk, and hands it back afterwards.
bubble.onTyping = (typing) => {
  if (inTauri) void invoke("overlay_typing", { typing });
};

// Clicking the pet or a bubble button can make the panel key (web views ask for it).
// Hand keyboard focus straight back unless the user is typing in the bubble.
addEventListener("pointerup", () => {
  if (inTauri && !bubble.typing) void invoke("overlay_typing", { typing: false });
});

const onCursor = (x: number, y: number) => {
  mind.onCursor(stage.toWorld(x, y));
  input.refresh(x, y);
};

if (inTauri) {
  void listen<[number, number]>("cursor", (e) => onCursor(e.payload[0], e.payload[1]));
  void listen<AgentEvent>("agent", (e) => agents.handle(e.payload));
  void listen<Ask>("permission", (e) => {
    openAsks.add(e.payload.id);
    bubble.ask(e.payload);
    askChanged();
  });
  void listen<string>("permission-closed", (e) => {
    openAsks.delete(e.payload);
    bubble.close(e.payload);
    askChanged();
  });
  void listen("overlay-resized", () => {
    stage.resize();
    mind.fitBounds();
  });
} else {
  addEventListener("pointermove", (e) => onCursor(e.clientX, e.clientY));
  void import("./demo").then((demo) => demo.install(agents, bubble, openAsks, askChanged));
}

// Render only as often as the current state needs; rAF stops by itself when hidden.
let last = performance.now();
let renders = 0;
function frame(now: number) {
  requestAnimationFrame(frame);
  if (now - last < 1000 / mind.fps - 2) return;
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  mind.update(dt);
  pet.holder.position.set(mind.x, mind.y, 0);
  pet.update(dt, mind.target, mind.gaze, mind.eyes);
  stage.frame(mind.x, mind.y + height / 2);
  stage.render();
  renders++;
  bubble.tick(now);
  const hudOffset = hud.hidden ? 0 : 30;
  if (!hud.hidden) {
    const left = Math.round(mind.x - hud.offsetWidth / 2);
    hud.style.transform = `translate(${left}px, ${Math.round(stage.height - mind.y - height - 26)}px)`;
  }
  bubble.place(mind.x, mind.y + height + hudOffset + 8);
}
requestAnimationFrame(frame);
setInterval(() => agents.tick(), 30_000);

if (import.meta.env.DEV) {
  Object.assign(window, { sidefolk: { mind, pet, agents, bubble, stage } });
  // Lets the terminal see what the overlay is doing when screenshots are not possible.
  if (inTauri) {
    let frames = 0;
    const count = () => {
      frames++;
      requestAnimationFrame(count);
    };
    requestAnimationFrame(count);
    const report = (line: string, focus = false) => void invoke("ui_log", { line, focus });
    // Clicking the pet must leave your current app frontmost.
    addEventListener("pointerup", () => setTimeout(() => report("after click", true), 250));
    void listen<string>("dev", (e) => {
      if (e.payload === "prompt") bubble.prompt();
      if (e.payload === "dismiss") bubble.dismissPrompt();
    });
    const onTyping = bubble.onTyping;
    bubble.onTyping = (typing) => {
      onTyping(typing);
      setTimeout(() => report(`typing=${typing}`, true), 250);
    };
    report(`overlay ${stage.width}x${stage.height} dpr=${devicePixelRatio}`);
    void listen("overlay-resized", () => setTimeout(() => report(`refit ${innerWidth}x${innerHeight}`), 100));
    void listen<AgentEvent>("agent", (e) => report(`agent ${e.payload.source} ${e.payload.kind} ${e.payload.detail}`));
    void listen<Ask>("permission", (e) => report(`ask ${e.payload.id} ${e.payload.title} ${e.payload.detail}`));
    let lastInteractive = false;
    setInterval(() => {
      const interactive = document.body.classList.contains("hover");
      if (interactive !== lastInteractive) report(`interactive=${(lastInteractive = interactive)}`);
    }, 100);
    setInterval(() => {
      report(`vis=${document.visibilityState} raf=${(frames / 10).toFixed(0)}/s renders=${(renders / 10).toFixed(0)}/s clip=${pet.clip} x=${mind.x.toFixed(0)} y=${mind.y.toFixed(0)} size=${stage.width}x${stage.height}`, true);
      frames = renders = 0;
    }, 10_000);
  }
}
