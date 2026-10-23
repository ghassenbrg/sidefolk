import * as chrono from "chrono-node";

// Understands "Friday at 3 to review the PR", "to stretch in 20 minutes" and the like on
// the user's machine, so setting a reminder never costs model tokens.

export type Parsed = { what: string; due: Date };

/** Times of day given without am/pm mean working hours: "at 3" is 15:00, "at 9" is 09:00. */
function workingHours(result: chrono.ParsedResult, due: Date) {
  const hour = result.start.get("hour");
  const meridiem = result.start.isCertain("meridiem");
  if (hour !== null && !meridiem && hour >= 1 && hour <= 7) due.setHours(hour + 12);
}

export function parseReminder(text: string, now = new Date()): Parsed | null {
  const results = chrono.parse(text, now, { forwardDate: true });
  const result = results[0];
  if (!result) return null;
  const due = result.start.date();
  workingHours(result, due);
  // A date without a time ("Friday") means the start of the working day.
  if (!result.start.isCertain("hour")) due.setHours(9, 0, 0, 0);
  // "at 3" said at 16:00 means tomorrow at 15:00, not an hour ago.
  if (due <= now) due.setDate(due.getDate() + 1);

  const what = (text.slice(0, result.index) + " " + text.slice(result.index + result.text.length))
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^(to|about|that)\s+/i, "")
    .replace(/\s+(to|about|that|on|at|in|by)$/i, "")
    .trim();
  if (!what) return null;
  return { what, due };
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
