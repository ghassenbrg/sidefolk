import * as chrono from "chrono-node";

// Understands "Friday at 3 to review the PR", "to stretch in 20 minutes" and the like on
// the user's machine, so setting a reminder never costs model tokens.

/** How a reminder comes back. Weekly/every-N-weeks repeat on the weekday of the first due date. */
export type Repeat = { every: "day" | "weekday" | "week" | "month"; n: number };
/** `alternative`: the other reading of a bare hour ("at 9": 21:00 today or 09:00 tomorrow). */
export type Parsed = { what: string; due: Date; repeat?: Repeat; alternative?: Date };

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

/** "tonight", "end of day", "tomorrow morning", "noon": into times the date parser reads exactly. */
function nameTimes(text: string): string {
  return text
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
  const first = results[0];
  if (!first) return null;
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
  return { due: chosen, used, alternative: candidates[1] };
}

export function parseReminder(input: string, now = new Date()): Parsed | null {
  const { rest: offsetText, ms: offset } = takeOffset(nameTimes(input));
  const withoutOffset = offset ? offsetText.replace(/[,;]?\s*remind me\s*/i, " ").trim() : offsetText;
  const { rest: text, repeat } = takeRepeat(withoutOffset);
  const resolved = resolve(chrono.parse(text, now, { forwardDate: true }), now, repeat);
  if (!resolved) {
    // "every weekday to stand up" with no time: the next one at 09:00.
    if (!repeat || !text.trim()) return null;
    const first = new Date(now);
    first.setHours(9, 0, 0, 0);
    const due = nextDue(first, repeat, now);
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
  // Weekday repeats start on a weekday.
  if (repeat?.every === "weekday") while (due.getDay() === 0 || due.getDay() === 6) due.setDate(due.getDate() + 1);

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
  const results = chrono.parse(nameTimes(when), now, { forwardDate: true });
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
