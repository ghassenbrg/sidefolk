import type { Reminder } from "./reminders";

export const EVENT_TTL_MS = 24 * 3_600_000;
export type EventProject = { path: string; label: string };
export type ProjectResolver = (wanted: string) => Promise<EventProject>;

/** Names only match a known project's exact basename. Full paths go through the host's
 * folder/root resolver. Duplicate names ask for a path instead of picking a recent session. */
export async function resolveEventProject(wanted: string, projects: readonly string[], resolveFolder: ProjectResolver): Promise<EventProject> {
  const name = wanted.trim();
  if (!name) throw new Error("Choose a project folder.");
  const paths = [...new Set(projects.filter(Boolean))];
  const exact = paths.filter((path) => path === name || path.split("/").pop() === name);
  if (exact.length > 1) throw new Error("Choose a full project path; that name matches several projects.");
  const target = exact[0] ?? (/^(?:\/|~\/)/.test(name) ? name : null);
  if (!target) throw new Error("Choose a full project path; no exact project match was found.");
  const resolved = await resolveFolder(target);
  if (!resolved.path.startsWith("/")) throw new Error("Choose a full project folder path.");
  return resolved;
}

/** Shared filtering keeps waiting/expired conditions out of due lists and native alarms. */
export function isScheduledReminder(r: Reminder): boolean {
  return !r.done && (!r.event || r.event.triggeredAt != null && r.event.expiredAt == null);
}

export function eventDescription(r: Reminder): string {
  const event = r.event;
  if (!event) return "";
  if (event.expiredAt != null) return `Expired: ${r.project} did not finish within 24 hours. No reminder was sent.`;
  if (event.triggeredAt != null) return `Triggered by ${r.project} finishing.`;
  return `When ${r.project} next finishes · Expires ${new Date(event.expires).toLocaleString()} (${Intl.DateTimeFormat().resolvedOptions().timeZone}).`;
}
