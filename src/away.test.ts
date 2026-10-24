import { describe, expect, it } from "vitest";
import { firstToday, morning, welcomeBack, type JournalEntry } from "./away";

const e = (kind: string, project: string, detail = "", source = "claude"): JournalEntry => ({ at: 0, source, session: "s", project, kind, detail });

describe("welcomeBack", () => {
  it("summarizes each project's latest outcome and missed questions", () => {
    const lines = welcomeBack(
      [
        e("prompt", "/git/api"),
        e("done", "/git/api", "Tests pass."),
        e("prompt", "/git/web"),
        e("ask", "/git/web", "Run a command? npm i"),
        e("answer", "/git/web", "not answered on the pet"),
        e("failed", "/git/docs", "rate_limit", "codex"),
      ],
      [],
    );
    expect(lines).toEqual([
      "api · Claude finished: Tests pass.",
      "web · still working",
      "web · a question went to the terminal",
      "docs · Codex hit a problem: rate_limit",
    ]);
  });
  it("is empty when nothing happened", () => {
    expect(welcomeBack([], [])).toEqual([]);
  });
});

describe("morning", () => {
  const now = new Date(2026, 9, 26, 8, 30);
  const at = (h: number, m = 0) => new Date(2026, 9, 26, h, m).getTime();
  it("puts today's meetings and reminders first, then overnight work", () => {
    const lines = morning(
      [{ at: at(2), source: "claude", session: "s", project: "/x/api", kind: "done", detail: "Tests pass." }],
      [{ id: "r", text: "Send the report", due: at(16), project: "", from: "you", created: 0, done: false, fired: false }],
      [{ title: "Standup", start: at(9, 30) }, { title: "Tomorrow's thing", start: at(9) + 86_400_000 }],
      now,
    );
    expect(lines[0]).toContain("Standup");
    expect(lines[1]).toContain("Send the report");
    expect(lines[2]).toContain("api · Claude finished: Tests pass.");
    expect(lines.join(" ")).not.toContain("Tomorrow's thing");
  });
  it("happens once a day", () => {
    const data = new Map<string, string>();
    const storage = { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => void data.set(k, v) };
    expect(firstToday(storage, now)).toBe(true);
    expect(firstToday(storage, now)).toBe(false);
    expect(firstToday(storage, new Date(2026, 9, 27, 8))).toBe(true);
  });
});
