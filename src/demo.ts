// Browser-only harness: number keys play fake agent events so the pet can be checked
// without the desktop app or any model calls. Not loaded inside Tauri.

import type { AgentEvent, Agents } from "./agents";
import type { Bubble } from "./bubble";

const cwd = "/Users/you/git/api";
const event = (kind: AgentEvent["kind"], detail = ""): AgentEvent => ({
  source: "claude",
  session: "demo",
  kind,
  detail,
  cwd,
});

export function install(agents: Agents, bubble: Bubble, openAsks: Set<string>, changed: () => void) {
  let asks = 0;
  const keys: Record<string, () => void> = {
    "1": () => agents.handle(event("think")),
    "2": () => agents.handle(event("read", "App.tsx")),
    "3": () => agents.handle(event("edit", "App.tsx")),
    "4": () => agents.handle(event("run", "npm test")),
    "5": () => {
      const id = `demo-${asks++}`;
      openAsks.add(id);
      bubble.ask({ id, source: "claude", session: "demo", title: "Run a command?", detail: "rm -rf node_modules", cwd, canDefer: true });
      changed();
    },
    "6": () => agents.handle(event("done", "Tests pass. 3 files changed.")),
    "7": () => agents.handle(event("failed", "rate_limit")),
    "8": () => bubble.prompt(),
    "0": () => agents.handle(event("end")),
  };
  addEventListener("keydown", (e) => {
    if (e.target instanceof HTMLInputElement) return;
    keys[e.key]?.();
  });
}
