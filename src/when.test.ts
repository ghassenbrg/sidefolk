import { describe, expect, it } from "vitest";
import { describeRepeat, nextDue, parseReminder, parseWhen } from "./when";

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

describe("repeats", () => {
  it("reads every weekday at 9", () => {
    const r = parseReminder("every weekday at 9 to stand up", now)!;
    expect(r.what).toBe("stand up");
    expect(r.repeat).toEqual({ every: "weekday", n: 1 });
    expect(at(r.due)).toEqual([23, 9, 0]);
  });
  it("starts a weekday repeat on Monday when said on Friday evening", () => {
    const friday = new Date(2026, 9, 23, 18, 0);
    const r = parseReminder("weekdays at 9 to check mail", friday)!;
    expect(at(r.due)).toEqual([26, 9, 0]);
  });
  it("reads every Monday and every 2 weeks", () => {
    const monday = parseReminder("every Monday at 10 to plan the week", now)!;
    expect(monday.repeat).toEqual({ every: "week", n: 1 });
    expect(at(monday.due)).toEqual([26, 10, 0]);
    expect(parseReminder("every 2 weeks on Friday at 4 to send the report", now)!.repeat).toEqual({ every: "week", n: 2 });
  });
  it("reads daily and monthly without a time", () => {
    const daily = parseReminder("daily to drink water", now)!;
    expect(daily.repeat).toEqual({ every: "day", n: 1 });
    expect(daily.what).toBe("drink water");
    expect(at(daily.due)).toEqual([23, 9, 0]);
    expect(parseReminder("pay rent monthly on the 1st", now)!.repeat).toEqual({ every: "month", n: 1 });
  });
  it("leaves one-off reminders alone", () => {
    expect(parseReminder("tomorrow at 9 to call the bank", now)!.repeat).toBeUndefined();
  });
  it("keeps the wall-clock time across daylight saving", () => {
    // Europe ends DST on 25 October 2026; 09:00 stays 09:00 whatever the zone.
    const first = new Date(2026, 9, 24, 9, 0);
    const next = nextDue(first, { every: "day", n: 1 }, new Date(2026, 9, 24, 10, 0));
    expect([next.getDate(), next.getHours()]).toEqual([25, 9]);
  });
  it("skips weekends and clamps monthly to short months", () => {
    const friday = new Date(2026, 9, 23, 9, 0);
    expect(nextDue(friday, { every: "weekday", n: 1 }, friday).getDay()).toBe(1);
    const jan31 = new Date(2027, 0, 31, 9, 0);
    const feb = nextDue(jan31, { every: "month", n: 1 }, jan31);
    expect([feb.getMonth(), feb.getDate()]).toEqual([1, 28]);
  });
  it("describes repeats", () => {
    expect(describeRepeat({ every: "weekday", n: 1 }, now)).toBe("every weekday");
    expect(describeRepeat({ every: "week", n: 2 }, now)).toBe("every 2 weeks on Thursday");
  });
});
