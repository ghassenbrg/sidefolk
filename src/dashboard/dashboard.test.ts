import { describe, expect, it } from "vitest";
import type { PetStatus, Waiting } from "./api";
import { fromFields } from "./reminders";
import { petState, requestTitle, sessionLabel, sessionOf } from "./ui";

const pet = (over: Partial<PetStatus> = {}): PetStatus => ({
  id: "main",
  name: "Pip",
  label: "Pip",
  main: true,
  project: null,
  out: true,
  clip: "idle",
  sessions: [],
  outcomes: [],
  ...over,
});
const waiting = (meta: Record<string, string>): Waiting => ({ id: "w", pet: "main", petName: "Pip", who: "Pip · api", title: "Run a command?", lines: [], meta, choices: [] });
const session = (state: string, id = "s") => ({ source: "claude", id, cwd: "/x/api", state, verb: state, detail: "", project: "/x/api", at: 0 });

describe("reminder fields", () => {
  it("reads local date and time", () => {
    const d = fromFields("2026-10-25", "10:30")!;
    expect([d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes()]).toEqual([2026, 9, 25, 10, 30]);
  });
  it("rejects missing or malformed fields", () => {
    expect(fromFields("", "10:00")).toBeNull();
    expect(fromFields("2026-10-25", "")).toBeNull();
    expect(fromFields("25/10/2026", "10:00")).toBeNull();
  });
});

describe("companion status", () => {
  it("needs you beats everything", () => expect(petState(pet({ sessions: [session("edit")] }), [waiting({})])).toBe("alert"));
  it("follows the top session", () => {
    expect(petState(pet({ sessions: [session("think")] }), [])).toBe("think");
    expect(petState(pet({ sessions: [session("run")] }), [])).toBe("work");
  });
  it("is done right after finishing, idle later", () => {
    const now = 1_000_000_000;
    const done = { kind: "done" as const, source: "claude", project: "", detail: "", at: now - 60_000 };
    expect(petState(pet({ outcomes: [done] }), [], now)).toBe("done");
    expect(petState(pet({ outcomes: [{ ...done, at: now - 3_600_000 }] }), [], now)).toBe("idle");
  });
  it("opens the live session first, else the last one that ended", () => {
    expect(sessionOf(pet({ sessions: [session("edit", "t1")] }))).toEqual({ source: "claude", session: "t1", cwd: "/x/api", live: true });
    expect(sessionOf(pet({ outcomes: [{ kind: "done", source: "claude", project: "/x/api", detail: "", at: 0, session: "s9" }] }))).toEqual({
      source: "claude",
      session: "s9",
      cwd: "/x/api",
      live: false,
    });
    expect(sessionOf(pet())).toBeNull();
  });
});

describe("wording", () => {
  it("names requests in plain words", () => {
    expect(requestTitle(waiting({ kind: "permission", action: "command", source: "codex" }))).toBe("Codex wants to run a command.");
    expect(requestTitle(waiting({ kind: "question", source: "claude" }))).toBe("Claude has a question.");
  });
  it("shortens session IDs people compare", () => expect(sessionLabel("04c1e7d2-5b8a")).toBe("Work session 04c1"));
});
