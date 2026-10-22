import { randomUUID } from "node:crypto";
import { z } from "zod";
import { reminderDate } from "../shared/intents.js";
import type { AppState, Item } from "../shared/types.js";

const title = z
  .string()
  .trim()
  .min(1)
  .max(240)
  .refine(
    (value) => !/^(?:this|that|it|something|your reminder)$/i.test(value),
    "Specify what to remember.",
  );
export const actionSchema = z.discriminatedUnion("type", [
  z
    .object({
      type: z.literal("reminder.create"),
      title,
      when: z.string().trim().min(1).max(200),
    })
    .strict(),
  z.object({ type: z.literal("todo.create"), title }).strict(),
]);
export type CompanionAction = z.infer<typeof actionSchema>;
const actionsSchema = z.array(actionSchema).min(1).max(3);

export function extractActions(text: string): {
  actions: CompanionAction[];
  error?: string;
  present: boolean;
} {
  const matches = [
    ...text.matchAll(/<SIDEFOLK_ACTIONS>([\s\S]*?)<\/SIDEFOLK_ACTIONS>/g),
  ];
  if (!matches.length)
    return text.includes("<SIDEFOLK_ACTIONS>")
      ? {
          actions: [],
          present: true,
          error: "The action was incomplete. Nothing was saved.",
        }
      : { actions: [], present: false };
  try {
    const actions = actionsSchema.parse(
      matches.flatMap((match) => {
        const value: unknown = JSON.parse(match[1]);
        if (!Array.isArray(value)) throw new Error("Expected an action list.");
        return value;
      }),
    );
    return { actions, present: true };
  } catch {
    return {
      actions: [],
      present: true,
      error:
        "I couldn’t validate that reminder or task. Nothing was saved; tell me what you want to remember and when.",
    };
  }
}

export function reminderConfirmation(
  item: Pick<Item, "title" | "dueAt">,
  now = Date.now(),
): string {
  const delay = item.dueAt! - now;
  const minutes = Math.max(1, Math.round(delay / 60_000));
  const when =
    delay > 0 && delay < 60 * 60_000
      ? `in ${minutes} minute${minutes === 1 ? "" : "s"}`
      : new Date(item.dueAt!).toLocaleString([], {
          dateStyle: "medium",
          timeStyle: "short",
        });
  return `I’ll remind you ${when}: ${item.title}.`;
}

// Validate the whole batch before mutating. Only the host can turn agent
// proposals into persisted reminders; natural-language claims are not actions.
export function applyActions(
  state: AppState,
  actions: CompanionAction[],
  requestedAt: number,
  now = Date.now(),
): { confirmations: string[]; error?: string } {
  const parsed = actionsSchema.safeParse(actions);
  if (!parsed.success)
    return {
      confirmations: [],
      error: "The action was invalid. Nothing was saved.",
    };
  const planned: Item[] = [];
  const seen = new Set<string>();
  for (const action of parsed.data) {
    const due =
      action.type === "reminder.create"
        ? reminderDate(action.when, new Date(requestedAt))?.getTime()
        : null;
    if (
      action.type === "reminder.create" &&
      (!due || due <= now || due > now + 5 * 366 * 24 * 60 * 60_000)
    )
      return {
        confirmations: [],
        error: `I haven’t saved “${action.title}” yet. What future time should I use?`,
      };
    const key = `${action.type}:${action.title.toLowerCase()}:${due}`;
    if (seen.has(key)) continue;
    seen.add(key);
    planned.push({
      id: randomUUID(),
      title: action.title,
      kind: action.type === "reminder.create" ? "reminder" : "todo",
      createdAt: now,
      dueAt: due ?? null,
      status: "pending",
      notifiedAt: null,
    });
  }
  state.items.unshift(...planned);
  state.pendingReminder = null;
  return {
    confirmations: planned.map((item) =>
      item.kind === "reminder"
        ? reminderConfirmation(item, now)
        : `Added to your list: ${item.title}.`,
    ),
  };
}
