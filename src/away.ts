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
