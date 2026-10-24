// Sample activity, so the pets can be tried without an AI tool and without model calls.
//
// `play` is the onboarding's "Try a demo": a short, labelled sample session with a sample
// request on the main pet. Its answer goes nowhere.
//
// `install` is the browser preview's harness: keys play fake agent events.
//   1 think · 2 read · 3 edit · 4 run · 5 permission question · 6 done · 7 failed · 0 end
//   p switches the fake project (api, web, docs) · c opens the main pet's command bar

import { sessionLabel, type AgentEvent } from "./agents";
import type { Crew } from "./crew";

const projects = ["/Users/you/git/api", "/Users/you/git/web", "/Users/you/git/docs"];

export function play(crew: Crew) {
  const pet = crew.main;
  const event = (kind: AgentEvent["kind"], detail = ""): AgentEvent => ({
    source: "codex",
    session: "demo-04",
    kind,
    detail,
    cwd: "/demo/website",
    project: "/demo/Website refresh",
  });
  const steps: [number, () => void][] = [
    [0, () => pet.bubble.say("This is a demo. Nothing here is connected or run.", 4)],
    [2500, () => pet.agents.handle(event("think"))],
    [4500, () => pet.agents.handle(event("read", "package.json"))],
    [7000, () => pet.agents.handle(event("edit", "index.html"))],
    [
      9500,
      () =>
        crew.question(pet, {
          id: "demo-request",
          who: `${pet.name} · Website refresh (demo)`,
          context: `Codex · ${sessionLabel("04")}`,
          title: "Run project tests?",
          lines: ["Codex is asking to run this command in Website refresh."],
          facts: [
            { label: "Command", value: "npm test" },
            { label: "Folder", value: "/work/website" },
          ],
          note: "Demo only: your answer is not sent anywhere.",
          choices: [
            { label: "Decline", value: "deny" },
            { label: "Allow once", value: "allow", primary: true },
          ],
          onChoose: (value) => {
            pet.bubble.say(`${value === "allow" ? "Allowed once" : "Declined"} — demo only. No command was run.`, 5);
            setTimeout(() => pet.agents.handle(event(value === "allow" ? "done" : "end", "Tests pass (sample).")), 3000);
          },
        }),
    ],
  ];
  for (const [at, step] of steps) setTimeout(step, at);
}

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
        detail: "rm -rf node_modules && npm ci && npm test -- --coverage --reporter=verbose",
        cwd: projects[project],
        project: projects[project],
        canDefer: true,
        kind: "command",
        expires: Date.now() + 60_000,
      }),
    "6": () => crew.handleEvent(event("done", "Tests pass. 3 files changed.")),
    "7": () => crew.handleEvent(event("failed", "rate_limit")),
    "0": () => crew.handleEvent(event("end")),
    d: () => play(crew),
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
