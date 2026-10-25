import { describeDue, describeRepeat, parseReminder } from "./when";

// What Quick add understands, all locally: no model call and no tokens (docs/V1.md §6). Plain
// English never becomes a shell command: only text that starts with `$` does, and only when the
// user turned commands on (Settings → Labs). Anything else is never sent to an AI tool.

export type Command =
  | { kind: "remind"; text: string }
  | { kind: "reminders" }
  | { kind: "open"; project: string | null }
  | { kind: "sidefolk" }
  | { kind: "rename"; name: string }
  | { kind: "hide" }
  | { kind: "help" }
  /** Opens a folder in an app ("open api in VS Code", "open a terminal in api"), a web address or an app. */
  | { kind: "open-thing"; target: string; app: string | null }
  /** A new Claude Code or Codex session in a folder, in the user's terminal. */
  | { kind: "start"; agent: "claude" | "codex"; folder: string | null; full: boolean }
  /** A dated note; `notebook` as typed ("evaluation"), or null to pick one. */
  | { kind: "note"; notebook: string | null; text: string }
  | { kind: "notebook"; name: string }
  | { kind: "notes" }
  /** `$ …`: a shell command for the user's terminal, after they see it. `folder` as typed ("api", "~/x"). */
  | { kind: "run"; command: string; folder: string | null }
  | { kind: "unknown"; text: string };

export function parse(input: string): Command {
  const text = input.trim().replace(/[.!?]+$/, "");
  const lower = text.toLowerCase();
  let m: RegExpMatchArray | null;

  if (/^(help|\?|what can you do)$/.test(lower)) return { kind: "help" };
  if (/^(?:show |list |open )?(?:my |the )?reminders$/.test(lower)) return { kind: "reminders" };
  // "what's today", "what do I have today": the day, in the window's Today.
  if (/^(?:what'?s|what is|what do i have|show me)\s+(?:on\s+|up\s+)?(?:for\s+)?today$/.test(lower)) return { kind: "sidefolk" };
  if ((m = text.match(/^remind me\b\s*(.*)$/i))) return { kind: "remind", text: m[1] };
  if (/^(?:show |open |list )?(?:my |the )?(?:notes|notebooks)$/.test(lower)) return { kind: "notes" };
  if ((m = text.match(/^(?:new|create|make)\s+(?:a\s+)?notebook\s+(?:called\s+|named\s+)?(.+)$/i))) return { kind: "notebook", name: m[1].trim() };
  // "note for evaluation: shipped X", "add to ideas: …", "note: …", "note that …". Kept as typed.
  const kept = input.trim();
  if ((m = kept.match(/^(?:note|jot|log|add)\s+(?:it\s+)?(?:for|to|in|into)\s+(?:my\s+|the\s+)?([^:]{1,60}?)\s*(?:notebook\s*)?:\s*(.+)$/is))) return { kind: "note", notebook: m[1], text: m[2].trim() };
  if ((m = kept.match(/^(?:note|jot down|write down)\s*(?::|that\s)\s*(.+)$/is))) return { kind: "note", notebook: null, text: m[1].trim() };
  if (/^(?:open|show)\s+(?:the\s+)?(?:sidefolk|dashboard|app|window)$/.test(lower)) return { kind: "sidefolk" };
  // "start a claude session in sidefolk", "new codex session in api with full access", "open a claude session".
  if ((m = text.match(/^(?:(?:start|new|launch|begin)\s+(?:an?\s+)?(?:new\s+)?|open\s+an?\s+(?:new\s+)?)(claude(?:\s+code)?|codex)(?:\s+session)?(?:\s+(?:in|for)\s+(~?[\w./-]+))?(\s+with\s+full\s+access)?$/i)))
    return { kind: "start", agent: m[1].toLowerCase().startsWith("codex") ? "codex" : "claude", folder: m[2] ?? null, full: !!m[3] };
  if ((m = text.match(/^(?:open|jump to|go to|back to|continue|resume)\s+(?:the\s+)?(?:(.+?)(?:'s)?\s+)?session$/i)))
    return { kind: "open", project: m[1] ?? null };
  if (/^(continue|resume)$/.test(lower)) return { kind: "open", project: null };
  if ((m = text.match(/^(?:open\s+)?(?:a\s+(?:new\s+)?)?terminal\s+in\s+(~?[\w./-]+)$/i))) return { kind: "open-thing", target: m[1], app: "terminal" };
  if ((m = text.match(/^open\s+(~?[\w./-]+)\s+in\s+([\w .+-]{2,30})$/i))) return { kind: "open-thing", target: m[1], app: m[2].trim() };
  if ((m = text.match(/^(?:rename (?:yourself |you )?to|call yourself|your name is)\s+(.+)$/i))) return { kind: "rename", name: m[1].trim() };
  if (/^(hide|go away|hide yourself)$/.test(lower)) return { kind: "hide" };
  // Anything with a date or time is a reminder ("call mom at 5pm", "dentist thu 2:30"), checked
  // before "open …" so "open enrollment closes friday 5pm" is one too (docs/V1.md V1-Q2).
  if (parseReminder(text)) return { kind: "remind", text };
  if ((m = text.match(/^open\s+(?:the\s+)?(\S.{0,60})$/i)) && !/\s(session|notebook)$/i.test(text)) return { kind: "open-thing", target: m[1], app: null };
  // "$ npm test in api": only an explicit `$` is a command. Checked on the raw input: a trailing
  // "?" or "." can be part of a command.
  const raw = input.trim();
  if ((m = raw.match(/^\$\s*(.+?)(?:\s+in\s+(~?[\w./-]+))?$/))) return { kind: "run", command: m[1], folder: m[2] ?? null };
  return { kind: "unknown", text };
}

export const HELP = [
  "remind me tomorrow at 9 to check the results · reminders",
  "open session · open api session · start a claude session in api",
  "open Sidefolk · hide · rename to Pip",
  "note for evaluation: shipped the login migration · notes",
  "open api in VS Code · open a terminal in api · open github.com",
  "$ npm test in api (commands, when on in Settings → Labs; you confirm first)",
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
      if (!parsed) return "Set a reminder (then pick when)";
      return `Remind you ${parsed.repeat ? `${describeRepeat(parsed.repeat, parsed.due)}, from ` : ""}${describeDue(parsed.due)}: ${parsed.what}`;
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
    case "open-thing":
      return command.app ? `Open ${command.target} in ${command.app}` : /\.[a-z]{2,}(\/|$)/i.test(command.target) ? `Open ${command.target} in your browser` : `Open ${command.target}`;
    case "start":
      return `Start ${command.agent === "codex" ? "Codex" : "Claude Code"} in ${command.folder ?? "your home folder"}${command.full ? (command.agent === "codex" ? " without approvals" : " in auto mode") : ""} (you confirm first)`;
    case "note":
      return command.notebook ? `Add to ${command.notebook}: ${command.text}` : `Add a note (I'll ask which notebook): ${command.text}`;
    case "notebook":
      return `Start a notebook called ${command.name}`;
    case "notes":
      return "Show your notebooks";
    case "run":
      return `Run \`${command.command}\` in ${command.folder ?? "your home folder"}, in your terminal (you confirm first)`;
    case "unknown":
      return "Save it as a note";
  }
}
