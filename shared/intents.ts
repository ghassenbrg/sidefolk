import * as chrono from "chrono-node";
import type { Intent } from "./types.js";

// Scheduling uses the computer's local timezone; chrono preserves the parsed span
// so the saved task does not accidentally include the scheduling phrase.
export function interpret(
  input: string,
  now = new Date(),
  pendingTitle?: string,
): Intent {
  const text = input.trim();
  const memory = text.match(
    /^(?:remember\s+that|remember\s+this\s*:?|learn\s+that)\s+(.+)/i,
  );
  if (memory) return { type: "memory", text: memory[1].trim() };
  if (
    /^(?:what(?:'s| is| did)?|show|list)\b.*\b(todo|to.do|reminder|unfinished|pending|tasks?)\b/i.test(
      text,
    )
  )
    return { type: "list" };
  if (
    /^(?:open|run|start|choose|select)\b.*\b(project|terminal|workspace)\b/i.test(
      text,
    )
  )
    return { type: "project" };
  const reminder =
    /^(?:hey\s+\w+[,!]?\s+)?(?:remind\s+me|remember\s+to|reminder\s*:?)/i;
  const isReminder = reminder.test(text);
  if (isReminder || pendingTitle) {
    const body = isReminder ? text.replace(reminder, "").trim() : text;
    const parsed = chrono.parse(body, now, { forwardDate: true })[0];
    if (parsed) {
      const before = body.slice(0, parsed.index);
      const after = body.slice(parsed.index + parsed.text.length);
      const title = (isReminder ? `${before} ${after}` : pendingTitle!)
        .replace(/^[\s,.:;-]*(?:to|about|of)\s+/i, "")
        .replace(/[\s,.;:]+$/g, "")
        .trim();
      const date = parsed.start.date();
      if (!parsed.start.isCertain("hour")) date.setHours(9, 0, 0, 0);
      if (title && date.getTime() > now.getTime())
        return { type: "reminder", title, dueAt: date.getTime() };
      return {
        type: "clarify",
        title: title || pendingTitle || "your reminder",
      };
    }
    if (isReminder) {
      const title = body
        .replace(/\b(?:later|sometime)\b/gi, "")
        .trim()
        .replace(/^(?:to|about|of)\s+/i, "")
        .trim();
      return { type: "clarify", title: title || "your reminder" };
    }
  }
  const todo = text.match(
    /^(?:add\s+|todo\s*:?\s*|to-do\s*:?\s*)(.+?)(?:\s+to\s+(?:my\s+)?(?:todos?|to-do(?:\s+list)?|list))?$/i,
  );
  if (todo) return { type: "todo", title: todo[1].trim() };
  return { type: "chat" };
}
