import type { Item } from "../shared/types.js";

// Pure state transition: an overdue reminder is delivered once, including after
// sleep/restart. Focus mode defers notification without discarding the reminder.
export function tickReminders(
  items: Item[],
  now: number,
  focus: boolean,
): { changed: boolean; notify: Item[] } {
  let changed = false;
  const notify: Item[] = [];
  for (const item of items) {
    if (
      item.kind !== "reminder" ||
      item.status === "done" ||
      item.dueAt === null ||
      item.dueAt > now
    )
      continue;
    if (item.status !== "due") {
      item.status = "due";
      changed = true;
    }
    if (!focus && item.notifiedAt === null) {
      item.notifiedAt = now;
      notify.push(item);
      changed = true;
    }
  }
  return { changed, notify };
}
