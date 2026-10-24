import { AGENT_NAMES, folder } from "./agents";
import type { Reminder } from "./reminders";
import { describeDue } from "./when";

/** Mirrors `Entry` in src-tauri/src/journal.rs. */
export type JournalEntry = { at: number; source: string; session: string; project: string; kind: string; detail: string };

/** Away this long (no keyboard or mouse) earns a "welcome back" briefing. */
export const AWAY_SECS = 30 * 60;

const agent = (source: string) => AGENT_NAMES[source as keyof typeof AGENT_NAMES] ?? source;

/** What happened while you were away, one line per project, then the next reminder. */
export function welcomeBack(entries: JournalEntry[], upcoming: Reminder[], now = new Date()): string[] {
  const projects = new Map<string, { outcome?: JournalEntry; missed: number; started: number }>();
  for (const e of entries) {
    const p = projects.get(e.project) ?? { missed: 0, started: 0 };
    if (e.kind === "done" || e.kind === "failed") p.outcome = e;
    if (e.kind === "answer" && e.detail === "not answered on the pet") p.missed++;
    if (e.kind === "start" || e.kind === "prompt") p.started++;
    projects.set(e.project, p);
  }
  const lines: string[] = [];
  for (const [project, p] of projects) {
    const where = project ? folder(project) : "Elsewhere";
    if (p.outcome) {
      const what = p.outcome.kind === "done" ? "finished" : "hit a problem";
      const detail = p.outcome.detail ? `: ${p.outcome.detail}` : ".";
      lines.push(`${where} · ${agent(p.outcome.source)} ${what}${detail}`);
    } else if (p.started) lines.push(`${where} · still working`);
    if (p.missed) lines.push(`${where} · ${p.missed === 1 ? "a question" : `${p.missed} questions`} went to the terminal`);
  }
  const next = upcoming[0];
  if (next) lines.push(`Next reminder: ${describeDue(new Date(next.due), now)} · ${next.text}`);
  return lines.slice(0, 6);
}

/** Today's meetings and reminders, then what happened overnight: the first briefing of a day. */
export function morning(entries: JournalEntry[], upcoming: Reminder[], meetings: { title: string; start: number }[], now = new Date()): string[] {
  const end = new Date(now);
  end.setHours(23, 59, 59, 999);
  const clock = (ms: number) => new Date(ms).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  const lines = [
    ...meetings.filter((m) => m.start <= end.getTime()).slice(0, 3).map((m) => `${clock(m.start)} · ${m.title}`),
    ...upcoming.filter((r) => r.due <= end.getTime()).slice(0, 3).map((r) => `${clock(r.due)} · ${r.text}`),
  ];
  // Overnight work, without its "next reminder" line (today's are listed above).
  const overnight = welcomeBack(entries, [], now);
  return [...lines, ...overnight].slice(0, 7);
}

/** Whether today's first briefing is still to come (kept per day in this Mac's storage). */
export function firstToday(storage: Pick<Storage, "getItem" | "setItem"> | null, now = new Date()): boolean {
  const day = now.toDateString();
  try {
    if (storage?.getItem("sidefolk.morning") === day) return false;
    storage?.setItem("sidefolk.morning", day);
  } catch {
    // Without storage every long absence gets the plain welcome back.
  }
  return true;
}

/** Monday 00:00 of the week `now` is in, local time. */
export function weekStart(now = new Date()) {
  const d = new Date(now);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return d;
}

/** Friday afternoon's look back: notes taken this week, then finished work per project. */
export function weekly(entries: JournalEntry[], notes: { notebook: string; date: string }[], now = new Date()): string[] {
  const start = weekStart(now);
  const pad = (n: number) => String(n).padStart(2, "0");
  const from = `${start.getFullYear()}-${pad(start.getMonth() + 1)}-${pad(start.getDate())}`;
  const lines: string[] = [];
  const books = new Map<string, number>();
  for (const n of notes) if (n.date >= from) books.set(n.notebook, (books.get(n.notebook) ?? 0) + 1);
  const total = [...books.values()].reduce((a, b) => a + b, 0);
  if (total) lines.push(`${total} ${total === 1 ? "note" : "notes"}: ${[...books].map(([b, n]) => `${b} (${n})`).join(", ")}`);
  const done = new Map<string, { source: string; count: number }>();
  for (const e of entries) {
    if (e.kind !== "done" || e.at < start.getTime()) continue;
    const key = e.project ? folder(e.project) : "Elsewhere";
    const d = done.get(key) ?? { source: e.source, count: 0 };
    d.count++;
    done.set(key, d);
  }
  for (const [project, d] of [...done].sort((a, b) => b[1].count - a[1].count).slice(0, 4))
    lines.push(`${project} · ${agent(d.source)} finished ${d.count === 1 ? "a task" : `${d.count} tasks`}`);
  return lines;
}

/** Whether this is Friday afternoon and the week's look back hasn't happened yet. */
export function weeklyDue(storage: Pick<Storage, "getItem" | "setItem"> | null, now = new Date()): boolean {
  if (now.getDay() !== 5 || now.getHours() < 15) return false;
  const week = weekStart(now).toDateString();
  try {
    if (storage?.getItem("sidefolk.weekly") === week) return false;
    storage?.setItem("sidefolk.weekly", week);
  } catch {
    return false;
  }
  return true;
}
