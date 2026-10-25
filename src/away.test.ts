import { describe, expect, it } from "vitest";
import { weekly, weeklyDue, weekStart, welcomeBack, type JournalEntry } from "./away";

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

describe("weekly", () => {
  const friday = new Date(2026, 9, 30, 16, 0);
  it("starts the week on Monday", () => expect(weekStart(friday).toDateString()).toBe(new Date(2026, 9, 26).toDateString()));
  it("sums up notes and finished work since Monday", () => {
    const monday = new Date(2026, 9, 26, 10).getTime();
    const lines = weekly(
      [
        { at: monday, source: "claude", session: "a", project: "/x/api", kind: "done", detail: "" },
        { at: monday + 3_600_000, source: "claude", session: "b", project: "/x/api", kind: "done", detail: "" },
        { at: monday - 86_400_000 * 3, source: "codex", session: "c", project: "/x/web", kind: "done", detail: "" },
      ],
      [
        { notebook: "Evaluation", date: "2026-10-27" },
        { notebook: "Evaluation", date: "2026-10-29" },
        { notebook: "Ideas", date: "2026-10-20" },
      ],
      friday,
    );
    expect(lines).toEqual(["2 notes: Evaluation (2)", "api · Claude finished 2 tasks"]);
  });
  it("is due once, on Friday afternoon", () => {
    const data = new Map<string, string>();
    const storage = { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => void data.set(k, v) };
    expect(weeklyDue(storage, new Date(2026, 9, 30, 10))).toBe(false);
    expect(weeklyDue(storage, friday)).toBe(true);
    expect(weeklyDue(storage, new Date(2026, 9, 30, 17))).toBe(false);
  });
});
