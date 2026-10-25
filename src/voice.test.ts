import { describe, expect, it } from "vitest";
import { problem, agentProblem } from "./voice";

const sources = import.meta.glob("./**/*.ts", { eager: true, query: "?raw", import: "default" }) as Record<string, string>;

describe("failure vocabulary", () => {
  it("gives a useful next step instead of backend diagnostics", () => {
    for (const raw of ["Error: ECONNREFUSED at /secret/config:42", "not_waiting", "serde failure {private: data}", "ENOSPC disk full", "EACCES permission denied", "rate_limit_exceeded", new Error("panic in thread")]) {
      const text = problem(raw);
      expect(text).not.toMatch(/Error:|[a-z]+_[a-z]+|secret|serde|panic/);
      expect(text.split(/\s+/).length).toBeLessThanOrEqual(12);
    }
    expect(problem("ENOSPC disk full")).toContain("free some space");
    expect(problem("changed on disk")).toContain("Reopen");
    expect(problem("That time has passed. Choose a later one.")).toBe("That time has passed. Choose a later one.");
  });
  it("names the agent without repeating its raw failure", () => {
    expect(agentProblem("Claude", "rate_limit_exceeded private token", "api")).toBe("Claude hit its usage limit in api.");
    expect(agentProblem("Codex", "unknown internal_error", "web")).toBe("Codex stopped in web; open the session to check.");
  });
  it("keeps raw catch formatting out of user-facing error paths", () => {
    for (const path of ["bubble.ts", "companion.ts", "reminders.ts", "dashboard/app.ts", "dashboard/home.ts", "dashboard/notes.ts", "dashboard/reminders.ts", "dashboard/settings.ts", "dashboard/setup.ts", "dashboard/tell.ts", "dashboard/notifications.ts", "dashboard/ui.ts", "dashboard/sessions.ts"]) {
      const source = sources[`./${path}`];
      expect(source, path).not.toMatch(/String\((?:e|error)\)|\$\{(?:e|error)\}/);
    }
  });
});
