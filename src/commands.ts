import { describeDue, describeRepeat, parseReminder } from "./when";

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
  /** A Spark worker for a project (folder name or path), or sending it home. */
  | { kind: "spark"; project: string; name: string | null; remove: boolean }
  /** A new Claude Code or Codex session in a folder, in the user's terminal. */
  | { kind: "start"; agent: "claude" | "codex"; folder: string | null; full: boolean }
  /** A dated note; `notebook` as typed ("evaluation"), or null to pick one. */
  | { kind: "note"; notebook: string | null; text: string }
  | { kind: "notebook"; name: string }
  | { kind: "notes" }
  /** A shell command to run in the user's terminal, after they see it. `folder` as typed ("api", "~/x"). */
  | { kind: "run"; command: string; folder: string | null }
  | { kind: "unknown"; text: string };

/** Commands people type to a terminal all day; also known before the PATH list arrives. */
const EVERYDAY = new Set(
  "ls ll la pwd cd cat less head tail grep rg find fd git gh npm npx pnpm yarn bun deno node python python3 pip pip3 uv make cargo rustc go swift xcodebuild brew docker kubectl ssh scp curl wget top htop du df ps kill mkdir touch cp mv rm tree code tsc jest vitest pytest ruby bundle rails mvn gradle java terraform aws gcloud".split(" "),
);
/** Words that are commands but more often start a sentence ("open the…", "find my notes"). */
const WORDS = new Set("open say find look which time date yes test man more w who last leave write talk join sort split what where when how why".split(" "));
let executables = new Set<string>();

/** The names on the user's PATH (from the app), so "terraform plan" is known without a list. */
export function knowCommands(names: string[]) {
  executables = new Set(names);
}

/** Text that is a shell command: an everyday command, or a PATH command written like one. */
function shellCommand(text: string): boolean {
  const [first, second = ""] = text.split(/\s+/);
  if (!/^[\w.+-]+$/.test(first)) return false;
  // "make a note", "find my keys", "go to the api session": English, not a command.
  if (/^(a|an|the|my|me|it|this|that|some|sure|up|out|to|of|for|your|our|i|you|we|please)$/i.test(second)) return false;
  if (EVERYDAY.has(first)) return true;
  if (WORDS.has(first.toLowerCase()) || !executables.has(first)) return false;
  // A sentence starting with a command name ("make a note") has no flags, paths or pipes.
  return text === first || /\s(-|\.|\/|~|\||>|\$|=)|[|&;]/.test(text);
}

