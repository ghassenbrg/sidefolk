import * as chrono from "chrono-node";

// Understands "Friday at 3 to review the PR", "to stretch in 20 minutes" and the like on
// the user's machine, so setting a reminder never costs model tokens.

/** How a reminder comes back. Weekly/every-N-weeks repeat on the weekday of the first due date. */
export type Repeat = { every: "day" | "weekday" | "week" | "month"; n: number };
export type Parsed = { what: string; due: Date; repeat?: Repeat };

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

/** Finds "every day", "daily", "on weekdays", "every 2 weeks", "every Monday", "monthly"… and
 * returns the text without it; "every Monday" leaves "Monday" for the date parser. */
export function takeRepeat(text: string): { rest: string; repeat?: Repeat } {
  const rules: [RegExp, (m: RegExpMatchArray) => Repeat, (m: RegExpMatchArray) => string][] = [
    [/\b(?:every|each) (\d+) (day|week|month)s\b/i, (m) => ({ every: m[2].toLowerCase() as Repeat["every"], n: Number(m[1]) }), () => ""],
    [/\b(?:every|each|on) ?(?:week ?days?|weekdays)\b|\bweekdays\b/i, () => ({ every: "weekday", n: 1 }), () => ""],
    [/\b(?:every|each) (day|morning|evening|night)\b|\bdaily\b/i, () => ({ every: "day", n: 1 }), (m) => (m[1] && m[1].toLowerCase() !== "day" ? `in the ${m[1]}` : "")],
    [new RegExp(`\\b(?:every|each) (${WEEKDAYS.join("|")})s?\\b`, "i"), () => ({ every: "week", n: 1 }), (m) => m[1]],
    [/\b(?:every|each) (week|month)\b|\b(weekly|monthly)\b/i, (m) => ({ every: (m[1] ?? m[2]).toLowerCase().replace("ly", "") as Repeat["every"], n: 1 }), () => ""],
  ];
  for (const [pattern, repeat, keep] of rules) {
    const m = text.match(pattern);
    if (m && m.index !== undefined) {
      const rest = (text.slice(0, m.index) + " " + keep(m) + " " + text.slice(m.index + m[0].length)).replace(/\s+/g, " ").trim();
      const r = repeat(m);
      if (r.n >= 1 && r.n <= 52) return { rest, repeat: r };
    }
  }
  return { rest: text };
}

/** The next time a repeating reminder is due after `after`, in local time, so 09:00 stays 09:00
 * across daylight-saving changes. Monthly on the 31st falls back to the month's last day. */
export function nextDue(first: Date, repeat: Repeat, after: Date): Date {
  const next = new Date(first);
  let guard = 0;
  while (next <= after && guard++ < 5000) {
    if (repeat.every === "day") next.setDate(next.getDate() + repeat.n);
    else if (repeat.every === "week") next.setDate(next.getDate() + 7 * repeat.n);
    else if (repeat.every === "weekday") {
      do next.setDate(next.getDate() + 1);
      while (next.getDay() === 0 || next.getDay() === 6);
    } else {
      const day = first.getDate();
      next.setDate(1);
      next.setMonth(next.getMonth() + repeat.n);
      next.setDate(Math.min(day, new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate()));
    }
  }
  return next;
}

/** "every day", "every weekday", "every 2 weeks on Friday", "every month on day 3". */
export function describeRepeat(repeat: Repeat, first: Date): string {
  const plural = repeat.n > 1 ? `${repeat.n} ${repeat.every}s` : repeat.every;
  if (repeat.every === "week") return `every ${plural} on ${first.toLocaleDateString([], { weekday: "long" })}`;
  if (repeat.every === "month") return `every ${plural} on day ${first.getDate()}`;
  return `every ${plural}`;
}

/** Times of day given without am/pm mean working hours: "at 3" is 15:00, "at 9" is 09:00. */
function workingHours(result: chrono.ParsedResult, due: Date) {
  const hour = result.start.get("hour");
  const meridiem = result.start.isCertain("meridiem");
  if (hour !== null && !meridiem && hour >= 1 && hour <= 7) due.setHours(hour + 12);
}

export function parseReminder(input: string, now = new Date()): Parsed | null {
  const { rest: text, repeat } = takeRepeat(input);
  const results = chrono.parse(text, now, { forwardDate: true });
  const result = results[0];
  if (!result) {
    // "every weekday to stand up" with no time: the next one at 09:00.
    if (!repeat || !text.trim()) return null;
    const first = new Date(now);
    first.setHours(9, 0, 0, 0);
    const due = nextDue(first, repeat, now);
    const what = text.replace(/^(to|about|that)\s+/i, "").trim();
    return what ? { what, due, repeat } : null;
  }
  const due = result.start.date();
  workingHours(result, due);
  // A date without a time ("Friday") means the start of the working day.
  if (!result.start.isCertain("hour")) due.setHours(9, 0, 0, 0);
  // "at 3" said at 16:00 means tomorrow at 15:00, not an hour ago.
  if (due <= now) due.setDate(due.getDate() + 1);
  // Weekday repeats start on a weekday.
  if (repeat?.every === "weekday") while (due.getDay() === 0 || due.getDay() === 6) due.setDate(due.getDate() + 1);

  const what = (text.slice(0, result.index) + " " + text.slice(result.index + result.text.length))
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^(to|about|that)\s+/i, "")
    .replace(/\s+(to|about|that|on|at|in|by)$/i, "")
    .trim();
  if (!what) return null;
  return repeat ? { what, due, repeat } : { what, due };
}

/** A time on its own ("tomorrow at 9", "2026-10-24T15:00"), with the same rules as above. */
export function parseWhen(when: string, now = new Date()): Date | null {
  const result = chrono.parse(when, now, { forwardDate: true })[0];
  if (!result) return null;
  const due = result.start.date();
  // Agents usually send ISO times, which mean exactly what they say.
  if (!/\d{4}-\d{2}-\d{2}T/.test(when)) workingHours(result, due);
  if (!result.start.isCertain("hour")) due.setHours(9, 0, 0, 0);
  return due > now ? due : null;
}

/** "today 15:00", "tomorrow 09:00", "Fri 24 Oct 15:00". */
export function describeDue(due: Date, now = new Date()): string {
  const time = due.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  const day = new Date(now);
  day.setHours(0, 0, 0, 0);
  const days = Math.floor((due.getTime() - day.getTime()) / 86_400_000);
  if (days === 0) return `today ${time}`;
  if (days === 1) return `tomorrow ${time}`;
  if (days === -1) return `yesterday ${time}`;
  return `${due.toLocaleDateString([], { weekday: "short", day: "numeric", month: "short" })} ${time}`;
}
