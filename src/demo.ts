// Browser preview only (npm run web): keys play fake agent events, so the companion can be
// checked without an AI tool or model calls. Not loaded inside the desktop app.
//
//   1 think · 2 read · 3 edit · 4 run · 5 permission request · 6 done · 7 failed · 0 end
//   r a reminder due now · p switches the fake project (api, web, docs) · c opens the field

import type { AgentEvent } from "./agents";
import type { Companion } from "./companion";

const projects = ["/Users/you/git/api", "/Users/you/git/web", "/Users/you/git/docs"];

export function install(companion: Companion) {
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
    "1": () => companion.handleEvent(event("think")),
    "2": () => companion.handleEvent(event("read", "App.tsx")),
    "3": () => companion.handleEvent(event("edit", "App.tsx")),
    "4": () => companion.handleEvent(event("run", "npm test")),
    "5": () =>
      companion.handleAsk({
        id: `demo-${asks++}`,
        source: "claude",
        session: `demo-${project}`,
        title: "Run a command?",
        detail: "rm -rf node_modules && npm ci && npm test -- --coverage --reporter=verbose",
        cwd: projects[project],
        project: projects[project],
        canDefer: true,
        kind: "command",
        expires: Date.now() + 60_000,
      }),
    "6": () => companion.handleEvent(event("done", "Tests pass. 3 files changed.")),
    "7": () => companion.handleEvent(event("failed", "rate_limit")),
    "0": () => companion.handleEvent(event("end")),
    r: () => void companion.run("remind me in 0 minutes to stretch"),
    p: () => {
      project = (project + 1) % projects.length;
      companion.pet.bubble.say(`Demo project: ${projects[project].split("/").pop()}`, 2);
    },
    c: () => companion.openPrompt(),
  };
  addEventListener("keydown", (e) => {
    if (e.target instanceof HTMLInputElement) return;
    keys[e.key]?.();
  });
}
