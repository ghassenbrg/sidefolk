import * as chrono from "chrono-node";

// Understands "Friday at 3 to review the PR", "to stretch in 20 minutes" and the like on
// the user's machine, so setting a reminder never costs model tokens.

/** How a reminder comes back. Weekly/every-N-weeks repeat on the weekday of the first due date. */
export type Repeat = { every: "day" | "weekday" | "week" | "month"; n: number; days?: number[] };
/** `alternative`: the other reading of a bare hour ("at 9": 21:00 today or 09:00 tomorrow). */
export type Parsed = { what: string; due: Date; repeat?: Repeat; alternative?: Date };

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

/** Finds "every day", "daily", "on weekdays", "every 2 weeks", "every Monday", "monthly"… and
 * returns the text without it; "every Monday" leaves "Monday" for the date parser. */
export function takeRepeat(text: string): { rest: string; repeat?: Repeat } {
  // "every Monday and Thursday", "mondays and thursdays", "every mon, wed and fri": a weekly
  // series on those days (docs/V1.md V1-Q4). The first day stays for the date parser.
  const day = `(?:${WEEKDAYS.map((d) => `${d.slice(0, 3)}(?:${d.slice(3)})?`).join("|")})s?`;
  const list = new RegExp(`\\b(?:(?:every|each|on)\\s+)?(${day}(?:\\s*(?:,|and|&)\\s*${day})+)\\b`, "i");
  const named = text.match(list);
  if (named && named.index !== undefined) {
    const days = [...new Set(named[1].split(/\s*(?:,|and|&)\s*/i).map((d) => WEEKDAYS.findIndex((w) => w.startsWith(d.toLowerCase().slice(0, 3)))).filter((d) => d >= 0))].sort((a, b) => a - b);
    if (days.length > 1) {
      const rest = `${text.slice(0, named.index)} ${text.slice(named.index + named[0].length)}`.replace(/\s+/g, " ").trim();
      return { rest, repeat: { every: "week", n: 1, days } };
    }
  }
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

/** "every day", "every weekday", "every 2 weeks on Friday", "every Monday and Thursday", "every month on day 3". */
export function describeRepeat(repeat: Repeat, first: Date): string {
  const plural = repeat.n > 1 ? `${repeat.n} ${repeat.every}s` : repeat.every;
  if (repeat.days?.length) {
    const names = repeat.days.map((d) => new Date(2026, 9, 25 + d).toLocaleDateString([], { weekday: "long" }));
    const joined = names.length > 1 ? `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}` : names[0];
    return repeat.n > 1 ? `every ${repeat.n} weeks on ${joined}` : `every ${joined}`;
  }
  if (repeat.every === "week") return `every ${plural} on ${first.toLocaleDateString([], { weekday: "long" })}`;
  if (repeat.every === "month") return `every ${plural} on day ${first.getDate()}`;
  return `every ${plural}`;
}

/** "10 minutes before", "an hour before", "2 days before": how much earlier than the time given. */
function takeOffset(text: string): { rest: string; ms: number } {
  const m = text.match(/\b(\d+|an?|one) (min(?:ute)?s?|hours?|days?) before\b/i);
  if (!m || m.index === undefined) return { rest: text, ms: 0 };
  const n = /^\d+$/.test(m[1]) ? Number(m[1]) : 1;
  const unit = m[2].toLowerCase().startsWith("min") ? 60_000 : m[2].toLowerCase().startsWith("hour") ? 3_600_000 : 86_400_000;
  return { rest: (text.slice(0, m.index) + " " + text.slice(m.index + m[0].length)).replace(/\s+/g, " ").trim(), ms: n * unit };
}

/** Named parts of the day, as the times they mean (docs/V1.md V1-Q3). */
const PART: Record<string, string> = { morning: "9am", afternoon: "3pm", evening: "6pm", night: "8pm" };
const DAYS = `today|tomorrow|${WEEKDAYS.join("|")}`;

const MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

/**
 * "tonight", "end of day", "tomorrow morning", "noon", "14h30", "on the 1st": into times the date
 * parser reads exactly. "the 1st" is the next 1st of a month, this month's if it's still to come.
 */
function nameTimes(text: string, now: Date): string {
  return text
    .replace(/\b(\d{1,2})h(\d{2})?\b/gi, (_, h: string, m?: string) => `${h}:${m ?? "00"}`)
    .replace(/\btonight\s+at\s+(\d{1,2}(?::\d{2})?)(?!\s*[ap]\.?m)/gi, "today at $1pm")
    .replace(/\bat\s+(\d{1,2}(?::\d{2})?)\s+tonight\b/gi, "today at $1pm")
    .replace(/\b(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b(?!\s+(?:of\s+)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec))/gi, (all, n: string) => {
      const day = Number(n);
      const month = day > now.getDate() ? now.getMonth() : now.getMonth() + 1;
      const date = new Date(now.getFullYear(), month, day);
      return day >= 1 && day <= 31 && date.getDate() === day ? `on ${MONTH_NAMES[date.getMonth()]} ${day}` : all;
    })
    .replace(/\b(?:by |at )?(?:the )?end of (?:the )?(?:work ?)?day\b|\beod\b/gi, "at 5pm")
    .replace(/\btonight\b/gi, "today at 8pm")
    .replace(/\bthis (morning|afternoon|evening)\b/gi, (_, part: string) => `today at ${PART[part.toLowerCase()]}`)
    .replace(new RegExp(`\\b(${DAYS})\\s+(morning|afternoon|evening|night)\\b`, "gi"), (_, day: string, part: string) => `${day} at ${PART[part.toLowerCase()]}`)
    .replace(/\bin the (morning|afternoon|evening)\b/gi, (_, part: string) => `at ${PART[part.toLowerCase()]}`)
    .replace(/\b(?:at |by )?noon\b/gi, "at 12pm");
}

const dateKnown = (r: chrono.ParsedResult) => r.start.isCertain("day") || r.start.isCertain("weekday");

/**
 * When a reminder is due, from the date parser's results. A date and a time said apart ("tomorrow
 * standup 9:30") are one moment. A bare hour ("at 3") is the soonest 3:00 or 15:00 from now that
 * falls between 07:00 and 21:59; a repeat keeps working hours instead (1–7 is the afternoon), so
 * "every weekday at 9" stays at 09:00. Without a time, the day starts at 09:00.
 */
function resolve(results: chrono.ParsedResult[], now: Date, repeat?: Repeat): { due: Date; used: chrono.ParsedResult[]; alternative?: Date } | null {
  // "plan the week on monday": a vague "the week" gives way to the day that's named.
  const specific = results.length > 1 ? results.filter((r) => !/^(?:the|this)\s+(?:week|month|year)$/i.test(r.text)) : results;
  const first = specific[0];
  if (!first) return null;
  results = specific;
  const timed = first.start.isCertain("hour") ? first : results.find((r) => r.start.isCertain("hour") && !dateKnown(r));
  const used = timed && timed !== first ? [first, timed] : [first];
  const hasDate = used.some(dateKnown);
  const due = first.start.date();
  if (!timed) {
    due.setHours(9, 0, 0, 0);
    return { due, used };
  }
  const hour = timed.start.get("hour") ?? 9;
  const minute = timed.start.get("minute") ?? 0;
  if (timed !== first) due.setHours(hour, minute, 0, 0);
  if (timed.start.isCertain("meridiem") || hour === 0 || hour > 12) {
    // An exact time ("at 9am", "in 20 minutes"): said for a time already gone today, it's tomorrow.
    if (!hasDate && due <= now) due.setDate(due.getDate() + 1);
    return { due, used };
  }
  const h = hour % 12;
  if (repeat) {
    due.setHours(h >= 1 && h <= 7 ? h + 12 : hour, minute, 0, 0);
    if (!hasDate && due <= now) due.setDate(due.getDate() + 1);
    return { due, used };
  }
  const days = hasDate ? [0] : [0, 1];
  const candidates = days
    .flatMap((plus) => [h, h + 12].map((hh) => {
      const d = new Date(hasDate ? due : now);
      d.setDate(d.getDate() + plus);
      d.setHours(hh, minute, 0, 0);
      return d;
    }))
    .filter((d) => d > now && d.getHours() >= 7 && d.getHours() <= 21)
    .sort((a, b) => a.getTime() - b.getTime());
  const chosen = candidates[0] ?? (() => {
    const d = new Date(due);
    d.setHours(h >= 1 && h <= 7 ? h + 12 : hour, minute, 0, 0);
    if (!hasDate && d <= now) d.setDate(d.getDate() + 1);
    return d;
  })();
  // The other reading is the other time of day ("9" as 21:00 or 09:00), not the same hour later.
  return { due: chosen, used, alternative: candidates.find((d) => d.getHours() !== chosen.getHours()) };
}

export function parseReminder(input: string, now = new Date()): Parsed | null {
  const { rest: offsetText, ms: offset } = takeOffset(nameTimes(input, now));
  const withoutOffset = offset ? offsetText.replace(/[,;]?\s*remind me\s*/i, " ").trim() : offsetText;
  const { rest: taken, repeat } = takeRepeat(withoutOffset);
  // "every evening" leaves "in the evening", which becomes a time too.
  const text = repeat ? nameTimes(taken, now) : taken;
  const resolved = resolve(chrono.parse(text, now, { forwardDate: true }), now, repeat);
  if (!resolved) {
    // "every weekday to stand up" with no time: the next 09:00 (on a weekday for weekdays).
    if (!repeat || !text.trim()) return null;
    const due = new Date(now);
    due.setHours(9, 0, 0, 0);
    if (due <= now) due.setDate(due.getDate() + 1);
    if (repeat.every === "weekday") while (due.getDay() === 0 || due.getDay() === 6) due.setDate(due.getDate() + 1);
    if (repeat.days?.length) while (!repeat.days.includes(due.getDay())) due.setDate(due.getDate() + 1);
    const what = text.replace(/^(to|about|that)\s+/i, "").trim();
    return what ? { what, due, repeat } : null;
  }
  const { due, used } = resolved;
  // "today to call the bank" said after 09:00 has no time left to pick: ask when instead.
  if (due <= now) return null;
  // "10 minutes before the 3pm call": earlier than the time given, never in the past.
  if (offset) {
    due.setTime(due.getTime() - offset);
    if (due <= now) return null;
  }
  // Weekday repeats start on a weekday; one on named days starts on the soonest of them.
  if (repeat?.every === "weekday") while (due.getDay() === 0 || due.getDay() === 6) due.setDate(due.getDate() + 1);
  if (repeat?.days?.length) {
    const time = [due.getHours(), due.getMinutes()] as const;
    due.setTime(now.getTime());
    due.setHours(time[0], time[1], 0, 0);
    while (!repeat.days.includes(due.getDay()) || due <= now) due.setDate(due.getDate() + 1);
  }

  let rest = text;
  for (const r of [...used].sort((a, b) => b.index - a.index)) rest = rest.slice(0, r.index) + " " + rest.slice(r.index + r.text.length);
  const what = rest
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^(to|about|that|of)\s+/i, "")
    .replace(/\s+(to|about|that|on|at|in|by|the|of)$/i, "")
    .replace(/[,;:]$/, "")
    .trim();
  if (!what) return null;
  const alternative = !offset && !repeat ? resolved.alternative : undefined;
  return { what, due, ...(repeat ? { repeat } : {}), ...(alternative ? { alternative } : {}) };
}

/** A time on its own ("tomorrow at 9", "2026-10-24T15:00"), with the same rules as above. */
export function parseWhen(when: string, now = new Date()): Date | null {
  const results = chrono.parse(nameTimes(when, now), now, { forwardDate: true });
  // Agents usually send ISO times, which mean exactly what they say.
  if (/\d{4}-\d{2}-\d{2}T/.test(when)) {
    const exact = results[0]?.start.date();
    return exact && exact > now ? exact : null;
  }
  const due = resolve(results, now)?.due;
  return due && due > now ? due : null;
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
