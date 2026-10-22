import * as chrono from "chrono-node";
import type { Intent } from "./types.js";

// Normalize conversational wrappers, not the task itself. Uncertain requests
// go to the agent instead of making the user learn a command syntax.
function requestBody(input: string): string {
  let text = input.trim();
  for (let i = 0; i < 3; i++) {
    text = text
      .replace(/^(?:hey|hi|hello)(?:\s+[\p{L}\p{N}_'-]{1,24})?[,!]\s*/iu, "")
      .replace(
        /^(?:hey|hi|hello)\s+(?=(?:can|could|would|will|please|remind|set|add|remember)\b)/i,
        "",
      )
      .replace(
        /^(?:(?:can|could|would|will)\s+(?:you|u)\s+(?:please\s+)?|please\s+|(?:i need|i want|i'd like)\s+(?:you\s+)?to\s+)/i,
        "",
      );
  }
  return text.trim();
}

export function reminderDate(when: string, reference: Date): Date | null {
  const parsed = chrono.parse(when, reference, { forwardDate: true })[0];
  if (!parsed) return null;
  const date = parsed.start.date();
  if (!parsed.start.isCertain("hour")) date.setHours(9, 0, 0, 0);
  return Number.isFinite(date.getTime()) ? date : null;
}

export function interpret(
  input: string,
  now = new Date(),
  pendingTitle?: string,
): Intent {
  const text = requestBody(input);
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
  if (
    /^remind\s+(?:me\s+)?(?:how|why|what|who|where|whether)\b/i.test(text) ||
    /\b(?:and|then)\s+(?:(?:also|please)\s+)?(?:remind|add|set|remember)\b/i.test(
      text,
    )
  )
    return { type: "chat" };
  const reminder =
    /^(?:remind(?:\s+(?:me|us))?(?=\s|[:,]|$)|remember\s+to|(?:set|create|add)\s+(?:me\s+)?(?:a\s+)?reminder(?:\s+for\s+me)?(?=\s|[:,]|$)|(?:give\s+me\s+a\s+)?nudge(?:\s+me)?(?=\s|[:,]|$))[:,]?\s*/i;
  const isReminder = reminder.test(text);
  if (isReminder || pendingTitle) {
    const body = isReminder ? text.replace(reminder, "").trim() : text;
    const parsed = chrono.parse(body, now, { forwardDate: true })[0];
    if (parsed) {
      const before = /\bfrom\s+now\b/i.test(parsed.text)
        ? body.slice(0, parsed.index).replace(/\b(?:in|after)\s*$/i, "")
        : body.slice(0, parsed.index);
      const after = body.slice(parsed.index + parsed.text.length);
      if (
        !isReminder &&
        !/^(?:(?:actually|make (?:that|it)|at|on|for|please|instead)\s*[,.:;-]?\s*)*$/i.test(
          `${before} ${after}`.trim(),
        )
      )
        return { type: "chat" };
      const title = (isReminder ? `${before} ${after}` : pendingTitle!)
        .replace(/^[\s,.:;-]*(?:to|about|of|for)\s+/i, "")
        .replace(/\s*,?\s*please[.!]?$/i, "")
        .replace(/[\s,.;:!?]+$/g, "")
        .trim();
      const date = parsed.start.date();
      if (!parsed.start.isCertain("hour")) date.setHours(9, 0, 0, 0);
      if (!title || /^(?:this|that|it|something|your reminder)$/i.test(title))
        return { type: "chat" };
      if (date.getTime() > now.getTime())
        return { type: "reminder", title, dueAt: date.getTime() };
      return { type: "clarify", title };
    }
    if (isReminder) {
      const title = body
        .replace(/\b(?:later|sometime)\b/gi, "")
        .trim()
        .replace(/^(?:to|about|of|for)\s+/i, "")
        .trim();
      if (!title || /^(?:this|that|it|something)$/i.test(title))
        return { type: "chat" };
      return { type: "clarify", title };
    }
  }
  const todo =
    text.match(/^(?:todo\s*:?\s*|to-do\s*:?\s*)(.+)$/i) ??
    text.match(
      /^add\s+(.+?)\s+to\s+(?:my\s+)?(?:todos?|to-do(?:\s+list)?|list)$/i,
    );
  if (todo) return { type: "todo", title: todo[1].trim() };
  return { type: "chat" };
}
