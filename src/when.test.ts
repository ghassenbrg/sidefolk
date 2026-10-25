import { describe, expect, it } from "vitest";
import { describeRepeat, nextDue, parseReminder, parseWhen, fromFields, parseEventReminder } from "./when";

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

describe("everyday phrasing (docs/V1.md V1-Q3)", () => {
  // Sunday 25 October 2026, 10:00 local time.
  const sunday = new Date(2026, 9, 25, 10, 0);
  it("reads a bare hour as the soonest one between 07:00 and 21:59, today when it can", () => {
    const r = parseReminder("at 3 to call mum", sunday)!;
    expect([r.what, ...at(r.due)]).toEqual(["call mum", 25, 15, 0]);
    expect(at(parseReminder("call mom at 5pm", sunday)!.due)).toEqual([25, 17, 0]);
    // "at 9" at 10:00 is ambiguous: tonight, with tomorrow morning as the other reading.
    const nine = parseReminder("at 9 to send the report", sunday)!;
    expect(at(nine.due)).toEqual([25, 21, 0]);
    expect(at(nine.alternative!)).toEqual([26, 9, 0]);
  });
  it("keeps a time said apart from its date", () => {
    const r = parseReminder("tomorrow standup 9:30", sunday)!;
    expect([r.what, ...at(r.due)]).toEqual(["standup", 26, 9, 30]);
  });
  it("puts an offset reminder before today's meeting, not tomorrow's", () => {
    const r = parseReminder("meeting at 3, remind me 10 minutes before", sunday)!;
    expect([r.what, ...at(r.due)]).toEqual(["meeting", 25, 14, 50]);
  });
  it("reads named times of day", () => {
    expect(at(parseReminder("tonight to water the plants", sunday)!.due)).toEqual([25, 20, 0]);
    expect(at(parseReminder("send the invoice end of day", sunday)!.due)).toEqual([25, 17, 0]);
    expect(at(parseReminder("tomorrow morning to call the bank", sunday)!.due)).toEqual([26, 9, 0]);
    expect(at(parseReminder("this afternoon to review the PR", sunday)!.due)).toEqual([25, 15, 0]);
    expect(at(parseReminder("lunch with Priya tomorrow at noon", sunday)!.due)).toEqual([26, 12, 0]);
  });
  it("reads a weekday with a time", () => {
    const r = parseReminder("dentist thursday 2:30", sunday)!;
    expect([r.what, ...at(r.due)]).toEqual(["dentist", 29, 14, 30]);
  });
});

describe("several days of the week (docs/V1.md V1-Q4)", () => {
  const sunday = new Date(2026, 9, 25, 10, 0);
  it("reads weekday lists as one weekly series on those days", () => {
    const r = parseReminder("every monday and thursday at 9 gym", sunday)!;
    expect(r.repeat).toEqual({ every: "week", n: 1, days: [1, 4] });
    expect([r.what, ...at(r.due)]).toEqual(["gym", 26, 9, 0]);
    expect(describeRepeat(r.repeat!, r.due)).toBe("every Monday and Thursday");
    const bins = parseReminder("bins out every tue and fri at 8pm", sunday)!;
    expect(bins.repeat?.days).toEqual([2, 5]);
    expect(at(bins.due)).toEqual([27, 20, 0]);
    expect(parseReminder("mondays, wednesdays and fridays at 7am run", sunday)!.repeat?.days).toEqual([1, 3, 5]);
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

describe("offsets", () => {
  it("reminds earlier than the time given", () => {
    const r = parseReminder("10 minutes before the call tomorrow at 3", now)!;
    expect(at(r.due)).toEqual([23, 14, 50]);
    expect(r.what).toBe("the call");
  });
  it("reads an offset after the event in voice-style capture", () => {
    const r = parseReminder("meeting tomorrow at 3, remind me 10 minutes before", now)!;
    expect(r.what).toBe("meeting");
    expect(at(r.due)).toEqual([23, 14, 50]);
  });
  it("reads an hour before", () => {
    const r = parseReminder("remind the team an hour before Friday at 10", now)!;
    expect(at(r.due)).toEqual([23, 9, 0]);
  });
  it("refuses an offset that lands in the past", () => {
    expect(parseReminder("2 hours before the demo at 5pm today", now)).toBeNull();
  });
});


describe("yearly and calendar policy", () => {
  it("keeps February 29 as the yearly anchor across clamped years", () => {
    const anchor = new Date(2024, 1, 29, 9);
    let due = anchor;
    for (const [year, day] of [[2025, 28], [2026, 28], [2027, 28], [2028, 29]]) {
      due = nextDue(anchor, { every: "year", n: 1 }, due);
      expect([due.getFullYear(), due.getMonth(), due.getDate(), due.getHours()]).toEqual([year, 1, day, 9]);
    }
    expect(describeRepeat({ every: "year", n: 1 }, anchor)).toContain("February 28 in non-leap years");
    expect(describeRepeat({ every: "month", n: 1 }, new Date(2027, 0, 31))).toContain("last day in shorter months");
    expect(parseReminder("renew yearly on October 30 at 9am", now)?.repeat).toEqual({ every: "year", n: 1 });
  });
  it("previews all chosen weekdays and counts weeks from the anchor", () => {
    const anchor = new Date(2026, 9, 26, 9);
    const repeat = { every: "week", n: 2, days: [1, 4] } as const;
    const rule = { ...repeat, days: [...repeat.days] };
    const thu = nextDue(anchor, rule, anchor);
    expect([thu.getDate(), thu.getDay(), thu.getHours()]).toEqual([29, 4, 9]);
    expect(nextDue(anchor, rule, thu).getDate()).toBe(9);
    const sunday = new Date(2026, 9, 25, 9);
    expect(nextDue(sunday, { every: "weekday", n: 1 }, new Date(sunday.getTime() - 1)).getDate()).toBe(26);
  });
  it.each(["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-10", "2026-10-00"])("rejects invalid calendar date %s", (date) => expect(fromFields(date, "09:00")).toBeNull());
  it.each(["24:00", "09:60", "-1:00"])("rejects invalid time %s", (time) => expect(fromFields("2026-10-25", time)).toBeNull());
  it.each(["every 2 days and 3 hours to stretch", "every 53 weeks on Friday at 9 to plan", "every last Friday at 9 to plan", "daily and weekly at 9 to plan"])("rejects the whole unsupported rule: %s", (text) => expect(parseReminder(text, now)).toBeNull());
});


describe("event conditions", () => {
  it("reads project completion before any incidental date words", () => {
    expect(parseEventReminder("remind me when api finishes")).toEqual({ project: "api", what: "api finishes" });
    expect(parseEventReminder('when "My API" is done to review tests')).toEqual({ project: "My API", what: "review tests" });
    expect(parseEventReminder("when tomorrow finishes")).toEqual({ project: "tomorrow", what: "tomorrow finishes" });
    expect(parseReminder("when tomorrow finishes")).toBeNull();
  });
  it.each(["$ echo when api finishes", "when api and web finishes", "when api finishes tomorrow", "when api fails", "when api finishes\nrun shell"])("never partially accepts %s", (text) => expect(parseEventReminder(text)).toBeNull());
});
