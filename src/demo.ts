// Browser-only harness: keys play fake agent events so the crew can be checked without the
// desktop app or any model calls. Not loaded inside Tauri.
//
//   1 think · 2 read · 3 edit · 4 run · 5 permission question · 6 done · 7 failed · 0 end
//   p switches the fake project (api, web, docs) · c opens the main pet's command bar

import type { AgentEvent } from "./agents";
import type { Crew } from "./crew";

const projects = ["/Users/you/git/api", "/Users/you/git/web", "/Users/you/git/docs"];

export function install(crew: Crew) {
  let project = 0;
  let asks = 0;
  const event = (kind: AgentEvent["kind"], detail = ""): AgentEvent => ({
    source: "claude",
    session: `demo-${project}`,
    kind,
    detail,
    cwd: projects[project],
    project: projects[project],
  });
  const keys: Record<string, () => void> = {
    "1": () => crew.handleEvent(event("think")),
    "2": () => crew.handleEvent(event("read", "App.tsx")),
    "3": () => crew.handleEvent(event("edit", "App.tsx")),
    "4": () => crew.handleEvent(event("run", "npm test")),
    "5": () =>
      crew.handleAsk({
        id: `demo-${asks++}`,
        source: "claude",
        session: `demo-${project}`,
        title: "Run a command?",
        detail: "rm -rf node_modules",
        cwd: projects[project],
        project: projects[project],
        canDefer: true,
      }),
    "6": () => crew.handleEvent(event("done", "Tests pass. 3 files changed.")),
    "7": () => crew.handleEvent(event("failed", "rate_limit")),
    "0": () => crew.handleEvent(event("end")),
    p: () => {
      project = (project + 1) % projects.length;
      crew.main.bubble.say(`Demo project: ${projects[project].split("/").pop()}`, 2);
    },
    c: () => crew.openPrompt(crew.main),
  };
  addEventListener("keydown", (e) => {
    if (e.target instanceof HTMLInputElement) return;
    keys[e.key]?.();
  });
}