export function parse(input: string): Command {
  const text = input.trim().replace(/[.!?]+$/, "");
  const lower = text.toLowerCase();
  let m: RegExpMatchArray | null;

  if (/^(help|\?|what can you do)$/.test(lower)) return { kind: "help" };
  if (/^(reminders|my reminders|list reminders)$/.test(lower)) return { kind: "reminders" };
  if ((m = text.match(/^remind me\b\s*(.*)$/i))) return { kind: "remind", text: m[1] };
  if (/^(notes|my notes|notebooks|open notes)$/.test(lower)) return { kind: "notes" };
  if ((m = text.match(/^(?:new|create|make)\s+(?:a\s+)?notebook\s+(?:called\s+|named\s+)?(.+)$/i))) return { kind: "notebook", name: m[1].trim() };
  // "note for evaluation: shipped X", "add to ideas: …", "note: …", "note that …". Kept as typed.
  const kept = input.trim();
  if ((m = kept.match(/^(?:note|jot|log|add)\s+(?:it\s+)?(?:for|to|in|into)\s+(?:my\s+|the\s+)?([^:]{1,60}?)\s*(?:notebook\s*)?:\s*(.+)$/is))) return { kind: "note", notebook: m[1], text: m[2].trim() };
  if ((m = kept.match(/^(?:note|jot down|write down)\s*(?::|that\s)\s*(.+)$/is))) return { kind: "note", notebook: null, text: m[1].trim() };
  if (/^(?:open|show)\s+(?:the\s+)?(?:sidefolk|dashboard|app|window)$/.test(lower)) return { kind: "sidefolk" };
  // "give api a spark", "add a spark for ~/git/api called Backend", "send the api spark home".
  if ((m = text.match(/^(?:give|get)\s+(?:the\s+)?(~?[\w./-]+?)(?:\s+project)?\s+an?\s+(?:spark|worker)(?:\s+(?:called|named)\s+(.+))?$/i)))
    return { kind: "spark", project: m[1], name: m[2]?.trim() ?? null, remove: false };
  if ((m = text.match(/^(?:add|new|create)\s+an?\s+(?:spark|worker)\s+(?:for|in)\s+(~?[\w./-]+)(?:\s+(?:called|named)\s+(.+))?$/i)))
    return { kind: "spark", project: m[1], name: m[2]?.trim() ?? null, remove: false };
  if ((m = text.match(/^(?:remove|send|dismiss)\s+(?:the\s+)?(~?[\w./-]+?)(?:'s)?\s+(?:spark|worker)(?:\s+home)?$/i)))
    return { kind: "spark", project: m[1], name: null, remove: true };
  // "start a claude session in sidefolk", "new codex session in api with full access", "open a claude session".
  if ((m = text.match(/^(?:(?:start|new|launch|begin)\s+(?:an?\s+)?(?:new\s+)?|open\s+an?\s+(?:new\s+)?)(claude(?:\s+code)?|codex)(?:\s+session)?(?:\s+(?:in|for)\s+(~?[\w./-]+))?(\s+with\s+full\s+access)?$/i)))
    return { kind: "start", agent: m[1].toLowerCase().startsWith("codex") ? "codex" : "claude", folder: m[2] ?? null, full: !!m[3] };
  if ((m = text.match(/^(?:open|jump to|go to|back to|continue|resume)\s+(?:the\s+)?(?:(.+?)(?:'s)?\s+)?session$/i)))
    return { kind: "open", project: m[1] ?? null };
  if (/^(continue|resume)$/.test(lower)) return { kind: "open", project: null };
  if ((m = text.match(/^(?:rename (?:yourself |you )?to|call yourself|your name is)\s+(.+)$/i))) return { kind: "rename", name: m[1].trim() };
  if (/^(hide|go away|hide yourself)$/.test(lower)) return { kind: "hide" };
  // "run npm test in api", "$ ls -la", or just "ls -la". Checked on the raw input: a trailing "?"
  // or "." can be part of a command.
  const raw = input.trim();
  if ((m = raw.match(/^(?:run|\$)\s+(.+?)(?:\s+in\s+(~?[\w./-]+))?$/i))) return { kind: "run", command: m[1], folder: m[2] ?? null };
  if (shellCommand(raw)) return { kind: "run", command: raw, folder: null };
  if ((/^(tomorrow|today|tonight|in \d+|every|daily|weekdays|monthly)\b/i.test(text) || /\bremind me\b.+\bbefore\b/i.test(text)) && parseReminder(text)) return { kind: "remind", text };
  return { kind: "unknown", text };
}

export const HELP = [
  "remind me tomorrow at 9 to check the results · reminders",
  "open session · open api session · start a claude session in api",
  "open Sidefolk · hide · rename to Pip",
  "note for evaluation: shipped the login migration · notes",
  "give api a spark · send the api spark home",
  "ls -la · run npm test in api (you confirm first)",
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
    case "spark":
      return command.remove ? `Send the ${command.project} Spark home` : `Give ${command.project} its own Spark${command.name ? ` called ${command.name}` : ""}`;
    case "start":
      return `Start ${command.agent === "codex" ? "Codex" : "Claude Code"} in ${command.folder ?? "your home folder"}${command.full ? " with full access" : ""} (you confirm first)`;
    case "note":
      return command.notebook ? `Add to ${command.notebook}: ${command.text}` : `Add a note (I'll ask which notebook): ${command.text}`;
    case "notebook":
      return `Start a notebook called ${command.name}`;
    case "notes":
      return "Show your notebooks";
    case "run":
      return `Run \`${command.command}\` in ${command.folder ?? "your home folder"}, in your terminal (you confirm first)`;
    case "unknown":
      return "I don't know that one yet. Try “remind me…” or “help”";
  }
}
