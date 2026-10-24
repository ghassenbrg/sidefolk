import { describe, expect, it } from "vitest";
import type { PetStatus, Settings, Waiting } from "./api";
import { describeEntry } from "./activity";
import { lookAvailable, PRESETS, suggestions } from "./comfort";
import { fromFields } from "./reminders";
import { petState, requestTitle, sessionLabel, sessionOf } from "./ui";

const pet = (over: Partial<PetStatus> = {}): PetStatus => ({
  id: "byte",
  name: "Byte",
  label: "Byte · api",
  main: false,
  project: "/x/api",
  look: { species: "cat", palette: "charcoal", accessory: "glasses" },
  out: true,
  clip: "idle",
  sessions: [],
  outcomes: [],
  ...over,
});
const waiting = (meta: Record<string, string>, petId = "byte"): Waiting => ({ id: "w", pet: petId, petName: "Byte", who: "Byte · api", title: "Run a command?", lines: [], meta, choices: [] });

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

describe("comfort presets", () => {
  const settings = { calm: false, sounds: true, presence: "always", detail: "full" } as Settings;
  it("Friendly changes no settings", () => expect(suggestions("friendly", settings)).toEqual([]));
  it("Professional lists each change it would make", () => {
    expect(suggestions("professional", settings).map((s) => s.key)).toEqual(["calm", "sounds", "presence", "detail"]);
    expect(suggestions("professional", { ...settings, calm: true, sounds: false }).map((s) => s.key)).toEqual(["presence", "detail"]);
  });
  it("Minimal is menu bar only", () => expect(PRESETS.minimal.settings.find((s) => s.key === "presence")?.change).toEqual({ presence: "menubar" }));
  it("each preset's companion has a body", () => {
    for (const preset of Object.values(PRESETS)) expect(lookAvailable(preset.look)).toBe(true);
  });
});

describe("pet status", () => {
  it("needs you beats everything", () => expect(petState(pet({ sessions: [{ source: "claude", id: "s", cwd: "", state: "edit", verb: "editing", detail: "", project: "", at: 0 }] }), [waiting({})])).toBe("alert"));
  it("follows the top session", () => {
    expect(petState(pet({ sessions: [{ source: "claude", id: "s", cwd: "", state: "think", verb: "thinking", detail: "", project: "", at: 0 }] }), [])).toBe("think");
    expect(petState(pet({ sessions: [{ source: "claude", id: "s", cwd: "", state: "run", verb: "running", detail: "", project: "", at: 0 }] }), [])).toBe("work");
  });
  it("is resting in the den, done right after finishing, idle later", () => {
    expect(petState(pet({ out: false }), [])).toBe("resting");
    const now = 1_000_000_000;
    const done = { kind: "done" as const, source: "claude", project: "", detail: "", at: now - 60_000 };
    expect(petState(pet({ outcomes: [done] }), [], now)).toBe("done");
    expect(petState(pet({ outcomes: [{ ...done, at: now - 3_600_000 }] }), [], now)).toBe("idle");
  });
  it("opens the live session first, else the last one that ended", () => {
    const live = { source: "codex", id: "t1", cwd: "/x/api", state: "edit", verb: "editing", detail: "", project: "/x/api", at: 0 };
    expect(sessionOf(pet({ sessions: [live] }))).toEqual({ source: "codex", session: "t1", cwd: "/x/api", live: true });
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
  it("reports a declined request as declined", () => {
    expect(describeEntry({ at: 0, source: "claude", session: "", project: "", kind: "answer", detail: "denied" }).title).toBe("You declined");
  });
});
