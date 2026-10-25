import { describe, expect, it } from "vitest";
import { matchesNote, matchNotebook, mondayOf, today, type Notebook } from "./notes";

const book = (name: string, updated = 0): Notebook => ({ id: name.toLowerCase().replace(/\s+/g, "-"), name, count: 0, updated });

describe("matchNotebook", () => {
  const books = [book("Evaluation H2 2026", 1), book("Ideas", 2), book("Project X decisions", 3)];
  it("takes an exact name in any case", () => {
    expect(matchNotebook(books, "IDEAS").exact?.name).toBe("Ideas");
    expect(matchNotebook(books, "evaluation h2 2026").exact?.name).toBe("Evaluation H2 2026");
  });
  it("never guesses: near names are offered, not picked (docs/V1.md V1-L3)", () => {
    expect(matchNotebook(books, "evaluation")).toEqual({ exact: null, near: [books[0]] });
    const two = [book("Evaluation H1 2026", 9), book("Evaluation H2 2026", 1)];
    expect(matchNotebook(two, "evaluation").near.map((b) => b.name)).toEqual(["Evaluation H1 2026", "Evaluation H2 2026"]);
    expect(matchNotebook(books, "recipes")).toEqual({ exact: null, near: [] });
  });
  it("writes today's local date", () => expect(today(new Date(2026, 0, 5, 23, 30))).toBe("2026-01-05"));
});

describe("searching the work log by text and date", () => {
  const now = new Date(2026, 9, 25, 10); // Sunday 25 October 2026
  const entry = (date: string, text = "led the RT migration", project = "api") => ({ line: 2, date, text, project });
  it("matches words in the text, project or notebook, and dates", () => {
    expect(matchesNote(entry("2026-10-03"), "Evaluation H2 2026", "evaluation october", now)).toBe(true);
    expect(matchesNote(entry("2026-10-03"), "Evaluation H2 2026", "evaluation november", now)).toBe(false);
    expect(matchesNote(entry("2026-04-12"), "Log", "2026-04", now)).toBe(true);
    expect(matchesNote(entry("2026-04-12"), "Log", "apr migration", now)).toBe(true);
    expect(matchesNote(entry("2026-04-12"), "Log", "api", now)).toBe(true);
  });
  it("understands this week and last week", () => {
    expect(matchesNote(entry("2026-10-20"), "Log", "this week", now)).toBe(true);
    expect(matchesNote(entry("2026-10-14"), "Log", "last week", now)).toBe(true);
    expect(matchesNote(entry("2026-10-14"), "Log", "this week migration", now)).toBe(false);
  });
  it("finds the Monday of a week", () => expect(mondayOf("2026-10-25")).toBe("2026-10-19"));
});
