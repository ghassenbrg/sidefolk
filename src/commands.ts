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
