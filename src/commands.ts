import { describeDue, parseReminder } from "./when";

// What the companion understands, all locally: no model call and no tokens. Anything else gets
// a short answer saying what it can do; it is never sent to an AI tool behind your back
// (docs/PLAN-V2.md: plain rules first, AI only when you ask for it).

export type Command =
  | { kind: "remind"; text: string }
  | { kind: "reminders" }
  | { kind: "open"; project: string | null }
  | { kind: "sidefolk" }
  | { kind: "rename"; name: string }
  | { kind: "hide" }
  | { kind: "help" }
  | { kind: "unknown"; text: string };

export function parse(input: string): Command {
  const text = input.trim().replace(/[.!?]+$/, "");
  const lower = text.toLowerCase();
  let m: RegExpMatchArray | null;

  if (/^(help|\?|what can you do)$/.test(lower)) return { kind: "help" };
  if (/^(reminders|my reminders|list reminders)$/.test(lower)) return { kind: "reminders" };
  if ((m = text.match(/^remind me\b\s*(.*)$/i))) return { kind: "remind", text: m[1] };
  if (/^(?:open|show)\s+(?:the\s+)?(?:sidefolk|dashboard|app|window)$/.test(lower)) return { kind: "sidefolk" };
  if ((m = text.match(/^(?:open|jump to|go to|back to|continue|resume)\s+(?:the\s+)?(?:(.+?)(?:'s)?\s+)?session$/i)))
    return { kind: "open", project: m[1] ?? null };
  if (/^(continue|resume)$/.test(lower)) return { kind: "open", project: null };
  if ((m = text.match(/^(?:rename (?:yourself |you )?to|call yourself|your name is)\s+(.+)$/i))) return { kind: "rename", name: m[1].trim() };
  if (/^(hide|go away|hide yourself)$/.test(lower)) return { kind: "hide" };
  return { kind: "unknown", text };
}

export const HELP = [
  "remind me tomorrow at 9 to check the results · reminders",
  "open session · open api session",
  "open Sidefolk · hide · rename to Pip",
];

/** What `explain` needs to know about the companion's sessions. */
export type ExplainContext = {
  name: string;
  /** The session "open session" would open (in a project folder, if named). */
  sessionFor(project: string | null): { agent: string; live: boolean } | null;
};

/** What Enter would do with this text; shown under every field that talks to the companion. */
export function explain(text: string, ctx: ExplainContext): string {
  const command = parse(text);
  switch (command.kind) {
    case "help":
      return "Show what I understand";
    case "remind": {
      const parsed = parseReminder(command.text);
      return parsed ? `Remind you ${describeDue(parsed.due)}: ${parsed.what}` : "Set a reminder (then pick when)";
    }
    case "reminders":
      return "Show your reminders";
    case "open": {
      const session = ctx.sessionFor(command.project);
      if (!session) return command.project ? `No work session in ${command.project} yet` : "No work session to open yet";
      return session.live ? `Bring ${session.agent}'s session forward` : `Continue ${session.agent}'s last session in a terminal`;
    }
    case "sidefolk":
      return "Open the Sidefolk window";
    case "rename":
      return `Rename ${ctx.name} to ${command.name}`;
    case "hide":
      return `Hide ${ctx.name} until you press the shortcut`;
    case "unknown":
      return "I don't know that one yet. Try “remind me…” or “help”";
  }
}
