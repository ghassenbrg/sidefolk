import { describe, expect, it } from "vitest";
import { matchNotebook, today, type Notebook } from "./notes";

const book = (name: string, updated = 0): Notebook => ({ id: name.toLowerCase().replace(/\s+/g, "-"), name, count: 0, updated });

describe("matchNotebook", () => {
  const books = [book("Evaluation H2 2026", 1), book("Ideas", 2), book("Project X decisions", 3)];
  it("finds a notebook by a word of its name, any case", () => {
    expect(matchNotebook(books, "evaluation")?.name).toBe("Evaluation H2 2026");
    expect(matchNotebook(books, "IDEAS")?.name).toBe("Ideas");
    expect(matchNotebook(books, "project x")?.name).toBe("Project X decisions");
    expect(matchNotebook(books, "decisions")?.name).toBe("Project X decisions");
  });
  it("prefers an exact name and the most recent of several", () => {
    const two = [book("Ideas old", 1), book("Ideas new", 5), book("Ideas", 0)];
    expect(matchNotebook(two, "ideas")?.name).toBe("Ideas");
    expect(matchNotebook(two.slice(0, 2), "ideas")?.name).toBe("Ideas new");
  });
  it("returns nothing for an unknown name", () => expect(matchNotebook(books, "recipes")).toBeNull());
  it("writes today's local date", () => expect(today(new Date(2026, 0, 5, 23, 30))).toBe("2026-01-05"));
});
