import {
  ACCESSORIES,
  ACCESSORY_NAMES,
  PALETTES,
  PALETTE_NAMES,
  SPECIES,
  SPECIES_NAMES,
  type AccessoryName,
  type PaletteName,
  type SpeciesName,
} from "./pet/look";

// The command bar understands a few plain phrases locally, so calling pets, sending them
// home and changing how they look never costs model tokens. Anything else is a task for an
// agent, which is what the bar did before it had commands.

export type Command =
  | { kind: "call"; who: string }
  | { kind: "home"; who: string | null }
  | { kind: "tell"; who: string | null; task: string }
  | { kind: "codex"; task: string }
  | { kind: "rename"; who: string | null; name: string }
  | { kind: "look"; who: string | null; palette?: PaletteName; accessory?: AccessoryName; species?: SpeciesName }
  | { kind: "crew" }
  | { kind: "customize"; who: string | null }
  | { kind: "forget"; who: string }
  | { kind: "adopt" }
  | { kind: "remind"; text: string }
  | { kind: "reminders" }
  | { kind: "help" }
  | { kind: "task"; text: string };

/** Matches a name or its label, ignoring case, a leading article and a plural "s". */
function pick<T extends string>(text: string, names: readonly T[], label: (name: T) => string): T | undefined {
  const t = text.trim().toLowerCase().replace(/^(the|a|an|some|your)\s+/, "");
  return names.find((n) => t === n || t === label(n).toLowerCase() || t === `${n}s` || `${t}s` === n);
}
const palette = (text: string) => pick(text, PALETTE_NAMES, (n) => PALETTES[n].label);
const species = (text: string) => pick(text, SPECIES_NAMES, (n) => SPECIES[n].label);
const accessory = (text: string) =>
  /^(nothing|none)$/i.test(text.trim()) ? ("none" as const) : pick(text, ACCESSORY_NAMES, (n) => ACCESSORIES[n]);

export function parse(input: string): Command {
  const text = input.trim().replace(/[.!?]+$/, "");
  const lower = text.toLowerCase();
  let m: RegExpMatchArray | null;

  if (/^(help|\?|what can you do)$/.test(lower)) return { kind: "help" };
  if (/^(crew|who|who'?s out|list|pets)$/.test(lower)) return { kind: "crew" };
  if (/^adopt( this session)?$/.test(lower)) return { kind: "adopt" };
  if ((m = text.match(/^(?:customi[sz]e|dress up|edit|change)(?:\s+(.+?))?(?:'s look)?$/i))) return { kind: "customize", who: m[1] ?? null };
  if (/^(reminders|my reminders|list reminders)$/.test(lower)) return { kind: "reminders" };
  if ((m = text.match(/^remind me\b\s*(.*)$/i))) return { kind: "remind", text: m[1] };
  if ((m = text.match(/^codex\s*[:,]?\s+(.+)$/i))) return { kind: "codex", task: m[1] };
  if ((m = text.match(/^(?:call|summon|bring|where(?:'s| is))\s+(.+)$/i))) return { kind: "call", who: m[1] };
  if (/^(go )?home$/.test(lower)) return { kind: "home", who: null };
  if ((m = text.match(/^send\s+(.+?)\s+home$/i)) || (m = text.match(/^(.+?),?\s+go\s+home$/i)))
    return { kind: "home", who: m[1] };
  if ((m = text.match(/^(?:forget|release|delete)\s+(.+)$/i))) return { kind: "forget", who: m[1] };
  if ((m = text.match(/^rename\s+(?:(.+?)\s+)?to\s+(.+)$/i))) return { kind: "rename", who: m[1] ?? null, name: m[2].trim() };
  if ((m = text.match(/^(?:(.+?),?\s+)?(?:wear|put on)\s+(.+)$/i))) {
    const a = accessory(m[2]);
    if (a) return { kind: "look", who: m[1] ?? null, accessory: a };
  }
  if ((m = text.match(/^(?:(.+?),?\s+)?(?:take off|remove)\s+(?:the\s+|your\s+)?(.+)$/i)) && accessory(m[2]))
    return { kind: "look", who: m[1] ?? null, accessory: "none" };
  if ((m = text.match(/^(?:(.+?),?\s+)?(?:color|colour|paint|turn into|turn|become|be)\s+(?:yourself\s+)?(.+)$/i))) {
    const p = palette(m[2]);
    if (p) return { kind: "look", who: m[1] ?? null, palette: p };
    const s = species(m[2]);
    if (s) return { kind: "look", who: m[1] ?? null, species: s };
  }
  if ((m = text.match(/^(?:tell|ask)\s+(.+?)\s+to\s+(.+)$/i))) return { kind: "tell", who: m[1], task: m[2] };
  if ((m = text.match(/^([\w-]{2,24}):\s+(.+)$/))) return { kind: "tell", who: m[1], task: m[2] };
  return { kind: "task", text };
}

export const HELP = [
  "call Pip · send Pip home · crew",
  "tell Pip to run the tests · Pip: fix the lint",
  "customize Pip · Pip wear glasses · Pip become a fox · rename Pip to Bun",
  "remind me Friday at 3 to review the PR · reminders",
];
