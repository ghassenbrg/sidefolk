import { describe, expect, it } from "vitest";
import { parseReminder, parseWhen } from "./when";

// Thursday 22 October 2026, 16:00 local time.
const now = new Date(2026, 9, 22, 16, 0);
const at = (d: Date) => [d.getDate(), d.getHours(), d.getMinutes()];

describe("parseReminder", () => {
  it("reads a weekday and a bare hour as working hours", () => {
    const r = parseReminder("Friday at 3 to review the PR", now)!;
    expect(r.what).toBe("review the PR");
    expect(at(r.due)).toEqual([23, 15, 0]);
  });
  it("reads relative times", () => {
    const r = parseReminder("to stretch in 20 minutes", now)!;
    expect(r.what).toBe("stretch");
    expect(at(r.due)).toEqual([22, 16, 20]);
  });
  it("puts a past time of day on the next day", () => {
    const r = parseReminder("at 9am about the standup", now)!;
    expect(r.what).toBe("the standup");
    expect(at(r.due)).toEqual([23, 9, 0]);
  });
  it("starts date-only reminders at 9:00", () => {
    const r = parseReminder("tomorrow to merge the release branch", now)!;
    expect(at(r.due)).toEqual([23, 9, 0]);
  });
  it("needs both a time and something to remember", () => {
    expect(parseReminder("to water the plants", now)).toBeNull();
    expect(parseReminder("tomorrow at 10", now)).toBeNull();
  });
});

describe("parseWhen", () => {
  it("takes ISO times literally and plain words with the same rules", () => {
    expect(at(parseWhen("2026-10-23T03:00", now)!)).toEqual([23, 3, 0]);
    expect(at(parseWhen("tomorrow at 4", now)!)).toEqual([23, 16, 0]);
    expect(at(parseWhen("in 2 hours", now)!)).toEqual([22, 18, 0]);
  });
  it("refuses the past and nonsense", () => {
    expect(parseWhen("2020-01-01T10:00", now)).toBeNull();
    expect(parseWhen("whenever", now)).toBeNull();
  });
});
