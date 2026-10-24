import { describe, expect, it } from "vitest";
import { due, headline, type CalendarEvent } from "./calendar";

const now = Date.UTC(2026, 9, 26, 14, 0);
const event = (id: string, inMin: number): CalendarEvent => ({ id, title: "Design review", start: now + inMin * 60_000, end: now + (inMin + 30) * 60_000, location: "", link: null, calendar: "Work" });

describe("calendar heads-up", () => {
  it("announces meetings inside the lead time, once", () => {
    const events = [event("a", 4), event("b", 20), event("c", -1), event("d", -5)];
    expect(due(events, 5, new Set(), now).map((e) => e.id)).toEqual(["a", "c"]);
    expect(due(events, 5, new Set(["a"]), now).map((e) => e.id)).toEqual(["c"]);
    expect(due(events, 30, new Set(), now).map((e) => e.id)).toEqual(["a", "b", "c"]);
  });
  it("says how soon", () => {
    expect(headline(event("a", 5), now)).toBe("Design review in 5 min");
    expect(headline(event("a", 0), now)).toBe("Design review now");
  });
});
